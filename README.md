# Structured Fund Cashflows

**An experimental ERC proposal for reconciling fund principal and funded cashflows.**

SFC distinguishes outstanding principal, funded amortization, gross yield, withholding and beneficiary claims. It extends the ERC-4626 accounting surface and specifies how principal follows transfers and asynchronous redemption custody. Author: **Afonso Dalvi (@Afonsodalvi)**.

**Status: local working paper, unsubmitted and unnumbered.** The `Draft` preamble is prepared for a future submission; it does not mean the Ethereum editors have admitted this proposal. No independent audit or universal security claim is made.

## Start here

- [Readable specification](docs/SPECIFICATION.md) — same normative content with canonical web links.
- [Submission source](ERCS/erc-draft_structured_fund_cashflows.md) — uses the upstream relative-link convention.
- [Deep comparison with RWA standards and market implementations](docs/RWA_COMPARISON_PT.md).
- [Review findings and design decisions](docs/REVIEW.md).
- [Compiler, dependency and transient-guard review](docs/TOOLCHAIN.md).
- [Validation evidence](docs/VALIDATION.md), [security model](docs/SECURITY.md), [architecture](docs/ARCHITECTURE.md) and [integration](docs/INTEGRATION.md).
- [Publication and ERC submission guide](docs/SUBMISSION.md), [forum draft](docs/MAGICIANS_POST.md) and [editorial PR body](docs/ERC_PR_BODY.md).

## What is standardized

| Method | Meaning |
| --- | --- |
| `scopeId()` | One immutable accounting domain |
| `principalOf(account)` | Remaining principal associated with freely held shares |
| `lockedPrincipalOf(controller)` | Captured principal in redemption/cancelation custody |
| `totalOutstandingPrincipal()` | Free plus locked principal |
| `cashflow(id)` | Immutable payment fields and consumption state |
| `claimCashflow(id, receiver)` | Authorized, exact, single-use net payment |

The interface identifier is **`0x2e0b288e`**. The specification, Solidity interface, events and struct fields are checked together. A matching selector alone is insufficient for conformance.

This profile uses one asset denomination and a vault that is its own share token. External share tokens, multiple asset entry points, cross-chain ledgers and rebasing shares require additional accounting design. Identity systems, valuation and entitlement allocation are product responsibilities. SFC does not claim to replace ERC-3643 or ERC-7943.

## Reference implementation

Both the vault and factory use OpenZeppelin `ReentrancyGuardTransient`; this artifact targets **Osaka**. OpenZeppelin **5.7.0** is the newest final release but is in its `dev` channel; the audited `latest` channel remains 5.6.1 as checked on 2026-10-03. See the [toolchain review](docs/TOOLCHAIN.md) for the exact compatibility and audit-status distinction.

`StructuredFundVault` implements synchronous deposit/mint, asynchronous redemption, cancelation, exact asset transfers, scoped principal, funded cashflows and segregated reserves. `StructuredFundFactory` creates one instance per fund/series/class through its immutable `StructuredFundVaultDeployer`, keeping creation bytecode within deployment limits. `StructuredFundEligibility` supplies a minimal allowlist/freeze policy; it is not full ERC-3643 compliance.

A bounded `recordCashflowBatch` books up to 64 records atomically. Allocation remains trusted: the batch is not proof of fairness, portfolio existence or a complete holder snapshot. The reference has no upgrade or legacy migration entry point.

## Reproduce

After cloning this repository, initialize its pinned submodules:

```sh
git submodule update --init --recursive
forge --version                         # v1.8.4
python3 -m pip install slither-analyzer==0.11.6
cargo install eipw --version 0.11.0 --locked
./scripts/verify.sh
```

Solidity 0.8.37, Osaka, optimizer 200 and via-IR are fixed in `foundry.toml`. Dependencies and tools are recorded in [dependencies.lock.json](dependencies.lock.json). Verification uses no RPC, account keys or deployment transaction. The editorial check fetches the pinned public ERC corpus on first use.

For faster development, run `forge test`. For the full evidence, use `verify.sh`: CI-profile unit/security/fuzz/invariant tests, complete interface comparison, bytecode limits, Slither review gate, coverage thresholds, upstream editorial lint and repository checks. Reports are written to `coverage/`; the reviewed snapshot is in [reports/](reports/validation.json). Recreate it with `python3 scripts/save_reports.py` only after successful verification.

The upstream linter has four explicitly reported exceptions for the missing assigned number/filename and real discussion URL. Its result is a local content check, not upstream CI approval.

## Publish your repository and submit the proposal

Create an empty GitHub repository named `structured-fund-cashflows`, then follow [the publication guide](docs/SUBMISSION.md). The standalone repository hosts the reference and evidence. The standards proposal itself is submitted separately through a fork and pull request to **ethereum/ERCs**, in **`ERCS/`**. An unrelated standalone repository cannot directly serve as a PR branch of upstream history.

## Licenses

The proposal, the normative interface and the copied upstream editorial configuration are CC0-1.0 ([LICENSE.md](LICENSE.md)). Reference implementation, tests, tooling and explanatory documentation are MIT ([LICENSE-MIT](LICENSE-MIT)), except where explicitly marked otherwise. Upstream dependencies retain their licenses. See [NOTICE.md](NOTICE.md).
