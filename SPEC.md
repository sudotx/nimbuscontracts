# Scripts Directory

This directory contains helper scripts for deploying and interacting with Nimbus prediction market contracts.

## Available Scripts

### interact.sh

Interactive script for common contract operations.

**Commands:**
- `info` - Get factory information
- `markets` - List all markets
- `market-info` - Get specific market details
- `buy` - Buy YES/NO shares
- `sell` - Sell shares
- `resolve` - Resolve a market (resolver only)
- `claim` - Claim winnings after resolution

**Examples:**
```bash
# Get factory info
./scripts/interact.sh info --network sepolia --factory 0x1234...

# View market details
./scripts/interact.sh market-info --network sepolia --market 0x5678...

# Buy YES shares
./scripts/interact.sh buy --network sepolia --market 0x5678... --yes --amount 0.1

# Resolve market as YES
./scripts/interact.sh resolve --network sepolia --market 0x5678... --outcome yes

# Claim winnings
./scripts/interact.sh claim --network sepolia --market 0x5678...
```

### test-deploy.sh

Quick local deployment for testing.

Automatically:
- Starts an Anvil local node (if not running)
- Deploys contracts to the local network
- Optionally creates a test market
- Provides example commands for interaction

**Usage:**
```bash
./scripts/test-deploy.sh
```

This is perfect for:
- Testing contract functionality locally
- Rapid development iterations
- Learning how the contracts work
- Debugging before testnet deployment

## Prerequisites

All scripts require:
- Foundry (forge, cast, anvil)
- Bash shell
- Environment variables set in `.env` file

## Tips

1. **Always test locally first**: Use `test-deploy.sh` before deploying to testnets
2. **Save addresses**: Keep track of factory and market addresses
3. **Check network**: Double-check you're on the right network before transactions
4. **Private keys**: Never commit private keys - use environment variables

## Environment Setup

Create a `.env` file in the project root:

```bash
# Copy example
cp .env.example .env

# Edit with your values
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=https://rpc.sepolia.org
ETHERSCAN_API_KEY=your_api_key
```

## Troubleshooting

### "command not found: forge"
Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`

### "Private key required"
Set `PRIVATE_KEY` in your `.env` file or use `--private-key` flag

### "Network not found"
Check that the network name is valid (local, sepolia, mainnet, base, etc.)

### Script not executable
Run: `chmod +x scripts/*.sh`
