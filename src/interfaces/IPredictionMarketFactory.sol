// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MarketCreationData, MarketType } from "../utils/Market.sol";

interface IPredictionMarketFactory {
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event MarketCreated(
        address indexed marketAddress,
        address indexed creator,
        address indexed resolver,
        string question,
        uint16 category,
        MarketType marketType,
        uint256 endTime
    );
    event PlatformFeeUpdated(uint16 oldFee, uint16 newFee);
    event ResolverApproved(address indexed resolver);
    event ResolverRevoked(address indexed resolver);

    error BackdatedMarket();
    error InvalidEndTime();
    error InvalidDuration();
    error InvalidFee();
    error InvalidRecipient();
    error ResolverNotApproved();
    error Unauthorized();

    function createBinaryMarket(MarketCreationData calldata marketCreationData) external returns (address market);
    function getTotalMarketCount() external view returns (uint256);

    function approveResolver(address resolver) external;
    function revokeResolver(address resolver) external;
    function setMinMarketDuration(uint24 duration) external;
    function setMaxMarketDuration(uint24 duration) external;
    function transferOwnership(address newOwner) external;
}
