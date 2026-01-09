# Prediction Market Platform

A decentralized prediction market platform built on Ethereum, enabling users to create and trade on binary outcome markets with automated market maker (AMM) liquidity.

## 🎯 Overview

This platform allows anyone to:
- **Create Markets**: Launch prediction markets on any binary outcome event
- **Trade Shares**: Buy/sell YES/NO shares with automated pricing
- **Provide Liquidity**: Earn fees by providing liquidity to markets
- **Resolve Markets**: Designated resolvers determine outcomes
- **Claim Winnings**: Winners claim proportional payouts from the collateral pool

## 🏗️ Architecture

### Core Contracts

1. **PredictionMarketFactory.sol**
   - Central factory for creating markets
   - Market registry and categorization
   - Template management
   - Resolver approval system
   - Platform fee collection

2. **PredictionMarket.sol**
   - Individual market contract
   - AMM-based trading (constant product formula)
   - Liquidity provision
   - Market resolution and payouts
   - State management

3. **Supporting Libraries**
   - `MathLib.sol`: Mathematical operations
   - `ReentrancyGuard.sol`: Reentrancy protection

## 📋 Features

### Market Creation
- **Flexible Parameters**: Set question, description, duration, resolution time
- **Categories**: Organize markets by category and subcategory
- **Templates**: Use predefined templates for common market types
- **Resolver System**: Approved resolvers ensure accurate outcomes
- **Initial Liquidity**: Optional liquidity seeding at creation

### Trading
- **AMM Pricing**: Constant product market maker (x * y = k)
- **Slippage Protection**: Set minimum shares/returns
- **Real-time Quotes**: Get price impact before trading
- **Fee Structure**:
  - Trading fee: 0.3%
  - Platform fee: Configurable (max 5%)

### Liquidity Provision
- **Add Liquidity**: Provide balanced liquidity to earn fees
- **Remove Liquidity**: Withdraw proportional reserves
- **LP Tokens**: Represent pool ownership
- **Fee Earnings**: Earn from trading fees

### Resolution & Claims
- **Resolver-based**: Designated resolver determines outcome
- **Invalidation**: Markets can be invalidated for refunds
- **Proportional Payouts**: Winners split collateral pool
- **Single Claim**: One-time claim after resolution

## 🚀 Getting Started

### Installation

```bash
# Clone repository
git clone <repo-url>
cd prediction-market-platform

# Install dependencies
npm install
# or
forge install
```

### Deployment

1. **Deploy Factory**
```solidity
// Deploy factory with fee settings
PredictionMarketFactory factory = new PredictionMarketFactory(
    feeRecipient,    // Address to receive platform fees
    50               // Platform fee in bps (50 = 0.5%)
);
```

2. **Create Market**
```solidity
// Create a binary prediction market
address market = factory.createBinaryMarket(
    "Will ETH reach $5000 by end of 2024?",  // question
    "Market resolves YES if ETH price...",    // description
    "Crypto",                                  // category
    "Price Predictions",                       // subcategory
    resolverAddress,                           // resolver
    endTime,                                   // trading end time
    resolutionTime,                            // resolution time
    0.1 ether                                  // initial liquidity
);
```

### Trading

```solidity
// Buy YES shares
PredictionMarket(market).buy{value: 1 ether}(
    true,      // isYes = true
    0          // minShares (slippage protection)
);

// Sell YES shares
PredictionMarket(market).sell(
    true,        // isYes = true
    100 ether,   // shareAmount
    0.5 ether    // minReturn (slippage protection)
);
```

### Liquidity Provision

```solidity
// Add initial liquidity (creator only)
PredictionMarket(market).addInitialLiquidity{value: 1 ether}();

// Add more liquidity (anyone)
PredictionMarket(market).addLiquidity{value: 0.5 ether}();

// Remove liquidity
PredictionMarket(market).removeLiquidity(
    liquidityAmount  // LP tokens to burn
);
```

### Resolution

```solidity
// Resolve market (resolver only)
PredictionMarket(market).resolve(
    true  // outcome: true = YES, false = NO
);

// Claim winnings
PredictionMarket(market).claim();
```

## 📊 Market States

1. **OPEN**: Active trading
2. **CLOSED**: Trading ended, awaiting resolution
3. **RESOLVED**: Outcome determined, claims available
4. **INVALID**: Market invalidated, refunds available

## 💰 Economics

### Pricing Formula
Uses constant product AMM: `x * y = k`

- **YES price** = `NO_reserve / (YES_reserve + NO_reserve)`
- **NO price** = `YES_reserve / (YES_reserve + NO_reserve)`

