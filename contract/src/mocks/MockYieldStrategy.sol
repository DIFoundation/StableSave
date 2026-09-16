// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MockUSDT} from "./MockUSDT.sol";
import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";

contract MockYieldStrategy is IYieldStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdt;

    constructor(address asset_) {
        usdt = IERC20(asset_);
    }

    function asset() external view returns (address) {
        return address(usdt);
    }

    function deposit(
        uint256 assets
    ) external returns (uint256) {
        usdt.safeTransferFrom(msg.sender, address(this), assets);

        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver
    ) external returns (uint256) {
        uint256 balance = usdt.balanceOf(address(this));

        require(balance >= assets, "insufficient strategy liquidity");

        usdt.safeTransfer(receiver, assets);

        return assets;
    }

    function totalAssets()
        external
        view
        returns (uint256)
    {
        return usdt.balanceOf(address(this));
    }

    function addYield(
        uint256 amount
    ) external {
        MockUSDT(address(usdt)).mint(address(this), amount);
    }

    function simulateLoss(
        uint256 amount
    ) external {
        uint256 balance = usdt.balanceOf(address(this));

        require(balance >= amount, "loss exceeds assets");

        usdt.safeTransfer(address(0xdead), amount);
    }
}