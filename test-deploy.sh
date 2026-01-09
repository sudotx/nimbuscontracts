#!/bin/bash

# Quick Local Deployment Test Script
# This script starts a local Anvil node and deploys the contracts for testing

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }
print_step() { echo -e "${BLUE}→ $1${NC}"; }

# Default Anvil private key (account 0)
DEFAULT_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
DEFAULT_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

echo -e "${BLUE}══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Nimbus Prediction Market - Local Test Deployment${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════${NC}"
echo ""

# Check if Anvil is running
if ! curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 > /dev/null 2>&1; then
    print_info "Starting Anvil local node..."
    anvil > /dev/null 2>&1 &
    ANVIL_PID=$!
    sleep 2
    print_success "Anvil started (PID: $ANVIL_PID)"
else
    print_info "Anvil already running"
    ANVIL_PID=""
fi

# Cleanup function
cleanup() {
    if [ -n "$ANVIL_PID" ]; then
        print_info "Stopping Anvil..."
        kill $ANVIL_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT

echo ""
print_step "Deploying contracts to local network..."
echo ""

# Deploy using the main deploy script
export PRIVATE_KEY=$DEFAULT_PRIVATE_KEY

./deploy.sh deploy \
    --network local \
    --fee-recipient $DEFAULT_ADDRESS \
    --fee-bps 100

# Get the latest deployment file
LATEST_DEPLOYMENT=$(ls -t deployments/local-*.json | head -1)

if [ ! -f "$LATEST_DEPLOYMENT" ]; then
    echo "Error: Deployment file not found"
    exit 1
fi

# Extract factory address
FACTORY_ADDRESS=$(cat $LATEST_DEPLOYMENT | grep -o '"factory": "[^"]*' | cut -d'"' -f4)

echo ""
print_success "Deployment complete!"
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Deployment Information"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Network:          Local (Anvil)"
echo "Factory Address:  $FACTORY_ADDRESS"
echo "Fee Recipient:    $DEFAULT_ADDRESS"
echo "Platform Fee:     100 bps (1%)"
echo ""
echo "Test Account:"
echo "  Address:        $DEFAULT_ADDRESS"
echo "  Private Key:    $DEFAULT_PRIVATE_KEY"
echo ""
echo "═══════════════════════════════════════════════════════"
echo ""

# Ask if user wants to create a test market
read -p "Would you like to create a test market? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "Creating test market..."

    END_TIME=$(($(date +%s) + 86400))  # 1 day from now
    RESOLUTION_TIME=$((END_TIME + 86400))  # 2 days from now

    cast send $FACTORY_ADDRESS \
        "createBinaryMarket(string,string,string,string,address,uint256,uint256,uint256)" \
        "Will ETH price exceed \$4000 in 24 hours?" \
        "This is a test market that resolves YES if Ethereum price exceeds 4000 USD within 24 hours" \
        "Crypto" \
        "Price Predictions" \
        "$DEFAULT_ADDRESS" \
        "$END_TIME" \
        "$RESOLUTION_TIME" \
        "10000000000000000" \
        --value "0.01ether" \
        --rpc-url http://127.0.0.1:8545 \
        --private-key $DEFAULT_PRIVATE_KEY \
        > /dev/null 2>&1

    # Get the market address from event
    TOTAL_MARKETS=$(cast call $FACTORY_ADDRESS "getTotalMarkets()(uint256)" --rpc-url http://127.0.0.1:8545)
    TOTAL_DEC=$(cast --to-dec $TOTAL_MARKETS)
    MARKET_INDEX=$((TOTAL_DEC - 1))

    MARKET_ADDRESS=$(cast call $FACTORY_ADDRESS "allMarkets(uint256)(address)" $MARKET_INDEX --rpc-url http://127.0.0.1:8545)

    print_success "Test market created!"
    echo ""
    echo "Market Address: $MARKET_ADDRESS"
    echo ""
fi

echo ""
print_info "You can now interact with the contracts using:"
echo ""
echo "  # Get factory info"
echo "  ./scripts/interact.sh info --network local --factory $FACTORY_ADDRESS"
echo ""
echo "  # List all markets"
echo "  ./scripts/interact.sh markets --network local --factory $FACTORY_ADDRESS"
echo ""

if [ -n "$MARKET_ADDRESS" ]; then
    echo "  # Get market info"
    echo "  ./scripts/interact.sh market-info --network local --market $MARKET_ADDRESS"
    echo ""
    echo "  # Buy YES shares (0.1 ETH)"
    echo "  ./scripts/interact.sh buy --network local --market $MARKET_ADDRESS --yes --amount 0.1"
    echo ""
fi

print_info "Press Ctrl+C to stop Anvil and exit"
echo ""

# Keep script running if we started Anvil
if [ -n "$ANVIL_PID" ]; then
    wait $ANVIL_PID
fi
