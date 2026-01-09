#!/bin/bash

# Nimbus Prediction Market Deployment Script
# This script helps deploy and verify contracts on various networks

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEPLOYMENT_DIR="deployments"
SCRIPT_CONTRACT="script/DeploymentScript.sol:DeploymentScript"

# Helper functions
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_step() {
    echo -e "${BLUE}→ $1${NC}"
}

# Check if required tools are installed
check_dependencies() {
    print_step "Checking dependencies..."

    if ! command -v forge &> /dev/null; then
        print_error "Foundry's forge not found. Please install Foundry first."
        exit 1
    fi

    if ! command -v cast &> /dev/null; then
        print_error "Foundry's cast not found. Please install Foundry first."
        exit 1
    fi

    print_success "All dependencies found"
}

# Create deployments directory
setup_deployment_dir() {
    if [ ! -d "$DEPLOYMENT_DIR" ]; then
        mkdir -p "$DEPLOYMENT_DIR"
        print_success "Created deployments directory"
    fi
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
    deploy          Deploy contracts to a network
    verify          Verify deployed contracts
    create-market   Create a sample market
    help            Show this help message

DEPLOY OPTIONS:
    --network       Network to deploy to (local, sepolia, mainnet, base, arbitrum, optimism)
    --fee-recipient Address to receive platform fees (required)
    --fee-bps       Platform fee in basis points (default: 50 for mainnet, 100 for testnet)
    --private-key   Private key for deployment (or set PRIVATE_KEY env var)
    --verify        Verify contracts after deployment
    --config        Use predefined config (mainnet, testnet, dev)

VERIFY OPTIONS:
    --network       Network where contract is deployed
    --address       Contract address to verify
    --args          Constructor arguments (comma-separated)

EXAMPLES:
    # Deploy to local network
    $0 deploy --network local --fee-recipient 0x1234... --fee-bps 100

    # Deploy to Sepolia with verification
    $0 deploy --network sepolia --fee-recipient 0x1234... --verify

    # Deploy using mainnet config
    $0 deploy --network mainnet --fee-recipient 0x1234... --config mainnet --verify

    # Verify a contract
    $0 verify --network sepolia --address 0x1234... --args "0xRecipient,50"

    # Create a sample market
    $0 create-market --network sepolia --factory 0x1234...

EOF
}

# Get RPC URL for network
get_rpc_url() {
    case $1 in
        local)
            echo "http://127.0.0.1:8545"
            ;;
        sepolia)
            echo "${SEPOLIA_RPC_URL:-https://rpc.sepolia.org}"
            ;;
        mainnet)
            echo "${MAINNET_RPC_URL:-https://eth.llamarpc.com}"
            ;;
        base)
            echo "${BASE_RPC_URL:-https://mainnet.base.org}"
            ;;
        base-sepolia)
            echo "${BASE_SEPOLIA_RPC_URL:-https://sepolia.base.org}"
            ;;
        arbitrum)
            echo "${ARBITRUM_RPC_URL:-https://arb1.arbitrum.io/rpc}"
            ;;
        arbitrum-sepolia)
            echo "${ARBITRUM_SEPOLIA_RPC_URL:-https://sepolia-rollup.arbitrum.io/rpc}"
            ;;
        optimism)
            echo "${OPTIMISM_RPC_URL:-https://mainnet.optimism.io}"
            ;;
        optimism-sepolia)
            echo "${OPTIMISM_SEPOLIA_RPC_URL:-https://sepolia.optimism.io}"
            ;;
        *)
            print_error "Unknown network: $1"
            exit 1
            ;;
    esac
}

# Get block explorer API URL
get_explorer_api() {
    case $1 in
        sepolia)
            echo "etherscan"
            ;;
        mainnet)
            echo "etherscan"
            ;;
        base|base-sepolia)
            echo "basescan"
            ;;
        arbitrum|arbitrum-sepolia)
            echo "arbiscan"
            ;;
        optimism|optimism-sepolia)
            echo "optimistic"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get default config values
get_config_values() {
    case $1 in
        mainnet)
            FEE_BPS=50
            MIN_DURATION=3600  # 1 hour
            MAX_DURATION=31536000  # 365 days
            MIN_LIQUIDITY="10000000000000000"  # 0.01 ETH
            ;;
        testnet)
            FEE_BPS=100
            MIN_DURATION=300  # 5 minutes
            MAX_DURATION=2592000  # 30 days
            MIN_LIQUIDITY="1000000000000000"  # 0.001 ETH
            ;;
        dev)
            FEE_BPS=200
            MIN_DURATION=60  # 1 minute
            MAX_DURATION=604800  # 7 days
            MIN_LIQUIDITY="100000000000000"  # 0.0001 ETH
            ;;
        *)
            print_error "Unknown config: $1"
            exit 1
            ;;
    esac
}

