// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PredictionMarketFactory} from "../src/PredictionMarketFactory.sol";
import {IPredictionMarketFactory} from "../src/interfaces/IPredictionMarketFactory.sol";

contract PredictionMarketFactoryTest is Test {
    PredictionMarketFactory factory;

    address owner = makeAddr("owner");
    address feeRecipient = makeAddr("feeRecipient");
    address creator = makeAddr("creator");
    address resolver = makeAddr("resolver");
    address alice = makeAddr("alice");

    uint16 platformFeeBps = 100; // 1%

    function setUp() public {
        vm.startPrank(owner);
        factory = new PredictionMarketFactory(feeRecipient, platformFeeBps);
        factory.approveResolver(resolver, true);
        vm.stopPrank();
    }

    function test_InitialState() public view {
        assertEq(factory.owner(), owner);
        assertEq(factory.feeRecipient(), feeRecipient);
        assertEq(factory.platformFeeBps(), platformFeeBps);
        assertTrue(factory.approvedResolvers(owner));
        assertTrue(factory.approvedResolvers(resolver));
    }

    function test_CreateBinaryMarket() public {
        vm.deal(creator, 0.1 ether);
        vm.prank(creator);

        address marketAddress = factory.createBinaryMarket{value: 0.1 ether}(
            "Test Question",
            "Test Description",
            "Test Category",
            "Test Subcategory",
            resolver,
            block.timestamp + 2 days,
            block.timestamp + 3 days,
            0.1 ether
        );

        assertTrue(marketAddress != address(0));
        assertEq(factory.getTotalMarkets(), 1);
        assertEq(factory.getAllMarkets().length, 1);

        IPredictionMarketFactory.MarketInfo memory info = factory.getMarketInfo(marketAddress);
        assertEq(info.creator, creator);
        assertEq(info.resolver, resolver);
        assertEq(info.category, "Test Category");
    }

    function test_CreateMarket_Validation() public {
        // Test resolver not approved
        vm.prank(creator);
        vm.expectRevert(bytes("ResolverNotApproved()"));
        factory.createBinaryMarket("Q", "D", "C", "S", alice, block.timestamp + 2 days, block.timestamp + 3 days, 0);

        // Test invalid duration
        vm.prank(creator);
        vm.expectRevert(bytes("InvalidDuration()"));
        factory.createBinaryMarket(
            "Q", "D", "C", "S", resolver, block.timestamp + 10 minutes, block.timestamp + 1 hours, 0
        );
    }

    function test_AdminFunctions() public {
        // Test setPlatformFee
        vm.prank(owner);
        factory.setPlatformFee(200);
        assertEq(factory.platformFeeBps(), 200);

        // Test setFeeRecipient
        vm.prank(owner);
        factory.setFeeRecipient(alice);
        assertEq(factory.feeRecipient(), alice);

        // Test approveResolver
        vm.prank(owner);
        factory.approveResolver(alice, true);
        assertTrue(factory.approvedResolvers(alice));

        // Test transferOwnership
        vm.prank(owner);
        factory.transferOwnership(alice);
        assertEq(factory.owner(), alice);
    }

    function testRevert_AdminFunctions_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("Unauthorized()"));
        factory.setPlatformFee(200);

        vm.prank(alice);
        vm.expectRevert(bytes("Unauthorized()"));
        factory.setFeeRecipient(alice);

        vm.prank(alice);
        vm.expectRevert(bytes("Unauthorized()"));
        factory.approveResolver(alice, true);

        vm.prank(alice);
        vm.expectRevert(bytes("Unauthorized()"));
        factory.transferOwnership(alice);
    }
}
