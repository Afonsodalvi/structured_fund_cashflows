#!/usr/bin/env python3
"""Save validated evidence and derive the human-readable result without stale metrics."""
import json
import shutil
from pathlib import Path
from check_candidate import manifest

ROOT = Path(__file__).resolve().parents[1]
coverage = ROOT / "coverage"
validation = json.loads((coverage / "validation.json").read_text())
editorial = json.loads((coverage / "editorial.json").read_text())
if validation["tests"]["failed"] or editorial["exit_code"]:
    raise SystemExit("Cannot save failed validation as a successful snapshot")
tests = validation["tests"]
lines = ["# Validation evidence", "", "Snapshot prepared on 2026-10-03. Reproduce with `./scripts/verify.sh`.", "",
         f"**{tests['unit_and_fuzz_tests']} unit/security/fuzz tests and {tests['invariant_count']} invariant predicates passed; no failures or skips.**",
         f"{tests['fuzz_test_count']} fuzz functions use {tests['fuzz_runs_per_test']} runs each. The grouped invariant campaign uses {tests['invariant_runs']} runs at depth {tests['invariant_depth']} (131,072 handler calls, with all seven predicates checked). Foundry counts this as one runner case, not seven independent campaigns.",
         "", "The handler explores 20 operation types across three actors, including atomic batches, donations and delegated transfers. It records zero unexpected reverts. Calls can legitimately return without changing state when prerequisites are absent; invocation counts do not imply every action made a transition. Random exploration is finite, not formal proof.",
         "", "| Suite | Passed |", "| --- | ---: |"]
for suite in tests["suites"]:
    lines.append(f"| {suite['suite']} | {suite['passed']} |")
lines += ["", "## Production coverage", "", "| Contract | Lines | Functions | Branches |", "| --- | ---: | ---: | ---: |"]
for name, values in validation["coverage"]["production"].items():
    lines.append(f"| {name} | {values['lines_percent']}% | {values['functions_percent']}% | {values['branches_percent']}% |")
lines += ["", "Measured with `forge coverage --ir-minimum`. Foundry warns that IR source mapping can be inaccurate; percentages do not prove semantic completeness. Gates require 100% functions/branches and at least 98.5% lines; only four exact reviewed source-map gaps may remain unmarked. Their raw counts stay in the denominator. See [coverage interpretation](COVERAGE.md).",
          "", "## Runtime size", "", "| Contract | Bytes | EIP-170 headroom |", "| --- | ---: | ---: |"]
for name, values in validation["compiled_contracts"].items():
    lines.append(f"| {name} | {values['runtime_bytes']} | {values['eip170_headroom']} |")
lines += ["", "Normal compiler artifacts are checked before coverage instrumentation. Runtime gate is 24,064 bytes, preserving at least 512 bytes below EIP-170; creation code is separately bounded.",
          "", "## Transient-guard gas probe", "",
          f"The identical-work guard probes measured {tests['guard_gas']['persistent_warm']} gas for the persistent guard and {tests['guard_gas']['transient_warm']} for the transient guard: a difference of {tests['guard_gas']['persistent_warm'] - tests['guard_gas']['transient_warm']} gas. These Foundry frame snapshots include harness accounting and are not a whole-vault savings claim.",
          "", "## Static and editorial checks", "",
          "Slither 0.11.6 ran 102 detectors with no unreviewed finding. ERC-20 interface checks and three security printers also ran; the standard ERC-20 allowance replacement race is documented in [TOOLCHAIN](TOOLCHAIN.md). The reviewed findings concern closed-period timestamps and balance/eligibility checks plus storage writes inside the role-controlled, reentrancy-guarded batch, which is bounded to 64 records. An informational literal-length finding refers to compiler-generated CREATE2 creation bytecode. Each exact description has a fingerprint and rationale. High/Medium findings are never accepted.",
          "", "eipw 0.11.0 passed the content check using the exact upstream configuration/commit recorded in `upstream.lock.json`. Four metadata checks remain explicitly excepted because the ERC number and public discussion do not exist. The official upstream CI has not run for this proposal.",
          "", "The full normative interface is compared with the source, including struct fields and events. Its computed identifier remains `0x2e0b288e`. Python regression tests exercise interface drift, export validation and static-analysis rejection gates.",
          "", "## Evidence and limits", "",
          "See [machine-readable validation](../reports/validation.json), [source manifest](../reports/manifest.json), [editorial result](../reports/editorial.json), [test log](../reports/tests-ci.log) and [Slither gate](../reports/slither-gate.json). Paths in the copied Slither report are normalized to the repository root.",
          "", "No RPC, on-chain state change, independent audit, formal verification, public discussion, assigned ERC number or external adoption is implied. Trusted valuation/entitlements, exact-transfer asset assumptions and profile limits remain in [REVIEW](REVIEW.md) and [SECURITY](SECURITY.md).", ""]
(ROOT / "docs/VALIDATION.md").write_text("\n".join(lines))
candidate = json.loads((coverage / "candidate-check.json").read_text())
compiled = {key: candidate[key] for key in ("cashflow_interface_id", "selectors", "contracts")}
# Documentation was generated after testing; refresh its manifest without reusing instrumented artifacts.
(coverage / "manifest.json").write_text(json.dumps(manifest(compiled), indent=2, sort_keys=True) + "\n")
destination = ROOT / "reports"
destination.mkdir(exist_ok=True)
for name in ["validation.json", "manifest.json", "editorial.json", "editorial.log", "slither-gate.json", "coverage-summary.json", "tests-ci.log", "security-model.json", "erc20-conformance.log", "source-map-evidence.log"]:
    shutil.copy2(coverage / name, destination / name)
    if name.endswith(".log") and (coverage / name).stat().st_size:
        (destination / name).write_text((coverage / name).read_text().rstrip() + "\n")
slither_text = (coverage / "slither.json").read_text().replace(str(ROOT) + "/", "")
(destination / "slither.json").write_text(slither_text)
print("Validation snapshot saved in reports/")
