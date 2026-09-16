// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {StableSaveVault} from "../src/StableSaveVault.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {MockYieldStrategy} from "../src/mocks/MockYieldStrategy.sol";

contract StableSaveVaultTest is Test {
    MockUSDT usdt;
    MockYieldStrategy strategy;
    StableSaveVault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant USDT = 1e6;

    function setUp() public {
        usdt = new MockUSDT();

        vault = new StableSaveVault(
            address(usdt),
            address(this),
            address(this)
        );

        usdt.mint(alice, 1_000_000 * USDT);
        usdt.mint(bob, 1_000_000 * USDT);

        vm.prank(alice);
        usdt.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdt.approve(address(vault), type(uint256).max);
    }

    function testCreateVault() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            15_000_000
        );

        StableSaveVault.Vault memory v =
            vault.getVault(vaultId);

        assertEq(v.owner, alice);
        assertEq(v.targetAmount, 15_000_000);
        assertEq(v.depositCount, 0);
        assertEq(uint256(v.status), 0);
    }

    function testDeposit() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            15_000_000
        );

        vm.prank(alice);

        vault.deposit(vaultId, 500 * USDT);

        StableSaveVault.Vault memory v =
            vault.getVault(vaultId);

        assertEq(v.depositedAmount, 500 * USDT);
        assertEq(v.shares, 500 * USDT);
        assertEq(v.depositCount, 1);
        assertEq(vault.totalShares(), 500 * USDT);
    }

    function testMultipleDeposits() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            15_000_000
        );

        vm.startPrank(alice);

        vault.deposit(vaultId, 500 * USDT);
        vault.deposit(vaultId, 500 * USDT);
        vault.deposit(vaultId, 1_000 * USDT);

        vm.stopPrank();

        StableSaveVault.Vault memory v =
            vault.getVault(vaultId);

        assertEq(v.depositedAmount, 2_000 * USDT);
        assertEq(v.depositCount, 3);
        assertEq(vault.totalAssets(), 2_000 * USDT);
    }

    function testMultipleVaults() public {
        vm.startPrank(alice);

        uint256 vaultOne = vault.createVault(
            30 days,
            15_000_000
        );

        uint256 vaultTwo = vault.createVault(
            90 days,
            45_000_000
        );

        vault.deposit(vaultOne, 500 * USDT);
        vault.deposit(vaultTwo, 1_000 * USDT);

        vm.stopPrank();

        assertEq(
            vault.previewVaultValue(vaultOne),
            500 * USDT
        );

        assertEq(
            vault.previewVaultValue(vaultTwo),
            1_000 * USDT
        );
    }

    function testMaturedWithdrawal() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            15_000_000
        );

        vm.prank(alice);
        vault.deposit(vaultId, 500 * USDT);

        uint256 beforeBalance = usdt.balanceOf(alice);

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        vault.withdraw(vaultId);

        uint256 afterBalance = usdt.balanceOf(alice);

        assertEq(
            afterBalance - beforeBalance,
            500 * USDT
        );

        StableSaveVault.Vault memory v =
            vault.getVault(vaultId);

        assertEq(v.shares, 0);
        assertEq(uint256(v.status), 1);
    }

    function testEarlyWithdrawalPenalty() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            15_000_000
        );

        vm.prank(alice);
        vault.deposit(vaultId, 500 * USDT);

        uint256 beforeBalance = usdt.balanceOf(alice);

        vm.prank(alice);
        vault.earlyWithdraw(vaultId);

        uint256 afterBalance = usdt.balanceOf(alice);

        // 2% penalty.
        uint256 expected = 490 * USDT;

        assertEq(
            afterBalance - beforeBalance,
            expected
        );
    }

    function testYieldIsDistributedByShares() public {
        strategy = new MockYieldStrategy(address(usdt));

        vault.setStrategy(address(strategy));

        vm.prank(alice);

        uint256 aliceVault = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(alice);
        vault.deposit(aliceVault, 100 * USDT);

        strategy.addYield(20 * USDT);

        vm.prank(alice);

        uint256 bobVault = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(bob);
        vault.deposit(bobVault, 100 * USDT);

        assertEq(
            vault.previewVaultValue(aliceVault),
            120 * USDT
        );

        assertEq(
            vault.previewVaultValue(bobVault),
            100 * USDT
        );
    }

    function testYieldSplitBetweenSimultaneousDepositors() public {
        strategy = new MockYieldStrategy(address(usdt));

        vault.setStrategy(address(strategy));

        vm.prank(alice);

        uint256 aliceVault = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(bob);

        uint256 bobVault = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(alice);
        vault.deposit(aliceVault, 100 * USDT);

        vm.prank(bob);
        vault.deposit(bobVault, 100 * USDT);

        strategy.addYield(20 * USDT);

        assertEq(
            vault.previewVaultValue(aliceVault),
            110 * USDT
        );

        assertEq(
            vault.previewVaultValue(bobVault),
            110 * USDT
        );
    }

    function testLaterDepositDoesNotCapturePreviousYield() public {
        strategy = new MockYieldStrategy(address(usdt));

        vault.setStrategy(address(strategy));

        vm.prank(alice);

        uint256 aliceVault = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(alice);
        vault.deposit(aliceVault, 100 * USDT);

        strategy.addYield(50 * USDT);

        vm.prank(bob);

        uint256 bobVault = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(bob);
        vault.deposit(bobVault, 100 * USDT);

        assertEq(
            vault.previewVaultValue(aliceVault),
            150 * USDT
        );

        assertEq(
            vault.previewVaultValue(bobVault),
            100 * USDT
        );
    }

    function testStrategyLossAffectsShareValue() public {
        strategy = new MockYieldStrategy(address(usdt));

        vault.setStrategy(address(strategy));

        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(alice);
        vault.deposit(vaultId, 100 * USDT);

        strategy.simulateLoss(20 * USDT);

        assertEq(
            vault.previewVaultValue(vaultId),
            80 * USDT
        );
    }

    function testCannotDepositAfterMaturity() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);

        vm.expectRevert(
            StableSaveVault.VaultMatured.selector
        );

        vault.deposit(vaultId, 100 * USDT);
    }

    function testCannotWithdrawBeforeMaturity() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(alice);
        vault.deposit(vaultId, 100 * USDT);

        vm.prank(alice);

        vm.expectRevert(
            StableSaveVault.VaultNotMatured.selector
        );

        vault.withdraw(vaultId);
    }

    function testOnlyOwnerCanWithdraw() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(alice);
        vault.deposit(vaultId, 100 * USDT);

        vm.warp(block.timestamp + 31 days);

        vm.prank(bob);

        vm.expectRevert(
            StableSaveVault.NotVaultOwner.selector
        );

        vault.withdraw(vaultId);
    }

    function testPauseBlocksDeposits() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            100 * USDT
        );

        vault.pause();

        vm.prank(alice);

        vm.expectRevert();

        vault.deposit(vaultId, 100 * USDT);
    }

    function testCannotSweepUSDT() public {
        usdt.mint(address(vault), 1_000 * USDT);

        assertEq(
            usdt.balanceOf(address(vault)),
            1_000 * USDT
        );
    }

    function testPreviewEarlyWithdrawal() public {
        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            100 * USDT
        );

        vm.prank(alice);
        vault.deposit(vaultId, 100 * USDT);

        (
            uint256 gross,
            uint256 penalty,
            uint256 net
        ) = vault.previewWithdraw(vaultId);

        assertEq(gross, 100 * USDT);
        assertEq(penalty, 2 * USDT);
        assertEq(net, 98 * USDT);
    }

    function testFuzzDeposit(
        uint256 amount
    ) public {
        amount = bound(
            amount,
            1 * USDT,
            100_000 * USDT
        );

        vm.prank(alice);

        uint256 vaultId = vault.createVault(
            30 days,
            amount
        );

        vm.prank(alice);

        vault.deposit(vaultId, amount);

        assertEq(
            vault.previewVaultValue(vaultId),
            amount
        );
    }
}