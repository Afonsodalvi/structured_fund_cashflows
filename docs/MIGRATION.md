# Adoption and migration boundaries

An existing upgradeable fund can implement this interface through compatible modules. Adding the six selectors alone is insufficient: all transfer, issuance, redemption, cashflow and reserve paths must preserve its accounting semantics.

The reference in this repository is immutable and uses a constructor. It cannot be installed as a replacement implementation behind an unrelated existing proxy. It includes no balance import, privileged migration mint or production upgrade script.

For an existing fund, inventory the actual deployed implementations and authorities, choose an accounting cutover block, reconcile share balances against positions and payments, identify free/locked/retired principal, and allocate NAV by class without counting a shared portfolio twice. Preserve previously recorded rights and prove the old and new representations cannot both be redeemed. Storage-layout and selector compatibility need separate validation.

Start adoption with a new series when practical. Existing positions require an explicit, product-specific migration module and fork tests against the real contracts. Never use a normal deposit without transferring assets to simulate a migration: it creates fictitious funding.

The current profile requires one fungible class, one asset denomination and the vault itself as share token. A pooled external token spanning asset entry points needs an extension of the accounting model before migration can be called conformant.
