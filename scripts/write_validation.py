#!/usr/bin/env python3
"""Build evidence from Foundry JSON, checking every declared test and invariant."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source_hashes(root=ROOT):
    paths = [root / "foundry.toml"]
    for folder in ("src", "test"):
        paths.extend(sorted((root / folder).rglob("*.sol")))
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def summarize_tests(results, root=ROOT):
    expected = {}
    for path in (root / "test").rglob("*.t.sol"):
        names = set(re.findall(r"function\s+((?:test|invariant_)\w*)\s*\(", path.read_text()))
        if names:
            expected[str(path.relative_to(root))] = names
    suites, actual, fuzz, predicates, campaigns, gas = [], {}, [], [], [], {}
    runner_cases = 0
    for identity, suite in sorted(results.items()):
        path, name = identity.split(":", 1)
        actual.setdefault(path, set())
        before = len(actual[path])
        for signature, result in suite["test_results"].items():
            if result["status"] != "Success" or result.get("counterexample"):
                raise SystemExit("Failed, skipped or counterexample-bearing test: " + signature)
            runner_cases += 1
            kind = result["kind"]
            if "Invariant" in kind:
                group = result.get("invariant_predicate_results", [])
                if not group or any(p["status"] != "Success" for p in group):
                    raise SystemExit("Missing or failed invariant predicate")
                if result.get("invariant_count") != len(group):
                    raise SystemExit("Incomplete invariant group")
                actual[path].update(p["name"] for p in group)
                predicates.extend(p["name"] for p in group)
                run = kind["Invariant"]
                if (run["runs"], run["calls"], run["reverts"]) != (512, 131072, 0):
                    raise SystemExit("Unexpected invariant configuration or reverts")
                if len(run["metrics"]) != 20 or any(m["reverts"] or not m["calls"] for m in run["metrics"].values()):
                    raise SystemExit("Missing handler action or unexpected revert")
                if sum(m["calls"] for m in run["metrics"].values()) != run["calls"]:
                    raise SystemExit("Inconsistent handler call totals")
                campaigns.append({k: run[k] for k in ("runs", "calls", "reverts", "metrics")})
            else:
                actual[path].add(signature.split("(", 1)[0])
                if "Fuzz" in kind:
                    if kind["Fuzz"]["runs"] != 4096:
                        raise SystemExit("Unexpected CI fuzz configuration")
                    fuzz.append(signature)
            gas.update(result.get("gas_snapshots", {}).get("guard", {}))
        suites.append({"suite": name, "path": path, "passed": len(actual[path]) - before})
    if actual != expected:
        raise SystemExit("Missing or unexpected tests compared with source declarations")
    if len(fuzz) != 5 or len(predicates) != 7 or len(campaigns) != 1:
        raise SystemExit("Unexpected fuzz/property/campaign count")
    if not gas or int(gas["transient_warm"]) >= int(gas["persistent_warm"]):
        raise SystemExit("Missing or regressed transient-guard gas measurement")
    passed = sum(s["passed"] for s in suites)
    return {"passed": passed, "unit_and_fuzz_tests": passed - len(predicates), "runner_cases": runner_cases,
            "failed": 0, "skipped": 0, "suites": suites, "profile": "ci", "seed": "0x534643",
            "fuzz_runs_per_test": 4096, "fuzz_test_count": len(fuzz), "invariant_count": len(predicates),
            "invariant_runs": 512, "invariant_depth": 256, "fail_on_revert": True,
            "invariant_predicates": sorted(predicates), "invariant_campaigns": campaigns,
            "guard_gas": {k: int(v) for k, v in gas.items()}}


def main():
    out = ROOT / "coverage"
    hashes = source_hashes()
    if json.loads((out / "test-inputs.json").read_text()) != hashes:
        raise SystemExit("Solidity inputs changed after the validation run started")
    tests = summarize_tests(json.loads((out / "tests-ci.json").read_text()))
    candidate = json.loads((out / "candidate-check.json").read_text())
    coverage = json.loads((out / "coverage-summary.json").read_text())
    static = json.loads((out / "slither-gate.json").read_text())
    if static["unreviewed"]:
        raise SystemExit("Static findings have not passed review")
    report = {
        "schema": 2, "candidate": "Structured Fund Cashflows", "publication_status": "local_unsubmitted",
        "author": "Afonso Dalvi (@Afonsodalvi)", "solidity_test_source_sha256": hashes,
        "environment": {"forge": subprocess.check_output(["forge", "--version"], text=True).strip(),
                        "slither": subprocess.check_output(["slither", "--version"], text=True).strip(),
                        "solc": "0.8.37", "optimizer_runs": 200, "via_ir": True, "evm": "osaka",
                        "dynamic_test_linking": False},
        "tests": tests,
        "coverage": {"profile": "default", "instrumentation": "forge coverage --ir-minimum",
                     "source_mapping_warning": True, "production": coverage},
        "static_analysis": static, "compiled_contracts": candidate["contracts"],
        "cashflow_interface_id": candidate["cashflow_interface_id"],
        "editorial_local_check": candidate["editorial_local_check"],
        "limitations": ["No independent audit or formal proof", "Trusted valuation and entitlement allocation",
                        "OpenZeppelin 5.7.0 is a final dev-channel release, not the audited npm latest",
                        "Osaka target requires compatible network execution rules", "No public discussion or editorial acceptance"]
    }
    (out / "validation.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("Validation evidence written from complete Foundry JSON results")


if __name__ == "__main__":
    main()
