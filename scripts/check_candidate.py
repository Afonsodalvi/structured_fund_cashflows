#!/usr/bin/env python3
"""Local editorial/ABI checks, size gate, reproducible source manifest, local export."""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
DRAFT = ROOT / "ERCS/erc-draft_structured_fund_cashflows.md"
HEADERS = ["Abstract", "Motivation", "Specification", "Rationale", "Backwards Compatibility",
           "Test Cases", "Reference Implementation", "Security Considerations", "Copyright"]
METHODS = {"scopeId()", "principalOf(address)", "lockedPrincipalOf(address)",
           "totalOutstandingPrincipal()", "cashflow(bytes32)", "claimCashflow(bytes32,address)"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_draft(text: str) -> dict[str, str]:
    match = re.match(r"\A---\n(.*?)\n---\n", text, re.S)
    require(match is not None, "Missing front matter")
    pairs = [line.split(": ", 1) for line in match.group(1).splitlines()]
    require(all(len(p) == 2 for p in pairs), "Invalid front matter field")
    meta = dict(pairs)
    require(list(meta) == ["eip", "title", "description", "author", "discussions-to", "status", "type",
                           "category", "created", "requires"], "Unexpected metadata order")
    require(0 < len(meta["title"]) <= 44, "Title must be at most 44 characters")
    require(0 < len(meta["description"]) <= 140, "Description must be at most 140 characters")
    require(meta["author"] == "Afonso Dalvi (@Afonsodalvi)", "Author must match confirmed identity")
    require(meta["status"] == "Draft" and meta["category"] == "ERC" and meta["type"] == "Standards Track",
            "Invalid candidate classification")
    datetime.date.fromisoformat(meta["created"])
    require(meta["requires"] == "20, 165, 4626, 7540", "Unexpected normative dependencies")
    require(re.findall(r"^## (.+)$", text, re.M) == HEADERS, "Missing or reordered ERC sections")
    require("Copyright and related rights waived via [CC0](../LICENSE.md)." in text, "Missing CC0 waiver")
    require(not re.search(r"\b(TODO|FIXME|TBD)\b", text), "Unresolved specification marker")
    require(not re.search(r"\]\(https?://", text), "Draft uses external links; review ERC link policy")
    declarations = re.findall(r"function\s+(\w+)\(([^)]*)\)", text)
    declared = {name + "(" + ",".join(p.strip().split()[0] for p in args.split(",") if p.strip()) + ")"
                for name, args in declarations}
    require(declared == METHODS, "Normative interface differs from expected selectors")
    code = re.search(r"```solidity\n(.*?)\n```", text, re.S)
    require(code is not None, "Missing normative Solidity interface")
    def solidity_tokens(value: str) -> list[str]:
        value = re.sub(r"//[^\n]*|/\*.*?\*/", "", value, flags=re.S)
        return re.findall(r"[A-Za-z_]\w*|[0-9]+|[^\s]", value)
    source = (ROOT / "src/interfaces/IStructuredFundCashflows.sol").read_text()
    require(solidity_tokens(code.group(1)) == solidity_tokens(source),
            "Normative interface differs from source (including structs, events and outputs)")
    require("`0x2e0b288e`" in text, "Specification interface ID is inconsistent")
    return meta


def artifacts() -> dict:
    interface = json.loads((ROOT / "out/IStructuredFundCashflows.sol/IStructuredFundCashflows.json").read_text())
    selectors = interface["methodIdentifiers"]
    require(set(selectors) == METHODS, "Compiled ABI differs from specification")
    interface_id = 0
    for selector in selectors.values():
        interface_id ^= int(selector, 16)
    sizes = {}
    # Leave explicit room below EIP-170 rather than accepting a boundary-sized deployment.
    for name in ("StructuredFundVault", "StructuredFundFactory", "StructuredFundEligibility", "StructuredFundVaultDeployer"):
        artifact = json.loads((ROOT / f"out/{name}.sol/{name}.json").read_text())
        metadata = json.loads(artifact["rawMetadata"])
        settings = metadata["settings"]
        require(metadata["compiler"]["version"].startswith("0.8.37+") and settings["evmVersion"] == "osaka"
                and settings["optimizer"]["enabled"] and settings["optimizer"]["runs"] == 200
                and settings["viaIR"], f"Unexpected compiler settings or instrumented artifact: {name}")
        code = artifact["deployedBytecode"]["object"].removeprefix("0x")
        init = artifact["bytecode"]["object"].removeprefix("0x")
        require(re.fullmatch(r"[0-9a-fA-F]*", code) is not None, f"Unlinked code: {name}")
        size = len(code) // 2
        require(size <= 24_064, f"{name} runtime exceeds 24,064 byte gate")
        require(len(init) // 2 <= 48_000, f"{name} creation code exceeds 48,000 byte gate")
        sizes[name] = {"runtime_bytes": size, "eip170_headroom": 24_576 - size,
                       "creation_bytes_without_arguments": len(init) // 2}
    return {"cashflow_interface_id": f"0x{interface_id:08x}", "selectors": selectors, "contracts": sizes}


def manifest(compiled: dict) -> dict:
    paths = [ROOT / name for name in ("foundry.toml", "README.md", "LICENSE-MIT", "LICENSE.md", "NOTICE.md",
             "CONTRIBUTING.md", "SECURITY.md", ".gitignore", ".gitmodules", "dependencies.lock.json", "upstream.lock.json",
             "lib/openzeppelin-contracts/package.json")]
    for folder in (ROOT / "src", ROOT / "test", ROOT / "scripts", ROOT / "ERCS", ROOT / "docs"):
        paths += sorted(p for p in folder.rglob("*") if p.is_file() and p.suffix in (".sol", ".py", ".sh", ".md", ".json"))
    paths += sorted((ROOT / "lib/openzeppelin-contracts/contracts").rglob("*.sol"))
    paths += sorted((ROOT / "lib/forge-std/src").rglob("*.sol"))
    hashes = {str(p.relative_to(ROOT)): sha(p) for p in paths}
    workflow = ROOT / ".github/workflows/verify.yml"
    hashes[".github/workflows/verify.yml"] = sha(workflow)
    hashes["config/eipw.toml"] = sha(ROOT / "config/eipw.toml")
    root_hash = hashlib.sha256(json.dumps(hashes, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"schema": 1, "candidate": "Structured Fund Cashflows", "source_tree_sha256": root_hash,
            "foundry": subprocess.check_output(["forge", "--version"], text=True).splitlines()[0],
            "compiler": "0.8.37", "evm": "osaka", "optimizer_runs": 200, "via_ir": True,
            "files_sha256": hashes, **compiled}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--discussion")
    parser.add_argument("--export", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    text = DRAFT.read_text()
    meta = check_draft(text)
    compiled = artifacts()
    require(compiled["cashflow_interface_id"] == "0x2e0b288e", "Unexpected interface identifier")
    result = manifest(compiled)
    if args.manifest:
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.discussion:
        url = urlparse(args.discussion)
        require(url.scheme == "https" and url.netloc == "ethereum-magicians.org"
                and re.fullmatch(r"/t/[^/]+/\d+/?", url.path) is not None and not url.query and not url.fragment,
                "Use the real canonical Ethereum Magicians topic URL")
        text = text.replace("discussions-to: " + meta["discussions-to"], "discussions-to: " + args.discussion, 1)
    if args.export:
        require(args.discussion is not None, "Export requires a real discussion URL; publication metadata is pending")
        dest = args.export.resolve()
        require(not dest.exists(), "Export destination already exists; choose a fresh directory")
        require(not dest.is_relative_to(ROOT / "src") and not dest.is_relative_to(ROOT / "test"), "Invalid export destination")
        (dest / "ERCS").mkdir(parents=True)
        (dest / "ERCS" / DRAFT.name).write_text(text)
        # Only the self-contained proposal belongs in the initial editorial pull request.
        # The independent reference repository carries implementation and validation evidence.
    print(json.dumps({"editorial_local_check": "passed", "publication_metadata_pending": not bool(args.discussion),
                      **compiled}, indent=2))


if __name__ == "__main__":
    main()
