# Mutually Assured Destruction (MAD)

A fixed-supply ERC-20 for Ethereum. `src/MADToken.sol:MADToken` mints the entire
supply once, to its immediate deployer, in its constructor.

| Property | Value |
| --- | --- |
| Name | Mutually Assured Destruction |
| Symbol | MAD |
| Decimals | 18 |
| Supply in MAD | 1,000,000,000 |
| Supply in base units | `1000000000000000000000000000` (10^27) |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None (`[]`) |
| Constructor transaction value | 0 ETH |
| Initial recipient | `msg.sender`, the immediate deployer |
| Owner / administrative roles | None |

## Behavior and assumptions

The brief specifies a name, symbol, supply, and constructor mint. The name is
branding: it does not add a destruction, mutual burn, or confiscation mechanism.
MAD uses the vendored OpenZeppelin Contracts v5.1.0 ERC20 implementation without
transfer overrides. There are no fees, taxes, rebases, pauses, blocklists, external
mint/burn methods, upgrade mechanisms, or post-deployment settings. Supply remains
constant. The constructor makes no external calls.

Transfers and delegated transfers deliver the exact amount and return `true`.
Invalid operations revert with OpenZeppelin's ERC-6093 custom errors. Zero-value
transfers and self-transfers are supported. Transfers to the zero address and
approvals to the zero spender are rejected. A transfer to an ordinary contract
does not invoke a receiver callback or check whether that contract can return tokens.

`approve` replaces the caller's allowance for the chosen spender. A finite
allowance decreases on `transferFrom`; `type(uint256).max` is an unlimited
allowance and is not decreased. A failed transfer leaves balances and allowances
unchanged. The deployer has exactly the same spending rights as any other holder.

Minting and transfers emit `Transfer`; explicit approvals emit `Approval`.
OpenZeppelin v5 does not emit `Approval` for allowance consumption during
`transferFrom`, so indexers should query `allowance` for the current value.

## Build and test

Foundry and Solidity 0.8.26 are required. All Solidity dependencies are vendored
as ordinary files under `lib/`; no dependency download is required. The compiler
must already be installed for a fully offline build. Versions, archive checksums,
and licenses are recorded in [DEPENDENCIES.md](DEPENDENCIES.md).

```sh
forge build
FOUNDRY_FUZZ_SEED=0x29a97616a436c63a35aa3e45a3b04c2ca965a5ecd8d95ce371b7deda0c199085 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer settings
(enabled, 200 runs), and `bytecode_hash = "none"`. Fuzz tests run 1,024 cases per
test. The stateful invariant runs 128 sequences of 64 operations with unexpected
reverts treated as failures. No test needs a network fork, wallet, or environment
variable; the command-line seed only controls Foundry's test generation.

Tests cover exact metadata and constructor mint events, direct and CREATE2
factory deployment, zero/full/self/ordinary transfers, finite and unlimited
allowances, revocation, unauthorized spending, rollback on errors, unavailable
admin operations, exact launch distribution transfers, and randomized balance
conservation across multiple holders. The launch-flow test checks token movements;
it does not simulate a Uniswap pool or replace the network's protected integration
checks. Test fixtures are under `test/` and are not launch contracts.

## Deployment and responsibilities

The only launch artifact is `MADToken` from `src/MADToken.sol`. Use its creation
bytecode from `out/MADToken.sol/MADToken.json`, with no appended constructor
arguments. Deploy directly through the launch factory using the pinned build
settings; no initialization call or library linking is needed. A normal wallet
deployment credits that wallet; a factory deployment credits the factory, not
the transaction origin or the caller of the factory. There is no deployment
address, signer, router, oracle, owner address, or other configuration to supply
to this token. No application contracts are part of this deliverable.

The supplied launch targets Ethereum (chain ID 1). The launch factory is
responsible for distributing the full initial balance: 10% to the launch's
MerkleDistributor, 75% for pool seeding, and the remaining 15% to the requester's
specified recipient `0x433c89e346976a3686cc237fcfe14d4eb84c831d`. These allocations
are factory responsibilities, not logic in the token constructor. The supplied
FWA pairing, pool parameters, and opening capitalization likewise belong to the
launch system. Ordinary token transfers need no exemptions. The subsequent
manifest step supplies the launch manifest; this project does not create one.

After launch, the launch operator should verify the deployed source/build,
metadata, total supply, and distribution events against the accepted manifest.
There is no owner setup, maintenance transaction, or minting authority to hand
over. Holders control their transfers and approvals and should only approve
trusted spenders. When changing a live allowance, applications should first
revoke it and wait for confirmation before setting a new value to mitigate the
standard ERC-20 allowance replacement race. Tokens sent to an inaccessible
address or contract cannot be recovered by an administrator.

Local verification consists of Foundry builds, unit/fuzz/invariant tests, and
formatting checks. Slither and Mythril are not part of this project's checks.
Independent adversarial review and deployed-source verification remain release
responsibilities; the test suite is not an independent security audit. This
project performs no broadcast or live-chain deployment.
