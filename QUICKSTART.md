# Quick Start Guide

## 🚀 5-Minute Setup

### Prerequisites
- Solidity ^0.8.20
- Hardhat or Foundry
- Node.js & npm

### Installation

```bash
# Install dependencies
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox

# Or with Foundry
forge install
```

### Deploy in 3 Steps

#### Step 1: Deploy Factory
```solidity
// scripts/deploy.js
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    
    const Factory = await ethers.getContractFactory("PredictionMarketFactory");
    const factory = await Factory.deploy(
        deployer.address,  // fee recipient
        50                 // 0.5% platform fee
    );
    
    await factory.waitForDeployment();
    console.log("Factory:", await factory.getAddress());
}

main();
```

#### Step 2: Create Market
```javascript
const factory = await ethers.getContractAt("PredictionMarketFactory", factoryAddress);

const tx = await factory.createBinaryMarket(
    "Will ETH reach $5000 by end of 2024?",
    "Resolves YES if ETH >= $5000 on Dec 31, 2024",
    "Crypto",
    "Price",
    resolverAddress,
    Math.floor(Date.now() / 1000) + 86400 * 30,  // 30 days
    Math.floor(Date.now() / 1000) + 86400 * 31,  // 31 days
    ethers.parseEther("0.1"),
    { value: ethers.parseEther("0.1") }
);

const receipt = await tx.wait();
const marketAddress = receipt.logs[0].args[0];
console.log("Market:", marketAddress);
```

#### Step 3: Trade
```javascript
const market = await ethers.getContractAt("PredictionMarket", marketAddress);

// Buy YES shares
await market.buy(
    true,                      // isYes
    0,                         // minShares (no slippage limit)
    { value: ethers.parseEther("0.1") }
);

// Check price
const price = await market.getCurrentPrice();
console.log("YES price:", price / 100, "%");
```

## 📱 Common Operations

### Create Market
```javascript
const market = await factory.createBinaryMarket(
    question,          // "Will X happen?"
    description,       // Detailed rules
    category,          // "Sports" | "Crypto" | etc
    subcategory,       // "Football" | "DeFi" | etc
    resolver,          // Who decides outcome
    endTime,           // When trading stops
    resolutionTime,    // When resolver can decide
    initialLiquidity,  // Starting pool size
    { value: ethAmount }
);
```

### Buy Shares
```javascript
// Get quote first
const [shares, newPrice] = await market.getBuyQuote(
    true,                         // YES
    ethers.parseEther("1.0")     // 1 ETH
);

// Execute trade
await market.buy(
    true,                         // YES
    shares * 99n / 100n,         // Accept 1% slippage
    { value: ethers.parseEther("1.0") }
);
```

### Sell Shares
```javascript
// Get quote
const [ethReturn, newPrice] = await market.getSellQuote(
    true,                         // YES
    ethers.parseEther("10.0")    // 10 shares
);

// Execute trade
await market.sell(
    true,                         // YES
    ethers.parseEther("10.0"),   // 10 shares
    ethReturn * 99n / 100n       // Accept 1% slippage
);
```

### Add Liquidity
```javascript
// First time (creator only)
await market.addInitialLiquidity({ value: ethers.parseEther("1.0") });

// Additional liquidity (anyone)
const lpTokens = await market.addLiquidity({ 
    value: ethers.parseEther("0.5") 
});
```

### Resolve Market
```javascript
// After resolution time
await market.connect(resolver).resolve(
    true  // YES wins
);
```

### Claim Winnings
```javascript
const payout = await market.claim();
console.log("Won:", ethers.formatEther(payout), "ETH");
```

## 🔍 Query Market Data

### Get Market Info
```javascript
const info = await market.getMarketInfo();
console.log({
    question: info.question,
    currentPrice: Number(info.currentPrice) / 100,  // %
    yesReserve: ethers.formatEther(info.yesReserve),
    noReserve: ethers.formatEther(info.noReserve),
    state: info.state  // 0=OPEN, 1=CLOSED, 2=RESOLVED, 3=INVALID
});
```

### Get User Position
```javascript
const position = await market.getUserPosition(userAddress);
console.log({
    yesShares: ethers.formatEther(position.yes),
    noShares: ethers.formatEther(position.no),
    lpTokens: ethers.formatEther(position.liquidity),
    potentialWinnings: ethers.formatEther(position.potentialWinnings)
});
```

