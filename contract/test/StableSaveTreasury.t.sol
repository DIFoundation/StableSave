// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {StableSaveTreasury} from "../src/StableSaveTreasury.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";

contract StableSaveTreasuryTest is Test {
    MockUSDT usdt;
    StableSaveTreasury treasury;

    address owner = address(this);
    address ops = address(0xBEEF);

    uint256 constant USDT = 1e6;

    function setUp() public {
        usdt = new MockUSDT();
        treasury = new StableSaveTreasury(owner);

        usdt.mint(address(treasury), 1_000 * USDT);
    }

    function testBalanceOfReflectsHeldTokens() public view {
        assertEq(treasury.balanceOf(usdt), 1_000 * USDT);
    }

    function testWithdrawSendsExactAmount() public {
        treasury.withdraw(usdt, ops, 100 * USDT);

        assertEq(usdt.balanceOf(ops), 100 * USDT);
        assertEq(treasury.balanceOf(usdt), 900 * USDT);
    }

    function testWithdrawAllSweepsFullBalance() public {
        uint256 amount = treasury.withdrawAll(usdt, ops);

        assertEq(amount, 1_000 * USDT);
        assertEq(usdt.balanceOf(ops), 1_000 * USDT);
        assertEq(treasury.balanceOf(usdt), 0);
    }

    function testWithdrawRevertsForNonOwner() public {
        vm.prank(ops);
        vm.expectRevert();
        treasury.withdraw(usdt, ops, 1 * USDT);
    }

    function testWithdrawRevertsOnZeroAddress() public {
        vm.expectRevert(StableSaveTreasury.ZeroAddress.selector);
        treasury.withdraw(usdt, address(0), 1 * USDT);
    }

    function testWithdrawRevertsOnZeroAmount() public {
        vm.expectRevert(StableSaveTreasury.ZeroAmount.selector);
        treasury.withdraw(usdt, ops, 0);
    }

    function testWithdrawAllRevertsWhenBalanceIsZero() public {
        treasury.withdrawAll(usdt, ops);

        vm.expectRevert(StableSaveTreasury.ZeroAmount.selector);
        treasury.withdrawAll(usdt, ops);
    }

    function testReceiveAcceptsNativeAndWithdrawNativeRescuesIt() public {
        vm.deal(address(this), 1 ether);

        (bool ok, ) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(treasury).balance, 1 ether);

        uint256 opsBalanceBefore = ops.balance;

        treasury.withdrawNative(payable(ops), 1 ether);

        assertEq(address(treasury).balance, 0);
        assertEq(ops.balance, opsBalanceBefore + 1 ether);
    }
}
