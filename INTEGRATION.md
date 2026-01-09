# Integration Guide

## Complete Usage Examples

### 1. Platform Setup

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PredictionMarketFactory.sol";
import "./PredictionMarket.sol";

contract PlatformIntegration {
    PredictionMarketFactory public factory;
    address public admin;
    
    constructor(address _feeRecipient, uint16 _platformFeeBps) {
        admin = msg.sender;
        factory = new PredictionMarketFactory(_feeRecipient, _platformFeeBps);
    }
    
    // Create a sports market
    function createSportsMarket(
        string memory team1,
        string memory team2,
        uint256 matchTime
    ) external payable returns (address) {
        string memory question = string(abi.encodePacked(
            "Will ", team1, " defeat ", team2, "?"
        ));
        
        return factory.createBinaryMarket{value: msg.value}(
            question,
            "Market resolves based on official match result",
            "Sports",
            "Football",
            msg.sender,
            matchTime,
            matchTime + 2 hours,
            msg.value
        );
    }
    
    // Create a price prediction market
    function createPriceMarket(
        string memory asset,
        uint256 targetPrice,
        uint256 deadline
    ) external payable returns (address) {
        string memory question = string(abi.encodePacked(
            "Will ", asset, " reach $", _toString(targetPrice), "?"
        ));
        
        return factory.createBinaryMarket{value: msg.value}(
            question,
            "Market resolves based on CoinGecko price at deadline",
            "Crypto",
            "Price",
            msg.sender,
            deadline,
            deadline + 1 days,
            msg.value
        );
    }
    
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
```

### 2. Trading Bot Integration

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPredictionMarket.sol";

contract TradingBot {
    IPredictionMarket public market;
    address public owner;
    
    uint256 public maxSlippageBps = 100; // 1%
    uint256 public minProfitBps = 50;    // 0.5%
    
    constructor(address _market) {
        market = IPredictionMarket(_market);
        owner = msg.sender;
    }
    
    // Buy when price is favorable
    function buyIfPriceBelow(bool isYes, uint256 maxPrice) 
        external 
        payable 
        onlyOwner 
    {
        uint256 currentPrice = market.getCurrentPrice();
        
        if (isYes) {
            require(currentPrice < maxPrice, "Price too high");
        } else {
            require((10000 - currentPrice) < maxPrice, "Price too high");
        }
        
        // Calculate minimum shares with slippage
        (uint256 expectedShares,) = market.getBuyQuote(isYes, msg.value);
        uint256 minShares = (expectedShares * (10000 - maxSlippageBps)) / 10000;
        
        market.buy{value: msg.value}(isYes, minShares);
    }
    
    // Sell when price is favorable
    function sellIfPriceAbove(bool isYes, uint256 minPrice, uint256 shareAmount) 
        external 
        onlyOwner 
    {
        uint256 currentPrice = market.getCurrentPrice();
        
        if (isYes) {
            require(currentPrice > minPrice, "Price too low");
        } else {
            require((10000 - currentPrice) > minPrice, "Price too low");
        }
        
        // Calculate minimum return with slippage
        (uint256 expectedReturn,) = market.getSellQuote(isYes, shareAmount);
        uint256 minReturn = (expectedReturn * (10000 - maxSlippageBps)) / 10000;
        
        market.sell(isYes, shareAmount, minReturn);
    }
    
    // Arbitrage between buy and sell if spread exists
    function arbitrage(bool isYes, uint256 amount) external payable onlyOwner {
        // Buy shares
        uint256 sharesBought = market.buy{value: msg.value}(isYes, 0);
        
        // Immediately sell
        market.sell(isYes, sharesBought, 0);
        
        // Check profit
        uint256 finalBalance = address(this).balance;
        require(finalBalance > amount, "No profit");
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    receive() external payable {}
}
```

### 3. Liquidity Provider Strategy

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPredictionMarket.sol";

contract LiquidityProvider {
    struct Position {
        address market;
        uint256 liquidity;
        uint256 depositTime;
        uint256 depositAmount;
    }
    
    mapping(address => Position[]) public userPositions;
    
    // Add liquidity to market
    function addLiquidity(address market) external payable {
        IPredictionMarket pm = IPredictionMarket(market);
        
        uint256 liquidityReceived = pm.addLiquidity{value: msg.value}();
        
        userPositions[msg.sender].push(Position({
            market: market,
            liquidity: liquidityReceived,
            depositTime: block.timestamp,
            depositAmount: msg.value
        }));
    }
    
    // Remove liquidity after minimum time
    function removeLiquidity(uint256 positionIndex, uint256 minTimeLocked) 
        external 
    {
        Position storage pos = userPositions[msg.sender][positionIndex];
        require(
            block.timestamp >= pos.depositTime + minTimeLocked,
            "Too early"
        );
        
        IPredictionMarket pm = IPredictionMarket(pos.market);
        pm.removeLiquidity(pos.liquidity);
        
        // Remove position
        uint256 lastIndex = userPositions[msg.sender].length - 1;
        if (positionIndex != lastIndex) {
            userPositions[msg.sender][positionIndex] = 
                userPositions[msg.sender][lastIndex];
        }
        userPositions[msg.sender].pop();
    }
    
    // Calculate total LP value across all positions
    function calculateTotalValue(address user) 
        external 
        view 
        returns (uint256 total) 
    {
        Position[] storage positions = userPositions[user];
        
        for (uint i = 0; i < positions.length; i++) {
            // Approximate value based on reserves
            // In production, you'd want more sophisticated valuation
            total += positions[i].depositAmount;
        }
        
        return total;
    }
    
    receive() external payable {}
}
```

### 4. Frontend Integration (JavaScript)

```javascript
// Web3 Setup
import { ethers } from 'ethers';

const FACTORY_ADDRESS = "0x...";
const FACTORY_ABI = [...];

class PredictionMarketSDK {
    constructor(provider, signer) {
        this.provider = provider;
        this.signer = signer;
        this.factory = new ethers.Contract(
            FACTORY_ADDRESS,
            FACTORY_ABI,
            signer
        );
    }

    // Create market
    async createMarket(params) {
        const {
            question,
            description,
            category,
            subcategory,
            resolver,
            endTime,
            resolutionTime,
            initialLiquidity
        } = params;

        const tx = await this.factory.createBinaryMarket(
            question,
            description,
            category,
            subcategory,
            resolver,
            endTime,
            resolutionTime,
            initialLiquidity,
            { value: ethers.parseEther(initialLiquidity.toString()) }
        );

        const receipt = await tx.wait();
        const event = receipt.logs.find(
            log => log.eventName === 'MarketCreated'
        );
        
        return event.args.marketAddress;
    }

    // Get market contract
    getMarket(address) {
        return new ethers.Contract(address, MARKET_ABI, this.signer);
    }

    // Buy shares
    async buyShares(marketAddress, isYes, ethAmount, maxSlippage = 1) {
        const market = this.getMarket(marketAddress);
        
        // Get quote
        const [expectedShares, newPrice] = await market.getBuyQuote(
            isYes,
            ethers.parseEther(ethAmount.toString())
        );
        
        // Calculate minimum shares (slippage protection)
        const minShares = expectedShares * BigInt(100 - maxSlippage) / 100n;
        
        // Execute trade
        const tx = await market.buy(
            isYes,
            minShares,
            { value: ethers.parseEther(ethAmount.toString()) }
        );
        
        return await tx.wait();
    }

    // Sell shares
    async sellShares(marketAddress, isYes, shareAmount, maxSlippage = 1) {
        const market = this.getMarket(marketAddress);
        
        // Get quote
        const [expectedReturn, newPrice] = await market.getSellQuote(
            isYes,
            ethers.parseEther(shareAmount.toString())
        );
        
        // Calculate minimum return (slippage protection)
        const minReturn = expectedReturn * BigInt(100 - maxSlippage) / 100n;
        
        // Execute trade
        const tx = await market.sell(
            isYes,
            ethers.parseEther(shareAmount.toString()),
            minReturn
        );
        
        return await tx.wait();
    }

    // Get market info
    async getMarketInfo(marketAddress) {
        const market = this.getMarket(marketAddress);
        const info = await market.getMarketInfo();
        
        return {
            question: info.question,
            description: info.description,
            creator: info.creator,
            resolver: info.resolver,
            endTime: Number(info.endTime),
            resolutionTime: Number(info.resolutionTime),
            state: info.state,
            outcome: info.outcome,
            currentPrice: Number(info.currentPrice) / 100, // Convert to %
            yesReserve: ethers.formatEther(info.yesReserve),
            noReserve: ethers.formatEther(info.noReserve),
            totalLiquidity: ethers.formatEther(info.totalLiquidity),
            collateralPool: ethers.formatEther(info.collateralPool)
        };
    }

    // Get user position
    async getUserPosition(marketAddress, userAddress) {
        const market = this.getMarket(marketAddress);
        const position = await market.getUserPosition(userAddress);
        
        return {
            yesShares: ethers.formatEther(position.yes),
            noShares: ethers.formatEther(position.no),
            liquidity: ethers.formatEther(position.liquidity),
            potentialWinnings: ethers.formatEther(position.potentialWinnings),
            hasClaimed: position.claimed
        };
    }

    // Get all markets
    async getAllMarkets() {
        const markets = await this.factory.getAllMarkets();
        
        const marketInfos = await Promise.all(
            markets.map(addr => this.getMarketInfo(addr))
        );
        
        return marketInfos;
    }

    // Filter markets by category
    async getMarketsByCategory(category) {
        const markets = await this.factory.getMarketsByCategory(category);
        
        const marketInfos = await Promise.all(
            markets.map(addr => this.getMarketInfo(addr))
        );
        
        return marketInfos;
    }

    // Claim winnings
    async claimWinnings(marketAddress) {
        const market = this.getMarket(marketAddress);
        const tx = await market.claim();
        return await tx.wait();
    }

    // Listen for trade events
    onTrade(marketAddress, callback) {
        const market = this.getMarket(marketAddress);
        
        market.on("Trade", (trader, isYes, isBuy, shares, cost, newPrice) => {
            callback({
                trader,
                isYes,
                isBuy,
                shares: ethers.formatEther(shares),
                cost: ethers.formatEther(cost),
                newPrice: Number(newPrice) / 100
            });
        });
    }
}

// Usage example
async function example() {
    const provider = new ethers.BrowserProvider(window.ethereum);
    const signer = await provider.getSigner();
    const sdk = new PredictionMarketSDK(provider, signer);

    // Create market
    const marketAddress = await sdk.createMarket({
        question: "Will ETH reach $5000?",
        description: "Market resolves YES if...",
        category: "Crypto",
        subcategory: "Price",
        resolver: await signer.getAddress(),
        endTime: Math.floor(Date.now() / 1000) + 86400 * 30,
        resolutionTime: Math.floor(Date.now() / 1000) + 86400 * 31,
        initialLiquidity: 0.1
    });

    console.log("Market created:", marketAddress);

    // Buy YES shares
    await sdk.buyShares(marketAddress, true, 0.1, 1);

    // Get current info
    const info = await sdk.getMarketInfo(marketAddress);
    console.log("Current price:", info.currentPrice, "%");

    // Listen for trades
    sdk.onTrade(marketAddress, (event) => {
        console.log("Trade:", event);
    });
}
```

### 5. Testing Script

```javascript
// test/PredictionMarket.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PredictionMarket", function() {
    let factory, market;
    let owner, resolver, trader1, trader2;

    beforeEach(async function() {
        [owner, resolver, trader1, trader2] = await ethers.getSigners();

        // Deploy factory
        const Factory = await ethers.getContractFactory("PredictionMarketFactory");
        factory = await Factory.deploy(owner.address, 50);

        // Create market
        const tx = await factory.createBinaryMarket(
            "Test question?",
            "Test description",
            "Test",
            "Test",
            resolver.address,
            Math.floor(Date.now() / 1000) + 86400,
            Math.floor(Date.now() / 1000) + 86400 * 2,
            ethers.parseEther("0.1"),
            { value: ethers.parseEther("0.1") }
        );

        const receipt = await tx.wait();
        const event = receipt.logs.find(e => e.fragment.name === "MarketCreated");
        const marketAddress = event.args[0];

        market = await ethers.getContractAt("PredictionMarket", marketAddress);
    });

    it("Should create market correctly", async function() {
        const question = await market.question();
        expect(question).to.equal("Test question?");
    });

    it("Should allow buying YES shares", async function() {
        await market.connect(trader1).buy(
            true,
            0,
            { value: ethers.parseEther("0.1") }
        );

        const balance = await market.yesBalanceOf(trader1.address);
        expect(balance).to.be.gt(0);
    });

    it("Should allow selling shares", async function() {
        // Buy first
        await market.connect(trader1).buy(
            true,
            0,
            { value: ethers.parseEther("0.1") }
        );

        const sharesBought = await market.yesBalanceOf(trader1.address);

        // Sell
        await market.connect(trader1).sell(true, sharesBought, 0);

        const balanceAfter = await market.yesBalanceOf(trader1.address);
        expect(balanceAfter).to.equal(0);
    });

    it("Should resolve and allow claims", async function() {
        // Trader buys YES
        await market.connect(trader1).buy(
            true,
            0,
            { value: ethers.parseEther("0.1") }
        );

        // Fast forward time
        await ethers.provider.send("evm_increaseTime", [86400 * 2]);
        await ethers.provider.send("evm_mine");

        // Resolve
        await market.connect(resolver).resolve(true);

        // Claim
        const balanceBefore = await ethers.provider.getBalance(trader1.address);
        await market.connect(trader1).claim();
        const balanceAfter = await ethers.provider.getBalance(trader1.address);

        expect(balanceAfter).to.be.gt(balanceBefore);
    });
});
```

This integration guide covers all major use cases for the prediction market platform!
