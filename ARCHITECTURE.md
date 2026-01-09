# Architecture Overview

## System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Prediction Market Platform                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  PredictionMarketFactory                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ • Market Creation & Registry                          │  │
│  │ • Template Management                                 │  │
│  │ • Resolver Approval System                            │  │
│  │ │ Category-based Organization                         │  │
│  │ • Platform Fee Management                             │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ creates
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    PredictionMarket (Instance)               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Trading Engine (AMM)                                  │  │
│  │  ├─ Buy/Sell Shares                                   │  │
│  │  ├─ Price Discovery (x * y = k)                       │  │
│  │  └─ Slippage Protection                               │  │
│  │                                                        │  │
│  │ Liquidity Management                                  │  │
│  │  ├─ Add Liquidity                                     │  │
│  │  ├─ Remove Liquidity                                  │  │
│  │  └─ LP Token Accounting                               │  │
│  │                                                        │  │
│  │ Resolution System                                     │  │
│  │  ├─ Resolver-based Outcomes                           │  │
│  │  ├─ Market Invalidation                               │  │
│  │  └─ Proportional Payouts                              │  │
│  │                                                        │  │
│  │ State Management                                      │  │
│  │  └─ OPEN → CLOSED → RESOLVED/INVALID                 │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                     Supporting Libraries                     │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │    MathLib       │  │ ReentrancyGuard  │                │
│  │  • sqrt()        │  │  • Protection    │                │
│  │  • mulDiv()      │  │  • State Lock    │                │
│  │  • bps()         │  └──────────────────┘                │
│  └──────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

### Market Creation Flow
```
User → Factory.createBinaryMarket()
  ↓
Factory validates parameters
  ↓
Factory deploys new PredictionMarket
  ↓
Factory registers market (category, creator, resolver)
  ↓
Optional: Initialize liquidity
  ↓
Emit MarketCreated event
  ↓
Return market address
```

### Trading Flow (Buy)
```
User → Market.buy(isYes, minShares) {value: ETH}
  ↓
Validate market is OPEN
  ↓
Calculate platform fee
  ↓
Calculate shares using AMM formula
  ↓
Update reserves (yesReserve ↓, noReserve ↑)
  ↓
Update user balance
  ↓
Update total supply
  ↓
Emit Trade event
```

### Trading Flow (Sell)
```
User → Market.sell(isYes, shareAmount, minReturn)
  ↓
Validate market is OPEN
  ↓
Check user has sufficient shares
  ↓
Calculate ETH return using AMM formula
  ↓
Update reserves (yesReserve ↑, noReserve ↓)
  ↓
Update user balance
  ↓
Update total supply
  ↓
Transfer ETH to user
  ↓
Emit Trade event
```

### Resolution Flow
```
Resolver → Market.resolve(outcome)
  ↓
Validate caller is resolver
  ↓
Validate time >= resolutionTime
  ↓
Set market state to RESOLVED
  ↓
Set outcome (YES/NO)
  ↓
Emit MarketResolved event
  ↓
Winners can now claim
```

### Claim Flow
```
Winner → Market.claim()
  ↓
Validate market is RESOLVED
  ↓
Validate user hasn't claimed
  ↓
Calculate proportional payout
  payout = (user_shares / total_winning_shares) * collateral_pool
  ↓
Mark user as claimed
  ↓
Transfer payout to user
  ↓
Emit WinningsClaimed event
```

## Key Design Decisions

### 1. AMM-Based Pricing
**Decision**: Use constant product formula (x * y = k)

**Rationale**:
- Automatic price discovery
- No need for order books
- Always available liquidity
- Simple and predictable
- Battle-tested in DeFi

**Trade-offs**:
- Price impact on large trades
- Impermanent loss for LPs
- Less capital efficient than other curves

### 2. Binary Markets Only (Initial Version)
**Decision**: Focus on YES/NO outcomes

**Rationale**:
- Simpler implementation
- Easier UX
- Most common use case
- Can be extended later

**Future**: Categorical and scalar markets

### 3. Resolver-Based Resolution
**Decision**: Designated resolver determines outcome

**Rationale**:
- Clear authority
- Fast resolution
- Flexible (can be oracle, DAO, or person)
- Can invalidate if needed

**Trade-offs**:
- Trust assumption
- Centralization risk
- Possible disputes

**Mitigations**:
- Resolver approval system
- Invalidation option
- Future: Oracle integration

### 4. Factory Pattern
**Decision**: Central factory creates markets

