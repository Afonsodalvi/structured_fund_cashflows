# Coverage interpretation and strict gate

Coverage is measured against all four production contracts with Solidity 0.8.37 and `forge coverage --ir-minimum`. The latest raw counts are in [coverage-summary.json](../reports/coverage-summary.json). Dependencies and test harnesses are not included in the product's percentages.

The gate requires **100% of functions and branches**, and **at least 98.5% of lines**, with no missing production file. It additionally rejects **every unmarked line except the four exact source locations reviewed below**. Those lines stay in the denominator and remain reported as uncovered; no adjusted “100%” is claimed.

| Vault statement | Behavioral evidence | Interpretation |
| --- | --- | --- |
| `pause`: `_pause()` | `test_MaxFunctionsTrackCapPauseEligibilityAndClaimable` and security pause tests assert limits and rejected entries | IR mapping does not attribute the wrapper statement, although the inherited pause operation executes |
| `unpause`: `_unpause()` | The same limit test resumes and checks restored entry capacity; stateful handler toggles both states | Wrapper-to-inherited-call attribution gap |
| `_update`: `_requireNotPaused()` | Transfer tests exercise this path; `test_SecuritySharesDoNotTransferDuringPause` asserts the rejection | Inlined inherited-check attribution gap |
| `requestRedeem`: `return 0` | Base `_request` asserts the returned zero; request aggregation tests assert request-zero state | Constant-return attribution gap |

The exact locations and text are pinned in `scripts/check_coverage.py`. Moving code requires reviewing the exception again. These are measured source-map limitations, not permission to omit tests. CI keeps [transaction traces](../reports/source-map-evidence.log) for the positive and negative behavior.

A coverage run without via-IR was attempted and failed with `Stack too deep` in the factory's configuration-heavy creation method. The normal artifact already uses via-IR. Production code is not distorted solely to raise a source-map number.

The new compiler exposed two previously unmeasured branches: withdrawing the entire claim and querying cancelation rights with a nonzero ID. Dedicated tests now cover both. Foundry's coverage instrument has its own compiler settings, so bytecode-size and gas measurements come from the normal optimized build before instrumentation.

A high percentage demonstrates exercised instrumented code, not proof that all economically relevant sequences have been tested. The seven stateful properties, callback matrix, rejection tests and manual trust-model review supply different evidence and are reported separately.
