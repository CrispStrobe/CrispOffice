#!/usr/bin/env python3
"""Compare guarded-provider receipts against the frozen first AOT observation.

This reads small JSON evidence only; it does not load models or execute inference.
The frozen synthetic panel measures nonregression, not general German accuracy.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import statistics
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_BASELINE = ROOT / "docs/validation/german-gector/2026-11-17-native-dart/provider-aot-v1.json"
DEFAULT_CASES = Path(__file__).with_name("cases.json")
# These are prior, unmodified observations, not hashes selected from a candidate.
BASELINE_SHA256 = "9fda0f778fe36c72af8141d7dd5f0c012b43882bb40046adc89b7bf76b9fd8bc"
CASES_SHA256 = "ec3309ebf99a3b1be9bb065fc91cd2afce2e362ebaa81f2d64d39a231c6defb9"
MAX_REPORT_BYTES = 2 * 1024 * 1024
REPORT_KIND = "quds-gector-native-dart-complete-check"
STATUSES = {"success", "unsupported", "unavailable", "failed", "cancelled"}
CONTROL_IDS = (
    "unsupported-de-AT", "unsupported-de-CH", "ignored-rule",
    "personal-vocabulary", "personal-vocabulary-removed", "protected-code",
    "emoji-source-offset", "capacity-fails-explicitly",
)
PROBE_LENGTHS = {64: (12, 61), 128: (25, 126), 256: (51, 256)}
SCOPE = (
    "Nonregression on the frozen 30-case synthetic panel: 18 de-DE error cases, "
    "10 de-DE clean controls, and 2 explicitly unsupported de-CH controls. "
    "The eight integration controls and three structural length probes are "
    "checked separately. This is not broad precision/recall, target-device "
    "qualification, or a release decision. Repeated outcome stability is "
    "reported by the producer; only its first result and warmup are retained."
)


class EvidenceError(ValueError):
    """The supplied evidence cannot establish this frozen comparison."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def mapping(value: Any, where: str) -> dict[str, Any]:
    require(type(value) is dict, f"{where}: expected an object")
    return value


def integer(value: Any, where: str, minimum: int = 0) -> int:
    require(type(value) is int and value >= minimum, f"{where}: expected integer >= {minimum}")
    return value


def number(value: Any, where: str) -> float:
    require(type(value) in (int, float), f"{where}: expected a finite nonnegative number")
    try:
        result = float(value)
    except (OverflowError, ValueError) as error:
        raise EvidenceError(f"{where}: invalid numeric evidence") from error
    require(math.isfinite(result) and result >= 0, f"{where}: expected a finite nonnegative number")
    return result


def text(value: Any, where: str, *, nonempty: bool = False) -> str:
    require(type(value) is str and (not nonempty or bool(value)), f"{where}: expected text")
    try:
        value.encode("utf-16-le")
    except UnicodeError as error:
        raise EvidenceError(f"{where}: invalid Unicode scalar text") from error
    return value


def digest(value: Any, where: str) -> str:
    require(type(value) is str and len(value) == 64
            and all(c in "0123456789abcdef" for c in value), f"{where}: invalid SHA-256")
    return value


def _object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, f"JSON object contains duplicate key: {key}")
        result[key] = value
    return result


def _finite_tree(value: Any, where: str) -> None:
    if type(value) is float:
        require(math.isfinite(value), f"{where}: nonfinite JSON number")
    elif type(value) is str:
        text(value, where)
    elif type(value) is dict:
        for key, item in value.items():
            text(key, f"{where}.key")
            _finite_tree(item, f"{where}.{key}")
    elif type(value) is list:
        for index, item in enumerate(value):
            _finite_tree(item, f"{where}[{index}]")


def decode(raw: bytes, where: str) -> Any:
    require(len(raw) <= MAX_REPORT_BYTES, f"{where}: evidence exceeds the 2 MiB limit")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=_object)
    except (UnicodeError, ValueError) as error:
        raise EvidenceError(f"{where}: malformed UTF-8 JSON: {error}") from error
    _finite_tree(value, where)
    return value


