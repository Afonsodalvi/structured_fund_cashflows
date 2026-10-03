#!/usr/bin/env python3
"""Turn Slither printer evidence into scoped security views for human review."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
own = {"StructuredFundVault", "StructuredFundFactory", "StructuredFundEligibility", "StructuredFundVaultDeployer"}
report = json.loads((ROOT / "coverage/security-printers.json").read_text())
if not report.get("success"):
    raise SystemExit("Security printers failed")
printers = {p["printer"]: p for p in report["results"]["printers"]}
if set(printers) != {"inheritance-graph", "function-summary", "vars-and-auth"}:
    raise SystemExit("Missing required security printer")
dot = next(e["name"]["content"] for e in printers["inheritance-graph"]["elements"] if e["type"] == "file")
edges = sorted({(a, b) for a, b in re.findall(r"c\d+_(\w+)\s*->\s*c\d+_(\w+)", dot) if a in own})
model = {"inheritance": edges, "function_summary": {}, "variables_and_authorization": {}}
for section in ("function-summary", "vars-and-auth"):
    blocks = re.split(r"\nContract (\w+)\n", printers[section]["description"])
    for i in range(1, len(blocks), 2):
        if blocks[i] in own:
            model["function_summary" if section == "function-summary" else "variables_and_authorization"][blocks[i]] = blocks[i+1].strip()
if set(model["function_summary"]) != own or set(model["variables_and_authorization"]) != own:
    raise SystemExit("Missing own-contract security view")
(ROOT / "coverage/security-model.json").write_text(json.dumps(model, indent=2, sort_keys=True) + "\n")
lines = ["# Security diagrams", "", "Generated from Slither 0.11.6 inheritance, function-summary and vars-and-auth printers. The role grouping below is reviewed against the source: an empty printer column is not proof of missing access control. Full own-contract tables are in [the model](../reports/security-model.json).", "", "## Inheritance", "", "```mermaid", "graph TD"]
for a, b in edges:
    lines.append(f"    {a} --> {b}")
lines += ["```", "", "The vault and factory both inherit ReentrancyGuardTransient. Eligibility and the factory-bound deployer do not expose a mutable financial ledger. The production contracts contain no proxy, initializer or upgrade entry point.", "", "## Entry points and boundaries", "", "```mermaid", "flowchart LR", '    Owner["Holder / approved operator"] --> Entry["Deposit, mint, transfer, request, claims"]', '    Settler["SETTLER_ROLE"] --> Settlement["Fulfill, repay, record individual / batch"]', '    Valuer["VALUER_ROLE"] --> NAV["Report credit NAV"]', '    Treasury["TREASURY_ROLE"] --> Deploy["Deploy credit"]', '    Entry --> Guard["Vault transient guard"]', '    Settlement --> Guard', '    NAV --> Guard', '    Deploy --> Guard', '    Guard --> Checks["Authorization, eligibility, bounds, accounting"]', '    Checks --> Asset["Exact ERC-20 asset interactions"]', '    Asset -. "callback rejected" .-> Guard', "```", "", "Twenty financial entry points (including the slippage wrapper) are exercised by the callback matrix. Pausing, role administration, operator approval and ERC-20 allowance approval retain their own authorization rules. Views stay readable during callbacks; they are not an atomic cross-protocol price oracle.", "", "## State and authorization", "", "```mermaid", "flowchart LR", '    Transfers["Holder transfers / operator entries"] --> Principal["Free principal + share balances"]', '    Requests["Authorized redemption / cancelation"] --> Locked["Captured principal + escrow"]', '    Settlement["Settler fulfillment"] --> Redemption["Retired principal + redemption reserve"]', '    Booking["Settler cashflow booking"] --> Cashflows["Immutable terms + cashflow reserve"]', '    Claims["Beneficiary / approved operator"] --> Consumed["Claimed bit + reserve release"]', '    Valuation["Valuer with nonce and evidence"] --> Credit["Credit NAV"]', '    Treasury["Treasury deploy / settler repay"] --> Cash["Managed cash and credit NAV"]', '    Admin["Default admin"] --> Roles["Operational role grants / revocations"]', "```", "", "The admin can change role holders; the two-day default-admin transfer delay does not timelock operational role grants. Cashflow allocation, NAV and off-chain evidence remain trusted assertions. The seven stateful properties reconcile principal, reserves, supply, NAV, immutable terms and limits after handler actions.", ""]
(ROOT / "docs/SECURITY_DIAGRAMS.md").write_text("\n".join(lines))
print("Three security diagrams and scoped Slither tables generated")
