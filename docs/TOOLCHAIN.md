# Toolchain and transient-guard review — 2026-10-03

This update applies to the standalone SFC reference repository. It changes compiler/dependency/runtime assumptions, not the six-method normative ABI (`0x2e0b288e`). No deployment or upgrade transaction is included.

## Verified versions

| Component | Previous | Selected | Evidence and scope |
| --- | --- | --- | --- |
| Solidity | 0.8.28 | **0.8.37** | [Latest final release](https://github.com/argotorg/solidity/releases/tag/v0.8.37), published 2026-09-10; includes important compiler fixes |
| EVM target | Cancun | **Osaka** | Current stable mainnet execution target; [Amsterdam support is still experimental](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |
| OpenZeppelin Contracts | 5.2.0 | **5.7.0** | [Latest final GitHub release](https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.7.0), published 2026-07-29; exact commit pinned |
| forge-std | 1.9.6 | **1.17.0** | [Final release](https://github.com/foundry-rs/forge-std/releases/tag/v1.17.0), published 2026-09-30 |
| Foundry | 1.7.1 | **1.8.4** | [Final release](https://github.com/foundry-rs/foundry/releases/tag/v1.8.4), published 2026-10-01 |
| Slither | 0.11.3 | **0.11.6** | [Final release](https://github.com/crytic/slither/releases/tag/0.11.6), published 2026-07-28 |

Versions are a dated snapshot, not floating constraints. `dependencies.lock.json` records tool versions, dependency commits and the EVM target. Both dependency working trees must be clean. CI checks the selected tools, compiler settings, ABI and contract size.

OpenZeppelin 5.7.0 is a final release, **published under npm `dev`, not the audited `latest` channel**. At this review, `latest` is 5.6.1. OpenZeppelin explicitly [distinguishes final unaudited releases from audited ones](https://github.com/OpenZeppelin/openzeppelin-contracts#release-tags). We selected 5.7.0 to meet the requested newest-final-version policy; this does not imply that this release or SFC has received an independent audit. RCs, master and nightly builds are not used.

Amsterdam/Glamsterdam is not the stable mainnet target on this date. The [Ethereum Foundation testnet announcement](https://blog.ethereum.org/en/2026/09/17/glamsterdam-testnet-announcement) schedules Sepolia for October 6 and leaves mainnet undecided. The reference deliberately uses Osaka and the established via-IR pipeline, without the experimental SSA CFG backend.

## ReentrancyGuardTransient

The vault and factory now inherit OpenZeppelin's `ReentrancyGuardTransient`. The guard uses EIP-1153 transient storage, scoped to the executing contract and transaction, and explicitly clears its lock after each successful call. A reverted call rolls back its transient writes. It avoids persistent guard writes and their refund accounting.

Supporting EIP-1153 is necessary but not sufficient for running this exact artifact: the selected compiler target is **Osaka**. Deployment must use a network compatible with that target. A chain described only as “EVM-compatible” or supporting Cancun is not automatically qualified. Recompilation for another fork needs a separate compatibility and validation decision.

The reference is immutable. Removing the previous persistent guard state changes storage layout; it is not a drop-in implementation upgrade for an existing proxy or Diamond. Compiler and dependency changes also change CREATE2 bytecode hashes and predicted addresses. The factory prediction/creation tests validate the new pair together.

### Security regression coverage

- A callback matrix attempts all 20 financial entry points, including the slippage wrapper and privileged operations; rejection must carry the guard's exact custom error.
- A fuzz test varies callback target and deposit amount, then performs another legitimate call in the same transaction.
- Required-callback failure, inexact payout and post-deposit slippage all roll back accounting and leave subsequent calls usable.
- Sequential deposit/transfer/request/cancel and two separate cashflow claims run in one transaction.
- A constructor's asset callback encounters the factory guard; another creation in the same transaction succeeds afterward.
- A callback to a different vault confirms that locks are isolated by contract address.
- Identical persistent/transient guard probes measure overhead. The result is saved in `reports/validation.json`; it is not a percentage saving for an entire fund transaction.

The guard does not validate NAV, entitlement allocation or off-chain evidence. Public accounting views retain their required non-reverting behavior; integrations must not assume that a callback observes an atomic cross-protocol snapshot.

## Imported OpenZeppelin changes reviewed

ERC-4626 now routes its default `maxWithdraw` through `previewRedeem(maxRedeem(...))`; SFC already overrides both asynchronous limits, so its intentionally reverting preview does not leak into a limit view. The new `_transferIn`/`_transferOut` hooks do not bypass SFC: its `_deposit` and asynchronous redemption paths retain exact balance-delta checks. SafeERC20's transfer implementation and decimals helper changed; dedicated asset-integration tests cover no-return, false-return, malformed-return and reverting tokens, including state rollback and a successful retry. AccessControlDefaultAdminRules still enforces the configured two-day transfer delay.

## Verification details

The CI fuzz profile uses **4,096 cases per fuzz function**. The stateful campaign uses **512 runs × 256 actions = 131,072 handler calls**, checking **seven predicates** after actions, across 20 action types and three investors. Foundry 1.8.4 groups predicates in one campaign; we do not multiply the action count by seven. Reports distinguish test functions, predicates and runner cases.

Tests use `vm.getBlockTimestamp()` where they need to observe `vm.warp()`: the compiler may legitimately cache `block.timestamp` within a transaction, which does not change on a real chain. This is a test-fixture correction, not a production timestamp workaround.

Dynamic test linking is disabled so source artifacts are canonical and usable by Slither. The normal compiler artifacts are measured before coverage. Slither's 102 detectors, ERC-20 interface checker, inheritance/function/state printers and exact-description finding gate are included in `verify.sh`. The ERC-20 checker flags the standard allowance replacement race as a design consideration; SFC retains OpenZeppelin's ERC-20 allowance behavior. Integrators should clear an existing allowance before replacing it and account for transaction ordering.

Coverage uses `--ir-minimum`; raw metrics and source-map limits are retained. Missing branches must be investigated rather than hidden by lowering thresholds. The four known unmarked source statements are documented in [COVERAGE](COVERAGE.md). No percentage is presented as proof of security.

## Local tools without changing the original project

The local validation tools can live under ignored `.tools/` directories. `verify.sh` prepends `.tools/foundry/bin`, `.tools/security/bin` and `.tools/editorial/bin` to PATH. Alternatively install the exact versions on PATH as shown in the README. Global tool upgrades are not required. The local Foundry release archive was checked against its official GitHub SHA-256 digest.

## Security skills applied

The review used [solidity-security](https://github.com/wshobson/agents/blob/main/plugins/blockchain-web3/skills/solidity-security/SKILL.md) and Trail of Bits' [secure-workflow-guide](https://github.com/trailofbits/skills/blob/main/plugins/building-secure-contracts/skills/secure-workflow-guide/SKILL.md). The workflow includes static triage, applicable ERC checks, [security diagrams](SECURITY_DIAGRAMS.md), stateful properties and manual review. These are review guides, not an audit certification.

Manual review retained the documented trust assumptions: NAV and settlement are privileged assertions; batch membership is not a completeness proof; slippage protection must be used where share price matters; on-chain evidence hashes provide no secrecy or proof of portfolio ownership. No upgrade mechanism, signature verifier, randomness source or arbitrary delegatecall was found in the production contracts.
