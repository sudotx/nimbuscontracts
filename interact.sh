#!/bin/bash

# Nimbus Prediction Market - Interaction Helper Script
# Quick commands for interacting with deployed contracts

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }
print_step() { echo -e "${BLUE}→ $1${NC}"; }

usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
    info              Get factory information
    markets           List all markets
    market-info       Get specific market information
    create            Create a new market
    buy               Buy shares in a market
    sell              Sell shares in a market
    resolve           Resolve a market
    claim             Claim winnings
    add-liquidity     Add liquidity to a market

OPTIONS:
    --network         Network (local, sepolia, mainnet, etc.)
    --factory         Factory contract address
    --market          Market contract address
    --private-key     Private key (or use PRIVATE_KEY env var)

EXAMPLES:
    # Get factory info
    $0 info --network sepolia --factory 0x1234...

    # List all markets
    $0 markets --network sepolia --factory 0x1234...

    # Get market details
    $0 market-info --network sepolia --market 0x5678...

    # Buy YES shares (0.1 ETH)
    $0 buy --network sepolia --market 0x5678... --yes --amount 0.1

    # Resolve market
    $0 resolve --network sepolia --market 0x5678... --outcome yes

EOF
}

get_rpc_url() {
    case $1 in
        local) echo "http://127.0.0.1:8545" ;;
        sepolia) echo "${SEPOLIA_RPC_URL:-https://rpc.sepolia.org}" ;;
        mainnet) echo "${MAINNET_RPC_URL:-https://eth.llamarpc.com}" ;;
        base) echo "${BASE_RPC_URL:-https://mainnet.base.org}" ;;
        base-sepolia) echo "${BASE_SEPOLIA_RPC_URL:-https://sepolia.base.org}" ;;
        arbitrum) echo "${ARBITRUM_RPC_URL:-https://arb1.arbitrum.io/rpc}" ;;
        arbitrum-sepolia) echo "${ARBITRUM_SEPOLIA_RPC_URL:-https://sepolia-rollup.arbitrum.io/rpc}" ;;
        optimism) echo "${OPTIMISM_RPC_URL:-https://mainnet.optimism.io}" ;;
        optimism-sepolia) echo "${OPTIMISM_SEPOLIA_RPC_URL:-https://sepolia.optimism.io}" ;;
        *) print_error "Unknown network: $1"; exit 1 ;;
    esac
}

factory_info() {
    local network=$1
    local factory=$2
    local rpc_url=$(get_rpc_url "$network")

    print_step "Fetching factory information..."

    echo ""
    echo "Factory Address: $factory"
    echo "Network: $network"
    echo ""

    # Get total markets
    total=$(cast call $factory "getTotalMarkets()" --rpc-url $rpc_url)
    echo "Total Markets: $(cast --to-dec $total)"

    # Get platform fee
    fee=$(cast call $factory "platformFeeBps()" --rpc-url $rpc_url)
    fee_dec=$(cast --to-dec $fee)
    echo "Platform Fee: $fee_dec bps ($(echo "scale=2; $fee_dec/100" | bc)%)"

    # Get fee recipient
    recipient=$(cast call $factory "feeRecipient()(address)" --rpc-url $rpc_url)
    echo "Fee Recipient: $recipient"

    # Get owner
    owner=$(cast call $factory "owner()(address)" --rpc-url $rpc_url)
    echo "Owner: $owner"

    echo ""
}

list_markets() {
    local network=$1
    local factory=$2
    local rpc_url=$(get_rpc_url "$network")

    print_step "Fetching all markets..."

    # Get all markets using pagination
    local result=$(cast call $factory "getActiveMarkets(uint256,uint256)(address[],uint256)" 0 100 --rpc-url $rpc_url)

    echo "$result"
}

market_info() {
    local network=$1
    local market=$2
    local rpc_url=$(get_rpc_url "$network")

    print_step "Fetching market information..."

    # Get market info
    local info=$(cast call $market "getMarketInfo()" --rpc-url $rpc_url)

    echo ""
    echo "Market Address: $market"
    echo ""

    # Get question
    question=$(cast call $market "question()(string)" --rpc-url $rpc_url)
    echo "Question: $question"

    # Get state
    state=$(cast call $market "state()(uint8)" --rpc-url $rpc_url)
    state_dec=$(cast --to-dec $state)
    state_name="UNKNOWN"
    case $state_dec in
        0) state_name="OPEN" ;;
        1) state_name="CLOSED" ;;
        2) state_name="RESOLVED" ;;
        3) state_name="INVALID" ;;
    esac
    echo "State: $state_name"

    # Get current price
    price=$(cast call $market "getCurrentPrice()(uint256)" --rpc-url $rpc_url)
    price_dec=$(cast --to-dec $price)
    echo "Current YES Price: $(echo "scale=2; $price_dec/100" | bc)%"

    # Get reserves
    yes_reserve=$(cast call $market "yesReserve()(uint256)" --rpc-url $rpc_url)
    no_reserve=$(cast call $market "noReserve()(uint256)" --rpc-url $rpc_url)
    echo "YES Reserve: $(cast --from-wei $(cast --to-dec $yes_reserve)) ETH"
    echo "NO Reserve: $(cast --from-wei $(cast --to-dec $no_reserve)) ETH"

    # Get collateral pool
    pool=$(cast call $market "collateralPool()(uint256)" --rpc-url $rpc_url)
    echo "Collateral Pool: $(cast --from-wei $(cast --to-dec $pool)) ETH"

    echo ""
}

