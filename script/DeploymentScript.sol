// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PredictionMarketFactory} from "../src/PredictionMarketFactory.sol";


/**
 * @title DeploymentScript
 * @notice Helper script for deploying the prediction market platform
 */
contract DeploymentScript {
    event FactoryDeployed(address indexed factory);
    event MarketDeployed(address indexed market);

    /**
     * @notice Deploy complete platform
     * @param feeRecipient Address to receive platform fees
     * @param platformFeeBps Platform fee in basis points (max 500 = 5%)
     * @return factory Address of deployed factory
     */
    function deployPlatform(
        address feeRecipient,
        uint16 platformFeeBps
    ) public returns (address factory) {
        require(feeRecipient != address(0), "Invalid fee recipient");
        require(platformFeeBps <= 500, "Fee too high");

        // Deploy factory
        PredictionMarketFactory newFactory = new PredictionMarketFactory(
            feeRecipient,
            platformFeeBps
        );

        factory = address(newFactory);
        emit FactoryDeployed(factory);

        return factory;
    }

    /**
     * @notice Deploy platform with initial configuration
     */
    function deployWithConfig(
        address feeRecipient,
        uint16 platformFeeBps,
        uint256 minDuration,
        uint256 maxDuration,
        uint256 minLiquidity,
        address[] memory approvedResolvers
    ) external returns (address factory) {
        // Deploy factory
        factory = deployPlatform(feeRecipient, platformFeeBps);
        
        PredictionMarketFactory factoryContract = PredictionMarketFactory(payable(factory));

        // Set configurations
        factoryContract.setMinMarketDuration(minDuration);
        factoryContract.setMaxMarketDuration(maxDuration);
        factoryContract.setMinInitialLiquidity(minLiquidity);

        // Approve resolvers
        for (uint i = 0; i < approvedResolvers.length; i++) {
            factoryContract.approveResolver(approvedResolvers[i], true);
        }

        return factory;
    }

    /**
     * @notice Create sample markets for testing
     */
    function createSampleMarkets(address factory) external payable {
        PredictionMarketFactory factoryContract = PredictionMarketFactory(payable(factory));

        // Market 1: Crypto price prediction
        address market1 = factoryContract.createBinaryMarket{value: 0.1 ether}(
            "Will ETH reach $5000 by end of 2024?",
            "Market resolves YES if Ethereum price reaches or exceeds $5000 USD by December 31, 2024, 23:59 UTC, according to CoinGecko.",
            "Crypto",
            "Price Predictions",
            msg.sender, // resolver
            block.timestamp + 90 days, // endTime
            block.timestamp + 91 days, // resolutionTime
            0.1 ether // initial liquidity
        );
        emit MarketDeployed(market1);

        // Market 2: Sports outcome
        address market2 = factoryContract.createBinaryMarket{value: 0.1 ether}(
            "Will Team A win the championship?",
            "Market resolves YES if Team A wins the 2024 championship title.",
            "Sports",
            "Basketball",
            msg.sender,
            block.timestamp + 60 days,
            block.timestamp + 61 days,
            0.1 ether
        );
        emit MarketDeployed(market2);

        // Market 3: Tech prediction
        address market3 = factoryContract.createBinaryMarket{value: 0.1 ether}(
            "Will AI model X be released in Q1 2024?",
            "Market resolves YES if the official release happens within Q1 2024 (Jan 1 - Mar 31).",
            "Technology",
            "AI",
            msg.sender,
            block.timestamp + 30 days,
            block.timestamp + 31 days,
            0.1 ether
        );
        emit MarketDeployed(market3);
    }
}

/**
 * @title DeploymentConfig
 * @notice Configuration presets for different networks
 */
library DeploymentConfig {
    struct Config {
        uint16 platformFeeBps;
        uint256 minDuration;
        uint256 maxDuration;
        uint256 minLiquidity;
    }

    function mainnetConfig() internal pure returns (Config memory) {
        return Config({
            platformFeeBps: 50,           // 0.5%
            minDuration: 1 hours,
            maxDuration: 365 days,
            minLiquidity: 0.01 ether
        });
    }

    function testnetConfig() internal pure returns (Config memory) {
        return Config({
            platformFeeBps: 100,          // 1%
            minDuration: 5 minutes,
            maxDuration: 30 days,
            minLiquidity: 0.001 ether
        });
    }

    function devConfig() internal pure returns (Config memory) {
        return Config({
            platformFeeBps: 200,          // 2%
            minDuration: 1 minutes,
            maxDuration: 7 days,
            minLiquidity: 0.0001 ether
        });
    }
}
