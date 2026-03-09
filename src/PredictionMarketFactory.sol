// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPredictionMarketFactory } from "./interfaces/IPredictionMarketFactory.sol";

import { MarketCreationData } from "./utils/Market.sol";
import { PredictionMarket } from "./PredictionMarket.sol";

/**
 * @title PredictionMarketFactory
 * @notice Factory contract for creating and managing prediction markets.
 * @dev Supports multiple market types, categories, and resolution mechanisms.
 */
contract PredictionMarketFactory is IPredictionMarketFactory {
    uint16 public constant MAX_FEE_BPS = 500;

    uint16 public platformFeeBps;
    uint24 public minMarketDuration = 1 hours;
    uint32 public maxMarketDuration = 365 days;
    address public feeRecipient;
    address public owner;

    uint256 public allMarketsLength;

    mapping(address => MarketInfo) public marketInfos;
    mapping(address => bool) public approvedResolvers;

    receive() external payable {}

    modifier onlyOwner() {
        require(msg.sender == owner, Unauthorized());
        _;
    }

    constructor(address _feeRecipient, uint16 _platformFeeBps) {
        require(_feeRecipient != address(0), "Invalid recipient");
        require(_platformFeeBps <= MAX_FEE_BPS, "Fee too high");
        
        owner = msg.sender;
        feeRecipient = _feeRecipient;
        platformFeeBps = _platformFeeBps;
        approvedResolvers[msg.sender] = true;
    }

    /**
     * @notice Create a new binary prediction market
     * @return market Address of the created market
     */
    function createBinaryMarket(MarketCreationData calldata marketCreationData) external returns (address market) {
        _validateMarketParams(marketCreationData);
        market = address(new PredictionMarket(marketCreationData));
        _registerMarket(market, marketCreationData);

        emit MarketCreated(
            market,
            msg.sender,
            resolver,
            question,
            category,
            MarketType.BINARY,
            endTime
        );
    }

    function setPlatformFee(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, InvalidFee());
        
        uint16 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;
        
        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), InvalidRecipient());
        
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    function approveResolver(address resolver) external onlyOwner {
        if (!approvedResolvers[resolver]) {
            approvedResolvers[resolver] = true;
            emit ResolverApproved(resolver);
        }
    }

    function revokeResolver(address resolver) external onlyOwner {
        if (approvedResolvers[resolver]) {
            delete approvedResolvers[resolver];
            emit ResolverRevoked(resolver);
        }
    }

    function setMinMarketDuration(uint256 duration) external onlyOwner {
        minMarketDuration = duration;
    }

    function setMaxMarketDuration(uint256 duration) external onlyOwner {
        maxMarketDuration = duration;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        owner = newOwner;
    }

    function getTotalMarketCount() external view returns (uint256) {
        return allMarketsLength;
    }

    function getMarketInfo(address market) 
        external 
        view 
        returns (MarketCreationData memory) 
    {
        return marketInfos[market];
    }

    function _validateMarketParams(MarketCreationData calldata marketCreationData) internal {
        address resolver = marketCreationData.resolver;
        uint256 duration = marketCreationData.endTime - block.timestamp;
        uint64 marketStartTime = marketCreationData.startTime;
        uint64 marketEndTime = marketCreationData.endTime;

        if (marketStartTime <= block.timestamp) revert BackdatedMarket();
        if (marketEndTime <= marketStartTime || marketEndTime <= block.timestamp) revert InvalidEndTime();
        if (!approvedResolvers[marketCreationData.resolver]) revert ResolverNotApproved();
        if (duration < minMarketDuration || duration > maxMarketDuration) revert InvalidDuration();
    }

    function _registerMarket(address market, MarketCreationData calldata marketCreationData) internal {
        marketInfos[market] = MarketInfo(
            MarketState.PRETRADE,
            marketCreationData,
            block.timestamp,
            0 // Unresolved.
        );

        allMarketsLength++;
    }
}
