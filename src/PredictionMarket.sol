// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPredictionMarket} from "./interfaces/IPredictionMarket.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {MathLib} from "./libraries/MathLib.sol";

/**
 * @title PredictionMarket
 * @notice Individual binary prediction market with AMM-based trading
 * @dev Uses constant product AMM for price discovery and liquidity
 */
contract PredictionMarket is IPredictionMarket, ReentrancyGuard {
    using MathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Market question
    string public question;
    
    /// @notice Detailed description
    string public description;
    
    /// @notice Market creator
    address public immutable CREATOR;
    
    /// @notice Market resolver
    address public immutable RESOLVER;
    
    /// @notice When trading closes
    uint256 public immutable END_TIME;
    
    /// @notice When market can be resolved
    uint256 public immutable RESOLUTION_TIME;
    
    /// @notice Platform fee in basis points
    uint16 public immutable PLATFORM_FEE_BPS;
    
    /// @notice Platform fee recipient
    address public immutable FEE_RECIPIENT;
    
    /// @notice Trading fee in basis points (0.3%)
    uint16 public constant TRADING_FEE_BPS = 30;
    
    /// @notice Market state
    MarketState public state;
    
    /// @notice Market outcome (true = YES, false = NO)
    bool public outcome;
    
    /// @notice Total YES shares
    uint256 public yesShares;
    
    /// @notice Total NO shares
    uint256 public noShares;
    
    /// @notice Collateral pool (ETH)
    uint256 public collateralPool;
    
    /// @notice YES reserve in AMM
    uint256 public yesReserve;
    
    /// @notice NO reserve in AMM
    uint256 public noReserve;
    
    /// @notice User YES balances
    mapping(address => uint256) public yesBalanceOf;
    
    /// @notice User NO balances
    mapping(address => uint256) public noBalanceOf;
    
    /// @notice LP token balances
    mapping(address => uint256) public liquidityBalanceOf;
    
    /// @notice Total LP tokens
    uint256 public totalLiquidity;
    
    /// @notice Has user claimed winnings
    mapping(address => bool) public hasClaimed;
    
    /// @notice Accumulated platform fees
    uint256 public accumulatedFees;


    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Trade(
        address indexed trader,
        bool indexed isYes,
        bool indexed isBuy,
        uint256 shares,
        uint256 cost,
        uint256 newPrice
    );

    event LiquidityAdded(
        address indexed provider,
        uint256 yesAmount,
        uint256 noAmount,
        uint256 liquidity
    );

    event LiquidityRemoved(
        address indexed provider,
        uint256 yesAmount,
        uint256 noAmount,
        uint256 liquidity
    );

    event MarketResolved(bool indexed outcome, uint256 timestamp);
    event MarketInvalidated(uint256 timestamp);
    event WinningsClaimed(address indexed user, uint256 amount);
    event FeesCollected(address indexed recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error MarketClosed();
    error MarketNotClosed();
    error MarketAlreadyResolved();
    error MarketNotResolved();
    error Unauthorized();
    error InvalidAmount();
    error InsufficientLiquidity();
    error SlippageExceeded();
    error TooEarly();
    error AlreadyClaimed();
    error NoWinnings();
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _question,
        string memory _description,
        address _creator,
        address _resolver,
        uint256 _endTime,
        uint256 _resolutionTime,
        uint16 _platformFeeBps,
        address _feeRecipient
    ) {
        require(_endTime > block.timestamp, "Invalid end time");
        require(_resolutionTime > _endTime, "Invalid resolution time");
        require(_creator != address(0), "Invalid creator");
        require(_resolver != address(0), "Invalid resolver");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        question = _question;
        description = _description;
        CREATOR = _creator;
        RESOLVER = _resolver;
        END_TIME = _endTime;
        RESOLUTION_TIME = _resolutionTime;
        PLATFORM_FEE_BPS = _platformFeeBps;
        FEE_RECIPIENT = _feeRecipient;
        state = MarketState.OPEN;
    }

    /*//////////////////////////////////////////////////////////////
                            TRADING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Buy YES or NO shares
     * @param isYes True to buy YES, false to buy NO
     * @param minShares Minimum shares to receive (slippage protection)
     */
    function buy(bool isYes, uint256 minShares) 
        external 
        payable 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(state == MarketState.OPEN, MarketClosed());
        require(block.timestamp < END_TIME, MarketClosed());
        require(msg.value > 0, InvalidAmount());
        require(yesReserve > 0 && noReserve > 0, InsufficientLiquidity());
        
        // Calculate platform fee
        uint256 platformFee = (msg.value * PLATFORM_FEE_BPS) / 10000;
        uint256 tradingAmount = msg.value - platformFee;
        accumulatedFees += platformFee;
        
        // Calculate shares received
        shares = _calculateBuyShares(isYes, tradingAmount);
        require(shares >= minShares, SlippageExceeded());
        
        // Update reserves
        if (isYes) {
            yesReserve -= shares;
            noReserve += tradingAmount;
            yesBalanceOf[msg.sender] += shares;
            yesShares += shares;
        } else {
            noReserve -= shares;
            yesReserve += tradingAmount;
            noBalanceOf[msg.sender] += shares;
            noShares += shares;
        }
        
        collateralPool += tradingAmount;
        
        uint256 newPrice = getCurrentPrice();
        emit Trade(msg.sender, isYes, true, shares, msg.value, newPrice);
        
        return shares;
    }

    /**
     * @notice Sell YES or NO shares
     * @param isYes True to sell YES, false to sell NO
     * @param shareAmount Amount of shares to sell
     * @param minReturn Minimum ETH to receive (slippage protection)
     */
    function sell(bool isYes, uint256 shareAmount, uint256 minReturn)
        external
        nonReentrant
        returns (uint256 ethReturn)
    {
        require(state == MarketState.OPEN, MarketClosed());
        require(block.timestamp < END_TIME, MarketClosed());
        require(shareAmount > 0, InvalidAmount());
        
        // Check balance
        uint256 userBalance = isYes ? yesBalanceOf[msg.sender] : noBalanceOf[msg.sender];
        require(userBalance >= shareAmount, "Insufficient shares");
        
        // Calculate ETH return
        ethReturn = _calculateSellReturn(isYes, shareAmount);
        require(ethReturn >= minReturn, SlippageExceeded());
        
        // Update reserves
        if (isYes) {
            yesReserve += shareAmount;
            noReserve -= ethReturn;
            yesBalanceOf[msg.sender] -= shareAmount;
            yesShares -= shareAmount;
        } else {
            noReserve += shareAmount;
            yesReserve -= ethReturn;
            noBalanceOf[msg.sender] -= shareAmount;
            noShares -= shareAmount;
        }
        
        collateralPool -= ethReturn;
        
        // Transfer ETH
        (bool success, ) = msg.sender.call{value: ethReturn}("");
        require(success, TransferFailed());
        
        uint256 newPrice = getCurrentPrice();
        emit Trade(msg.sender, isYes, false, shareAmount, ethReturn, newPrice);
        
        return ethReturn;
    }

    /*//////////////////////////////////////////////////////////////
                          LIQUIDITY PROVISION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add initial liquidity (creates 50/50 pool)
     */
    function addInitialLiquidity() external payable nonReentrant {
        require(msg.sender == CREATOR, Unauthorized());
        require(yesReserve == 0 && noReserve == 0, "Already initialized");
        require(msg.value > 0, InvalidAmount());
        
        // Create 50/50 pool
        uint256 halfValue = msg.value / 2;
        yesReserve = halfValue;
        noReserve = halfValue;
        
        // Mint LP tokens (using geometric mean)
        uint256 liquidity = MathLib.sqrt(halfValue * halfValue);
        totalLiquidity = liquidity;
        liquidityBalanceOf[msg.sender] = liquidity;
        
        collateralPool = msg.value;
        
        emit LiquidityAdded(msg.sender, halfValue, halfValue, liquidity);
    }

    /**
     * @notice Add liquidity to existing pool
     */
    function addLiquidity() 
        external 
        payable 
        nonReentrant 
        returns (uint256 liquidity) 
    {
        require(state == MarketState.OPEN, MarketClosed());
        require(msg.value > 0, InvalidAmount());
        require(yesReserve > 0 && noReserve > 0, "Not initialized");
        
        // Calculate proportional amounts
        uint256 totalReserve = yesReserve + noReserve;
        uint256 yesAmount = (msg.value * yesReserve) / totalReserve;
        uint256 noAmount = msg.value - yesAmount;
        
        // Mint LP tokens proportionally
        liquidity = (msg.value * totalLiquidity) / totalReserve;
        
        yesReserve += yesAmount;
        noReserve += noAmount;
        totalLiquidity += liquidity;
        liquidityBalanceOf[msg.sender] += liquidity;
        collateralPool += msg.value;
        
        emit LiquidityAdded(msg.sender, yesAmount, noAmount, liquidity);
        
        return liquidity;
    }

    /**
     * @notice Remove liquidity from pool
     * @param liquidityAmount Amount of LP tokens to burn
     */
    function removeLiquidity(uint256 liquidityAmount)
        external
        nonReentrant
        returns (uint256 yesAmount, uint256 noAmount)
    {
        require(liquidityAmount > 0, InvalidAmount());
        require(liquidityBalanceOf[msg.sender] >= liquidityAmount, "Insufficient liquidity");
        require(state != MarketState.RESOLVED, "Market resolved");
        
        // Calculate proportional amounts
        yesAmount = (liquidityAmount * yesReserve) / totalLiquidity;
        noAmount = (liquidityAmount * noReserve) / totalLiquidity;
        
        // Burn LP tokens
        liquidityBalanceOf[msg.sender] -= liquidityAmount;
        totalLiquidity -= liquidityAmount;
        
        yesReserve -= yesAmount;
        noReserve -= noAmount;
        
        uint256 ethReturn = yesAmount + noAmount;
        collateralPool -= ethReturn;
        
        // Transfer ETH
        (bool success, ) = msg.sender.call{value: ethReturn}("");
        require(success, TransferFailed());
        
        emit LiquidityRemoved(msg.sender, yesAmount, noAmount, liquidityAmount);
        
        return (yesAmount, noAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            RESOLUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Resolve market with outcome
     * @param _outcome True for YES, false for NO
     */
    function resolve(bool _outcome) external nonReentrant {
        require(msg.sender == RESOLVER, Unauthorized());
        require(block.timestamp >= RESOLUTION_TIME, TooEarly());
        require(state == MarketState.CLOSED || state == MarketState.OPEN, 
            MarketAlreadyResolved());
        
        outcome = _outcome;
        state = MarketState.RESOLVED;
        
        emit MarketResolved(_outcome, block.timestamp);
    }

    /**
     * @notice Invalidate market (refund all participants)
     */
    function invalidate() external nonReentrant {
        require(msg.sender == RESOLVER || msg.sender == CREATOR, Unauthorized());
        require(state != MarketState.RESOLVED, MarketAlreadyResolved());
        
        state = MarketState.INVALID;
        
        emit MarketInvalidated(block.timestamp);
    }

    /**
     * @notice Claim winnings after resolution
     */
    function claim() external nonReentrant returns (uint256 payout) {
        require(state == MarketState.RESOLVED, MarketNotResolved());
        require(!hasClaimed[msg.sender], AlreadyClaimed());
        
        uint256 winningShares = outcome ? yesBalanceOf[msg.sender] : noBalanceOf[msg.sender];
        require(winningShares > 0, NoWinnings());
        
        // Calculate payout proportionally
        uint256 totalWinningShares = outcome ? yesShares : noShares;
        payout = (winningShares * collateralPool) / totalWinningShares;
        
        hasClaimed[msg.sender] = true;
        
        // Transfer winnings
        (bool success, ) = msg.sender.call{value: payout}("");
        require(success, TransferFailed());
        
        emit WinningsClaimed(msg.sender, payout);
        
        return payout;
    }

    /**
     * @notice Claim refund if market invalidated
     */
    function claimRefund() external nonReentrant returns (uint256 refund) {
        require(state == MarketState.INVALID, "Market not invalid");
        require(!hasClaimed[msg.sender], AlreadyClaimed());
        
        uint256 userYes = yesBalanceOf[msg.sender];
        uint256 userNo = noBalanceOf[msg.sender];
        require(userYes > 0 || userNo > 0, NoWinnings());
        
        // Proportional refund based on total shares held
        uint256 totalUserShares = userYes + userNo;
        uint256 totalShares = yesShares + noShares;
        refund = (totalUserShares * collateralPool) / totalShares;
        
        hasClaimed[msg.sender] = true;
        
        // Transfer refund
        (bool success, ) = msg.sender.call{value: refund}("");
        require(success, TransferFailed());
        
        emit WinningsClaimed(msg.sender, refund);
        
        return refund;
    }

    /**
     * @notice Collect accumulated platform fees
     */
    function collectFees() external nonReentrant {
        require(msg.sender == FEE_RECIPIENT, Unauthorized());
        require(accumulatedFees > 0, "No fees");
        
        uint256 fees = accumulatedFees;
        accumulatedFees = 0;
        
        (bool success, ) = FEE_RECIPIENT.call{value: fees}("");
        require(success, TransferFailed());
        
        emit FeesCollected(FEE_RECIPIENT, fees);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current YES price (in basis points, 10000 = 100%)
     */
    function getCurrentPrice() public view returns (uint256) {
        if (yesReserve == 0 || noReserve == 0) return 5000; // 50%
        
        uint256 totalReserve = yesReserve + noReserve;
        return (noReserve * 10000) / totalReserve;
    }

    /**
     * @notice Get quote for buying shares
     */
    function getBuyQuote(bool isYes, uint256 ethAmount) 
        external 
        view 
        returns (uint256 shares, uint256 newPrice) 
    {
        if (yesReserve == 0 || noReserve == 0) {
            return (0, 5000);
        }
        
        uint256 tradingAmount = ethAmount - (ethAmount * PLATFORM_FEE_BPS) / 10000;
        shares = _calculateBuyShares(isYes, tradingAmount);
        
        // Calculate new price after trade
        if (isYes) {
            uint256 newYesReserve = yesReserve - shares;
            uint256 newNoReserve = noReserve + tradingAmount;
            newPrice = (newNoReserve * 10000) / (newYesReserve + newNoReserve);
        } else {
            uint256 newYesReserve = yesReserve + tradingAmount;
            uint256 newNoReserve = noReserve - shares;
            newPrice = (newNoReserve * 10000) / (newYesReserve + newNoReserve);
        }
        
        return (shares, newPrice);
    }

    /**
     * @notice Get quote for selling shares
     */
    function getSellQuote(bool isYes, uint256 shareAmount)
        external
        view
        returns (uint256 ethReturn, uint256 newPrice)
    {
        if (yesReserve == 0 || noReserve == 0) {
            return (0, 5000);
        }
        
        ethReturn = _calculateSellReturn(isYes, shareAmount);
        
        // Calculate new price after trade
        if (isYes) {
            uint256 newYesReserve = yesReserve + shareAmount;
            uint256 newNoReserve = noReserve - ethReturn;
            newPrice = (newNoReserve * 10000) / (newYesReserve + newNoReserve);
        } else {
            uint256 newYesReserve = yesReserve - ethReturn;
            uint256 newNoReserve = noReserve + shareAmount;
            newPrice = (newNoReserve * 10000) / (newYesReserve + newNoReserve);
        }
        
        return (ethReturn, newPrice);
    }

    /**
     * @notice Get user position
     */
    function getUserPosition(address user)
        external
        view
        returns (
            uint256 yes,
            uint256 no,
            uint256 liquidity,
            uint256 potentialWinnings,
            bool claimed
        )
    {
        yes = yesBalanceOf[user];
        no = noBalanceOf[user];
        liquidity = liquidityBalanceOf[user];
        claimed = hasClaimed[user];
        
        if (state == MarketState.RESOLVED && !claimed) {
            uint256 winningShares = outcome ? yes : no;
            if (winningShares > 0) {
                uint256 totalWinningShares = outcome ? yesShares : noShares;
                potentialWinnings = (winningShares * collateralPool) / totalWinningShares;
            }
        }
        
        return (yes, no, liquidity, potentialWinnings, claimed);
    }

    /**
     * @notice Get market info
     */
    function getMarketInfo()
        external
        view
        returns (
            string memory _question,
            string memory _description,
            address _creator,
            address _resolver,
            uint256 _endTime,
            uint256 _resolutionTime,
            MarketState _state,
            bool _outcome,
            uint256 currentPrice,
            uint256 _yesReserve,
            uint256 _noReserve,
            uint256 _totalLiquidity,
            uint256 _collateralPool
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
            getCurrentPrice(),
            yesReserve,
            noReserve,
            totalLiquidity,
            collateralPool
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _calculateBuyShares(bool isYes, uint256 ethAmount)
        internal
        view
        returns (uint256 shares)
    {
        // Constant product formula: x * y = k
        // shares = reserveOut - (k / (reserveIn + ethAmount))
        
        uint256 k = yesReserve * noReserve;
        
        if (isYes) {
            uint256 newNoReserve = noReserve + ethAmount;
            uint256 newYesReserve = k / newNoReserve;
            shares = yesReserve - newYesReserve;
            
            // Apply trading fee
            shares = (shares * (10000 - TRADING_FEE_BPS)) / 10000;
        } else {
            uint256 newYesReserve = yesReserve + ethAmount;
            uint256 newNoReserve = k / newYesReserve;
            shares = noReserve - newNoReserve;
            
            // Apply trading fee
            shares = (shares * (10000 - TRADING_FEE_BPS)) / 10000;
        }
        
        return shares;
    }

    function _calculateSellReturn(bool isYes, uint256 shareAmount)
        internal
        view
        returns (uint256 ethReturn)
    {
        // Constant product formula: x * y = k
        // ethReturn = reserveIn - (k / (reserveOut + shareAmount))
        
        uint256 k = yesReserve * noReserve;
        
        if (isYes) {
            uint256 newYesReserve = yesReserve + shareAmount;
            uint256 newNoReserve = k / newYesReserve;
            ethReturn = noReserve - newNoReserve;
        } else {
            uint256 newNoReserve = noReserve + shareAmount;
            uint256 newYesReserve = k / newNoReserve;
            ethReturn = yesReserve - newYesReserve;
        }
        
        // Apply trading fee
        ethReturn = (ethReturn * (10000 - TRADING_FEE_BPS)) / 10000;
        
        return ethReturn;
    }

    /**
     * @notice Force close market if past end time
     */
    function forceClose() external {
        require(block.timestamp >= END_TIME, TooEarly());
        require(state == MarketState.OPEN, "Not open");
        
        state = MarketState.CLOSED;
    }

    receive() external payable {}
}
