// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";

contract StableSaveVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_PENALTY_BPS = 1_000; // 10%
    uint256 public constant MINIMUM_LIQUIDITY = 1e3;

    IERC20 public immutable usdt;

    IYieldStrategy public strategy;

    address public immutable treasury;

    uint256 public earlyWithdrawalPenaltyBps = 200; // 2%

    uint256 private _nextVaultId = 1;

    uint256 public totalShares;

    enum VaultStatus {
        Active,
        Withdrawn
    }

    struct Vault {
        address owner;
        uint256 startTime;
        uint256 maturityTime;
        uint256 targetAmount;
        uint256 depositedAmount;
        uint256 shares;
        uint256 depositCount;
        uint256 lastDepositAt;
        VaultStatus status;
    }

    mapping(uint256 => Vault) private _vaults;
    mapping(address => uint256[]) private _userVaultIds;

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed owner,
        uint256 startTime,
        uint256 maturityTime,
        uint256 targetAmount
    );

    event DepositMade(
        uint256 indexed vaultId,
        address indexed owner,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    event VaultWithdrawn(
        uint256 indexed vaultId,
        address indexed owner,
        uint256 grossAmount,
        uint256 penalty,
        uint256 netAmount,
        bool early,
        uint256 timestamp
    );

    event StrategyUpdated(
        address indexed previousStrategy,
        address indexed newStrategy
    );

    event PenaltyUpdated(uint256 previousBps, uint256 newBps);

    error InvalidDuration();
    error InvalidTarget();
    error InvalidVault();
    error NotVaultOwner();
    error VaultNotActive();
    error VaultMatured();
    error VaultNotMatured();
    error NoShares();
    error InvalidStrategy();
    error StrategyAlreadyConfigured();
    error InvalidPenalty();
    error InsufficientLiquidity();
    error InvalidShares();

    constructor(
        address _usdt,
        address _treasury,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_usdt != address(0), "USDT zero address");
        require(_treasury != address(0), "Treasury zero address");

        usdt = IERC20(_usdt);
        treasury = _treasury;
    }

    // ---------------------------------------------------------
    // VAULT CREATION
    // ---------------------------------------------------------

    function createVault(
        uint256 duration,
        uint256 targetAmount
    ) external whenNotPaused returns (uint256 vaultId) {
        if (duration == 0) revert InvalidDuration();
        if (targetAmount == 0) revert InvalidTarget();

        vaultId = _nextVaultId++;

        uint256 start = block.timestamp;
        uint256 maturity = start + duration;

        _vaults[vaultId] = Vault({
            owner: msg.sender,
            startTime: start,
            maturityTime: maturity,
            targetAmount: targetAmount,
            depositedAmount: 0,
            shares: 0,
            depositCount: 0,
            lastDepositAt: 0,
            status: VaultStatus.Active
        });

        _userVaultIds[msg.sender].push(vaultId);

        emit VaultCreated(vaultId, msg.sender, start, maturity, targetAmount);
    }

    // ---------------------------------------------------------
    // DEPOSITS
    // ---------------------------------------------------------

    function deposit(
        uint256 vaultId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        Vault storage vault = _getOwnedVault(vaultId);

        if (vault.status != VaultStatus.Active) {
            revert VaultNotActive();
        }

        if (block.timestamp >= vault.maturityTime) {
            revert VaultMatured();
        }

        if (amount == 0) revert InvalidTarget();

        uint256 assetsBefore = totalAssets();

        uint256 shares = _convertToShares(amount, assetsBefore);

        if (shares == 0) revert InvalidShares();

        usdt.safeTransferFrom(msg.sender, address(this), amount);

        if (address(strategy) != address(0)) {
            usdt.forceApprove(address(strategy), amount);

            uint256 deposited = strategy.deposit(amount);

            require(deposited == amount, "Strategy deposit mismatch");
        }

        vault.depositedAmount += amount;
        vault.shares += shares;
        vault.depositCount += 1;
        vault.lastDepositAt = block.timestamp;

        totalShares += shares;

        emit DepositMade(vaultId, msg.sender, amount, shares, block.timestamp);
    }

    // ---------------------------------------------------------
    // WITHDRAWAL
    // ---------------------------------------------------------

    function withdraw(uint256 vaultId) external nonReentrant whenNotPaused {
        Vault storage vault = _getOwnedVault(vaultId);

        if (vault.status != VaultStatus.Active) {
            revert VaultNotActive();
        }

        if (block.timestamp < vault.maturityTime) {
            revert VaultNotMatured();
        }

        _withdraw(vaultId, vault, false);
    }

    function earlyWithdraw(
        uint256 vaultId
    ) external nonReentrant whenNotPaused {
        Vault storage vault = _getOwnedVault(vaultId);

        if (vault.status != VaultStatus.Active) {
            revert VaultNotActive();
        }

        if (block.timestamp >= vault.maturityTime) {
            revert VaultMatured();
        }

        _withdraw(vaultId, vault, true);
    }

    function _withdraw(
        uint256 vaultId,
        Vault storage vault,
        bool early
    ) internal {
        uint256 shares = vault.shares;

        if (shares == 0) revert NoShares();

        uint256 grossAmount = _convertToAssets(shares);

        uint256 penalty;

        if (early) {
            penalty = (grossAmount * earlyWithdrawalPenaltyBps) / BPS;
        }

        uint256 netAmount = grossAmount - penalty;

        vault.shares = 0;
        vault.status = VaultStatus.Withdrawn;

        totalShares -= shares;

        _ensureLiquidity(grossAmount);

        if (penalty > 0) {
            usdt.safeTransfer(treasury, penalty);
        }

        usdt.safeTransfer(vault.owner, netAmount);

        emit VaultWithdrawn(
            vaultId,
            vault.owner,
            grossAmount,
            penalty,
            netAmount,
            early,
            block.timestamp
        );
    }

    // ---------------------------------------------------------
    // PREVIEWS
    // ---------------------------------------------------------

    function previewWithdraw(
        uint256 vaultId
    )
        external
        view
        returns (uint256 grossAmount, uint256 penalty, uint256 netAmount)
    {
        Vault storage vault = _getVault(vaultId);

        grossAmount = _convertToAssets(vault.shares);

        if (block.timestamp < vault.maturityTime) {
            penalty = (grossAmount * earlyWithdrawalPenaltyBps) / BPS;
        }

        netAmount = grossAmount - penalty;
    }

    function previewVaultValue(
        uint256 vaultId
    ) external view returns (uint256) {
        Vault storage vault = _getVault(vaultId);

        return _convertToAssets(vault.shares);
    }

    // ---------------------------------------------------------
    // SHARE ACCOUNTING
    // ---------------------------------------------------------

    function convertToShares(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets, totalAssets());
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares);
    }

    function _convertToShares(
        uint256 assets,
        uint256 assetsBefore
    ) internal view returns (uint256) {
        if (totalShares == 0) {
            // burn MINIMUM_LIQUIDITY once at the very first deposit
            return assets - MINIMUM_LIQUIDITY; // minted separately to address(0)
        }
        return (assets * totalShares) / assetsBefore;
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        if (shares == 0 || totalShares == 0) {
            return 0;
        }

        return (shares * totalAssets()) / totalShares;
    }

    // ---------------------------------------------------------
    // ASSET MANAGEMENT
    // ---------------------------------------------------------

    function totalAssets() public view returns (uint256) {
        uint256 idleAssets = usdt.balanceOf(address(this));

        if (address(strategy) == address(0)) {
            return idleAssets;
        }

        return idleAssets + strategy.totalAssets();
    }

    function _ensureLiquidity(uint256 amount) internal {
        uint256 idle = usdt.balanceOf(address(this));

        if (idle >= amount) {
            return;
        }

        uint256 required = amount - idle;

        if (address(strategy) == address(0)) {
            revert InsufficientLiquidity();
        }

        uint256 withdrawn = strategy.withdraw(required, address(this));

        if (withdrawn < required) {
            revert InsufficientLiquidity();
        }
    }

    // ---------------------------------------------------------
    // STRATEGY
    // ---------------------------------------------------------

    function setStrategy(address newStrategy) external onlyOwner {
        if (totalShares != 0) {
            revert StrategyAlreadyConfigured();
        }

        if (newStrategy != address(0)) {
            if (IYieldStrategy(newStrategy).asset() != address(usdt)) {
                revert InvalidStrategy();
            }
        }

        address previous = address(strategy);

        strategy = IYieldStrategy(newStrategy);

        emit StrategyUpdated(previous, newStrategy);
    }

    function exitStrategy() external onlyOwner {
        uint256 assets = strategy.totalAssets();
        if (assets > 0) strategy.withdraw(assets, address(this));
        // keep strategy address so deposits flow through again, or set to zero:
        strategy = IYieldStrategy(address(0));
    }

    // ---------------------------------------------------------
    // ADMIN CONFIG
    // ---------------------------------------------------------

    function setEarlyWithdrawalPenaltyBps(
        uint256 newPenaltyBps
    ) external onlyOwner {
        if (newPenaltyBps > MAX_PENALTY_BPS) {
            revert InvalidPenalty();
        }

        uint256 previous = earlyWithdrawalPenaltyBps;

        earlyWithdrawalPenaltyBps = newPenaltyBps;

        emit PenaltyUpdated(previous, newPenaltyBps);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------------
    // VIEWS
    // ---------------------------------------------------------

    function getVault(uint256 vaultId) external view returns (Vault memory) {
        return _getVault(vaultId);
    }

    function getUserVaultIds(
        address user
    ) external view returns (uint256[] memory) {
        return _userVaultIds[user];
    }

    function nextVaultId() external view returns (uint256) {
        return _nextVaultId;
    }

    function isMatured(uint256 vaultId) external view returns (bool) {
        return block.timestamp >= _getVault(vaultId).maturityTime;
    }

    function vaultCount(address user) external view returns (uint256) {
        return _userVaultIds[user].length;
    }

    // ---------------------------------------------------------
    // INTERNAL HELPERS
    // ---------------------------------------------------------

    function _getVault(
        uint256 vaultId
    ) internal view returns (Vault storage vault) {
        if (vaultId == 0 || vaultId >= _nextVaultId) {
            revert InvalidVault();
        }

        vault = _vaults[vaultId];
    }

    function _getOwnedVault(
        uint256 vaultId
    ) internal view returns (Vault storage vault) {
        vault = _getVault(vaultId);

        if (vault.owner != msg.sender) {
            revert NotVaultOwner();
        }
    }
}
