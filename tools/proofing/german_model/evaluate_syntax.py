#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Evaluation-only German syntax experiment; never registered by an app.

spaCy supplies statistical annotations. The small agreement planner below is
independently authored and uses the existing first-party finite verb table.
It is a diagnostic prototype, not a general grammar checker or shipping backend.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import re
import resource
import sys
import time


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def paradigms(source: Path) -> dict[str, tuple[str, str]]:
    # Extract factual forms from the existing reviewed first-party Dart table.
    pattern = r"_GermanPresentParadigm\(\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',?\s*\)"
    found = re.findall(pattern, source.read_text())
    if len(found) != 57:
        raise ValueError(f"First-party paradigm table changed: {len(found)}")
    return {lemma: (third, plural) for lemma, _, _, third, plural, _ in found}


def agreement_edits(doc, forms, noun_evidence=None):
    edits = []
    for subject in doc:
        if subject.dep_ != "sb" or subject.pos_ not in {"NOUN", "PROPN"}:
            continue
        verb = subject.head
        if verb.pos_ not in {"VERB", "AUX"} or verb.morph.get("VerbForm") != ["Fin"]:
            continue
        # Coordination changes subject number; this experiment abstains.
        if any(t.dep_ in {"cj", "cd"} for t in subject.subtree):
            continue
        numbers = subject.morph.get("Number")
        if len(numbers) != 1 or numbers[0] not in {"Sing", "Plur"}:
            continue
        if noun_evidence is not None:
            lexical = noun_evidence.get((subject.idx, subject.text))
            if not lexical or lexical["unresolved"] or lexical["numbers"] != numbers:
                continue
        table = forms.get(verb.lemma_)
        if not table or verb.text.lower() not in table:
            continue
        expected = table[numbers[0] == "Plur"]
        if verb.text.lower() == expected:
            continue
        if verb.text[0].isupper():
            expected = expected[0].upper() + expected[1:]
        edits.append({"start": verb.idx, "end": verb.idx + len(verb.text),
                      "original": verb.text, "replacement": expected,
                      "subject": subject.text, "number": numbers[0]})
    return edits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True)
    parser.add_argument("--cases", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--noun-evidence", type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; preserve prior evidence")
    root = Path(__file__).resolve().parents[3]
    source = root / "packages/quds_office_engine/lib/src/proofing/german_writing_rules.dart"
    forms = paradigms(source)
    import spacy
    started = time.perf_counter()
    # Entity recognition has no role in this agreement experiment.
    model = spacy.load(args.model, disable=["ner"])
    startup = time.perf_counter() - started
    noun_evidence = None
    if args.noun_evidence:
        lexical = json.loads(args.noun_evidence.read_text())
        if lexical["cases_sha256"] != sha256(args.cases) or lexical["model_version"] != model.meta["version"]:
            raise ValueError("Noun evidence belongs to different input or model")
        noun_evidence = {}
        for item in lexical["nouns"]:
            key = (item["start"], item["text"])
            entries = noun_evidence.setdefault(item["id"], {})
            if key in entries:
                raise ValueError("Duplicate noun evidence")
            entries[key] = item
    rows = []
    for case in json.loads(args.cases.read_text()):
        text = case["input"]
        begin = time.perf_counter()
        doc = model(text)
        # Swiss/Austrian syntax/model policy is unqualified; do not suggest.
        supported = case.get("locale", "de-DE") == "de-DE"
        evidence = noun_evidence.get(case["id"], {}) if noun_evidence is not None else None
        edits = agreement_edits(doc, forms, evidence) if supported else []
        output = text
        for edit in sorted(edits, key=lambda e: e["start"], reverse=True):
            output = output[:edit["start"]] + edit["replacement"] + output[edit["end"]:]
        rows.append({**case, "output": output, "edits": edits,
                     "supported": supported, "exact": output == case.get("expected", text),
                     "milliseconds": (time.perf_counter() - begin) * 1000,
                     "tokens": [{"text": t.text, "start": t.idx, "end": t.idx + len(t.text),
                                 "head": t.head.i, "dependency": t.dep_, "pos": t.pos_,
                                 "lemma": t.lemma_, "morphology": t.morph.to_dict()}
                                for t in doc]})
    errors = [r for r in rows if r["kind"] == "error"]
    clean = [r for r in rows if r["kind"] == "clean"]
    report = {"scope": "Evaluation-only statistical syntax with first-party bounded agreement planner; Python code-point offsets, not application UTF-16 findings.",
              "application_enabled": False, "model": model.meta,
              "runtime": {"python": platform.python_version(), "platform": platform.platform(),
                          "spacy": importlib.metadata.version("spacy"),
                          "omp_num_threads": os.environ.get("OMP_NUM_THREADS")},
              "cases_sha256": sha256(args.cases), "planner_sha256": sha256(Path(__file__)),
              "noun_evidence_sha256": sha256(args.noun_evidence) if args.noun_evidence else None,
              "paradigms_sha256": sha256(source), "startup_seconds": startup,
              "max_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * (1 if sys.platform == "darwin" else 1024),
              "summary": {"errors": len(errors), "exact_errors": sum(r["exact"] for r in errors),
                          "clean": len(clean), "clean_changed": sum(r["output"] != r["input"] for r in clean),
                          "unsupported": sum(not r["supported"] for r in rows)},
              "cases": rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["summary"]), flush=True)


if __name__ == "__main__":
    main()