def indexed(rows: Any, expected: list[str] | tuple[str, ...], where: str) -> dict[str, dict[str, Any]]:
    require(type(rows) is list, f"{where}: expected a list")
    result = {}
    for index, value in enumerate(rows):
        row = mapping(value, f"{where}[{index}]")
        identity = text(row.get("id"), f"{where}[{index}].id", nonempty=True)
        require(identity not in result, f"{where}: duplicate case {identity}")
        result[identity] = row
    require(set(result) == set(expected),
            f"{where}: case coverage differs; missing={sorted(set(expected) - set(result))}, "
            f"extra={sorted(set(result) - set(expected))}")
    return result


def validate_timing(value: Any, where: str, count: int) -> list[float]:
    timing = mapping(value, where)
    samples = timing.get("samples_ms")
    require(type(samples) is list and len(samples) == count and count > 0,
            f"{where}: expected {count} timing samples")
    values = [number(sample, f"{where}.samples_ms[{i}]") for i, sample in enumerate(samples)]
    ordered = sorted(values)
    expected = {
        "median_ms": statistics.median(values),
        "p95_ms": ordered[math.ceil(len(values) * .95) - 1],
        "maximum_ms": ordered[-1],
    }
    for key, computed in expected.items():
        reported = number(timing.get(key), f"{where}.{key}")
        require(math.isclose(reported, computed, rel_tol=1e-12, abs_tol=1e-9),
                f"{where}.{key}: does not match recorded samples")
    return values


def validate_result(row: dict[str, Any], where: str, *, expected_id: str,
                    source: str, language: str, start_offset: int = 7) -> None:
    for key, expected in (("id", expected_id), ("input", source), ("language", language)):
        require(row.get(key) == expected, f"{where}.{key}: frozen input or locale differs")
    require(integer(row.get("start_offset"), f"{where}.start_offset") == start_offset,
            f"{where}.start_offset: frozen source offset differs")
    status = text(row.get("status"), f"{where}.status")
    require(status in STATUSES, f"{where}.status: unknown result status")
    message = row.get("message")
    require(message is None or type(message) is str, f"{where}.message: expected text or null")
    corrected = text(row.get("corrected"), f"{where}.corrected")
    number(row.get("elapsed_ms"), f"{where}.elapsed_ms")
    findings = row.get("findings")
    require(type(findings) is list, f"{where}.findings: expected a list")
    encoded = source.encode("utf-16-le")
    boundaries = {0}
    offset = 0
    for character in source:
        offset += len(character.encode("utf-16-le")) // 2
        boundaries.add(offset)
    previous_start = -1
    previous_end = -1
    replacements = []
    for index, value in enumerate(findings):
        finding = mapping(value, f"{where}.findings[{index}]")
        at = f"{where}.findings[{index}]"
        start = integer(finding.get("start"), f"{at}.start") - start_offset
        end = integer(finding.get("end"), f"{at}.end") - start_offset
        require(start in boundaries and end in boundaries and start <= end,
                f"{at}: span is outside the original text or splits a UTF-16 scalar")
        require(start >= previous_end and start > previous_start,
                f"{at}: finding spans overlap, repeat an insertion point, or are unordered")
        original = text(finding.get("original"), f"{at}.original")
        replacement = text(finding.get("replacement"), f"{at}.replacement")
        text(finding.get("rule_id"), f"{at}.rule_id", nonempty=True)
        require(encoded[start * 2:end * 2].decode("utf-16-le") == original,
                f"{at}: original text does not match its UTF-16 span")
        require(original != replacement, f"{at}: a finding must change its source text")
        replacements.append((start, end, replacement.encode("utf-16-le")))
        previous_start, previous_end = start, end
    reconstructed = encoded
    for start, end, replacement in reversed(replacements):
        reconstructed = reconstructed[:start * 2] + replacement + reconstructed[end * 2:]
    require(reconstructed.decode("utf-16-le") == corrected,
            f"{where}: findings do not reconstruct corrected text exactly")
    if status != "success":
        require(not findings and corrected == source,
                f"{where}: unsuccessful or unsupported result must not expose edits")
        require(type(message) is str and bool(message), f"{where}: missing failure/unsupported message")


