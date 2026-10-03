"""Ensure partial test evidence and coverage gaps cannot become a passing report."""
import copy
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / (name + ".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


validation = module("write_validation")
coverage = module("check_coverage")


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "test").mkdir()
        predicates = ["invariant_P" + str(i) for i in range(7)]
        names = ["test_Unit"] + ["testFuzz_P" + str(i) for i in range(5)] + predicates
        (self.root / "test/Fixture.t.sol").write_text("\n".join("function " + n + "() {}" for n in names))
        self.items = {n + "()": {"status": "Success", "kind": {"Fuzz": {"runs": 4096}}} for n in names[1:6]}
        self.items["test_Unit()"] = {"status": "Success", "kind": {"Unit": {}},
                                     "gas_snapshots": {"guard": {"persistent_warm": "300", "transient_warm": "200"}}}
        self.items[predicates[0] + "()"] = {
            "status": "Success", "invariant_count": 7,
            "invariant_predicate_results": [{"name": n, "status": "Success"} for n in predicates],
            "kind": {"Invariant": {"runs": 512, "calls": 131072, "reverts": 0,
                "metrics": {str(i): {"calls": 6554 if i < 12 else 6553, "reverts": 0} for i in range(20)}}}}
        self.results = {"test/Fixture.t.sol:Fixture": {"test_results": self.items}}

    def check(self):
        return validation.summarize_tests(self.results, self.root)

    def test_complete_predicate_group_is_counted_without_multiplying_calls(self):
        result = self.check()
        self.assertEqual((result["passed"], result["runner_cases"], result["unit_and_fuzz_tests"]), (13, 7, 6))
        self.assertEqual(result["invariant_campaigns"][0]["calls"], 131072)

    def test_missing_source_test_is_rejected(self):
        del self.items["testFuzz_P0()"]
        with self.assertRaisesRegex(SystemExit, "Missing or unexpected tests"):
            self.check()

    def test_failed_individual_invariant_is_rejected(self):
        self.items["invariant_P0()"]["invariant_predicate_results"][3]["status"] = "Failure"
        with self.assertRaisesRegex(SystemExit, "failed invariant"):
            self.check()

    def test_weak_fuzz_configuration_is_rejected(self):
        self.items["testFuzz_P0()"]["kind"]["Fuzz"]["runs"] = 512
        with self.assertRaisesRegex(SystemExit, "fuzz configuration"):
            self.check()

    def test_shorter_invariant_campaign_is_rejected(self):
        self.items["invariant_P0()"]["kind"]["Invariant"]["calls"] = 65536
        with self.assertRaisesRegex(SystemExit, "invariant configuration"):
            self.check()

    def test_skipped_test_is_rejected(self):
        self.items["test_Unit()"]["status"] = "Skipped"
        with self.assertRaisesRegex(SystemExit, "skipped"):
            self.check()

    def test_incomplete_handler_metrics_are_rejected(self):
        del self.items["invariant_P0()"]["kind"]["Invariant"]["metrics"]["0"]
        with self.assertRaisesRegex(SystemExit, "handler action"):
            self.check()

    def test_guard_gas_regression_is_rejected(self):
        self.items["test_Unit()"]["gas_snapshots"]["guard"]["transient_warm"] = "301"
        with self.assertRaisesRegex(SystemExit, "gas measurement"):
            self.check()


class CoverageGateTests(unittest.TestCase):
    def setUp(self):
        self.results = {name: {"counts": {"LF": 1, "LH": 1, "FNF": 1, "FNH": 1, "BRF": 1, "BRH": 1},
                              "uncovered_lines": {}} for name in coverage.NAMES}

    def test_reviewed_ir_gaps_keep_raw_line_counts(self):
        v = self.results["StructuredFundVault"]
        v["counts"].update(LF=304, LH=300)
        v["uncovered_lines"] = copy.deepcopy(coverage.IR_GAPS)
        coverage.validate(self.results)
        self.assertEqual(v["counts"]["LH"], 300)

    def test_one_uncovered_branch_is_rejected(self):
        self.results["StructuredFundVault"]["counts"]["BRH"] = 0
        with self.assertRaisesRegex(SystemExit, "Coverage gate"):
            coverage.validate(self.results)

    def test_unreviewed_line_is_rejected_even_above_percentage_threshold(self):
        v = self.results["StructuredFundVault"]
        v["counts"].update(LF=304, LH=303)
        v["uncovered_lines"] = {999: "unreviewed();"}
        with self.assertRaisesRegex(SystemExit, "Unreviewed"):
            coverage.validate(self.results)

    def test_missing_contract_is_rejected(self):
        del self.results["StructuredFundFactory"]
        with self.assertRaisesRegex(SystemExit, "Missing production"):
            coverage.validate(self.results)
