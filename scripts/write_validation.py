#!/usr/bin/env python3
"""Build machine-readable evidence from successful local tool runs."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "coverage"
log = (out / "tests-ci.log").read_text()
suites = []
pattern = r"Ran (\d+) tests for ([^\n:]+):(\w+)\n(.*?)Suite result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) skipped;"
for match in re.finditer(pattern, log, re.S):
    count, path, name, body, status, passed, failed, skipped = match.groups()
    if status != "ok" or int(failed) or int(skipped) or int(count) != int(passed):
        raise SystemExit("Failed or incomplete test suite")
    suites.append({"suite": name, "path": path, "passed": int(passed)})
if len(suites) != 6:
    raise SystemExit("Expected all six candidate test suites")
fuzz = re.findall(r"\[PASS\] testFuzz_.*?\(runs: (\d+),", log)
invariants = re.findall(r"\[PASS\] invariant_.*?\(runs: (\d+), calls: (\d+), reverts: (\d+)\)", log)
if len(fuzz) != 4 or any(int(r) != 2048 for r in fuzz):
    raise SystemExit("Unexpected CI fuzz configuration")
if len(invariants) != 5 or any(tuple(map(int, r)) != (256, 32768, 0) for r in invariants):
    raise SystemExit("Unexpected invariant configuration or reverts")
candidate = json.loads((out / "candidate-check.json").read_text())
coverage = json.loads((out / "coverage-summary.json").read_text())
static = json.loads((out / "slither-gate.json").read_text())
if static["unreviewed"]:
    raise SystemExit("Static findings have not passed review")
inputs = [root / "foundry.toml"]
for folder in ("src", "test"):
    inputs.extend(sorted((root / folder).rglob("*.sol")))
hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
report = {
    "schema": 1, "candidate": "Structured Fund Cashflows", "publication_status": "local_unsubmitted",
    "author": "Afonso Dalvi (@Afonsodalvi)", "solidity_test_source_sha256": hashes,
    "environment": {"forge": subprocess.check_output(["forge", "--version"], text=True).strip(),
                    "slither": subprocess.check_output(["slither", "--version"], text=True).strip(),
                    "solc": "0.8.28", "optimizer_runs": 200, "via_ir": True, "evm": "cancun"},
    "tests": {"passed": sum(s["passed"] for s in suites), "failed": 0, "skipped": 0, "suites": suites,
              "profile": "ci", "fuzz_runs_per_test": 2048, "fuzz_test_count": 4,
              "invariant_runs": 256, "invariant_depth": 128, "invariant_count": 5,
              "fail_on_revert": True, "seed": "0x534643"},
    "coverage": {"profile": "default", "instrumentation": "forge coverage --ir-minimum",
                 "source_mapping_warning": True, "production": coverage},
    "static_analysis": static, "compiled_contracts": candidate["contracts"],
    "cashflow_interface_id": candidate["cashflow_interface_id"],
    "editorial_local_check": candidate["editorial_local_check"],
    "limitations": ["No independent audit or formal proof", "Trusted valuation and entitlement allocation",
                    "No automatic migration of existing Unified deployments", "No public discussion or editorial acceptance"]
}
(out / "validation.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
print(f"Validation evidence written: {out / 'validation.json'}")
