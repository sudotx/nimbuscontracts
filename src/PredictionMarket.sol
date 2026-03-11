// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPredictionMarket } from "./interfaces/IPredictionMarket.sol";

import { MathLib } from "./libraries/MathLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { MarketCreationData, MarketState } from "./utils/Market.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PredictionMarket
 * @notice Individual binary prediction market with AMM-based trading
 * @dev Uses constant product AMM for price discovery and liquidity
 */
contract PredictionMarket is IPredictionMarket, ReentrancyGuard {
    using MathLib for uint256;
    using SafeERC20 for IERC20;
    
    uint8 public constant NORMALIZER_DECIMAL = 18;
    uint16 public constant PLATFORM_FEE_BPS = 10;
    uint16 public constant TRADING_FEE_BPS = 30;

    IERC20 public immutable TOKEN; // Collateral. Trading token. USDC.
    address public immutable CREATOR;
    address public immutable RESOLVER;
    address public immutable FEE_RECIPIENT;

    uint64 public immutable END_TIME;
    uint64 public immutable RESOLUTION_TIME;

    MarketState public state;

    string public question;
    string public description;
    bool public outcome;

    uint256 public collateralPool;

    uint256 public yesShares;
    uint256 public noShares;

    uint256 public yesReserve = 1e27;
    uint256 public noReserve = 1e27;

    uint256 public totalReserve = yesReserve + noReserve;
    uint256 public product = yesReserve * noReserve;
    uint256 public accumulatedFees;

    mapping(address => UserPosition) public userPosition;
    mapping(address => bool) public hasClaimed;

    receive() external payable {}

    constructor(address token, MarketCreationData memory marketCreationData) {
        require(marketCreationData.endTime > block.timestamp, "Invalid end time");
        require(marketCreationData.creator != address(0), "Invalid creator");
        require(marketCreationData.resolver != address(0), "Invalid resolver");
        require(marketCreationData.feeRecipient != address(0), "Invalid fee recipient");
        
        TOKEN = IERC20(token);

        question = marketCreationData.question;
        description = marketCreationData.description;
        CREATOR = marketCreationData.creator;
        RESOLVER = marketCreationData.resolver;
        END_TIME = marketCreationData.endTime;
        FEE_RECIPIENT = marketCreationData.feeRecipient;
    }

    // Amount is coming in, USDC maybe, if yes you're buying yes, else buying no.
    function buy(bool isYes, uint256 shareAmount, uint256 minShares) external returns (uint256 shares) {
        require(state == MarketState.OPEN, MarketClosed());
        require(block.timestamp < END_TIME, MarketClosed());
        require(yesReserve > 0 && noReserve > 0, InsufficientLiquidity());

        TOKEN.safeTransferFrom(msg.sender, address(this), shareAmount);
        
        uint256 platformFee = (shareAmount * PLATFORM_FEE_BPS) / 100;
        accumulatedFees += platformFee;

        uint256 tradingAmount = shareAmount - platformFee;
        uint256 normalizedTradingAmount = _normalizeAmountTo18Decimals(tradingAmount);
        shares = _calculateBuyShares(isYes, normalizedTradingAmount);
        require(shares >= minShares, SlippageExceeded());
        
        if (isYes) {
            yesReserve -= shares;
            noReserve += normalizedTradingAmount;
            userPosition[msg.sender].yesBalance += shares;
            yesShares += shares;
        } else {
            noReserve -= shares;
            yesReserve += normalizedTradingAmount;
            userPosition[msg.sender].noBalance += shares;
            noShares += shares;
        }
        
        collateralPool += tradingAmount;
        
        Prices memory newPrices = getCurrentPrices();
        emit Trade(msg.sender, isYes, true, shares, shareAmount, newPrices);
    }

    function sell(
        bool isYes,
        uint256 shareAmount,
        uint256 minReturn,
        address receiver
    ) external  returns (uint256 returnAmount) {
        require(state == MarketState.OPEN, MarketClosed());
        require(block.timestamp < END_TIME, MarketClosed());
        require(shareAmount > 0, InvalidAmount());
        
        uint256 userBalance = isYes ? userPosition[msg.sender].yesBalance : userPosition[msg.sender].noBalance;
        require(userBalance > shareAmount, "Insufficient shares");
        
        uint256 shareReturn = _calculateSellReturn(isYes, shareAmount);

        returnAmount = _normalizeAmountToDefaultDecimals(shareReturn);
        require(returnAmount >= minReturn, SlippageExceeded()); // 🚩
        
        if (isYes) {
            yesReserve += shareAmount;
            noReserve -= shareReturn;
            userPosition[msg.sender].yesBalance -= shareAmount;
            yesShares -= shareAmount;
        } else {
            noReserve += shareAmount;
            yesReserve -= shareReturn;
            userPosition[msg.sender].noBalance -= shareAmount;
            noShares -= shareAmount;
        }
        
        collateralPool -= shareAmount;
        
        TOKEN.safeTransferFrom(address(this), receiver, returnAmount);
        
        Prices memory newPrices = getCurrentPrices();
        emit Trade(msg.sender, isYes, false, shareAmount, returnAmount, newPrices);
    }

    function resolve(bool _outcome) external {
        require(msg.sender == RESOLVER, Unauthorized());
        require(block.timestamp >= RESOLUTION_TIME, TooEarly());
        require(state == MarketState.CLOSED || state == MarketState.OPEN, MarketAlreadyResolved());
        
        outcome = _outcome;
        state = MarketState.RESOLVED;
        
        emit MarketResolved(_outcome, block.timestamp);
    }

    function invalidate() external {
        require(msg.sender == RESOLVER || msg.sender == CREATOR, Unauthorized());
        // Only invalidate an open/closed market.
        require(state == MarketState.OPEN || state == MarketState.CLOSED, MarketAlreadyResolved());
        
        state = MarketState.INVALID;
        
        emit MarketInvalidated(block.timestamp);
    }

    function claim() external returns (uint256 payout) {
        require(state == MarketState.RESOLVED, MarketNotResolved());
        require(!hasClaimed[msg.sender], AlreadyClaimed());
        
        UserPosition memory position = userPosition[msg.sender];
        uint256 winningShares = outcome ? position.yesBalance : position.noBalance;
        require(winningShares > 0, NoWinnings());
        
        uint256 totalWinningShares = outcome ? yesShares : noShares;
        payout = (winningShares * collateralPool) / totalWinningShares;
        
        hasClaimed[msg.sender] = true;
        
        TOKEN.safeTransfer(msg.sender, payout);
        
        emit WinningsClaimed(msg.sender, payout);
    }

    function claimRefund() external returns (uint256 refund) {
        require(state == MarketState.INVALID, "Market not invalid");
        require(!hasClaimed[msg.sender], AlreadyClaimed());
        
        UserPosition memory position = userPosition[msg.sender];
        uint256 userYes = position.yesBalance;
        uint256 userNo = position.noBalance;
        require(userYes > 0 || userNo > 0, NoWinnings());
        
        uint256 totalUserShares = userYes + userNo;
        uint256 totalShares = yesShares + noShares;
        refund = (totalUserShares * collateralPool) / totalShares;
        
        hasClaimed[msg.sender] = true;
        
        TOKEN.safeTransfer(msg.sender, refund);
        
        emit WinningsClaimed(msg.sender, refund);
    }

    function collectFees() external {
        require(msg.sender == FEE_RECIPIENT, Unauthorized());
        require(accumulatedFees > 0, "No fees");
        
        uint256 fees = accumulatedFees;
        accumulatedFees = 0;
        
        TOKEN.safeTransfer(FEE_RECIPIENT, fees);
        
        emit FeesCollected(FEE_RECIPIENT, fees);
    }

    function getCurrentPrices() public view returns (Prices memory prices) {
        prices.yesPrice = (noReserve * NORMALIZER_DECIMAL) / totalReserve;
        prices.noPrice = (yesReserve * NORMALIZER_DECIMAL) / totalReserve;
    }

    function getBuyQuote(bool isYes, uint256 amount) public view returns (uint256 shares, uint256 newPrice) {
        uint256 tradingAmount = amount - (amount * PLATFORM_FEE_BPS) / 100;
        uint256 normalizedTradingAmount = _normalizeAmountTo18Decimals(tradingAmount);
        shares = _calculateBuyShares(isYes, normalizedTradingAmount);
        
        if (isYes) {
            uint256 newNoReserve = noReserve + normalizedTradingAmount;
            newPrice = (newNoReserve * NORMALIZER_DECIMAL) / totalReserve;
        } else {
            uint256 newYesReserve = yesReserve + normalizedTradingAmount;
            newPrice = (newYesReserve * NORMALIZER_DECIMAL) / totalReserve;
        }
    }

    function getSellQuote(bool isYes, uint256 shareAmount) public  view returns (uint256 returnAmount, uint256 newPrice) {
        returnAmount = _calculateSellReturn(isYes, shareAmount);
        
        if (isYes) {
            uint256 newNoReserve = noReserve - returnAmount;
            newPrice = (newNoReserve * NORMALIZER_DECIMAL) / totalReserve;
        } else {
            uint256 newYesReserve = yesReserve - returnAmount;
            newPrice = (newYesReserve * NORMALIZER_DECIMAL) / totalReserve;
        }
    
        returnAmount = _normalizeAmountToDefaultDecimals(returnAmount);
    }

    function getUserPosition(address user) external view returns (UserPosition memory) {
        return userPosition[user];
    }

    function getMarketInfo() external view
        returns (
            string memory, string memory, address, address,
            uint256, uint256, MarketState, bool, Prices memory,
            uint256,uint256, uint256
        )
    {
        return (
            question,
            description,
            CREATOR,
            RESOLVER,
            END_TIME,
            RESOLUTION_TIME,
            state,
            outcome,
            getCurrentPrices(),
            yesReserve,
            noReserve,
            collateralPool
        );
    }

    function forceClose() external {
        require(block.timestamp >= END_TIME, TooEarly());
        require(state == MarketState.OPEN, "Not open");
        
        state = MarketState.CLOSED;
    }

    function _calculateBuyShares(bool isYes, uint256 normalizedAmount) internal view returns (uint256 shares) {
        if (isYes)
            shares = yesReserve - (product / (noReserve + normalizedAmount));
        else 
            shares = noReserve - (product / (yesReserve + normalizedAmount));
        
        shares = (shares * TRADING_FEE_BPS) / 100;
    }

    function _calculateSellReturn(bool isYes, uint256 shareAmount) internal view returns (uint256 returnAmount) {
        if (isYes)
            returnAmount = noReserve - (product / (yesReserve + shareAmount));
        else 
            returnAmount = yesReserve - (product / (noReserve + shareAmount));
        
        returnAmount = (returnAmount * TRADING_FEE_BPS) / 100;
    }

    function _normalizeAmountTo18Decimals(uint256 amount) internal view returns (uint256 normalizedAmount) {
        normalizedAmount = (amount * 1e18) / (10 ** IERC20Metadata(address(TOKEN)).decimals());
    }

    function _normalizeAmountToDefaultDecimals(uint256 amount) internal view returns (uint256 normalizedAmount) {
        normalizedAmount = (amount * 10 ** IERC20Metadata(address(TOKEN)).decimals()) / 1e18;
    }
}
