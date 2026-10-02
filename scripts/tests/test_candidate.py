"""Regression tests for publication guards and interface drift, without network publication."""
import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("candidate", ROOT / "scripts/check_candidate.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class CandidateChecks(unittest.TestCase):
    def setUp(self):
        self.text = candidate.DRAFT.read_text()

    def test_current_interface_matches_all_normative_fields(self):
        self.assertEqual(candidate.check_draft(self.text)["title"], "Structured Fund Cashflows")

    def test_indexed_event_drift_is_rejected(self):
        changed = self.text.replace("bytes32 indexed scopeId,", "bytes32 scopeId,")
        with self.assertRaisesRegex(SystemExit, "Normative interface differs"):
            candidate.check_draft(changed)

    def test_return_type_drift_with_unchanged_selector_is_rejected(self):
        changed = self.text.replace("returns (uint256 netAssets);", "returns (bytes32 netAssets);")
        with self.assertRaisesRegex(SystemExit, "Normative interface differs"):
            candidate.check_draft(changed)

    def test_struct_order_drift_is_rejected(self):
        changed = self.text.replace("uint256 principal;\n        uint256 grossYield;", "uint256 grossYield;\n        uint256 principal;")
        with self.assertRaisesRegex(SystemExit, "Normative interface differs"):
            candidate.check_draft(changed)

    def test_old_copyright_path_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, "Missing CC0 waiver"):
            candidate.check_draft(self.text.replace("[CC0](../LICENSE.md)", "[CC0](/LICENSE)"))

    def run_export(self, arguments):
        compiled = {"cashflow_interface_id": "0x2e0b288e", "selectors": {}, "contracts": {}}
        with patch.object(sys, "argv", ["check_candidate.py"] + arguments), \
             patch.object(candidate, "artifacts", return_value=compiled), \
             patch.object(candidate, "manifest", return_value={}), contextlib.redirect_stdout(io.StringIO()):
            candidate.main()

    def test_export_requires_real_discussion_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(SystemExit, "Export requires"):
                self.run_export(["--export", str(Path(directory) / "export")])

    def test_export_rejects_noncanonical_url(self):
        with self.assertRaisesRegex(SystemExit, "real canonical"):
            self.run_export(["--discussion", "https://example.com/discussion"])

    def test_export_is_editorial_only_and_never_overwrites(self):
        # A syntax-only fixture; no network request or public-topic existence is asserted.
        discussion = "https://ethereum-magicians.org/t/local-test-fixture/1"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "export"
            args = ["--discussion", discussion, "--export", str(output)]
            self.run_export(args)
            files = [str(p.relative_to(output)) for p in output.rglob("*") if p.is_file()]
            self.assertEqual(files, ["ERCS/erc-draft_structured_fund_cashflows.md"])
            self.assertIn("discussions-to: " + discussion, (output / files[0]).read_text())
            with self.assertRaisesRegex(SystemExit, "already exists"):
                self.run_export(args)

    def test_static_gate_rejects_unreviewed_high_and_low_findings(self):
        for impact in ["High", "Medium", "Low"]:
            with tempfile.TemporaryDirectory() as directory:
                report = Path(directory) / "finding.json"
                report.write_text(json.dumps({"success": True, "results": {"detectors": [
                    {"check": "arbitrary-review-fixture", "impact": impact, "description": "Unreviewed finding"}
                ]}}))
                run = subprocess.run([sys.executable, str(ROOT / "scripts/check_slither.py"), str(report)], capture_output=True)
                self.assertNotEqual(run.returncode, 0)
                self.assertIn(b"Unreviewed Slither findings", run.stderr)

    def test_failed_static_analysis_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "finding.json"
            report.write_text(json.dumps({"success": False}))
            run = subprocess.run([sys.executable, str(ROOT / "scripts/check_slither.py"), str(report)], capture_output=True)
            self.assertNotEqual(run.returncode, 0)


if __name__ == "__main__":
    unittest.main()
