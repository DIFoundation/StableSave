// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StableSaveTreasury
/// @notice Collects early-withdrawal penalty fees forwarded by
/// StableSaveVault (`StableSaveVault.earlyWithdraw`).
/// @dev A plain ERC20 `transfer`/`safeTransfer` into this contract never
/// calls any function on it — there's nothing for this contract to "do"
/// when it receives USDT. Its whole job is to hold that balance safely
/// and let the owner move it out deliberately later (covering operating
/// costs, reinvestment, migrating to a new treasury, etc.), which is why
/// this is a separate, minimal contract rather than logic bolted onto an
/// EOA. Ownership should sit behind a multisig once this is live.
contract StableSaveTreasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event Withdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event NativeReceived(address indexed from, uint256 amount);
    event NativeWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error NativeTransferFailed();

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Accepts native BOT sent here by mistake so it isn't
    /// permanently stuck. StableSaveVault itself only ever sends USDT
    /// here, never native BOT — this is purely a safety net.
    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }

    /// @notice Current balance of `token` held by this treasury.
    function balanceOf(IERC20 token) external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice Withdraw an exact `amount` of `token` to `to`.
    function withdraw(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        token.safeTransfer(to, amount);

        emit Withdrawn(address(token), to, amount);
    }

    /// @notice Withdraw the entire balance of `token` to `to`.
    function withdrawAll(
        IERC20 token,
        address to
    ) external onlyOwner nonReentrant returns (uint256 amount) {
        if (to == address(0)) revert ZeroAddress();

        amount = token.balanceOf(address(this));

        if (amount == 0) revert ZeroAmount();

        token.safeTransfer(to, amount);

        emit Withdrawn(address(token), to, amount);
    }

    /// @notice Rescue native BOT accidentally sent to this contract.
    function withdrawNative(
        address payable to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();

        emit NativeWithdrawn(to, amount);
    }
}
