#!/usr/bin/env python3
"""Require the exact, unmodified upstream dependency commits used in validation."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
lock = json.loads((ROOT / "dependencies.lock.json").read_text())
for dependency in lock["dependencies"]:
    path = ROOT / dependency["path"]
    commit = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
    if commit != dependency["commit"]:
        raise SystemExit(f"Dependency commit mismatch: {dependency['path']}")
    dirty = subprocess.check_output(["git", "-C", str(path), "status", "--porcelain"], text=True)
    if dirty:
        raise SystemExit(f"Modified dependency: {dependency['path']}")
print("Pinned dependencies verified")
