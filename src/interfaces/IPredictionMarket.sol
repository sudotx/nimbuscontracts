// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPredictionMarket {
    event FeesCollected(address indexed recipient, uint256 amount);
    event MarketInvalidated(uint256 timestamp);
    event MarketResolved(bool indexed outcome, uint256 timestamp);
    event Trade(
        address indexed trader,
        bool indexed isYes,
        bool indexed isBuy,
        uint256 shares,
        uint256 cost,
        Prices newPrices
    );
    event WinningsClaimed(address indexed user, uint256 amount);

    error AlreadyClaimed();
    error InsufficientLiquidity();
    error InvalidAmount();
    error MarketAlreadyResolved();
    error MarketClosed();
    error MarketNotClosed();
    error MarketNotResolved();
    error NoWinnings();
    error SlippageExceeded();
    error TooEarly();
    error TransferFailed();
    error Unauthorized();

    struct UserPosition {
        uint256 yesBalance;
        uint256 noBalance;
    }

    struct Prices {
        uint256 yesPrice;
        uint256 noPrice;
    }

    function buy(bool isYes, uint256 shareAmount, uint256 minShares) external returns (uint256 shares);
    function sell(
        bool isYes,
        uint256 shareAmount,
        uint256 minReturn, 
        address receiver
    ) external returns (uint256 shares);
    
    function resolve(bool outcome) external;
    function invalidate() external;
    function claim() external returns (uint256 payout);
    function claimRefund() external returns (uint256 refund);
    
    function getCurrentPrices() external view returns (Prices memory prices);

    function getBuyQuote(bool isYes, uint256 amount) external view returns (uint256 shares, uint256 newPrice);
    function getSellQuote(bool isYes, uint256 shareAmount) external view returns (uint256 returnAmount, uint256 newPrice);
    
    function getUserPosition(address user) external view returns (UserPosition memory);
}
