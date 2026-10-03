#!/usr/bin/env python3
"""Require the exact, unmodified upstream dependency commits used in validation."""
import json
import subprocess
import re
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
for command, expected in [("forge", lock["tools"]["foundry"].removeprefix("v")), ("slither", lock["tools"]["slither"])]:
    version = subprocess.check_output([command, "--version"], text=True).splitlines()[0]
    if not re.search(r"(?<![\d.])" + re.escape(expected) + r"(?![\d.])", version):
        raise SystemExit(f"Unexpected {command} version: {version}; expected {expected}")
config = json.loads(subprocess.check_output(["forge", "config", "--json"], text=True))
if config["solc"] != lock["tools"]["solc"] or config["evm_version"] != lock["evm"] or config["dynamic_test_linking"]:
    raise SystemExit("Unexpected compiler/EVM or dynamic test linking enabled")
print("Pinned compiler, EVM and security toolchain verified")
