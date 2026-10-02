#!/usr/bin/env python3
"""Check local links, independent paths and generated specification consistency."""
import re
from pathlib import Path
from render_spec import render

ROOT = Path(__file__).resolve().parents[1]
own = [p for p in ROOT.rglob("*") if p.is_file() and not any(
    part in {".git", "lib", "out", "cache", "coverage", ".cache", "reports", "__pycache__", "dist"}
    for part in p.relative_to(ROOT).parts)]
errors = []
for path in own:
    if path.is_symlink():
        errors.append(f"Owned file must not be a symlink: {path.relative_to(ROOT)}")
    if path.suffix not in {".md", ".sol", ".py", ".sh", ".toml", ".yml", ".json"}:
        continue
    text = path.read_text()
    if re.search(r"/(?:Users|home)/[^/\s]+/|\.\./lib/", text):
        errors.append(f"Non-portable parent/workspace path: {path.relative_to(ROOT)}")
    if path.suffix == ".md":
        for destination in re.findall(r"\]\(([^)]+)\)", text):
            if re.match(r"https?://|mailto:|#", destination):
                continue
            if path.parent.name == "ERCS" and re.fullmatch(r"\./eip-\d+\.md", destination):
                continue  # Intentionally resolved by the combined upstream corpus.
            target = destination.split("#", 1)[0]
            if target and not (path.parent / target).exists():
                errors.append(f"Broken local link {path.relative_to(ROOT)} -> {target}")
if (ROOT / "docs/SPECIFICATION.md").read_text() != render():
    errors.append("Generated specification is stale")
if errors:
    raise SystemExit("\n".join(errors))
print("Independent repository paths and documentation links verified")
