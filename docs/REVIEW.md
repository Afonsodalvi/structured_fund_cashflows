# Review decisions — 2026-10-02

This is an internal specification and implementation review. It is not an independent audit. Sources, formal status and market-evidence limits are recorded in [the comparison](RWA_COMPARISON_PT.md).

| Finding | Resolution | Evidence |
| --- | --- | --- |
| Legacy editorial export used EIPS/eip-* and the old license link | Export now targets ERCS/erc-* and the exact current copyright text | Upstream-config eipw run; export/repository checks |
| Earlier dividend/FDT proposals were treated as canonical relative ERC links despite not being present in the official corpus | Removed broken canonical links; explicitly acknowledged mechanisms in the rationale and cited original author sources in research | Comparison and corpus review |
| ERC-7575 share discovery was incomplete | Added `vault(asset)` lookup and share interface ID `0xf815c03d` | Lookup, negative-asset and 30,000-gas discovery tests |
| Asynchronous deposit principal timing was unspecified | Principal is added on delivery of shares, never for pending/refundable assets | Normative clarification; reference explicitly advertises synchronous deposits only |
| Already recognized yield could be misunderstood as remaining NAV | Both principal and yield committed from managed value must leave NAV; external unrecognized yield is not subtracted twice | Existing accrued/partial-yield regression tests and batch accounting test |
| A distribution spanning beneficiaries lacked an atomic reference entry point | Added bounded batches of up to 64; a late invalid/underfunded record rolls back all records, NAV and tax transfers | New batch unit/security/fuzz tests |
| Interface checking compared selectors only | Solidity interface tokens, including struct order, outputs and event indexing, now match normative text | Tooling regression tests |
| Identifier domain said implementation address | Clarified vault address, including proxy address when applicable | Normative text |
| Record immutability could be read to forbid changing claimed | Only `claimed` can transition false→true; every other field remains immutable | Normative text and existing claim tests |
| Initial version could be read as universally composable with ERC-7575 | Explicit one-asset, self-share profile; external shares and FX are outside its conservation model | Scope, integration boundaries, comparison |
| Factory creation runtime approached the configured size reserve after hardening | Isolated creation in an immutable factory-bound deployer; preserved the 512-byte margin gate | Deployment authorization, prediction, rollback and bytecode checks |
| Reference depended on parent repository libraries/workflow | Independent Git repository, exact upstream submodule commits, local workflow and source manifest | Fresh-clone verification |

The factory also registers the predicted CREATE2 address before the external deployment call, with a reentrancy guard and atomic rollback. The immutable deployer uses identical creation code and constructor arguments for prediction and creation.

## Decisions retained

The interface stays at six methods and identifier `0x2e0b288e`. Factory, eligibility policy, batch booking, NAV reporting, role names and credit deployment are reference-specific APIs. The standard does not add a loan engine or a second compliance system.

Principal is an aggregate contributed-capital reconciliation ledger, not a tax-lot basis or guaranteed redemption amount. Transfer rounding floors pro rata; transferring all shares takes the residual. Splitting a transfer can change the distribution of rounding residue. Integrators must not infer individual purchase costs from this ledger.

Gross funding in the reference is stricter than the minimum net-reserve obligation of the interface. The reference remits withholding atomically to an immutable recipient. Tax calculation and evidence authenticity remain external.

## Material limits and open design questions

Allocation is trusted. A batch proves atomic booking of its supplied list, not that all eligible holders were included or that payouts were proportional. Pending shares remain economically outstanding until fulfillment; cashflow principal cannot consume their captured principal. Product policy must reconcile their yield and NAV treatment before booking distributions. The reference is not an automated production distribution engine for every entitlement policy.

Large distributions beyond 64 records need a reviewed snapshot/epoch mechanism that gates price-sensitive operations; splitting a single economic distribution into ordinary sequential calls can create intermediate-price exposure. No such multi-transaction epoch mechanism is supplied here.

The profile excludes shared external share tokens, multi-asset denomination, share rebases, fee-share issuance and cross-chain synchronization. This reduces ambiguity but limits direct integration with existing multi-entry-point architectures. Community feedback should decide whether to widen the profile before advancing it.

Mandatory evidence commitments, interval-based principal payments, recoverability of historical rights after a lost key, and operator discovery are explicit discussion topics. Their absence from a universal solution is not concealed by reference-code coverage.

Publication still requires a real public discussion and editorial numbering. Formal verification, independent audit and external implementer adoption have not occurred.
