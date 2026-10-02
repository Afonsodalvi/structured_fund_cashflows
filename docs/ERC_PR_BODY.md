## Proposal

Introduce Structured Fund Cashflows, a scoped ERC-4626 extension for remaining principal and funded principal/yield/withholding obligations. It defines principal movement with shares, capture during redemption custody, retirement independently of recovery value, and authorized single-use cashflow claims.

The proposal complements vault lifecycle and compliance standards. It does not claim novelty for tranches, dividend preservation, withdrawal queues or withholding itself. It requires one asset denomination and a vault that is its own share token.

## Discussion and validation

The submitted preamble must contain the real Ethereum Magicians discussion URL. The source is prepared with author Afonso Dalvi (@Afonsodalvi); number and filename are subject to editorial assignment.

Local validation includes specification/interface consistency, Foundry unit/security/fuzz/invariant tests, reserve conservation, static analysis, coverage gates and eipw against the pinned upstream configuration. Before publishing this PR, replace this paragraph with a link to the exact public reference commit and its actual results in the discussion thread, subject to repository link rules. No independent audit or approval guarantee is asserted.
