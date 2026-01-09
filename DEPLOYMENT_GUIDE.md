# Nimbus Prediction Market - Deployment Guide

This guide explains how to deploy and verify the Nimbus prediction market contracts.

## Prerequisites

1. **Install Foundry**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your values
   ```

3. **Fund your deployment wallet** with native tokens for the target network

## Quick Start

### Deploy to Local Network

1. Start a local node:
   ```bash
   anvil
   ```

2. Deploy contracts:
   ```bash
   ./deploy.sh deploy \
     --network local \
     --fee-recipient 0xYourAddress \
     --fee-bps 100
   ```

### Deploy to Testnet (Sepolia)

```bash
./deploy.sh deploy \
  --network sepolia \
  --fee-recipient 0xYourAddress \
  --config testnet \
  --verify
```

### Deploy to Mainnet

```bash
./deploy.sh deploy \
  --network mainnet \
  --fee-recipient 0xYourAddress \
  --config mainnet \
  --verify
```

## Supported Networks

- `local` - Local Anvil/Hardhat node
- `sepolia` - Ethereum Sepolia testnet
- `mainnet` - Ethereum mainnet
- `base` - Base mainnet
- `base-sepolia` - Base Sepolia testnet
- `arbitrum` - Arbitrum One
- `arbitrum-sepolia` - Arbitrum Sepolia
- `optimism` - Optimism mainnet
- `optimism-sepolia` - Optimism Sepolia

## Configuration Presets

### Mainnet Config
- Platform Fee: 50 bps (0.5%)
- Min Duration: 1 hour
- Max Duration: 365 days
- Min Liquidity: 0.01 ETH

### Testnet Config
- Platform Fee: 100 bps (1%)
- Min Duration: 5 minutes
- Max Duration: 30 days
- Min Liquidity: 0.001 ETH

### Dev Config
- Platform Fee: 200 bps (2%)
- Min Duration: 1 minute
- Max Duration: 7 days
- Min Liquidity: 0.0001 ETH

## Deployment Commands

### Basic Deployment

```bash
./deploy.sh deploy \
  --network <NETWORK> \
  --fee-recipient <ADDRESS> \
  --fee-bps <BASIS_POINTS>
```

### Deployment with Verification

```bash
./deploy.sh deploy \
  --network <NETWORK> \
  --fee-recipient <ADDRESS> \
  --config <CONFIG_PRESET> \
  --verify
```

### Using Custom Private Key

```bash
./deploy.sh deploy \
  --network <NETWORK> \
  --fee-recipient <ADDRESS> \
  --private-key <YOUR_PRIVATE_KEY>
```

## Verification

### Verify After Deployment

Contracts are automatically verified if you use the `--verify` flag during deployment.

### Verify Existing Contract

```bash
./deploy.sh verify \
  --network sepolia \
  --address 0xFactoryAddress \
  --args "0xFeeRecipient,50"
```

## Create Sample Markets

After deploying the factory, you can create sample markets:

```bash
./deploy.sh create-market \
  --network sepolia \
  --factory 0xYourFactoryAddress
```

## Manual Deployment (Alternative)

If you prefer to deploy manually using forge:

### 1. Deploy Factory

```bash
forge create src/PredictionMarketFactory.sol:PredictionMarketFactory \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args <FEE_RECIPIENT> <FEE_BPS>
```

### 2. Verify Factory

```bash
forge verify-contract \
  --chain-id 11155111 \
  --num-of-optimizations 200 \
  --watch \
  --constructor-args $(cast abi-encode "constructor(address,uint16)" <FEE_RECIPIENT> <FEE_BPS>) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --compiler-version v0.8.20 \
  <FACTORY_ADDRESS> \
  src/PredictionMarketFactory.sol:PredictionMarketFactory
```

### 3. Create a Market

```bash
cast send <FACTORY_ADDRESS> \
  "createBinaryMarket(string,string,string,string,address,uint256,uint256,uint256)" \
  "Will ETH reach $5000?" \
  "Market resolves YES if ETH hits $5000 by end date" \
  "Crypto" \
  "Price" \
  <RESOLVER_ADDRESS> \
  <END_TIMESTAMP> \
  <RESOLUTION_TIMESTAMP> \
  <INITIAL_LIQUIDITY_WEI> \
  --value <INITIAL_LIQUIDITY_WEI> \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

## Deployment Output

After successful deployment, you'll receive:

1. **Factory Address** - Save this for creating markets
2. **Deployment File** - JSON file in `deployments/` directory with all details
3. **Verification Status** - Confirmation of contract verification

Example deployment file (`deployments/sepolia-20240101-120000.json`):

```json
{
  "network": "sepolia",
  "timestamp": "2024-01-01T12:00:00Z",
  "deploymentScript": "0x1234...",
  "factory": "0x5678...",
  "feeRecipient": "0xabcd...",
  "platformFeeBps": 100,
  "deployer": "0xef01..."
}
```

## Interacting with Deployed Contracts

### Using Cast

```bash
# Get total markets
cast call <FACTORY_ADDRESS> "getTotalMarkets()" --rpc-url <RPC_URL>

# Get market info
cast call <FACTORY_ADDRESS> "getMarketInfo(address)" <MARKET_ADDRESS> --rpc-url <RPC_URL>

# Create a market
cast send <FACTORY_ADDRESS> "createBinaryMarket(...)" [...args] --rpc-url <RPC_URL> --private-key <KEY>
```

### Using Etherscan/Block Explorer

1. Navigate to your factory address on the block explorer
2. Use the "Read Contract" tab to query data
3. Use the "Write Contract" tab to create markets (after connecting wallet)

## Troubleshooting

### "Verification failed"

- Ensure your API key is set correctly
- Check that constructor arguments match deployment
- Verify compiler version matches (v0.8.20)

### "Insufficient funds"

- Ensure your wallet has enough native tokens for:
  - Deployment gas fees
  - Initial liquidity (if creating markets)

### "Network not found"

- Check RPC URL is correct
- Ensure network is supported
- Try using a different RPC endpoint

### "Private key required"

- Set `PRIVATE_KEY` environment variable in `.env`
- Or use `--private-key` flag

## Security Recommendations

1. **Never commit `.env` file** - It contains sensitive keys
2. **Use a separate deployment wallet** - Don't use your main wallet
3. **Test on testnet first** - Always deploy to testnet before mainnet
4. **Verify contracts** - Always verify on block explorers
5. **Audit before mainnet** - Get professional audit for mainnet deployments
6. **Use hardware wallet for mainnet** - Consider Ledger/Trezor for production

## Cost Estimates

### Sepolia Testnet
- Factory deployment: ~0.01 SepoliaETH
- Market creation: ~0.005 SepoliaETH + initial liquidity

### Mainnet (estimates based on gas price)
- Factory deployment: ~$50-200 (depending on gas)
- Market creation: ~$25-100 per market

## Next Steps

After deployment:

1. ✅ Save factory address
2. ✅ Verify contract on block explorer
3. ✅ Test market creation
4. ✅ Set up frontend integration
5. ✅ Configure approved resolvers
6. ✅ Create initial markets

## Support

For issues or questions:
- Check the [README](./README.md)
- Review [Architecture docs](./ARCHITECTURE.md)
- Open an issue on GitHub

## License

MIT
