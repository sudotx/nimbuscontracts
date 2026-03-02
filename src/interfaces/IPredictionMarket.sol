// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPredictionMarket {
    function buy(bool isYes, uint256 minShares) external returns (uint256 shares);
    function sell(bool isYes, uint256 shareAmount, uint256 minReturn) 
        external
        returns (uint256 shares);
    
    function resolve(bool outcome) external;
    function invalidate() external;
    function claim() external returns (uint256 payout);
    function claimRefund() external returns (uint256 refund);
    
    function getCurrentPrice() external view returns (uint256);

    // Get Quote can handle the buy and sell quotes.
    function getQuote(bool isYes, uint256 amount) external view returns (uint256 shares, uint256 newPrice);
    
    function getUserPosition(address user)
        external
        view
        returns (
            uint256 yes,
            uint256 no,
            uint256 liquidity,
            uint256 potentialWinnings,
            bool claimed
        );
}
