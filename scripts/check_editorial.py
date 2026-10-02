#!/usr/bin/env python3
"""Run the upstream ERC linter against a pinned corpus, with explicit pre-submission exceptions."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PENDING = ["preamble-eip", "preamble-file-name", "preamble-discussions-to", "preamble-re-discussions-to"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path)
    parser.add_argument("--eipw", default=os.environ.get("EIPW", "eipw"))
    parser.add_argument("--strict", action="store_true", help="Use after the real number and discussion are assigned")
    args = parser.parse_args()
    lock = json.loads((ROOT / "upstream.lock.json").read_text())
    corpus = args.corpus or ROOT / ".cache/ERCs"
    if not corpus.exists():
        corpus.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init", "-q", str(corpus)], check=True)
        subprocess.run(["git", "-C", str(corpus), "remote", "add", "origin", lock["repository"]], check=True)
        subprocess.run(["git", "-C", str(corpus), "fetch", "-q", "--depth=1", "origin", lock["commit"]], check=True)
        subprocess.run(["git", "-C", str(corpus), "checkout", "-q", "--detach", "FETCH_HEAD"], check=True)
    commit = subprocess.check_output(["git", "-C", str(corpus), "rev-parse", "HEAD"], text=True).strip()
    if commit != lock["commit"]:
        raise SystemExit("Editorial corpus does not match upstream.lock.json")
    dirty = subprocess.check_output(["git", "-C", str(corpus), "status", "--porcelain"], text=True)
    if dirty:
        raise SystemExit("Editorial corpus has local modifications")
    config = (ROOT / lock["config"]).read_bytes()
    upstream_config = subprocess.check_output(["git", "-C", str(corpus), "show", f"{commit}:{lock['config']}"])
    if config != upstream_config:
        raise SystemExit("Editorial configuration differs from pinned upstream")
    version = subprocess.run([args.eipw, "--version"], text=True, capture_output=True)
    # eipw 0.11.0 uses EX_USAGE even for --version/--help.
    version_text = (version.stdout + version.stderr).strip()
    if version_text != "eipw " + lock["eipw_version"]:
        raise SystemExit("Unexpected eipw version: " + version_text)
    pending = [] if args.strict else PENDING
    with tempfile.TemporaryDirectory(prefix="sfc-editorial-") as temporary:
        folder = Path(temporary) / "ERCS"
        folder.mkdir()
        # Upstream CI normalizes both repositories to eip-N.md for reference resolution.
        for path in (corpus / "ERCS").glob("erc-*.md"):
            if re.fullmatch(r"erc-\d+\.md", path.name):
                (folder / path.name.replace("erc-", "eip-", 1)).write_bytes(path.read_bytes())
        draft = ROOT / "ERCS/erc-draft_structured_fund_cashflows.md"
        target = folder / draft.name
        target.write_bytes(draft.read_bytes())
        (Path(temporary) / "LICENSE.md").write_bytes((ROOT / "LICENSE.md").read_bytes())
        command = [args.eipw, "--config", str(ROOT / lock["config"])]
        for name in pending:
            command += ["--allow", name]
        result = subprocess.run(command + [str(target)], text=True, capture_output=True)
    output = ROOT / "coverage"
    output.mkdir(exist_ok=True)
    (output / "editorial.log").write_text(result.stdout + result.stderr)
    report = {"upstream_commit": commit, "eipw": version_text,
              "upstream_config_sha256": hashlib.sha256(config).hexdigest(),
              "draft_sha256": hashlib.sha256(draft.read_bytes()).hexdigest(),
              "pending_metadata_exceptions": pending, "exit_code": result.returncode,
              "editorial_content_check": "passed" if result.returncode == 0 else "failed",
              "official_upstream_ci_run": False, "submission_ready_metadata": not pending}
    (output / "editorial.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if result.returncode:
        print(result.stdout + result.stderr)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
