#!/usr/bin/env python3
"""Gate findings without globally suppressing a detector."""
import json
import hashlib
import re
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
baseline = json.loads(Path(__file__).with_name("slither-reviewed.json").read_text())["reviewed"]
if not data.get("success"):
    raise SystemExit("Slither did not complete successfully")
accepted = []
rejected = []
for finding in data.get("results", {}).get("detectors", []):
    # Only exact reviewed findings are accepted. High/Medium never enter the allowlist.
    normalized = re.sub(r"\((src/[A-Za-z0-9_]+\.sol)#\d+(?:-\d+)?\)", r"(\1)", finding["description"])
    reviewed = finding["impact"] not in {"High", "Medium"} and any(
        finding["check"] == entry["check"] and finding["impact"] == entry["impact"]
        and hashlib.sha256(normalized.encode()).hexdigest() == entry["normalized_description_sha256"]
        for entry in baseline)
    (accepted if reviewed else rejected).append(finding)
print(json.dumps({"findings": len(accepted) + len(rejected), "reviewed_accepted": len(accepted),
                  "accepted_by_check": {name: sum(f["check"] == name for f in accepted)
                                        for name in sorted({f["check"] for f in accepted})},
                  "unreviewed": [{"check": f["check"], "impact": f["impact"], "description": f["description"]}
                                 for f in rejected]}, indent=2))
if rejected:
    raise SystemExit("Unreviewed Slither findings block this candidate")
