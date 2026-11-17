#!/usr/bin/env python3
"""Fail-closed verification of spaCy reference payloads, without model packages."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import struct
import sys

from export_reference import (
    FEATURES, NUMERICAL_POLICY, PIPELINE, ROW_COUNTS, RUNTIME, SCHEMA,
    WHEEL_SHA256, WHEEL_SIZE, coordinate_maps, load_cases,
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON field: {key}")
        result[key] = value
    return result


def read_json(path: Path):
    require(path.is_file() and not path.is_symlink(), "Required JSON file missing or symlinked")
    require(path.stat().st_size <= 16 * 1024 * 1024, "Reference JSON is too large")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=object_pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError("Nonfinite JSON value")))


def safe_path(root: Path, path: str) -> Path:
    require(isinstance(path, str) and "\\" not in path, "Invalid reference member path")
    relative = PurePosixPath(path)
    require(not relative.is_absolute() and str(relative) == path and ".." not in relative.parts,
            "Unsafe reference member path")
    result = root.joinpath(*relative.parts)
    require(result.is_relative_to(root), "Reference path escapes root")
    require(all(not root.joinpath(*relative.parts[:i]).is_symlink() for i in range(1, len(relative.parts) + 1)),
            "Reference symlinks are not permitted")
    return result


def checked_bytes(root: Path, entry: dict) -> bytes:
    path = safe_path(root, entry["path"])
    require(path.is_file(), f"Required reference payload missing: {entry['path']}")
    require(type(entry["size_bytes"]) is int and 0 <= entry["size_bytes"] <= 64 * 1024 * 1024,
            "Invalid reference payload size")
    require(path.stat().st_size == entry["size_bytes"], f"Size differs: {entry['path']}")
    payload = path.read_bytes()
    require(hashlib.sha256(payload).hexdigest() == entry["sha256"], f"SHA-256 differs: {entry['path']}")
    return payload


def stage_shapes(tokens: int, steps: int) -> dict[str, list[int]]:
    stages = {"tok2vec.output": [tokens, 96], "tagger.scores": [tokens, 55],
              "morphologizer.scores": [tokens, 671], "lemmatizer.scores": [tokens, 1311]}
    if not tokens:
        return stages
    stages.update({"tok2vec.embed.concat": [tokens, 576], "tok2vec.embed.affine": [tokens, 96, 3],
                   "tok2vec.embed.maxout": [tokens, 96], "tok2vec.embed.norm": [tokens, 96],
                   "tok2vec.encoder.input": [tokens + 8, 96], "parser.reduce": [tokens, 64],
                   "parser.lower_cache": [tokens + 1, 8, 64, 2]})
    for i in range(4):
        prefix = f"tok2vec.encoder.layer.{i}."
        stages[prefix + "window"] = [tokens + 8, 288]
        stages[prefix + "affine"] = [tokens + 8, 96, 3]
        for name in ("maxout", "norm", "residual"):
            stages[prefix + name] = [tokens + 8, 96]
    for i in range(steps):
        stages[f"parser.step.{i}.sum"] = [1, 64, 2]
        stages[f"parser.step.{i}.hidden"] = [1, 64]
        stages[f"parser.step.{i}.scores"] = [1, 137]
    return stages


def verify(directory: Path, cases_path: Path | None = None) -> dict:
    root = directory.resolve(strict=True)
    manifest = read_json(root / "manifest.json")
    require(manifest.get("schema") == SCHEMA and manifest.get("complete") is True, "Incomplete/unsupported reference manifest")
    require(manifest["model"]["sha256"] == WHEEL_SHA256 and manifest["model"]["size_bytes"] == WHEEL_SIZE,
            "Unapproved source model identity")
    require(manifest["model"]["pipeline"] == PIPELINE, "Unexpected pipeline selection")
    require(manifest["model"]["excluded"] == ["ner"] and manifest["model"]["disabled"] == ["senter"],
            "Unexpected excluded or disabled components")
    require(manifest["numerical_policy"] == NUMERICAL_POLICY, "Reference tolerance policy changed")
    require(manifest["environment"]["runtime_pins"] == RUNTIME, "Unsupported oracle versions")
    require(manifest["environment"]["python"] == "3.12.14", "Unsupported reference Python")
    require(manifest["ordinary_pipeline_annotations_exact"] is True and manifest["ordinary_tok2vec_bit_exact"] is True,
            "Reference hook neutrality is missing")
    require(manifest["split"] in ("development", "acceptance"), "Invalid reference split")
    require(isinstance(manifest["cases"], list) and 1 <= len(manifest["cases"]) <= 512, "Reference cases missing")
    require(manifest["case_count"] == len(manifest["cases"]), "Case denominator differs")
    require([len(manifest["labels"][n]) for n in ("tagger", "morphologizer", "lemmatizer", "parser")] == [55, 671, 1311, 137],
            "Label/action inventory is incomplete")
    require({row["path"] for row in manifest["notices"]} == {"LICENSE", "LICENSES_SOURCES"}, "Required model notices missing")
    expected_cases = None
    if cases_path is not None:
        require(hashlib.sha256(cases_path.read_bytes()).hexdigest() == manifest["cases_file_sha256"], "Fixture input SHA-256 differs")
        _, cases = load_cases(cases_path, manifest["split"])
        expected_cases = {case["id"]: case for case in cases}
        require(set(expected_cases) == {case["id"] for case in manifest["cases"]}, "Fixture IDs do not match the selected split")
    retained = {"manifest.json"}
    checked_bytes(root, manifest["environment"]["lock"])
    retained.add(manifest["environment"]["lock"]["path"])
    for entry in manifest["notices"]:
        checked_bytes(root, entry)
        retained.add(entry["path"])
    tokens_total = stages_total = steps_total = 0
    seen = set()
    for entry in manifest["cases"]:
        ident = entry["id"]
        require(isinstance(ident, str) and re.fullmatch(r"[a-z][a-z0-9-]{0,63}", ident) is not None and ident not in seen,
                "Duplicate/unsafe reference case ID")
        seen.add(ident)
        require({f["path"] for f in entry["files"]} == {f"{ident}/case.json", f"{ident}/traces.f32"}, "Case payload inventory differs")
        for member in entry["files"]:
            checked_bytes(root, member)
            retained.add(member["path"])
        case = read_json(root / ident / "case.json")
        require(case["schema"] == SCHEMA and case["case"]["id"] == ident, "Case identity differs")
        if expected_cases is not None:
            require(case["case"] == expected_cases[ident], "Case input differs from frozen text")
        text = case["case"]["text"]
        require(hashlib.sha256(text.encode("utf-8")).hexdigest() == entry["input_sha256"] == case["input_sha256"], "Case input digest differs")
        bytes_at, utf16_at = coordinate_maps(text)
        annotations = case["annotations"]["tokens"]
        count = len(annotations)
        require(count == entry["tokens"], "Token denominator differs")
        require("".join(t["text"] + t["whitespace"] for t in annotations) == text, "Token/whitespace reconstruction differs")
        previous = 0
        for i, token in enumerate(annotations):
            start, end = token["start_codepoint"], token["end_codepoint"]
            require(type(start) is int and type(end) is int and previous <= start < end <= len(text), "Invalid scalar token span")
            require(token["i"] == i and type(token["head"]) is int and 0 <= token["head"] < count, "Invalid token/head index")
            require(text[start:end] == token["text"], "Token surface differs from original slice")
            require([token["start_byte"], token["end_byte"], token["start_utf16"], token["end_utf16"]] ==
                    [bytes_at[start], bytes_at[end], utf16_at[start], utf16_at[end]], "Byte/UTF-16 token boundaries differ")
            for key in ("orth_id", "norm_id"):
                require(isinstance(token[key], str) and token[key].isdigit() and 0 <= int(token[key]) < 2 ** 64,
                        "Lexical uint64 ID is not an exact decimal string")
            previous = end
        features = case["features"]
        require(features["columns"] == FEATURES and features["hash_seeds"] == list(range(8, 14)) and features["rows"] == ROW_COUNTS,
                "Lexical feature contract differs")
        require(len(features["uint64_decimal"]) == count == len(features["buckets"]), "Feature token denominator differs")
        for row, buckets in zip(features["uint64_decimal"], features["buckets"]):
            require(len(row) == len(buckets) == 6, "Missing lexical feature")
            require(all(isinstance(x, str) and x.isdigit() and int(x) < 2 ** 64 for x in row), "Feature ID is not uint64 decimal")
            for column, ids in enumerate(buckets):
                require(len(ids) == 4 and all(type(i) is int and 0 <= i < ROW_COUNTS[column] for i in ids), "Invalid embedding bucket")
        steps = case["parser_steps"]
        require(len(steps) == entry["parser_steps"] and (0 < len(steps) <= 8 * count + 32 if count else not steps), "Parser transition denominator differs")
        for i, step in enumerate(steps):
            require(step["step"] == i and len(step["feature_token_ids"]) == 8, "Parser step/features missing")
            require(all(type(index) is int and -1 <= index < count for index in step["feature_token_ids"]), "Invalid parser feature index")
            chosen = step["chosen_action"]
            require(len(step["valid_actions"]) == 137 and all(type(x) is bool for x in step["valid_actions"]), "Invalid action mask")
            require(type(chosen) is int and 0 <= chosen < 137 and step["valid_actions"][chosen], "Chosen parser action is invalid")
            require(step["chosen_name"] == manifest["labels"]["parser"][chosen], "Parser action label order differs")
            for arc in step["arcs_before"]:
                require(isinstance(arc["label"], str) and arc["label"].isdigit() and int(arc["label"]) < 2 ** 64,
                        "Parser label ID is not uint64 decimal")
        require(len(case["lemma_decisions"]) == count, "Lemmatizer decisions missing")
        expected = stage_shapes(count, len(steps))
        require(set(case["traces"]) == set(expected), "Required numeric stage inventory differs")
        require(len(expected) == entry["trace_stages"], "Stage denominator differs")
        payload = (root / ident / "traces.f32").read_bytes()
        intervals = []
        for name, descriptor in case["traces"].items():
            require(descriptor["file"] == "traces.f32" and descriptor["dtype"] == "float32-le" and descriptor["order"] == "C",
                    "Unsupported trace container")
            require(descriptor["shape"] == expected[name], f"Trace shape differs: {ident}/{name}")
            start, size = descriptor["offset_bytes"], descriptor["size_bytes"]
            require(type(start) is int and type(size) is int and start >= 0 and start % 4 == 0 and size == math.prod(expected[name]) * 4,
                    "Invalid trace allocation/offset")
            require(start + size <= len(payload), "Truncated numerical trace")
            part = payload[start:start + size]
            require(hashlib.sha256(part).hexdigest() == descriptor["sha256"], f"Stage digest differs: {ident}/{name}")
            require(all(math.isfinite(value[0]) for value in struct.iter_unpack("<f", part)), "Nonfinite numerical trace")
            intervals.append((start, start + size))
        end = 0
        for start, stop in sorted(intervals):
            require(start == end, "Numeric traces overlap or leave unaccounted bytes")
            end = stop
        require(end == len(payload), "Unaccounted numerical payload suffix")
        require(case["ordinary_pipeline_annotations_exact"] is True and case["ordinary_tok2vec_bit_exact"] is True,
                "Case hook neutrality is missing")
        tokens_total += count
        stages_total += len(expected)
        steps_total += len(steps)
    require(tokens_total > 0 and tokens_total == manifest["token_count"], "Zero/mismatched token denominator")
    require(stages_total == manifest["trace_stage_count"] and steps_total == manifest["parser_step_count"], "Stage/parser totals differ")
    actual = {str(path.relative_to(root)) for path in root.rglob("*") if path.is_file()}
    require(actual == retained, "Missing or unexpected files in reference bundle")
    return {"status": "verified", "scope": "reference integrity only", "split": manifest["split"],
            "cases": len(seen), "tokens": tokens_total, "trace_stages": stages_total, "parser_steps": steps_total,
            "manifest_sha256": hashlib.sha256((root / "manifest.json").read_bytes()).hexdigest()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--cases", type=Path)
    args = parser.parse_args(argv)
    try:
        result = verify(args.reference, args.cases)
    except (ValueError, OSError, KeyError, TypeError, IndexError) as error:
        print(f"Reference verification FAILED: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