def validate_measured(row: dict[str, Any], where: str, *, identity: str,
                      source: str, language: str, token_count: int | None = None) -> list[float]:
    validate_result(row, where, expected_id=identity, source=source, language=language)
    require(row.get("expected_status") == ("success" if language == "de-DE" else "unsupported"),
            f"{where}.expected_status: frozen locale policy differs")
    count = integer(row.get("tokens_first_pass"), f"{where}.tokens_first_pass", 1)
    require(count <= 512 and (token_count is None or count == token_count),
            f"{where}.tokens_first_pass: invalid or changed prepared-input length")
    require(type(row.get("stable_repeats")) is bool, f"{where}.stable_repeats: expected boolean")
    warmup = mapping(row.get("warmup"), f"{where}.warmup")
    validate_result(warmup, f"{where}.warmup", expected_id=f"{identity}-warmup", source=source, language=language)
    if row["stable_repeats"]:
        require(all(warmup[key] == row[key] for key in ("status", "corrected", "findings")),
                f"{where}: stable_repeats contradicts the retained warmup")
    samples = validate_timing(row.get("timing"), f"{where}.timing", 3)
    require(row["elapsed_ms"] == samples[0], f"{where}.elapsed_ms: differs from first measured sample")
    return samples


def validate_report(value: Any, corpus: list[dict[str, Any]], where: str) -> dict[str, Any]:
    report = mapping(value, where)
    require(type(report.get("schema_version")) is int and report["schema_version"] == 1,
            f"{where}: unsupported receipt schema")
    require(report.get("kind") == REPORT_KIND, f"{where}: wrong receipt kind")
    require(report.get("completed") is True, f"{where}: receipt is incomplete")
    require(report.get("source_stable") is True, f"{where}: source changed during execution")
    require(type(report.get("operational_passed")) is bool, f"{where}.operational_passed: expected boolean")
    require(report.get("cases_sha256") == CASES_SHA256, f"{where}: frozen corpus identity differs")
    digest(report.get("reference_sha256"), f"{where}.reference_sha256")
    digest(report.get("native_library_sha256"), f"{where}.native_library_sha256")
    model = mapping(report.get("model"), f"{where}.model")
    require(set(model) == {"file", "sha256", "bytes", "source_model_sha256", "revision"},
            f"{where}.model: incomplete or unknown model identity fields")
    model_file = text(model.get("file"), f"{where}.model.file", nonempty=True)
    require(PurePosixPath(model_file).name == model_file and "\\" not in model_file,
            f"{where}.model.file: expected a basename")
    digest(model.get("sha256"), f"{where}.model.sha256")
    digest(model.get("source_model_sha256"), f"{where}.model.source_model_sha256")
    text(model.get("revision"), f"{where}.model.revision", nonempty=True)
    model_bytes = integer(model.get("bytes"), f"{where}.model.bytes", 1)
    assets = mapping(report.get("bundle_assets"), f"{where}.bundle_assets")
    require(len(assets) == 13 and assets.get(model_file) == model["sha256"],
            f"{where}: incomplete model/sidecar identity inventory")
    for name, sha in assets.items():
        require(PurePosixPath(name).name == name and "\\" not in name, f"{where}: invalid asset basename")
        digest(sha, f"{where}.bundle_assets.{name}")
    sources = mapping(report.get("source_files"), f"{where}.source_files")
    require(bool(sources), f"{where}: missing source inventory")
    for name, sha in sources.items():
        path = PurePosixPath(name)
        require(not path.is_absolute() and ".." not in path.parts and "\\" not in name,
                f"{where}: source inventory must use repository-relative paths")
        digest(sha, f"{where}.source_files.{name}")
    runtime = mapping(report.get("runtime"), f"{where}.runtime")
    for key in ("dart", "os", "os_version"):
        text(runtime.get(key), f"{where}.runtime.{key}", nonempty=True)
    integer(runtime.get("processors"), f"{where}.runtime.processors", 1)
    for key, expected in (("native_threads", 2), ("warmups_per_input", 1), ("repeats_per_input", 3)):
        require(type(runtime.get(key)) is int and runtime[key] == expected,
                f"{where}.runtime.{key}: frozen execution protocol differs")
    require(type(runtime.get("product_mode")) is bool, f"{where}.runtime.product_mode: expected boolean")
    for key in ("executable", "entrypoint"):
        pin = mapping(runtime.get(key), f"{where}.runtime.{key}")
        text(pin.get("file"), f"{where}.runtime.{key}.file", nonempty=True)
        integer(pin.get("bytes"), f"{where}.runtime.{key}.bytes", 1)
        digest(pin.get("sha256"), f"{where}.runtime.{key}.sha256")
    number(report.get("setup_ms"), f"{where}.setup_ms")
    rss = integer(report.get("peak_process_rss_bytes"), f"{where}.peak_process_rss_bytes", 1)
    cases = indexed(report.get("cases"), [row["id"] for row in corpus], f"{where}.cases")
    short_samples = []
    for frozen in corpus:
        identity = frozen["id"]
        row = cases[identity]
        at = f"{where}.cases.{identity}"
        language = frozen.get("locale", "de-DE")
        expected = frozen.get("expected", frozen["input"])
        samples = validate_measured(row, at, identity=identity, source=frozen["input"], language=language)
        for key, wanted in (("kind", frozen["kind"]), ("expected", expected),
                            ("source_locale", language), ("evaluation_locale", language)):
            require(row.get(key) == wanted, f"{at}.{key}: frozen corpus value differs")
        reference = text(row.get("reference_unguarded"), f"{at}.reference_unguarded")
        for key, computed in (("matches_expected", row["corrected"] == expected),
                              ("matches_unguarded_reference", row["corrected"] == reference)):
            require(type(row.get(key)) is bool and row[key] == computed, f"{at}.{key}: inconsistent evidence")
        if row["status"] == "success" and row["tokens_first_pass"] <= 64:
            short_samples.extend(samples)
    probes = indexed(report.get("long_complete_check_probes"),
                     [f"repeated-sentences-up-to-{length}" for length in PROBE_LENGTHS], f"{where}.probes")
    for budget, (repeats, token_count) in PROBE_LENGTHS.items():
        identity = f"repeated-sentences-up-to-{budget}"
        row = probes[identity]
        require(type(row.get("token_budget")) is int and row["token_budget"] == budget,
                f"{where}.probes.{identity}: token budget differs")
        samples = validate_measured(row, f"{where}.probes.{identity}", identity=identity,
                                    source=" ".join(["Das Haus ist schön."] * repeats),
                                    language="de-DE", token_count=token_count)
        if budget == 64:
            short_samples.extend(samples)
    aggregate = validate_timing(report.get("warm_checks_up_to_64_wordpieces"),
                                f"{where}.short_timing", len(short_samples))
    require(sorted(aggregate) == sorted(short_samples), f"{where}: short aggregate does not match its cases/probe")
    sentence = "Du geht heute nach Hause."
    control_specs = {
        "unsupported-de-AT": (sentence, "de-AT", "unsupported", sentence),
        "unsupported-de-CH": (sentence, "de-CH", "unsupported", sentence),
        "ignored-rule": (sentence, "de-DE", "success", sentence),
        "personal-vocabulary": (sentence, "de-DE", "success", sentence),
        "personal-vocabulary-removed": (sentence, "de-DE", "success", "Du gehst heute nach Hause."),
        "protected-code": (f"`{sentence}`", "de-DE", "success", f"`{sentence}`"),
        "emoji-source-offset": (f"😀 {sentence}", "de-DE", "success", "😀 Du gehst heute nach Hause."),
        "capacity-fails-explicitly": (" ".join(["Haus"] * 600), "de-DE", "failed", " ".join(["Haus"] * 600)),
    }
    controls = indexed(report.get("controls"), CONTROL_IDS, f"{where}.controls")
    for identity, (source, language, status, corrected) in control_specs.items():
        row = controls[identity]
        validate_result(row, f"{where}.controls.{identity}", expected_id=identity, source=source, language=language)
        computed = row["status"] == status and row["corrected"] == corrected
        require(type(row.get("passed")) is bool and row["passed"] == computed,
                f"{where}.controls.{identity}.passed: inconsistent control evidence")
    operational = (
        all(row["status"] == row["expected_status"] and row["stable_repeats"] for row in cases.values())
        and all(row["status"] == "success" and row["stable_repeats"] for row in probes.values())
        and all(row["passed"] for row in controls.values())
    )
    require(report["operational_passed"] == operational, f"{where}: operational_passed contradicts retained results")
    budgets = mapping(report.get("engineering_budgets"), f"{where}.engineering_budgets")
    for key, computed in (("p95_at_most_500_ms", report["warm_checks_up_to_64_wordpieces"]["p95_ms"] <= 500),
                          ("peak_rss_at_most_768_mib", rss <= 768 * 1024 * 1024),
                          ("gguf_at_most_160_mib", model_bytes <= 160 * 1024 * 1024)):
        require(type(budgets.get(key)) is bool and budgets[key] == computed,
                f"{where}.engineering_budgets.{key}: contradicts recorded measurement")
    return {"report": report, "cases": cases, "probes": probes, "controls": controls, "operational": operational}


