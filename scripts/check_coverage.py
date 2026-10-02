#!/usr/bin/env python3
"""Evaluate measured coverage of candidate production code, excluding vendored code."""
import json
import sys
from pathlib import Path

names = {"StructuredFundVault", "StructuredFundFactory", "StructuredFundEligibility", "StructuredFundVaultDeployer"}
results = {}
for block in Path(sys.argv[1]).read_text().split("end_of_record"):
    fields = {line.split(":", 1)[0]: line.split(":", 1)[1] for line in block.splitlines() if ":" in line}
    source = fields.get("SF", "")
    name = Path(source).stem
    if name not in names or not source.endswith("src/" + name + ".sol"):
        continue
    counts = {key: int(fields[key]) for key in ("LF", "LH", "FNF", "FNH", "BRF", "BRH")}
    def ratio(hit, total):
        return 100 * counts[hit] / counts[total] if counts[total] else 100.0
    results[name] = {"lines_percent": round(ratio("LH", "LF"), 2),
                     "functions_percent": round(ratio("FNH", "FNF"), 2),
                     "branches_percent": round(ratio("BRH", "BRF"), 2), "counts": counts}
print(json.dumps(results, indent=2, sort_keys=True))
if set(results) != names:
    raise SystemExit("Missing production coverage record")
for name, stats in results.items():
    if stats["lines_percent"] < 95 or stats["functions_percent"] < 100 or stats["branches_percent"] < 95:
        raise SystemExit(f"Coverage gate failed for {name}")