# Deploy contracts
deploy() {
    local network=""
    local fee_recipient=""
    local fee_bps=""
    local private_key="${PRIVATE_KEY}"
    local should_verify=false
    local config=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --network)
                network="$2"
                shift 2
                ;;
            --fee-recipient)
                fee_recipient="$2"
                shift 2
                ;;
            --fee-bps)
                fee_bps="$2"
                shift 2
                ;;
            --private-key)
                private_key="$2"
                shift 2
                ;;
            --verify)
                should_verify=true
                shift
                ;;
            --config)
                config="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$network" ]; then
        print_error "Network is required. Use --network"
        exit 1
    fi

    if [ -z "$fee_recipient" ]; then
        print_error "Fee recipient is required. Use --fee-recipient"
        exit 1
    fi

    if [ -z "$private_key" ]; then
        print_error "Private key is required. Use --private-key or set PRIVATE_KEY env var"
        exit 1
    fi

    # Apply config if specified
    if [ -n "$config" ]; then
        get_config_values "$config"
    fi

    # Set default fee if not specified
    if [ -z "$fee_bps" ]; then
        if [[ "$network" == *"mainnet"* ]] || [[ "$network" == "base" ]] || [[ "$network" == "arbitrum" ]] || [[ "$network" == "optimism" ]]; then
            fee_bps=50
        else
            fee_bps=100
        fi
    fi

    local rpc_url=$(get_rpc_url "$network")

    print_header "Deploying to $network"
    print_info "RPC URL: $rpc_url"
    print_info "Fee Recipient: $fee_recipient"
    print_info "Platform Fee: $fee_bps bps ($(echo "scale=2; $fee_bps/100" | bc)%)"

    # Create deployment file
    local deployment_file="$DEPLOYMENT_DIR/${network}-$(date +%Y%m%d-%H%M%S).json"

    print_step "Compiling contracts..."
    forge build

    print_step "Deploying PredictionMarketFactory..."

    # Deploy using cast
    local deploy_cmd="forge create $SCRIPT_CONTRACT \
        --rpc-url $rpc_url \
        --private-key $private_key"

    print_info "Running deployment..."
    deployment_output=$(eval $deploy_cmd)

    # Extract deployed address
    factory_address=$(echo "$deployment_output" | grep "Deployed to:" | awk '{print $3}')

    if [ -z "$factory_address" ]; then
        print_error "Failed to extract factory address from deployment output"
        echo "$deployment_output"
        exit 1
    fi

    print_success "DeploymentScript deployed at: $factory_address"

    # Call deployPlatform function
    print_step "Deploying factory through DeploymentScript..."

    deploy_tx=$(cast send $factory_address \
        "deployPlatform(address,uint16)" \
        "$fee_recipient" \
        "$fee_bps" \
        --rpc-url $rpc_url \
        --private-key $private_key \
        --json)

    # Get factory address from event logs
    print_step "Extracting factory address from logs..."

    # Get transaction hash
    tx_hash=$(echo "$deploy_tx" | jq -r '.transactionHash')

    # Get receipt
    receipt=$(cast receipt $tx_hash --rpc-url $rpc_url --json)

    # Extract FactoryDeployed event
    factory_deployed=$(echo "$receipt" | jq -r '.logs[] | select(.topics[0] == "0x'$(cast keccak "FactoryDeployed(address)")'") | .topics[1]')

    if [ -z "$factory_deployed" ] || [ "$factory_deployed" == "null" ]; then
        print_error "Failed to extract factory address from event logs"
        exit 1
    fi

    # Convert to address (remove leading zeros)
    actual_factory=$(cast --to-address "$factory_deployed")

    print_success "PredictionMarketFactory deployed at: $actual_factory"

    # Save deployment info
    cat > "$deployment_file" << EOF
{
  "network": "$network",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deploymentScript": "$factory_address",
  "factory": "$actual_factory",
  "feeRecipient": "$fee_recipient",
  "platformFeeBps": $fee_bps,
  "deployer": "$(cast wallet address --private-key $private_key)"
}
EOF

    print_success "Deployment info saved to: $deployment_file"

    # Verify if requested
    if [ "$should_verify" = true ]; then
        local explorer=$(get_explorer_api "$network")
        if [ -n "$explorer" ]; then
            print_step "Verifying contracts..."
            verify_contracts "$network" "$actual_factory" "$fee_recipient" "$fee_bps"
        else
            print_info "Verification not available for network: $network"
        fi
    fi

    print_header "Deployment Complete"
    echo -e "${GREEN}Factory Address: $actual_factory${NC}"
    echo -e "${YELLOW}Save this address for future interactions!${NC}"
}

