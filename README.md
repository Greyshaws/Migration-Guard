# Migration Guard

This tool catches migration-class bugs in deployed smart contracts. Runs as a CI gate before deploy and as a live monitor after.

For the design rationale, the exploit analysis, and the architectural
choices, see [`writeup.pdf`](https://docs.google.com/document/d/1QB5Ey5emDlOMKrnFr4K8SZrpvkqOVWC_XIw-JYzJ3K8/edit?usp=sharing).

## Requirements

- **Foundry** (`forge` 0.2.0 or later) — [installation](https://book.getfoundry.sh/getting-started/installation)
- **Python 3.7+** with the standard library (no extra packages required)
- **An Ethereum mainnet RPC URL** — free-tier
  [Alchemy](https://www.alchemy.com/) or [Infura](https://www.infura.io/)
  works; an archive node is required for historical-block forks 
- **bash** (the CLI wrappers are POSIX-shell scripts; tested on macOS
  and Ubuntu)

## Install

```bash
git clone  upgrade-guard
cd upgrade-guard
forge install                 
export ETH_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
```

Verify the install:

```bash
forge build                   
forge test                    
```

The test suite forks Ethereum mainnet at specific historical blocks, so the
first `forge test` run takes 10-30 seconds depending on RPC latency.
Subsequent runs use Foundry's fork cache and complete in 2-3 seconds.

## Quick start: catching the Aevo exploit

The shipped `upgrade-guard.toml` is pre-configured to evaluate the Aevo /
Ribbon DOV ProxyOwner contract at the block immediately following the
December 2025 upgrade. Run the tool:

```bash
./bin/upgrade-guard upgrade-guard.toml
```

You will see output like:

(image)

The exit code is `1` when any property fails. The two failures point to
verifiable on-chain artifacts:

- The owner returned by `auth.OwnerCheck` is the attacker-controlled wallet (`0xB594F7e7Ad...`), readable directly from storage slot 0 of the proxy admin on Etherscan.
- The `auth.DetectTxOrigin` property reports two `ORIGIN` opcodes at byte offsets 1188 and 3077 in the deployed bytecode, independently verifiable by decoding the contract code.

## Running against live mainnet (monitor mode)

The same property library can be evaluated against the latest block on
live mainnet:

```bash
./bin/upgrade-guard-monitor upgrade-guard.toml
```

## Generating a config for a new target

The `upgrade-guard-init` command reads on-chain state for a given address and produces a starter `upgrade-guard.toml` populated with what could be auto-detected. Marks the rest as `TODO`.

```bash
./bin/upgrade-guard-init 0x<contract-address> path/to/new-config.toml
```

## Configuration

All configuration lives in a single TOML file. The shipped `upgrade-guard.toml` documents every available field with comments. An example:

```toml
[protocol]
name  = "your-protocol"
chain = "ethereum"

[fork]
block = 23994254     # block to evaluate against in CI mode

[[admin_contracts]]
name        = "main_proxy_admin"
address     = "0x..."
owner_slot  = 0

[properties.admin_owner_in_approved_set]
enabled         = true
approved_owners = ["0x...multisig"]

[properties.tx_origin_in_authorization]
enabled = true

# Plus blocks for each of the other four properties — see
# upgrade-guard.toml for the full schema.
```

## CI integration

A reference GitHub Actions workflow is shipped at
`.github/workflows/upgrade-guard.yml`. To use it in your own repository:

1. Copy the workflow file into your project's `.github/workflows/`.
2. Add `ETH_RPC_URL` as a repository secret (Settings → Secrets and
   variables → Actions).
3. Commit your `upgrade-guard.toml` to the repository root.
4. Open a pull request. The workflow checks out the code, installs
   Foundry and Python, runs `./bin/upgrade-guard upgrade-guard.toml`,
   posts the report as a comment on the PR, and fails the build if any
   property failed.


## Properties shipped

The POC ships with six properties spanning six bug categories. Each
implements the `IMigrationProperty` interface and runs identically in
pre-deploy and post-deploy contexts.

| Property                          | Category                            | What it checks                                                                                          |
| --------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `auth.OwnerCheck`                 | Authorization regression (state)    | Reads the admin contract's owner from storage; fails if not in the approved set.                        |
| `auth.DetectTxOrigin`             | Authorization regression (bytecode) | Scans deployed bytecode for the `ORIGIN` opcode with proper PUSH-operand skipping; fails if found.      |
| `scaling.MatchOracleDecimals`     | Scaling drift                       | Calls `decimals()` on the configured oracle; fails if the return value differs from consumer expectation. |
| `storage.ProxyStateCheck`         | Storage / init regression           | Verifies the proxy's initialized flag is set and the EIP-1967 implementation slot points to deployed code. |
| `surface.FindLiveSelectors`       | Surface persistence                 | Probes declared-dead selectors with an unauthorized caller (`vm.prank`); fails if any are still callable. |
| `liquidity.PoolDepthCheck`        | Liquidity decay                     | Reads the legacy contract's TVL and the oracle source's liquidity; fails if pool depth is below the configured safety ratio. |

## Adding a new property

To add a new property:

1. Create a new contract under `src/properties/` implementing
   `IMigrationProperty` (`id`, `category`, `check` functions plus the
   `PropertyResult` return struct).
2. Add a `[properties.<name>]` block to `upgrade-guard.toml` and
   corresponding parser logic in `bin/parse-config.py`.
3. Import and instantiate the property in `script/RunAll.s.sol` and
   `script/MonitorOnce.s.sol`, with an `if (enabled) { ... }` guard
   reading the new environment variable.
4. Add tests under `test/`.

## Running tests

```bash
forge test                       
forge test -vvv                  
forge test --match-contract OracleDecimalConsistencyTest   
forge test --match-test test_failsOnDecimalMismatch_aevoStyle  
```

## Limitations

Read at [`writeup.pdf`](https://docs.google.com/document/d/1QB5Ey5emDlOMKrnFr4K8SZrpvkqOVWC_XIw-JYzJ3K8/edit?usp=sharing).

## Troubleshooting

**`Error: missing environment variable ETH_RPC_URL`** — set the variable
in your shell with `export ETH_RPC_URL="..."`. The CLI wrappers source it
from the environment; they do not read from `.env` files.

**`forge test` fails with `Error: archive node required`** — your RPC
provider does not support archive access for the historical blocks the
tests fork. Switch to a provider with archive access (Alchemy and Infura
free tiers include this) or set `[rpc_endpoints]` in `foundry.toml`.

**`STATUS: FAIL` but the build exit code is 0** — the `bin/upgrade-guard`
script uses `tee` and `grep` to propagate the failure status. If you are
running the underlying `forge script` command directly instead of through
the wrapper, the exit code will not propagate. Always use the bin/
wrappers in CI.

**Compilation succeeds locally but fails in CI with a `stack too deep`
error** — `foundry.toml` enables `via_ir = true` which is required for
the runner scripts. Verify the setting is present and that the CI
environment is reading the same `foundry.toml`.

## License

[MIT, or your preferred license — add a LICENSE file]