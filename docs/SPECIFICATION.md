# Structured Fund Cashflows

Working paper — no assigned ERC number or public discussion yet.

Author: Afonso Dalvi (@Afonsodalvi). This readable copy is generated from the [submission source](../ERCS/erc-draft_structured_fund_cashflows.md); only standard links and presentation are adapted.

## Abstract

This proposal extends [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) with an interface for observing principal associated with fund shares and claiming funded cashflows. Each implementation exposes one immutable accounting scope. Cashflows distinguish repayment of principal, gross yield, and withholding, and identify a beneficiary, a closed reporting period, and an evidence commitment. Transferable shares carry their remaining principal; previously recorded cashflow rights remain with their designated beneficiary. Redemption retires associated principal independently of the amount of assets recovered. The interface complements existing vault entry and exit standards without specifying portfolio origination, valuation, seniority, or legal enforcement.

## Motivation

Vault integrations can observe shares and assets but cannot consistently distinguish an amortization of invested principal from a distribution of gross yield or a net payment after withholding. A share balance is not a record of remaining contributed principal, and a decrease in that principal may reflect either an actual funded amortization or retirement of a position after a loss.

Structured credit products also separate a fund into series and share classes. If accounting scope and monetary units are implicit, an integrator can combine incompatible positions, count escrowed redemption shares as unissued inventory, or leave principal assigned to an account after its shares have moved.

The proposed interface provides a common vocabulary and observable state for these operations. It does not assert that tranching, dividend claims, taxation, or asynchronous withdrawals are new mechanisms. Its intended interoperability benefit is reconciliation of principal movements and funded cashflow obligations using a consistent, narrowly defined API.

## Specification

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED, NOT RECOMMENDED, MAY, and OPTIONAL in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Scope and units