### List All Markets
```javascript
const allMarkets = await factory.getAllMarkets();
console.log(`Total markets: ${allMarkets.length}`);

for (const addr of allMarkets) {
    const market = await ethers.getContractAt("PredictionMarket", addr);
    const info = await market.getMarketInfo();
    console.log(`- ${info.question}`);
}
```

## 🎯 Use Case Templates

### Sports Match
```javascript
await factory.createBinaryMarket(
    "Will Lakers win vs Warriors on Nov 30?",
    "Resolves YES if Lakers win, NO if Warriors win, INVALID if cancelled",
    "Sports",
    "NBA",
    sportsOracle,
    matchStartTime,
    matchStartTime + 3600 * 4,  // 4 hours after
    ethers.parseEther("0.5")
);
```

### Price Prediction
```javascript
await factory.createBinaryMarket(
    "Will BTC exceed $100k in 2024?",
    "Resolves YES if Bitcoin reaches $100,000 at any point before Dec 31, 2024 23:59 UTC per CoinGecko",
    "Crypto",
    "Bitcoin",
    priceOracle,
    deadlineTimestamp,
    deadlineTimestamp + 86400,
    ethers.parseEther("1.0")
);
```

### DAO Proposal
```javascript
await factory.createBinaryMarket(
    "Will DAO Proposal #42 pass?",
    "Resolves YES if proposal receives >50% yes votes",
    "Governance",
    "DAOName",
    daoMultisig,
    voteEndTime,
    voteEndTime + 3600,
    ethers.parseEther("0.1")
);
```

## 🛠️ Testing

### Hardhat
```bash
npx hardhat test
```

### Foundry
```bash
forge test -vvv
```

### Test Coverage
```bash
npx hardhat coverage
```

## 📊 Frontend Integration

### React Example
```jsx
import { useState, useEffect } from 'react';
import { useContract, useContractRead } from 'wagmi';

function MarketCard({ marketAddress }) {
    const market = useContract({
        address: marketAddress,
        abi: MARKET_ABI
    });

    const { data: info } = useContractRead({
        ...market,
        functionName: 'getMarketInfo'
    });

    const buyYes = async () => {
        await market.write.buy([true, 0], {
            value: parseEther('0.1')
        });
    };

    return (
        <div>
            <h3>{info?.question}</h3>
            <p>YES: {info?.currentPrice / 100}%</p>
            <button onClick={buyYes}>Buy YES (0.1 ETH)</button>
        </div>
    );
}
```

## 🔐 Security Checklist

Before deploying to mainnet:

- [ ] Audit all contracts
- [ ] Test with various edge cases
- [ ] Set appropriate fee limits
- [ ] Configure approved resolvers
- [ ] Test resolution process
- [ ] Verify emergency procedures
- [ ] Document all parameters
- [ ] Set up monitoring
- [ ] Prepare upgrade path
- [ ] Insurance/bug bounty program

## 💡 Tips

1. **Start small**: Deploy with low initial liquidity
2. **Test thoroughly**: Use testnet first
3. **Monitor gas**: Optimize for your network
4. **Clear questions**: Avoid ambiguous markets
5. **Trusted resolvers**: Use known oracles
6. **Document rules**: Make resolution criteria clear
7. **Set reasonable times**: Allow enough trading time
8. **Backup resolvers**: Have contingency plans

## 📚 Next Steps

1. Read full [README.md](./README.md)
2. Check [ARCHITECTURE.md](./ARCHITECTURE.md)
3. Review [INTEGRATION.md](./INTEGRATION.md)
4. Join community Discord
5. Start building!

## 🆘 Troubleshooting

### "Insufficient liquidity" error
- Market needs initial liquidity
- Call `addInitialLiquidity()` first

### "Market closed" error
- Trading has ended
- Check `endTime`

### "Slippage exceeded" error
- Price moved between quote and execution
- Increase `minShares` tolerance

### "Unauthorized" error
- Only resolver can resolve
- Check resolver address

### Gas too high
- Reduce trade size
- Wait for lower gas prices
- Use L2 solution

## 📞 Support

- GitHub Issues: [repo/issues]
- Discord: [link]
- Docs: [docs.site]
- Email: support@example.com

Happy trading! 🎉
