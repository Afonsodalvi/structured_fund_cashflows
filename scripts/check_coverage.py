#!/usr/bin/env python3
"""Preserve raw coverage and reject missing paths, allowing only reviewed IR mapping gaps."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES = {"StructuredFundVault", "StructuredFundFactory", "StructuredFundEligibility", "StructuredFundVaultDeployer"}
# Exact locations and statements, not denominator exclusions. See docs/COVERAGE.md.
IR_GAPS = {153: "_pause();", 157: "_unpause();", 280: "_requireNotPaused();", 334: "return 0;"}


def parse_lcov(text, root=ROOT):
    results = {}
    for block in text.split("end_of_record"):
        fields = {line.split(":", 1)[0]: line.split(":", 1)[1] for line in block.splitlines() if ":" in line}
        source = fields.get("SF", "")
        name = Path(source).stem
        if name not in NAMES or not source.endswith("src/" + name + ".sol"):
            continue
        if name in results:
            raise SystemExit("Duplicate production coverage record")
        counts = {key: int(fields[key]) for key in ("LF", "LH", "FNF", "FNH", "BRF", "BRH")}
        source_lines = (root / "src" / (name + ".sol")).read_text().splitlines()
        gaps = {}
        for row in block.splitlines():
            if row.startswith("DA:"):
                number, hits = map(int, row[3:].split(",")[:2])
                if not hits:
                    gaps[number] = source_lines[number - 1].strip()
        def ratio(hit, total):
            return round(100 * counts[hit] / counts[total], 2) if counts[total] else 100.0
        results[name] = {"lines_percent": ratio("LH", "LF"), "functions_percent": ratio("FNH", "FNF"),
                         "branches_percent": ratio("BRH", "BRF"), "counts": counts,
                         "uncovered_lines": gaps}
    return results


def validate(results):
    if set(results) != NAMES:
        raise SystemExit("Missing production coverage record")
    for name, stats in results.items():
        c = stats["counts"]
        if c["LF"] <= 0 or c["FNF"] <= 0 or c["FNH"] != c["FNF"] or c["BRH"] != c["BRF"]:
            raise SystemExit("Coverage gate failed for " + name)
        if c["LH"] > c["LF"] or c["LH"] < c["LF"] * 0.985:
            raise SystemExit("Line coverage gate failed for " + name)
        allowed = IR_GAPS if name == "StructuredFundVault" else {}
        gaps = {int(k): v for k, v in stats["uncovered_lines"].items()}
        if any(allowed.get(number) != statement for number, statement in gaps.items()):
            raise SystemExit("Unreviewed source coverage gap for " + name)
        if len(gaps) != c["LF"] - c["LH"]:
            raise SystemExit("Inconsistent line coverage counts for " + name)


if __name__ == "__main__":
    result = parse_lcov(Path(sys.argv[1]).read_text())
    print(json.dumps(result, indent=2, sort_keys=True))
    validate(result)