buy_shares() {
    local network=$1
    local market=$2
    local is_yes=$3
    local amount=$4
    local private_key="${PRIVATE_KEY}"
    local rpc_url=$(get_rpc_url "$network")

    if [ -z "$private_key" ]; then
        print_error "Private key required"
        exit 1
    fi

    print_step "Buying $([ "$is_yes" = true ] && echo "YES" || echo "NO") shares..."

    # Get quote first
    quote=$(cast call $market "getBuyQuote(bool,uint256)(uint256,uint256)" $is_yes $(cast --to-wei $amount) --rpc-url $rpc_url)

    print_info "Quote received"

    # Buy shares
    cast send $market \
        "buy(bool,uint256)" \
        $is_yes \
        0 \
        --value "${amount}ether" \
        --rpc-url $rpc_url \
        --private-key $private_key

    print_success "Shares purchased successfully"
}

resolve_market() {
    local network=$1
    local market=$2
    local outcome=$3
    local private_key="${PRIVATE_KEY}"
    local rpc_url=$(get_rpc_url "$network")

    if [ -z "$private_key" ]; then
        print_error "Private key required"
        exit 1
    fi

    local outcome_bool="false"
    if [ "$outcome" = "yes" ] || [ "$outcome" = "true" ]; then
        outcome_bool="true"
    fi

    print_step "Resolving market with outcome: $([ "$outcome_bool" = "true" ] && echo "YES" || echo "NO")"

    cast send $market \
        "resolve(bool)" \
        $outcome_bool \
        --rpc-url $rpc_url \
        --private-key $private_key

    print_success "Market resolved successfully"
}

claim_winnings() {
    local network=$1
    local market=$2
    local private_key="${PRIVATE_KEY}"
    local rpc_url=$(get_rpc_url "$network")

    if [ -z "$private_key" ]; then
        print_error "Private key required"
        exit 1
    fi

    print_step "Claiming winnings..."

    cast send $market \
        "claim()" \
        --rpc-url $rpc_url \
        --private-key $private_key

    print_success "Winnings claimed successfully"
}

main() {
    if [ $# -eq 0 ]; then
        usage
        exit 0
    fi

    command=$1
    shift

    local network=""
    local factory=""
    local market=""
    local amount=""
    local is_yes="true"
    local outcome=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --network) network="$2"; shift 2 ;;
            --factory) factory="$2"; shift 2 ;;
            --market) market="$2"; shift 2 ;;
            --amount) amount="$2"; shift 2 ;;
            --yes) is_yes="true"; shift ;;
            --no) is_yes="false"; shift ;;
            --outcome) outcome="$2"; shift 2 ;;
            --private-key) PRIVATE_KEY="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    case $command in
        info)
            [ -z "$network" ] || [ -z "$factory" ] && { print_error "Network and factory required"; exit 1; }
            factory_info "$network" "$factory"
            ;;
        markets)
            [ -z "$network" ] || [ -z "$factory" ] && { print_error "Network and factory required"; exit 1; }
            list_markets "$network" "$factory"
            ;;
        market-info)
            [ -z "$network" ] || [ -z "$market" ] && { print_error "Network and market required"; exit 1; }
            market_info "$network" "$market"
            ;;
        buy)
            [ -z "$network" ] || [ -z "$market" ] || [ -z "$amount" ] && { print_error "Network, market, and amount required"; exit 1; }
            buy_shares "$network" "$market" "$is_yes" "$amount"
            ;;
        resolve)
            [ -z "$network" ] || [ -z "$market" ] || [ -z "$outcome" ] && { print_error "Network, market, and outcome required"; exit 1; }
            resolve_market "$network" "$market" "$outcome"
            ;;
        claim)
            [ -z "$network" ] || [ -z "$market" ] && { print_error "Network and market required"; exit 1; }
            claim_winnings "$network" "$market"
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
