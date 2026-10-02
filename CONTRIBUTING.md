# Contributing

Discuss semantic changes with the author before proposing compatibility claims. Changes to selectors, return tuples, indexed event fields, units or principal/reserve behavior require coordinated updates to the specification, interface, tests and integration documentation.

Run `./scripts/verify.sh`. Include the failure scenario and expected before/after behavior in a PR. Keep source code, validation evidence and editorial metadata consistent. Do not invent an ERC number, discussion URL, deployment address or adoption claim. Update `docs/SPECIFICATION.md` through `python3 scripts/render_spec.py`.

This repository develops the reference and working paper. Formal publication uses ethereum/ERCs and its editorial process; see [SUBMISSION](docs/SUBMISSION.md). Sensitive security issues should follow [SECURITY](SECURITY.md).