**Rationale**:
- Market registry
- Standardization
- Discovery
- Platform fee collection
- Access control

### 5. LP Tokens for Liquidity
**Decision**: Issue tokens representing pool ownership

**Rationale**:
- Transferable positions
- Clear accounting
- Composability
- Standard DeFi pattern

### 6. Single Claim
**Decision**: Users claim once after resolution

**Rationale**:
- Gas efficient
- Simple accounting
- Prevents gaming
- Clear finality

## Security Considerations

### 1. Reentrancy Protection
- All external calls protected with nonReentrant modifier
- State changes before transfers
- Use of checks-effects-interactions pattern

### 2. Integer Overflow
- Solidity 0.8+ built-in protection
- Additional checks in critical calculations

### 3. Access Control
- Resolver-only resolution
- Creator-only certain operations
- State-based restrictions

### 4. Slippage Protection
- minShares parameter on buys
- minReturn parameter on sells
- Prevents sandwich attacks

### 5. State Validation
- Strict state machine
- Time-based restrictions
- Balance checks

### 6. Front-running Mitigation
- Slippage parameters
- AMM price discovery
- Transparent pricing

## Gas Optimization Strategies

### 1. Storage Layout
- Pack structs efficiently
- Use immutable for constants
- Minimize SLOAD operations

### 2. Batch Operations
- getUserMarkets returns multiple markets
- getMarkets supports pagination

### 3. Event-based Indexing
- Comprehensive events for off-chain indexing
- Reduce need for on-chain queries

### 4. Calculation Efficiency
- Inline simple calculations
- Cache frequently used values
- Use unchecked where safe

## Upgrade Path

### Phase 1: Current (Binary Markets)
- YES/NO markets
- AMM trading
- Resolver-based resolution

### Phase 2: Enhanced Features
- Categorical markets (multiple outcomes)
- Scalar markets (range predictions)
- Oracle integrations (Chainlink, UMA)

### Phase 3: Advanced
- Conditional markets
- Cross-chain markets
- Automated resolution
- Reputation system

### Phase 4: DAO Governance
- Protocol upgrades via DAO
- Fee parameter changes
- Resolver disputes
- Treasury management

## Market Economics

### Fee Structure
```
Trade Amount: 1 ETH
├─ Platform Fee: 0.5% = 0.005 ETH → feeRecipient
└─ Trading Amount: 0.995 ETH
   └─ Trading Fee: 0.3% = 0.00299 ETH → stays in pool (LPs)
   └─ Net to pool: 0.99201 ETH
```

### LP Incentives
- Earn trading fees
- Proportional to liquidity provided
- Risk: impermanent loss if outcome becomes certain

### Arbitrage Opportunities
- Price differences between markets
- Buy low, sell high
- Helps keep prices efficient

### Market Maker Incentives
- Provide initial liquidity
- Earn from spread
- Risk: adverse selection

## Performance Metrics

### On-chain Operations
- Market creation: ~200k gas
- Buy/sell: ~80-120k gas
- Add liquidity: ~100k gas
- Claim: ~50k gas

### Scalability
- Unlimited markets per factory
- No cross-market dependencies
- Parallel execution possible

### Query Performance
- O(1) for individual market data
- O(n) for market lists (use pagination)
- Event-based indexing recommended

## Comparison to Alternatives

### vs Order Book Markets
**Advantages**:
- Always available liquidity
- No order matching needed
- Simpler UX
- Automatic price discovery

**Disadvantages**:
- Price impact on large orders
- Less capital efficient
- No limit orders

### vs LMSR (Logarithmic Market Scoring Rule)
**Advantages**:
- Simpler math
- Better understood
- Standard DeFi pattern

**Disadvantages**:
- More price impact
- Less optimal subsidy

### vs Peer-to-Peer Betting
**Advantages**:
- Always available
- No need to match exact positions
- Continuous trading

**Disadvantages**:
- Requires liquidity providers
- More complex

## Integration Patterns

### 1. Trading Bot
- Monitor prices
- Execute trades based on strategy
- Arbitrage across markets

### 2. LP Strategy
- Provide liquidity
- Collect fees
- Manage positions

### 3. Oracle Integration
- Automated resolution
- On-chain data feeds
- Trustless outcomes

### 4. Frontend Application
- Market discovery
- Trading interface
- Portfolio tracking
- Analytics dashboard

### 5. Aggregator
- Search across categories
- Compare markets
- Best price routing
- Volume tracking

This architecture provides a solid foundation for a scalable prediction market platform with clear upgrade paths!