# Verify contracts
verify_contracts() {
    local network="$1"
    local factory_address="$2"
    local fee_recipient="$3"
    local fee_bps="$4"

    local explorer=$(get_explorer_api "$network")

    if [ -z "$explorer" ]; then
        print_error "Verification not supported for network: $network"
        exit 1
    fi

    print_header "Verifying Contracts on $network"

    # Check for API key
    local api_key=""
    case $explorer in
        etherscan)
            api_key="${ETHERSCAN_API_KEY}"
            ;;
        basescan)
            api_key="${BASESCAN_API_KEY}"
            ;;
        arbiscan)
            api_key="${ARBISCAN_API_KEY}"
            ;;
        optimistic)
            api_key="${OPTIMISTIC_API_KEY}"
            ;;
    esac

    if [ -z "$api_key" ]; then
        print_error "API key required for verification. Set ${explorer^^}_API_KEY env var"
        exit 1
    fi

    local rpc_url=$(get_rpc_url "$network")

    print_step "Verifying PredictionMarketFactory..."

    forge verify-contract \
        --chain-id $(cast chain-id --rpc-url $rpc_url) \
        --num-of-optimizations 200 \
        --watch \
        --constructor-args $(cast abi-encode "constructor(address,uint16)" "$fee_recipient" "$fee_bps") \
        --etherscan-api-key "$api_key" \
        --compiler-version $(forge --version | grep -oP 'v\K[0-9.]+') \
        $factory_address \
        src/PredictionMarketFactory.sol:PredictionMarketFactory \
        || print_error "Verification failed (contract may already be verified)"

    print_success "Verification complete"
}

# Create a sample market
create_market() {
    local network=""
    local factory=""
    local private_key="${PRIVATE_KEY}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --network)
                network="$2"
                shift 2
                ;;
            --factory)
                factory="$2"
                shift 2
                ;;
            --private-key)
                private_key="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [ -z "$network" ] || [ -z "$factory" ]; then
        print_error "Network and factory address are required"
        exit 1
    fi

    local rpc_url=$(get_rpc_url "$network")

    print_header "Creating Sample Market"

    local end_time=$(($(date +%s) + 86400))  # 1 day from now
    local resolution_time=$((end_time + 86400))  # 2 days from now

    print_step "Creating market: 'Will ETH price exceed $4000 tomorrow?'"

    cast send $factory \
        "createBinaryMarket(string,string,string,string,address,uint256,uint256,uint256)" \
        "Will ETH price exceed \$4000 tomorrow?" \
        "This market resolves YES if Ethereum price exceeds 4000 USD within 24 hours" \
        "Crypto" \
        "Price Predictions" \
        "$(cast wallet address --private-key $private_key)" \
        "$end_time" \
        "$resolution_time" \
        "10000000000000000" \
        --value "0.01ether" \
        --rpc-url $rpc_url \
        --private-key $private_key

    print_success "Market created successfully"
}

# Main script logic
main() {
    check_dependencies
    setup_deployment_dir

    if [ $# -eq 0 ]; then
        usage
        exit 0
    fi

    command=$1
    shift

    case $command in
        deploy)
            deploy "$@"
            ;;
        verify)
            local network=""
            local address=""
            local args=""

            while [[ $# -gt 0 ]]; do
                case $1 in
                    --network)
                        network="$2"
                        shift 2
                        ;;
                    --address)
                        address="$2"
                        shift 2
                        ;;
                    --args)
                        args="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            if [ -z "$network" ] || [ -z "$address" ]; then
                print_error "Network and address are required for verification"
                exit 1
            fi

            IFS=',' read -ra ARGS <<< "$args"
            verify_contracts "$network" "$address" "${ARGS[0]}" "${ARGS[1]}"
            ;;
        create-market)
            create_market "$@"
            ;;
        help)
            usage
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