### Fees
- **Trading Fee**: 0.3% (stays in pool for LPs)
- **Platform Fee**: Configurable, max 5% (goes to platform)

### Payouts
Winners receive proportional share of collateral pool:
```
payout = (user_winning_shares / total_winning_shares) * collateral_pool
```

## 🔒 Security Features

- **Reentrancy Protection**: All external calls protected
- **Access Control**: Resolver-only resolution, creator privileges
- **Slippage Protection**: Min/max limits on trades
- **State Validation**: Proper state transitions enforced
- **Integer Overflow**: Solidity 0.8+ built-in protection

## 🛠️ Advanced Features

### Templates
Pre-configured market types:
- Sports matches
- Price predictions
- Event outcomes
- Custom templates

### Categories
Organize markets by:
- Main category (e.g., "Sports", "Politics", "Crypto")
- Subcategory (e.g., "Football", "US Elections", "DeFi")

### Resolver System
- Approved resolver list
- Creator can be resolver
- Multiple markets per resolver

### Query Functions
- Get all markets
- Filter by category
- Filter by creator/resolver
- Pagination support
- User position tracking

## 📈 View Functions

### Market Info
```solidity
function getMarketInfo() external view returns (
    string memory question,
    string memory description,
    address creator,
    address resolver,
    uint256 endTime,
    uint256 resolutionTime,
    MarketState state,
    bool outcome,
    uint256 currentPrice,
    uint256 yesReserve,
    uint256 noReserve,
    uint256 totalLiquidity,
    uint256 collateralPool
);
```

### Trading Quotes
```solidity
// Get buy quote
function getBuyQuote(bool isYes, uint256 ethAmount) 
    external view returns (uint256 shares, uint256 newPrice);

// Get sell quote
function getSellQuote(bool isYes, uint256 shareAmount)
    external view returns (uint256 ethReturn, uint256 newPrice);
```

### User Position
```solidity
function getUserPosition(address user) external view returns (
    uint256 yesShares,
    uint256 noShares,
    uint256 liquidity,
    uint256 potentialWinnings,
    bool hasClaimed
);
```

## 🧪 Testing

```bash
# Run tests
forge test

# Run with gas report
forge test --gas-report

# Run specific test
forge test --match-test testMarketCreation
```

## 📝 Example Use Cases

### Sports Betting
```solidity
createBinaryMarket(
    "Will Team A win the championship?",
    "Resolves YES if Team A wins...",
    "Sports",
    "Basketball",
    oracleResolver,
    gameEndTime,
    gameEndTime + 1 hours,
    1 ether
);
```

### Price Predictions
```solidity
createBinaryMarket(
    "Will BTC exceed $100k in 2024?",
    "Resolves YES if Bitcoin price...",
    "Crypto",
    "Price",
    priceOracleResolver,
    block.timestamp + 365 days,
    block.timestamp + 366 days,
    5 ether
);
```

### Event Outcomes
```solidity
createBinaryMarket(
    "Will the proposal pass?",
    "DAO governance proposal XYZ...",
    "Governance",
    "DAO Proposals",
    governanceResolver,
    voteEndTime,
    voteEndTime + 1 days,
    0.5 ether
);
```

## 🎨 Frontend Integration

### Web3 Setup
```javascript
import { ethers } from 'ethers';

const factoryAddress = "0x...";
const factoryABI = [...];

const factory = new ethers.Contract(
    factoryAddress, 
    factoryABI, 
    signer
);
```

### Create Market
```javascript
const tx = await factory.createBinaryMarket(
    question,
    description,
    category,
    subcategory,
    resolver,
    endTime,
    resolutionTime,
    initialLiquidity,
    { value: ethers.parseEther("0.1") }
);
```

### Trade
```javascript
const market = new ethers.Contract(marketAddress, marketABI, signer);

// Get quote
const [shares, newPrice] = await market.getBuyQuote(true, ethAmount);

// Execute trade
const tx = await market.buy(true, minShares, { value: ethAmount });
```

## 🔮 Future Enhancements

- [ ] Categorical markets (multiple outcomes)
- [ ] Scalar markets (range predictions)
- [ ] Conditional markets (dependent outcomes)
- [ ] Oracle integrations (Chainlink, UMA)
- [ ] Advanced AMM curves (LMSR, logarithmic)
- [ ] Market maker incentives
- [ ] Reputation system for resolvers
- [ ] Automated market resolution
- [ ] Cross-chain markets
- [ ] NFT-based outcomes

## 📄 License

MIT License

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create feature branch
3. Add tests
4. Submit pull request

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Not financial advice.

## 📞 Support

- Issues: GitHub Issues
- Docs: [Full Documentation]
- Community: [Discord/Telegram]
