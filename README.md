# StableSave

A micro-savings vault on BOTChain. Save ₦500 daily in USDT. Earn yield and break the "spend before month end" cycle.

StableSave lets a user lock up a savings goal — an amount and a duration — and
top it up with small, frequent USDT deposits (e.g. ₦500/day worth of USDT).
Funds can be routed into a pluggable yield strategy while they wait, and
withdrawing before the goal matures costs a small penalty, which is the
behavioral nudge that keeps people from raiding their own savings.

## How it works

- **Create a vault** — `createVault(duration, targetAmount)` opens a personal
  savings goal for the caller: a target USDT amount and a maturity date
  (`now + duration`). A wallet can hold many vaults at once (e.g. "New Phone
  Fund", "Rent", "Emergency Buffer").
- **Deposit anytime, any amount** — `deposit(vaultId, amount)` adds USDT to a
  vault. There's no fixed schedule enforced on-chain; the "₦500 daily" cadence
  is a product/UX pattern, not a contract restriction, so users aren't
  penalized for missing a day or topping up a lump sum.
- **Shared yield, per-vault accounting** — deposited USDT can be routed into a
  yield strategy (`IYieldStrategy`). All vaults share one underlying pool and
  are accounted for with an ERC-4626-style share system, so yield (or loss)
  earned by the strategy is distributed across every vault in proportion to
  its shares, without needing to be manually swept or claimed.
- **Withdraw at maturity** — `withdraw(vaultId)` is only callable once
  `block.timestamp >= maturityTime` and returns the vault's full current
  value (deposits + accrued yield).
- **Early withdrawal costs a penalty** — `earlyWithdraw(vaultId)` is always
  available, but takes a small cut (default 2%, capped at 10% by the
  contract, owner-adjustable) that goes to a treasury address. This is the
  "spend before month end" friction the product is built around.

## Project layout

```
contract/                Foundry project — the on-chain vault
  src/StableSaveVault.sol       Core vault contract
  src/StableSaveTreasury.sol    Minimal treasury contract for penalty fees
  src/interfaces/IYieldStrategy.sol  Pluggable yield strategy interface
  src/mocks/                    MockUSDT + MockYieldStrategy for local testing
  script/Deploy.s.sol           Deployment script
  test/StableSaveVault.t.sol    Foundry test suite
  test/StableSaveTreasury.t.sol Treasury contract test suite
```

There is currently no frontend in this repo — the contract is the whole
project so far. Let me know if you'd like a web app (wallet connect, daily
deposit reminder, vault dashboard) built on top of it.

## Getting started

```shell
cd contract
cp .env.example .env   # fill in USDT_ADDRESS, TREASURY_ADDRESS, PRIVATE_KEY
forge build
forge test
```

### Deploy

```shell
cd contract
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url botchain_testnet \
  --private-key $PRIVATE_KEY \
  --broadcast
```

RPC endpoints for BOTChain testnet/mainnet are pre-configured in
`contract/foundry.toml`.

If `TREASURY_ADDRESS` is left blank in `.env`, the script deploys a fresh
`StableSaveTreasury` (owned by the deployer) and wires it into the vault
automatically. Set `TREASURY_ADDRESS` instead to point at an
already-deployed treasury — e.g. a multisig, or a `StableSaveTreasury`
from a previous run.

## Contract design notes

- **Shares, not raw balances.** `Vault.shares` (per-vault) and `totalShares`
  (contract-wide) track ownership of the pooled assets, the same pattern
  ERC-4626 vaults use. This is what lets yield distribute automatically: as
  the strategy's `totalAssets()` grows, every existing share becomes worth
  more USDT without any state changes needed.
- **First deposit sets the exchange rate.** The very first deposit into the
  vault (across all users) mints shares 1:1 with the USDT deposited. To stop
  that first deposit from being a 1-wei dust amount that would make the
  share price trivial to manipulate via a direct USDT transfer to the
  contract, `deposit()` requires the first deposit to be at least
  `MINIMUM_LIQUIDITY` (1000 raw units, i.e. 0.001 USDT at 6 decimals).
- **Strategy changes are restricted.** `setStrategy()` can only be called
  while `totalShares == 0` (i.e. before anyone has deposited, or after
  everyone has fully withdrawn). This is intentional: swapping strategies
  under active deposits would need careful accounting to avoid a share-price
  discontinuity, which this version deliberately avoids rather than getting
  subtly wrong. Use `exitStrategy()` to pull funds back to idle USDT if a
  strategy needs to be retired.
- **Rounding favors the vault.** Share math always rounds down, so
  redemptions can be at most a few wei short of the theoretical value —
  negligible at USDT's 6 decimals, but worth knowing if you're writing tests
  or off-chain accounting against exact amounts.
- **Treasury is mutable, USDT is not.** `usdt` is set once at deployment
  and can never change — swapping the underlying asset would break every
  vault's accounting. `treasury` can be updated via `setTreasury()`
  (owner-only) since a fixed EOA with no recovery path is a real risk,
  not a convenience worth losing. Point it at `StableSaveTreasury` (a
  minimal, owner-controlled contract that just holds and forwards
  penalty fees) or a multisig — never a personal wallet.

## Testing

```shell
cd contract
forge test -vv
```

20 tests cover vault creation, single/multiple deposits across
single/multiple vaults, maturity gating, early-withdrawal penalties, yield
distribution (including simultaneous depositors and late joiners not
capturing past yield), strategy loss propagation, pausing, and the
first-deposit/strategy-exit edge cases described above. A further 8 tests
cover `StableSaveTreasury` directly.