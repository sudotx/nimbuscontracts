// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPredictionMarketFactory {
    enum MarketType {
        BINARY,           // YES/NO
        CATEGORICAL,      // Multiple outcomes
        SCALAR,          // Range-based
        CONDITIONAL      // Depends on another market
    }

    struct MarketInfo {
        address creator;
        address resolver;
        string category;
        string subcategory;
        uint256 createdAt;
        bool isActive;
        MarketType marketType;
    }

    function createBinaryMarket(
        string calldata question,
        string calldata description,
        string calldata category,
        string calldata subcategory,
        address resolver,
        uint256 endTime,
        uint256 resolutionTime,
        uint256 initialLiquidity
    ) external payable returns (address market);

    function getAllMarkets() external view returns (address[] memory);

    function getMarketsByCategory(string calldata category)
        external
        view
        returns (address[] memory);

    function getTotalMarkets() external view returns (uint256);

    function getMarketInfo(address market)
        external
        view
        returns (MarketInfo memory);
}