An implementation MUST implement ERC-4626 and [ERC-165](https://eips.ethereum.org/EIPS/eip-165), including the modifications specified by [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540) when an asynchronous flow is implemented. In this profile, the vault itself MUST be the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) share token, and the asset address and asset decimals MUST remain unchanged throughout the scope lifetime. It MUST expose an immutable, nonzero `scopeId`. One scope MUST represent a single fungible accounting class. Separate series or classes with different entitlements MUST NOT be combined under one scope. A scope identifier is a domain identifier, not proof of legal ownership or of a portfolio's authenticity.

All monetary values in this interface MUST use the native units of the ERC-4626 `asset`. Share quantities MUST use the native units of the share token. Implementations MUST NOT silently substitute 18-decimal accounting units for an asset with different decimals.

The domain of a cashflow identifier is the chain, the vault address, its scope, and the identifier. For a proxy, the vault address is the proxy address, not the replaceable logic contract. Identical identifiers on different implementations do not imply identical rights.

### Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

interface IStructuredFundCashflows {
    struct Cashflow {
        address beneficiary;
        uint256 principal;
        uint256 grossYield;
        uint256 withheld;
        uint64 periodStart;
        uint64 periodEnd;
        bytes32 evidenceHash;
        bool claimed;
    }

    event CashflowRecorded(
        bytes32 indexed cashflowId,
        bytes32 indexed scopeId,
        address indexed beneficiary,
        uint256 principal,
        uint256 grossYield,
        uint256 withheld,
        uint64 periodStart,
        uint64 periodEnd,
        bytes32 evidenceHash
    );
    event CashflowClaimed(
        bytes32 indexed cashflowId,
        address indexed beneficiary,
        address indexed receiver,
        uint256 netAssets
    );
    event PrincipalMoved(address indexed from, address indexed to, uint256 principal);
    event PrincipalRetired(address indexed controller, uint256 principal, uint256 shares);

    function scopeId() external view returns (bytes32);
    function principalOf(address account) external view returns (uint256);
    function lockedPrincipalOf(address controller) external view returns (uint256);
    function totalOutstandingPrincipal() external view returns (uint256);
    function cashflow(bytes32 cashflowId) external view returns (Cashflow memory);
    function claimCashflow(bytes32 cashflowId, address receiver) external returns (uint256 netAssets);
}
```

Implementations MUST return `true` from `supportsInterface` for `0x2e0b288e`, obtained by XORing the selectors of the six functions above. Events do not contribute to the interface identifier. The identifier MUST be recalculated if the normative interface changes; implementations MUST NOT use an arbitrarily assigned ERC number as the identifier.

### Principal accounting

`principalOf(account)` MUST return the remaining contributed principal associated with that account's freely held shares. `lockedPrincipalOf(controller)` MUST return principal associated with shares held for pending redemption or claimable cancelation under that controller. Both views MUST be caller independent, MUST NOT revert, and MUST return zero for an account without the corresponding principal. `scopeId`, `totalOutstandingPrincipal`, and `cashflow` MUST also be caller independent and MUST NOT revert. An account with no freely held shares MUST have zero freely held principal.

`totalOutstandingPrincipal` MUST equal the sum of freely held and locked principal. A zero address or an internal escrow address MUST NOT introduce a second copy of locked principal into this total.

A completed synchronous deposit or mint MUST add the actual assets contributed to the receiver's principal. For an asynchronous deposit, pending or refundable assets MUST NOT create principal. Principal MUST be credited exactly once to the receiver when shares are delivered by the deposit or mint claim, using the assets consumed by that claim. Partial claims MUST NOT create duplicate principal. If shares are transferable, a transfer of `s` shares from an account holding `b` shares MUST move `floor(principalOf(from) * s / b)` principal to the recipient, using the pre-transfer balances. A transfer of all shares MUST move all remaining principal. Self-transfers MUST NOT change principal. Non-self transfers MUST emit `PrincipalMoved`, including zero-value transfers. The rule applies to every transfer path, including a privileged transfer if supported. A privileged share transfer MUST NOT silently reassign a previously recorded cashflow. An implementation MAY prohibit transfers consistently with ERC-4626.

Moving shares to redemption custody MUST remove the corresponding principal from the owner's freely held principal and associate it with the controller's locked principal. Cancelation MUST restore the captured principal with the returned shares. Escrow aggregation MUST NOT recalculate that captured principal from the pooled ERC-20 balance of multiple owners.

When a redemption irrevocably retires shares, the associated principal MUST be retired exactly once and `PrincipalRetired` MUST be emitted. That principal MUST cease to be outstanding by the time the redemption is claimed. Retirement is independent of the assets recovered and MUST NOT be reported as a funded cashflow amortization solely because a redemption occurred.

Principal under this proposal is a reconciliation ledger. It is not a jurisdiction-specific tax basis, an asset valuation, a promise to repay the original contribution, or a per-lot purchase history.

### Cashflow records

A recorded cashflow MUST have a nonzero, previously unused identifier and beneficiary, a nonzero evidence hash, `periodStart < periodEnd`, `periodEnd <= block.timestamp`, `withheld <= grossYield`, and a nonzero `principal + grossYield`. A period is described by the half-open interval `[periodStart, periodEnd)`. An implementation MAY enforce stricter ordering or non-overlap requirements and MUST disclose them to integrators.

At recording, `claimed` MUST be `false`. The beneficiary and every other record field MUST become immutable at recording. Only `claimed` MAY subsequently change, exactly once from `false` to `true` on a successful claim. Implementations MUST preserve the record after consumption and MUST NOT reuse its identifier. `cashflow` MUST be caller independent and MUST return a zero-valued record for an unknown identifier.

The net beneficiary entitlement is:

```text
netAssets = principal + grossYield - withheld
```

The implementation MUST reserve the full net amount before emitting `CashflowRecorded`. Recorded liabilities MUST NOT be counted as assets available for another cashflow, investment, or redemption. Withheld amounts MUST NOT remain simultaneously available as beneficiary entitlement or vault NAV. This requirement does not prescribe the tax remittance mechanism.

The cashflow's principal component MUST NOT exceed the beneficiary's freely held principal. Recording MUST reduce that principal and total outstanding principal by the same amount exactly once. Claiming MUST NOT reduce them a second time. Any principal or yield already included in managed portfolio value MUST cease to be counted in ERC-4626 `totalAssets` when committed to a cashflow obligation. Externally funded yield not previously included in managed value MUST NOT be subtracted from it a second time. Assets already reserved for claims MUST NOT inflate the conversion rate of remaining shares. Yield MUST NOT be silently added to the principal ledger.

Recorded cashflow rights MUST remain with the designated beneficiary when shares subsequently move. A future holder receives the remaining share-associated principal, not a previously recorded payment obligation. Implementations MUST emit `CashflowRecorded` with the exact immutable values.

This proposal does not specify the mutation method that establishes a record. It can be established by authorized settlement, proof verification, or another mechanism, subject to all funding and immutability requirements above. Implementations MUST document the authority or proof mechanism that determines entitlements. An evidence hash alone MUST NOT be described as verification of a real-world event. Implementations MUST document record-date entitlement, the treatment of pending redemption shares, and the method used to reconcile multiple beneficiaries against a common NAV. Related allocations SHOULD be booked atomically or with share-price-sensitive operations gated until completion; partial booking MUST NOT be presented as a complete distribution snapshot.

### Claim

`claimCashflow` MUST require authorization from the beneficiary. An implementation MAY support beneficiary-approved operators and MAY enforce documented compliance restrictions on the beneficiary and receiver. A share allowance alone MUST NOT authorize consumption of an independently recorded cashflow.

A successful claim MUST transfer exactly `netAssets` of the asset to the receiver, mark the record as claimed, reduce the corresponding reserve, return that amount, and emit `CashflowClaimed`. If the transfer fails or is inexact, the entire claim MUST revert. Zero net assets, such as a fully withheld yield-only record, MUST be consumable and marked claimed without requiring an asset transfer.

The zero address and the vault itself MUST be invalid receivers. An unknown record, already consumed record, unauthorized claimant, or invalid receiver MUST cause the claim to revert. Claims MUST NOT be duplicated, including through external token callbacks. An implementation MAY pause claims, but MUST disclose its pause and recovery policy.

### Composition with asynchronous vaults

Implementations with asynchronous redemption SHOULD compose with [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540). Its pending and claimable redemption views continue to use shares, independently of the principal ledger. Principal held in a pending request MUST NOT be simultaneously amortized as freely held principal. Cancelation restores captured principal; irrevocable redemption retires it.

Claims under this proposal are separate from ERC-4626 deposit, mint, withdraw, and redeem. A cashflow MUST NOT create an implicit redemption request, and the same asset liability MUST NOT back both a cashflow claim and a redemption claim.

## Rationale

### One accounting scope

Different seniorities and series can have different prices and rights. A single scope with one fungible share class avoids imposing a portfolio-specific tranche representation on the standard. Implementations can expose multiple independent scopes through their own registries or factories.

### Principal separate from NAV

NAV measures managed value. Principal records contributed capital still associated with outstanding positions. Losses can make NAV smaller than principal, and accrued yield can make it larger. Reporting the two as identical makes amortization and loss reconciliation ambiguous. Explicit retirement distinguishes cancellation of an economic position from return of its original capital.

### Individual immutable cashflows

Named beneficiaries and permanent identifiers permit an integrator to determine who can claim a funded obligation and whether it has been consumed. Snapshot distributions and proof-based batches remain possible implementation choices. The standard does not require enumeration of every holder, a specific Merkle format, global iteration, or a portfolio's settlement authority.

### Gross yield and withholding

Gross yield, retained yield, and returned principal describe different economic movements. A net amount alone cannot expose those distinctions. This interface standardizes the fields without prescribing tax rules, rates, reporting requirements, or payment recipients.

### Integration boundaries

This profile uses one asset denomination and a share token implemented by the vault itself. It does not define foreign-exchange conversion, multiple asset entry points sharing an external token, fee-share issuance, rebasing shares, or cross-chain principal synchronization. Extending the interface to those cases requires an explicit conservation model; advertising their compatibility without that model would leave principal ambiguous. Non-transferable vaults remain possible.

An asynchronous deposit is credited on delivery of shares rather than on submission of the request: pending assets may still be refunded. Redemption principal is captured before aggregation so cancelation can restore the same amount.

The interface uses gross yield and withholding without interpreting local tax rules. A principal repayment and a distribution from already accrued yield both remove managed value; subtracting only the principal component can overstate the remaining NAV.

### Related standards

ERC-4626 describes vault shares and asset exchanges; ERC-7540 extends those exchanges with asynchronous request lifecycles. [ERC-3643](https://eips.ethereum.org/EIPS/eip-3643) addresses regulated token identity and compliance. [ERC-3525](https://eips.ethereum.org/EIPS/eip-3525) and [ERC-3475](https://eips.ethereum.org/EIPS/eip-3475) provide alternative position representations. [ERC-7943](https://eips.ethereum.org/EIPS/eip-7943) provides a common interface for compliance controls and enforcement, while [ERC-7776](https://eips.ethereum.org/EIPS/eip-7776) addresses financial statement data. [ERC-7575](https://eips.ethereum.org/EIPS/eip-7575) permits external share tokens and multiple asset entry points, which need a separate principal-denomination model before they can be supported here. Earlier dividend-accumulator and funds-distribution designs already preserve historical payouts through token transfers; this proposal does not claim that mechanism as new. The proposed interface targets the narrower reconciliation of remaining share-associated principal and funded principal/yield/withholding obligations. Community review should assess whether this warrants an independent extension or can be incorporated into existing work.

## Backwards Compatibility

The proposal introduces new views, events, and a claim method. It does not change ERC-4626 selectors or its asset/share units. Existing vaults are not compliant solely because they expose similarly named methods: they must maintain the specified ledger and reserve semantics.

Previously recorded entitlements do not automatically follow share transfers. Integrators must distinguish freely held principal, locked principal, retired principal, and claimable cashflows. Legacy implementations lacking principal associated with transferred shares require explicit migration and reconciliation.

## Test Cases

At minimum, implementations should cover these cases, with all asset amounts in native units:

| Case | Initial state | Action | Expected result |
| --- | --- | --- | --- |
| Principal transfer | 100 shares, principal 100 | Transfer 40 shares | Principal 60/40; total 100 |
| Integral transfer | Remaining shares, principal 1 | Transfer all remaining shares | Sender principal 0; recipient receives 1 |
| Funded cashflow | Principal 100; P=20, Y=5, W=1 | Record then claim | Outstanding principal 80; net reserve/payment 24; withholding 1 |
| Double claim | Previously consumed id | Claim again | Revert; no state or asset movement |
| Historical beneficiary | Record for A, then transfer shares A→B | A claims | B receives remaining principal; A retains recorded right |
| Redemption loss | Locked principal 100; assets recovered 70 | Finalize redemption | Principal retired 100; redemption pays 70; no amortization record implied |
| Cancelation | Captured principal 40 | Cancel and claim returned shares | Exactly 40 principal restored |
| Fully withheld yield | P=0, Y=1, W=1 | Claim | Claimed true; zero asset transfer |
| Inexact transfer | Funded unclaimed cashflow | Asset delivers less than net | Entire claim reverts; right remains unconsumed |

## Reference Implementation

The accompanying candidate implementation maintains separate managed cash, credit NAV, redemption reserves, cashflow reserves, free principal, and controller-associated locked principal. Synchronous entry uses ERC-4626 rounding; redemption custody preserves issued supply until fulfillment. Mutation methods and access-control choices are examples rather than required parts of this interface. An implementation may book a bounded list of beneficiary records atomically while keeping the standardized claim interface individual. The specification does not infer or prove a correct allocation merely from successful recording.

## Security Considerations

Authorization and correct entitlement calculation are distinct. An authorized settlement party can still allocate a payment incorrectly. Implementations must disclose their valuation, entitlement, proof, compliance, and administrative assumptions. Evidence commitments do not authenticate off-chain assets or cross-chain settlement by themselves.

Cashflow reserves must remain segregated from deployable assets and redemption obligations. Principal cannot be copied between freely held and escrowed positions, reduced twice, or treated as proof of recoverable value. Share transfers require precise rounding and complete transfer of residual principal when the sender exits its full balance. Flooring on repeated small transfers can leave more principal with the sender than a single aggregate transfer would; this ledger is not a per-lot cost basis. Allocating one holder a payment out of shared NAV can affect every holder's share value. Correct record-date allocation, treatment of escrowed shares, and atomic distribution boundaries therefore require explicit product policy. The six methods do not prove proportionality or fairness.

Token callbacks can reenter recording or claim operations. State transitions must be atomic, with claims consumed before external interactions and guarded against reentrancy. Assets with fees, rebasing, arbitrary balance changes, pauses, or blacklists may violate availability and funding assumptions. An implementation should reject unsupported asset behavior and disclose its supported asset model.

Operators may be authorized to redirect a beneficiary's payment to an eligible receiver. Such authority must be deliberate, revocable, and clearly exposed. A frozen beneficiary can remain unable to claim, so implementations must disclose recovery and governance policies. Timestamp checks only establish a closed reporting period; they do not prove a cashflow's economic timing or authenticity.

Portfolio default, incorrect valuation, unfair settlement ordering, compromised governance, unavailable evidence, and migration errors remain material risks outside this interface. Automated tests and static analysis do not establish universal security or regulatory compliance.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
