// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IYieldStrategy {
    function asset() external view returns (address);

    function deposit(uint256 assets) external returns (uint256);

    function withdraw(
        uint256 assets,
        address receiver
    ) external returns (uint256);

    function totalAssets() external view returns (uint256);
}