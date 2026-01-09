// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPredictionMarket {
    enum MarketState {
        OPEN,        // Trading active
        CLOSED,      // Trading ended, awaiting resolution
        RESOLVED,    // Outcome determined
        INVALID      // Market invalidated
    }

    function buy(bool isYes, uint256 minShares) external payable returns (uint256 shares);
    
    function sell(bool isYes, uint256 shareAmount, uint256 minReturn) 
        external 
        returns (uint256 ethReturn);
    
    function addInitialLiquidity() external payable;
    
    function addLiquidity() external payable returns (uint256 liquidity);
    
    function removeLiquidity(uint256 liquidityAmount) 
        external 
        returns (uint256 yesAmount, uint256 noAmount);
    
    function resolve(bool outcome) external;
    
    function invalidate() external;
    
    function claim() external returns (uint256 payout);
    
    function claimRefund() external returns (uint256 refund);
    
    function getCurrentPrice() external view returns (uint256);
    
    function getBuyQuote(bool isYes, uint256 ethAmount) 
        external 
        view 
        returns (uint256 shares, uint256 newPrice);
    
    function getSellQuote(bool isYes, uint256 shareAmount)
        external
        view
        returns (uint256 ethReturn, uint256 newPrice);
    
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
