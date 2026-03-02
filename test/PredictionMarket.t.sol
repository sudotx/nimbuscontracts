// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";
import {IPredictionMarket} from "../src/interfaces/IPredictionMarket.sol";

contract PredictionMarketTest is Test {
    PredictionMarket market;

    address creator = makeAddr("creator");
    address resolver = makeAddr("resolver");
    address feeRecipient = makeAddr("feeRecipient");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 endTime = block.timestamp + 1 days;
    uint256 resolutionTime = block.timestamp + 2 days;
    uint16 platformFeeBps = 100; // 1%

    function setUp() public {
        vm.startPrank(creator);
        market = new PredictionMarket(
            "Will it rain tomorrow?",
            "A market on whether it will rain tomorrow in SF",
            creator,
            resolver,
            endTime,
            resolutionTime,
            platformFeeBps,
            feeRecipient
        );
        vm.stopPrank();
    }

    function test_InitialState() public view {
        assertEq(market.question(), "Will it rain tomorrow?");
        assertEq(market.CREATOR(), creator);
        assertEq(market.RESOLVER(), resolver);
        assertEq(market.FEE_RECIPIENT(), feeRecipient);
        assertEq(market.END_TIME(), endTime);
        assertEq(market.RESOLUTION_TIME(), resolutionTime);
        assertEq(uint16(market.PLATFORM_FEE_BPS()), platformFeeBps);
        assertEq(uint256(market.state()), uint256(IPredictionMarket.MarketState.OPEN));
    }

    function test_AddInitialLiquidity() public {
        vm.deal(creator, 1 ether);
        vm.startPrank(creator);
        market.addInitialLiquidity{value: 1 ether}();
        vm.stopPrank();

        assertEq(market.yesReserve(), 0.5 ether);
        assertEq(market.noReserve(), 0.5 ether);
        assertEq(market.collateralPool(), 1 ether);
        assertTrue(market.totalLiquidity() > 0);
        assertEq(market.liquidityBalanceOf(creator), market.totalLiquidity());
    }

    function testRevert_AddInitialLiquidity_NotCreator() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        market.addInitialLiquidity{value: 1 ether}();
    }
    
    function test_BuySellShares() public {
        // Setup liquidity
        vm.deal(creator, 1 ether);
        vm.startPrank(creator);
        market.addInitialLiquidity{value: 1 ether}();
        vm.stopPrank();

        // Alice buys YES shares
        vm.deal(alice, 0.1 ether);
        vm.prank(alice);
        uint256 yesSharesBought = market.buy{value: 0.1 ether}(true, 0);
        assertTrue(yesSharesBought > 0);
        assertEq(market.yesBalanceOf(alice), yesSharesBought);

        // Bob buys NO shares
        vm.deal(bob, 0.1 ether);
        vm.prank(bob);
        uint256 noSharesBought = market.buy{value: 0.1 ether}(false, 0);
        assertTrue(noSharesBought > 0);
        assertEq(market.noBalanceOf(bob), noSharesBought);
        
        // Alice sells YES shares
        vm.prank(alice);
        market.sell(true, yesSharesBought, 0);
        assertEq(market.yesBalanceOf(alice), 0);
    }

    function test_ResolveAndClaim() public {
         // Setup liquidity and trades
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        market.addInitialLiquidity{value: 1 ether}();
        
        vm.deal(alice, 0.1 ether);
        vm.prank(alice);
        market.buy{value: 0.1 ether}(true, 0); // Alice buys YES

        vm.deal(bob, 0.1 ether);
        vm.prank(bob);
        market.buy{value: 0.1 ether}(false, 0); // Bob buys NO

        // Close market
        vm.warp(endTime);
        market.forceClose();
        assertEq(uint256(market.state()), uint256(IPredictionMarket.MarketState.CLOSED));

        // Resolve market
        vm.warp(resolutionTime);
        vm.prank(resolver);
        market.resolve(true); // YES wins
        assertEq(uint256(market.state()), uint256(IPredictionMarket.MarketState.RESOLVED));
        assertTrue(market.outcome());

        // Alice (winner) claims
        uint256 aliceInitialBalance = alice.balance;
        vm.prank(alice);
        uint256 payout = market.claim();
        assertTrue(payout > 0);
        assertTrue(alice.balance > aliceInitialBalance);

        // Bob (loser) tries to claim
        vm.prank(bob);
        vm.expectRevert(bytes("NoWinnings()"));
        market.claim();
    }

    function test_InvalidateAndRefund() public {
        // Setup liquidity and trades
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        market.addInitialLiquidity{value: 1 ether}();
        
        vm.deal(alice, 0.1 ether);
        vm.prank(alice);
        market.buy{value: 0.1 ether}(true, 0);

        // Invalidate market
        vm.prank(resolver);
        market.invalidate();
        assertEq(uint256(market.state()), uint256(IPredictionMarket.MarketState.INVALID));
        
        // Alice claims refund
        uint256 aliceInitialBalance = alice.balance;
        vm.prank(alice);
        uint256 refund = market.claimRefund();
        assertTrue(refund > 0);
        assertTrue(alice.balance > aliceInitialBalance);
    }

    function test_CollectFees() public {
        // Setup liquidity and trades to generate fees
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        market.addInitialLiquidity{value: 1 ether}();
        
        vm.deal(alice, 0.1 ether);
        vm.prank(alice);
        market.buy{value: 0.1 ether}(true, 0);
        
        assertTrue(market.accumulatedFees() > 0);

        uint256 recipientInitialBalance = feeRecipient.balance;
        vm.prank(feeRecipient);
        market.collectFees();
        assertTrue(feeRecipient.balance > recipientInitialBalance);
        assertEq(market.accumulatedFees(), 0);
    }
}
