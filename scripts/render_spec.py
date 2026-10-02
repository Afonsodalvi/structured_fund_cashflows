#!/usr/bin/env python3
"""Make the working paper readable in this standalone repository."""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def render():
    source = (ROOT / "ERCS/erc-draft_structured_fund_cashflows.md").read_text()
    metadata, body = source.split("---\n", 2)[1:]
    fields = dict(line.split(": ", 1) for line in metadata.splitlines() if ": " in line)
    body = re.sub(r"\]\(\./eip-(\d+)\.md\)", r"](https://eips.ethereum.org/EIPS/eip-\1)", body)
    return ("# Structured Fund Cashflows\n\nWorking paper — no assigned ERC number or public discussion yet.\n\n"
            + "Author: " + fields["author"] + ". This readable copy is generated from the "
            + "[submission source](../ERCS/erc-draft_structured_fund_cashflows.md); only standard links and presentation are adapted.\n"
            + body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    target = ROOT / "docs/SPECIFICATION.md"
    text = render()
    if args.check:
        if not target.exists() or target.read_text() != text:
            raise SystemExit("Readable specification is stale; run scripts/render_spec.py")
    else:
        target.write_text(text)