def _metric(receipt: dict[str, Any]) -> dict[str, Any]:
    report = receipt["report"]
    cases = list(receipt["cases"].values())
    errors = [row for row in cases if row["kind"] == "error" and row["language"] == "de-DE"]
    clean = [row for row in cases if row["kind"] == "clean" and row["language"] == "de-DE"]
    return {
        "supported_error_cases": len(errors),
        "exact_fixes": sum(row["status"] == "success" and row["corrected"] == row["expected"] for row in errors),
        "supported_clean_controls": len(clean),
        "unchanged_clean_controls": sum(row["status"] == "success" and row["corrected"] == row["input"] for row in clean),
        "operational_passed": receipt["operational"],
        "product_mode": report["runtime"]["product_mode"],
        "setup_ms": report["setup_ms"],
        "peak_process_rss_bytes": report["peak_process_rss_bytes"],
        "short_timing": {key: value for key, value in report["warm_checks_up_to_64_wordpieces"].items() if key != "samples_ms"},
        "engineering_budgets": report["engineering_budgets"],
    }


def compare(baseline_raw: bytes, candidate_raw: bytes, cases_raw: bytes) -> dict[str, Any]:
    """Return a fail-closed, JSON-safe receipt; malformed evidence is not a pass."""
    result: dict[str, Any] = {
        "schema_version": 1, "kind": "quds-gector-guarded-provider-comparison",
        "scope": SCOPE, "frozen_baseline_sha256": BASELINE_SHA256,
        "baseline_sha256": hashlib.sha256(baseline_raw).hexdigest(),
        "candidate_sha256": hashlib.sha256(candidate_raw).hexdigest(),
        "cases_sha256": hashlib.sha256(cases_raw).hexdigest(),
        "evidence_valid": False, "operational_passed": False,
        "guarded_nonregression_passed": False, "passed": False, "evidence_errors": [],
    }
    try:
        require(result["baseline_sha256"] == BASELINE_SHA256, "baseline: bytes differ from the frozen first AOT receipt")
        require(result["cases_sha256"] == CASES_SHA256, "corpus: bytes differ from the frozen 30-case panel")
        corpus = decode(cases_raw, "corpus")
        baseline = validate_report(decode(baseline_raw, "baseline"), corpus, "baseline")
        candidate = validate_report(decode(candidate_raw, "candidate"), corpus, "candidate")
        left, right = baseline["report"], candidate["report"]
        for key in ("model", "bundle_assets", "native_library_sha256", "reference_sha256"):
            require(left[key] == right[key], f"candidate.{key}: immutable artifact/reference identity drift")
        require(set(left["source_files"]) <= set(right["source_files"]),
                "candidate.source_files: previously sealed source files are missing")
        for identity, old in baseline["cases"].items():
            new = candidate["cases"][identity]
            for key in ("reference_unguarded", "tokens_first_pass"):
                require(old[key] == new[key], f"candidate.cases.{identity}.{key}: frozen reference/input drift")
        result["evidence_valid"] = True
        result["baseline"] = _metric(baseline)
        result["candidate"] = _metric(candidate)
        added, lost, clean_changes, unexpected, statuses, finding_changes, changes = [], [], [], [], [], [], []
        for section in ("cases", "probes", "controls"):
            for identity, old in baseline[section].items():
                new = candidate[section][identity]
                observation = {"section": section, "id": identity,
                               "baseline": {key: old[key] for key in ("status", "corrected", "findings")},
                               "candidate": {key: new[key] for key in ("status", "corrected", "findings")}}
                if observation["baseline"] != observation["candidate"]:
                    changes.append(observation)
                if old["status"] != new["status"]:
                    statuses.append({"section": section, "id": identity, "baseline": old["status"], "candidate": new["status"]})
                if old["findings"] != new["findings"]:
                    finding_changes.append({"section": section, "id": identity,
                                            "baseline": old["findings"], "candidate": new["findings"]})
                if section != "cases" or old["language"] != "de-DE":
                    continue
                if old["kind"] == "clean" and new["corrected"] != old["input"]:
                    clean_changes.append(identity)
                elif old["kind"] == "error":
                    before = old["status"] == "success" and old["corrected"] == old["expected"]
                    after = new["status"] == "success" and new["corrected"] == old["expected"]
                    if before and not after:
                        lost.append(identity)
                    if after and not before:
                        added.append(identity)
                    if new["corrected"] != old["corrected"] and not after:
                        unexpected.append(identity)
        gates = {
            "status_policy_preserved": not statuses,
            "previous_exact_fixes_preserved": not lost,
            "supported_clean_text_unchanged": not clean_changes,
            "no_new_unexpected_error_edits": not unexpected,
            "integration_controls_preserved": all(candidate["controls"][key]["passed"] for key in CONTROL_IDS),
            "structural_controls_preserved": all(row["corrected"] == row["input"] for row in candidate["probes"].values()),
        }
        source_changes = []
        for name in sorted(set(left["source_files"]) | set(right["source_files"])):
            old, new = left["source_files"].get(name), right["source_files"].get(name)
            if old != new:
                source_changes.append({"path": name, "baseline": old, "candidate": new})
        result.update({
            "operational_passed": candidate["operational"],
            "guarded_nonregression_passed": all(gates.values()),
            "gates": gates, "added_exact_fixes": added, "lost_exact_fixes": lost,
            "supported_clean_changes": clean_changes, "new_unexpected_error_edits": unexpected,
            "status_changes": statuses, "finding_changes": finding_changes,
            "outcome_changes": changes, "source_changes": source_changes,
            "performance_note": "Engineering budget flags are reported separately and do not prove target-device performance.",
        })
        result["passed"] = result["operational_passed"] and result["guarded_nonregression_passed"]
    except (EvidenceError, TypeError, KeyError, IndexError, OverflowError, RecursionError) as error:
        result["evidence_errors"].append(str(error))
    return result


def read_evidence(path: Path) -> bytes:
    with path.open("rb") as source:
        value = source.read(MAX_REPORT_BYTES + 1)
    require(len(value) <= MAX_REPORT_BYTES, f"{path.name}: evidence exceeds the 2 MiB limit")
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args(argv)
    try:
        require(not options.output.exists(), "Refusing to overwrite an existing comparison report or input.")
        result = compare(read_evidence(options.baseline), read_evidence(options.candidate), read_evidence(options.cases))
        options.output.parent.mkdir(parents=True, exist_ok=True)
        with options.output.open("x", encoding="utf-8") as target:
            json.dump(result, target, ensure_ascii=False, indent=2, allow_nan=False)
            target.write("\n")
        print(json.dumps({key: result[key] for key in
                          ("evidence_valid", "operational_passed", "guarded_nonregression_passed", "passed", "evidence_errors")}))
        return 0 if result["passed"] else 1
    except (OSError, EvidenceError) as error:
        print(f"Guarded-provider comparison rejected: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
