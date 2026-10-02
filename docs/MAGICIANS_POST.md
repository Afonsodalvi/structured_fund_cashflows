# Proposed ERC: Structured Fund Cashflows

I would like feedback on a narrowly scoped extension to ERC-4626 for remaining principal and funded cashflow reconciliation.

Vault asset/share conversions and asynchronous requests do not give integrators a common interface to distinguish principal amortization, gross yield, withholding and the retirement of principal after a loss. The proposed interface exposes these movements without standardizing loan origination, a valuation oracle, a waterfall or legal enforcement.

The interface has six methods: `scopeId`, `principalOf`, `lockedPrincipalOf`, `totalOutstandingPrincipal`, `cashflow` and `claimCashflow`. Amounts use asset-native units. Share transfers move remaining principal; previously recorded payment rights remain with their beneficiary. A funded payment segregates its net obligation before becoming claimable. Redeeming a loss-making position retires its associated principal independently of assets recovered.

Earlier dividend-paying and Funds Distribution Token proposals, including the work discussed as ERC-1726 and ERC-2222, already preserve historical distributions across transfers. SFC does not claim that mechanism as new. The question is whether the combined principal/reserve/gross-net semantics offer enough interoperable value to justify an extension.

The initial profile has one asset denomination and requires the vault to be its share token. External share tokens and multi-asset entry points need a coherent denomination and retirement model. The reference supports synchronous entry, asynchronous redemption, cancelation and atomic bounded distribution batches. It uses trusted valuation and entitlement allocation, and has no independent audit.

Questions for review:

1. Is remaining contributed principal sufficiently useful as an interoperable ledger when it is neither NAV nor tax-lot basis?
2. Should external share tokens be addressed in a separate profile before this proposal advances?
3. Which record-date and pending-redemption policies can be made interoperable without prescribing a fund's distribution algorithm?
4. Is a mandatory nonzero evidence commitment useful, or should it be optional?
5. Should principal-only amortizations use an interval, or would an effective timestamp fit better?
6. Should operator approval for cashflow claims remain implementation-defined or become a separate interface?
7. Is this better advanced as an independent extension or incorporated into existing distribution work?

The accompanying repository contains the specification, reference, test evidence and comparison. Add its actual published URL before posting. No ERC number has been assigned.

Author: Afonso Dalvi (@Afonsodalvi).
