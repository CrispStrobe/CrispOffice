"""Small evidence-only regression controls; no native runtime or model required."""
from __future__ import annotations

import contextlib
import copy
import io
import json
import math
from pathlib import Path
import statistics
from tempfile import TemporaryDirectory
import unittest

import compare_guarded_provider as compare


def encoded(value):
    return json.dumps(value, ensure_ascii=False).encode("utf-8")


def timing(samples):
    ordered = sorted(samples)
    return {"samples_ms": samples, "median_ms": statistics.median(samples),
            "p95_ms": ordered[math.ceil(len(samples) * .95) - 1], "maximum_ms": ordered[-1]}


class GuardedComparisonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.baseline_raw = compare.DEFAULT_BASELINE.read_bytes()
        cls.cases_raw = compare.DEFAULT_CASES.read_bytes()
        cls.baseline = json.loads(cls.baseline_raw)

    def setUp(self):
        self.candidate = copy.deepcopy(self.baseline)

    def result(self):
        return compare.compare(self.baseline_raw, encoded(self.candidate), self.cases_raw)

    def case(self, identity, section="cases"):
        return next(row for row in self.candidate[section] if row["id"] == identity)

    def replace(self, identity, corrected, section="cases"):
        row = self.case(identity, section)
        finding = [] if corrected == row["input"] else [{
            "start": row["start_offset"],
            "end": row["start_offset"] + len(row["input"].encode("utf-16-le")) // 2,
            "original": row["input"], "replacement": corrected, "rule_id": "gector.de.grammar",
        }]
        for observed in [row, *([row["warmup"]] if "warmup" in row else [])]:
            observed["corrected"], observed["findings"] = corrected, copy.deepcopy(finding)
        if section == "cases":
            row["matches_expected"] = corrected == row["expected"]
            row["matches_unguarded_reference"] = corrected == row["reference_unguarded"]
        return row

    def refresh_operational(self):
        rows = self.candidate["cases"]
        probes = self.candidate["long_complete_check_probes"]
        samples = [sample for row in rows if row["status"] == "success" and row["tokens_first_pass"] <= 64
                   for sample in row["timing"]["samples_ms"]]
        samples.extend(probes[0]["timing"]["samples_ms"])
        self.candidate["warm_checks_up_to_64_wordpieces"] = timing(samples)
        self.candidate["engineering_budgets"]["p95_at_most_500_ms"] = timing(samples)["p95_ms"] <= 500
        self.candidate["operational_passed"] = (
            all(row["status"] == row["expected_status"] and row["stable_repeats"] for row in rows)
            and all(row["status"] == "success" and row["stable_repeats"] for row in probes)
            and all(row["passed"] for row in self.candidate["controls"]))

    def assert_invalid(self, fragment=None):
        result = self.result()
        self.assertFalse(result["passed"], result)
        self.assertFalse(result["evidence_valid"], result)
        self.assertTrue(result["evidence_errors"], result)
        if fragment:
            self.assertIn(fragment, " ".join(result["evidence_errors"]))
        return result

    def test_identical_frozen_receipt_passes_with_recomputed_counts(self):
        result = self.result()
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["baseline"]["exact_fixes"], 5)
        self.assertEqual(result["candidate"]["unchanged_clean_controls"], 10)
        self.assertEqual(result["candidate"]["short_timing"]["p95_ms"], 62.017)
        self.assertEqual(result["finding_changes"], [])

    def test_added_exact_fix_is_separate_from_preserved_baseline(self):
        self.replace("verb-wir", "Wir sind zufrieden.")
        result = self.result()
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["added_exact_fixes"], ["verb-wir"])
        self.assertEqual(result["lost_exact_fixes"], [])
        self.assertEqual(result["candidate"]["exact_fixes"], 6)
        self.assertEqual(result["finding_changes"][0]["id"], "verb-wir")

    def test_lost_exact_fix_fails_even_when_operational_status_passes(self):
        self.replace("verb-du", self.case("verb-du")["input"])
        result = self.result()
        self.assertTrue(result["evidence_valid"], result)
        self.assertTrue(result["operational_passed"])
        self.assertFalse(result["guarded_nonregression_passed"])
        self.assertEqual(result["lost_exact_fixes"], ["verb-du"])

    def test_new_supported_clean_edit_fails(self):
        self.replace("clean-simple", "Das ist ein schönes Heim.")
        result = self.result()
        self.assertTrue(result["operational_passed"], result)
        self.assertFalse(result["passed"])
        self.assertEqual(result["supported_clean_changes"], ["clean-simple"])

    def test_new_non_gold_edit_on_unresolved_error_fails(self):
        self.replace("verb-wir", "Wir seid zufrieden.")
        result = self.result()
        self.assertFalse(result["passed"], result)
        self.assertEqual(result["new_unexpected_error_edits"], ["verb-wir"])

    def test_valid_alternate_span_is_reported_without_losing_the_exact_fix(self):
        self.replace("verb-du", "Du gehst heute nach Hause.")
        result = self.result()
        self.assertTrue(result["passed"], result)
        difference = result["finding_changes"][0]
        self.assertEqual(difference["baseline"][0]["start"], 10)
        self.assertEqual(difference["candidate"][0]["start"], 7)
        self.assertEqual(result["added_exact_fixes"], [])

    def test_unsupported_locale_status_drift_is_explicit(self):
        row = self.case("clean-swiss")
        row["status"] = row["warmup"]["status"] = "success"
        row["message"] = row["warmup"]["message"] = None
        self.refresh_operational()
        result = self.result()
        self.assertTrue(result["evidence_valid"], result)
        self.assertFalse(result["passed"])
        self.assertEqual(result["status_changes"], [{"section": "cases", "id": "clean-swiss",
                         "baseline": "unsupported", "candidate": "success"}])

    def test_unsupported_and_failed_results_cannot_expose_edits(self):
        self.replace("clean-swiss", "Die Straße ist groß.")
        self.assert_invalid("must not expose edits")

    def test_missing_duplicate_and_foreign_cases_fail(self):
        for mode in ("missing", "duplicate", "foreign"):
            with self.subTest(mode=mode):
                self.setUp()
                if mode == "missing":
                    self.candidate["cases"].pop()
                elif mode == "duplicate":
                    self.candidate["cases"][-1] = copy.deepcopy(self.candidate["cases"][0])
                else:
                    self.candidate["cases"][-1]["id"] = "replacement-panel-case"
                self.assert_invalid()

    def test_missing_structural_and_operational_controls_fail(self):
        for section in ("controls", "long_complete_check_probes"):
            with self.subTest(section=section):
                self.setUp()
                self.candidate[section].pop()
                self.assert_invalid("coverage differs")

    def test_frozen_case_text_gold_locale_and_input_lengths_cannot_drift(self):
        for key, value in (("input", "Changed input."), ("expected", "Changed gold."),
                           ("source_locale", "de-AT"), ("language", "de-CH"),
                           ("evaluation_locale", "de-AT"), ("tokens_first_pass", 8),
                           ("reference_unguarded", "Different reference."), ("start_offset", 8)):
            with self.subTest(key=key):
                self.setUp()
                row = self.case("verb-du")
                row[key] = value
                if key == "reference_unguarded":
                    row["matches_unguarded_reference"] = False
                self.assert_invalid()

    def test_false_summary_flags_and_incomplete_source_evidence_fail(self):
        for key, value in (("completed", False), ("source_stable", False), ("operational_passed", False),
                           ("completed", 1), ("source_files", {}), ("schema_version", True)):
            with self.subTest(key=key):
                self.setUp()
                self.candidate[key] = value
                self.assert_invalid()

    def test_removed_source_seal_fails_but_changed_source_is_visible(self):
        path = next(iter(self.candidate["source_files"]))
        del self.candidate["source_files"][path]
        self.assert_invalid("previously sealed source files")
        self.setUp()
        self.candidate["source_files"][path] = "0" * 64
        result = self.result()
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["source_changes"][0]["path"], path)

    def test_nonfinite_negative_and_boolean_numeric_evidence_fail(self):
        for value in (float("nan"), float("inf"), -1, True, None, "12"):
            with self.subTest(value=value):
                self.setUp()
                self.case("verb-du")["elapsed_ms"] = value
                self.assert_invalid()
        self.setUp()
        self.candidate["unrelated_extra"] = {"value": float("inf")}
        self.assert_invalid("nonfinite")

    def test_timing_summaries_and_aggregate_samples_must_recompute(self):
        for mode in ("p95", "samples", "first_elapsed", "aggregate"):
            with self.subTest(mode=mode):
                self.setUp()
                row = self.case("verb-du")
                if mode == "p95":
                    row["timing"]["p95_ms"] = 0
                elif mode == "samples":
                    row["timing"]["samples_ms"].pop()
                elif mode == "first_elapsed":
                    row["elapsed_ms"] += 1
                else:
                    samples = self.candidate["warm_checks_up_to_64_wordpieces"]["samples_ms"]
                    samples[0] += 1
                    self.candidate["warm_checks_up_to_64_wordpieces"] = timing(samples)
                self.assert_invalid()

    def test_findings_must_reconstruct_original_utf16_text(self):
        for key, value in (("start", 6), ("end", 10000), ("original", "wrong"),
                           ("replacement", "different"), ("start", True)):
            with self.subTest(key=key):
                self.setUp()
                self.case("verb-du")["findings"][0][key] = value
                self.assert_invalid()

    def test_overlapping_or_duplicate_findings_fail(self):
        self.case("verb-du")["findings"].append(copy.deepcopy(self.case("verb-du")["findings"][0]))
        self.assert_invalid("overlap")

    def test_utf16_span_cannot_split_non_bmp_scalar(self):
        row = self.case("emoji-source-offset", "controls")
        row["findings"][0]["start"] = row["start_offset"] + 1
        self.assert_invalid("splits a UTF-16 scalar")

    def test_warmup_contradiction_and_unstable_repeats_do_not_pass(self):
        row = self.case("verb-du")
        row["warmup"]["findings"] = []
        row["warmup"]["corrected"] = row["input"]
        self.assert_invalid("stable_repeats contradicts")
        row["stable_repeats"] = False
        self.refresh_operational()
        result = self.result()
        self.assertTrue(result["evidence_valid"], result)
        self.assertFalse(result["operational_passed"])
        self.assertFalse(result["passed"])

    def test_immutable_model_native_reference_and_sidecar_drift_fail(self):
        for mode in ("native", "reference", "model_bytes", "sidecar", "missing_sidecar"):
            with self.subTest(mode=mode):
                self.setUp()
                if mode in ("native", "reference"):
                    key = "native_library_sha256" if mode == "native" else "reference_sha256"
                    self.candidate[key] = "0" * 64
                elif mode == "model_bytes":
                    self.candidate["model"]["bytes"] += 1
                elif mode == "sidecar":
                    self.candidate["bundle_assets"]["gector-guards.json"] = "0" * 64
                else:
                    del self.candidate["bundle_assets"]["NOTICE"]
                self.assert_invalid()

    def test_baseline_reformatting_or_replacement_cannot_reselect_the_baseline(self):
        for replacement in (encoded(self.baseline), encoded(self.candidate) + b"\n", b"{}"):
            with self.subTest(size=len(replacement)):
                result = compare.compare(replacement, encoded(self.candidate), self.cases_raw)
                self.assertFalse(result["passed"])
                self.assertIn("frozen first AOT", result["evidence_errors"][0])

    def test_corpus_changes_are_rejected_before_comparing_outputs(self):
        result = compare.compare(self.baseline_raw, encoded(self.candidate), self.cases_raw + b"\n")
        self.assertFalse(result["passed"])
        self.assertIn("frozen 30-case", result["evidence_errors"][0])

    def test_malformed_duplicate_key_and_nonfinite_json_fail_without_crashing(self):
        for raw in (b"{", b"\xff", b'{"cases": [], "cases": []}', b'{"value": NaN}',
                    b'{"value": 1e400}', b'{"value": ' + b"9" * 5000 + b"}"):
            with self.subTest(raw=raw):
                result = compare.compare(self.baseline_raw, raw, self.cases_raw)
                self.assertFalse(result["passed"])
                self.assertTrue(result["evidence_errors"])

    def test_missing_runtime_provenance_is_not_admitted(self):
        for key in ("product_mode", "entrypoint", "executable"):
            with self.subTest(key=key):
                self.setUp()
                del self.candidate["runtime"][key]
                self.assert_invalid()

    def test_engineering_budget_failure_is_visible_and_separate_from_quality(self):
        self.candidate["peak_process_rss_bytes"] = 900 * 1024 * 1024
        self.candidate["engineering_budgets"]["peak_rss_at_most_768_mib"] = False
        result = self.result()
        self.assertTrue(result["passed"], result)
        self.assertFalse(result["candidate"]["engineering_budgets"]["peak_rss_at_most_768_mib"])
        self.candidate["engineering_budgets"]["peak_rss_at_most_768_mib"] = True
        self.assert_invalid("contradicts recorded measurement")

    def test_control_failure_and_structural_false_edit_cannot_pass(self):
        self.replace("personal-vocabulary", "Du gehst heute nach Hause.", "controls")
        self.case("personal-vocabulary", "controls")["passed"] = False
        self.refresh_operational()
        result = self.result()
        self.assertTrue(result["evidence_valid"], result)
        self.assertFalse(result["gates"]["integration_controls_preserved"])
        self.setUp()
        row = self.case("repeated-sentences-up-to-64", "long_complete_check_probes")
        self.replace(row["id"], row["input"].replace("schön", "schlecht", 1), "long_complete_check_probes")
        result = self.result()
        self.assertTrue(result["operational_passed"], result)
        self.assertFalse(result["gates"]["structural_controls_preserved"])

    def test_cli_preserves_evidence_and_writes_negative_comparison(self):
        with TemporaryDirectory() as temporary:
            candidate = Path(temporary) / "candidate.json"
            output = Path(temporary) / "comparison.json"
            self.replace("verb-du", self.case("verb-du")["input"])
            candidate.write_bytes(encoded(self.candidate))
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(compare.main(["--candidate", str(candidate), "--output", str(output)]), 1)
                original = output.read_bytes()
                self.assertEqual(compare.main(["--candidate", str(candidate), "--output", str(output)]), 2)
                self.assertEqual(output.read_bytes(), original)
                before = candidate.read_bytes()
                self.assertEqual(compare.main(["--candidate", str(candidate), "--output", str(candidate)]), 2)
                self.assertEqual(candidate.read_bytes(), before)
            self.assertEqual(json.loads(original)["lost_exact_fixes"], ["verb-du"])


if __name__ == "__main__":
    unittest.main()
