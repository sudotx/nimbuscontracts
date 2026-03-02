// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MarketInfo } from "../utils/Market.sol";

interface IPredictionMarketFactory {
    function createBinaryMarket(MarketInfo calldata marketInfo) external returns (address market);
    function getTotalMarketCount() external view returns (uint256);
    function getMarketInfo(address market) external view returns (MarketInfo memory);
}
