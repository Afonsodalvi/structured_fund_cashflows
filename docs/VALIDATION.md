# Validation evidence

Snapshot prepared on 2026-10-03. Reproduce with `./scripts/verify.sh`.

**113 unit/security/fuzz tests and 7 invariant predicates passed; no failures or skips.**
5 fuzz functions use 4096 runs each. The grouped invariant campaign uses 512 runs at depth 256 (131,072 handler calls, with all seven predicates checked). Foundry counts this as one runner case, not seven independent campaigns.

The handler explores 20 operation types across three actors, including atomic batches, donations and delegated transfers. It records zero unexpected reverts. Calls can legitimately return without changing state when prerequisites are absent; invocation counts do not imply every action made a transition. Random exploration is finite, not formal proof.

| Suite | Passed |
| --- | ---: |
| StructuredFundInvariantTest | 7 |
| StructuredFundAssetIntegrationTest | 5 |
| StructuredFundSecurityTest | 46 |
| StructuredFundTransientTest | 9 |
| StructuredFundCompositionTest | 10 |
| StructuredFundEventsTest | 6 |
| StructuredFundFactoryTest | 5 |
| StructuredFundVaultTest | 32 |

## Production coverage

| Contract | Lines | Functions | Branches |
| --- | ---: | ---: | ---: |
| StructuredFundEligibility | 100.0% | 100.0% | 100.0% |
| StructuredFundFactory | 100.0% | 100.0% | 100.0% |
| StructuredFundVault | 98.68% | 100.0% | 100.0% |
| StructuredFundVaultDeployer | 100.0% | 100.0% | 100.0% |

Measured with `forge coverage --ir-minimum`. Foundry warns that IR source mapping can be inaccurate; percentages do not prove semantic completeness. Gates require 100% functions/branches and at least 98.5% lines; only four exact reviewed source-map gaps may remain unmarked. Their raw counts stay in the denominator. See [coverage interpretation](COVERAGE.md).

## Runtime size

| Contract | Bytes | EIP-170 headroom |
| --- | ---: | ---: |
| StructuredFundEligibility | 3684 | 20892 |
| StructuredFundFactory | 4560 | 20016 |
| StructuredFundVault | 18236 | 6340 |
| StructuredFundVaultDeployer | 21061 | 3515 |

Normal compiler artifacts are checked before coverage instrumentation. Runtime gate is 24,064 bytes, preserving at least 512 bytes below EIP-170; creation code is separately bounded.

## Transient-guard gas probe

The identical-work guard probes measured 23434 gas for the persistent guard and 21533 for the transient guard: a difference of 1901 gas. These Foundry frame snapshots include harness accounting and are not a whole-vault savings claim.

## Static and editorial checks

Slither 0.11.6 ran 102 detectors with no unreviewed finding. ERC-20 interface checks and three security printers also ran; the standard ERC-20 allowance replacement race is documented in [TOOLCHAIN](TOOLCHAIN.md). The reviewed findings concern closed-period timestamps and balance/eligibility checks plus storage writes inside the role-controlled, reentrancy-guarded batch, which is bounded to 64 records. An informational literal-length finding refers to compiler-generated CREATE2 creation bytecode. Each exact description has a fingerprint and rationale. High/Medium findings are never accepted.

eipw 0.11.0 passed the content check using the exact upstream configuration/commit recorded in `upstream.lock.json`. Four metadata checks remain explicitly excepted because the ERC number and public discussion do not exist. The official upstream CI has not run for this proposal.

The full normative interface is compared with the source, including struct fields and events. Its computed identifier remains `0x2e0b288e`. Python regression tests exercise interface drift, export validation and static-analysis rejection gates.

## Evidence and limits

See [machine-readable validation](../reports/validation.json), [source manifest](../reports/manifest.json), [editorial result](../reports/editorial.json), [test log](../reports/tests-ci.log) and [Slither gate](../reports/slither-gate.json). Paths in the copied Slither report are normalized to the repository root.

No RPC, on-chain state change, independent audit, formal verification, public discussion, assigned ERC number or external adoption is implied. Trusted valuation/entitlements, exact-transfer asset assumptions and profile limits remain in [REVIEW](REVIEW.md) and [SECURITY](SECURITY.md).
