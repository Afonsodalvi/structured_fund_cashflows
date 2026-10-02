# Validation evidence

Snapshot prepared on 2026-10-02. Reproduce with `./scripts/verify.sh`.

**102 Solidity tests passed; 0 failed; 0 skipped.**
Four fuzz tests use 2048 runs each. Five stateful invariants use 256 runs at depth 128 each (32,768 handler calls per invariant), with zero unexpected reverts.

The handler explores 17 operation types across three actors. Batch atomicity and accounting have separate unit/security/fuzz tests; batches are not a separate handler action. Random exploration is finite, not formal proof.

| Suite | Passed |
| --- | ---: |
| StructuredFundInvariantTest | 5 |
| StructuredFundSecurityTest | 46 |
| StructuredFundCompositionTest | 10 |
| StructuredFundEventsTest | 6 |
| StructuredFundFactoryTest | 5 |
| StructuredFundVaultTest | 30 |

## Production coverage

| Contract | Lines | Functions | Branches |
| --- | ---: | ---: | ---: |
| StructuredFundEligibility | 100.0% | 100.0% | 100.0% |
| StructuredFundFactory | 100.0% | 100.0% | 100.0% |
| StructuredFundVault | 98.68% | 100.0% | 100.0% |
| StructuredFundVaultDeployer | 100.0% | 100.0% | 100.0% |

Measured with `forge coverage --ir-minimum`. Foundry warns that IR source mapping can be inaccurate; percentages do not prove semantic completeness. Gates require at least 95% lines/branches and 100% functions in own production contracts.

## Runtime size

| Contract | Bytes | EIP-170 headroom |
| --- | ---: | ---: |
| StructuredFundEligibility | 3684 | 20892 |
| StructuredFundFactory | 4471 | 20105 |
| StructuredFundVault | 18055 | 6521 |
| StructuredFundVaultDeployer | 21036 | 3540 |

Normal compiler artifacts are checked before coverage instrumentation. Runtime gate is 24,064 bytes, preserving at least 512 bytes below EIP-170; creation code is separately bounded.

## Static and editorial checks

Slither 0.11.3 completed with no unreviewed finding. The reviewed findings concern closed-period timestamps and balance/eligibility checks plus storage writes inside the role-controlled, reentrancy-guarded batch, which is bounded to 64 records. An informational literal-length finding refers to compiler-generated CREATE2 creation bytecode. Each exact description has a fingerprint and rationale. High/Medium findings are never accepted.

eipw 0.11.0 passed the content check using the exact upstream configuration/commit recorded in `upstream.lock.json`. Four metadata checks remain explicitly excepted because the ERC number and public discussion do not exist. The official upstream CI has not run for this proposal.

The full normative interface is compared with the source, including struct fields and events. Its computed identifier remains `0x2e0b288e`. Python regression tests exercise interface drift, export validation and static-analysis rejection gates.

## Evidence and limits

See [machine-readable validation](../reports/validation.json), [source manifest](../reports/manifest.json), [editorial result](../reports/editorial.json), [test log](../reports/tests-ci.log) and [Slither gate](../reports/slither-gate.json). Paths in the copied Slither report are normalized to the repository root.

No RPC, on-chain state change, independent audit, formal verification, public discussion, assigned ERC number or external adoption is implied. Trusted valuation/entitlements, exact-transfer asset assumptions and profile limits remain in [REVIEW](REVIEW.md) and [SECURITY](SECURITY.md).
