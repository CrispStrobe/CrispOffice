#!/usr/bin/env python3
"""Export an uncompleted human review packet from a real native query report.

Observed sense fields are checked against hash-verified current pack records.
This exports evidence; it does not run the provider or approve lexical quality.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import zlib

from build_packs import DEFAULT_OUTPUT, ROOT, digest, require, shard

PANEL = (
    ("bank", "en-US"), ("run", "en-US"), ("happy", "en-GB"),
    ("ice cream", "en-US"), ("children", "en-US"), ("dogs", "en-US"),
    ("Bank", "de-DE"), ("Häusern", "de-DE"), ("Maße", "de-DE"),
    ("Masse", "de-DE"), ("sich freuen", "de-DE"), ("Straße", "de-CH"),
    ("qudsxyzzynotaword", "en-US"), ("qudsxyzzynotaword", "de-DE"),
    ("banque", "fr-FR"),
)


def observed_sense(source):
    """The fields serialized by native_pack_test.dart (not extra source data)."""
    return {
        "id": source["id"], "source": source["source"],
        "pos": source.get("pos"), "gloss": source.get("gloss"),
        "labels": source.get("labels", []),
        "examples": source.get("examples", []),
        "terms": [{"id": term["id"], "text": term["text"],
                   "labels": term.get("labels", [])} for term in source["terms"]],
        "relations": source.get("relations", []),
    }


def verified_bytes(directory, name, metadata):
    logical_path = Path(name)
    require(not logical_path.is_absolute() and ".." not in logical_path.parts,
            "Unsafe pack path")
    compressed = metadata.get("compression") == "deflate-raw"
    path = directory / (name + ".deflate" if compressed else name)
    require(path.resolve().is_relative_to(directory.resolve()), "Unsafe pack link")
    value = path.read_bytes()
    if compressed:
        require(len(value) == metadata["compressedSize"] and
                digest(value) == metadata["compressedSha256"], "Compressed source mismatch")
        inflater = zlib.decompressobj(-15)
        value = inflater.decompress(value, metadata["size"] + 1)
        require(inflater.eof and not inflater.unused_data and
                not inflater.unconsumed_tail, "Invalid compressed source framing")
    require(len(value) == metadata["size"] and digest(value) == metadata["sha256"],
            "Logical source mismatch")
    return value


def make_packet(report_path: Path, packs: Path):
    report_bytes = report_path.read_bytes()
    report = json.loads(report_bytes)
    require(report.get("status") == "passed", "A successful native query report is required")
    queries = report.get("queries", [])
    require([(q["text"], q["language"]) for q in queries] == list(PANEL),
            "Expected the complete ordered 15-query native panel")
    manifests, pack_records, sources = {}, {}, {}
    for locale in ("en", "de"):
        directory = packs / locale
        manifest_bytes = (directory / "manifest.json").read_bytes()
        manifest = json.loads(manifest_bytes)
        manifests[locale] = manifest
        identity = manifest["packId"] + ":" + digest(manifest_bytes)
        notices = []
        for name in manifest["noticePaths"]:
            value = verified_bytes(directory, name, manifest["files"][name])
            notices.append({"path": name, "sha256": digest(value), "bytes": len(value)})
        pack_records[locale] = {
            "identity": identity, "source": manifest["source"],
            "source_url": manifest["sourceUrl"], "license": manifest["license"],
            "attribution": manifest["attribution"], "notices": notices,
        }
    verified_shards = {}
    for query in queries:
        locale = query["language"].split("-")[0]
        if locale not in manifests:
            require(query["status"] == "unsupportedLanguage" and query["pack"] is None
                    and not query["senses"], "Unsupported-language control changed")
            continue
        require(query["pack"] == pack_records[locale]["identity"], "Report pack identity changed")
        expected = "noEntry" if query["text"] == "qudsxyzzynotaword" else "ready"
        require(query["status"] == expected and bool(query["senses"]) == (expected == "ready"),
                "Native query outcome changed")
        seen = set()
        for observed in query["senses"]:
            sid = observed["id"]
            require(sid not in seen, "Duplicate observed sense")
            seen.add(sid)
            name = "senses/" + shard(sid) + ".json"
            key = (locale, name)
            if key not in verified_shards:
                value = verified_bytes(packs / locale, name, manifests[locale]["files"][name])
                verified_shards[key] = json.loads(value)
            source = verified_shards[key].get(sid)
            require(source is not None and observed == observed_sense(source),
                    "Observed sense differs from current source: " + sid)
            sources[sid] = source
    return {
        "schema_version": 1,
        "review_status": "not_reviewed",
        "scope": "Bounded human review packet. Export success is not human approval or a fresh provider run.",
        "report": {"sha256": digest(report_bytes),
                   "started_at_utc": report.get("started_at_utc"),
                   "finished_at_utc": report.get("finished_at_utc"),
                   "dart_version": report.get("dart_version")},
        "packs": pack_records,
        "queries": queries,
        "source_records": sources,
        "source_record_note": "Full verified source records include term notes, source IDs and term relations omitted from the native report projection.",
        "reviewer": None, "reviewed_at": None, "language_expertise": None,
        "decisions": [{"text": text, "language": language, "decision": None,
                       "sense_ids": [], "term_ids": [], "notes": None}
                      for text, language in PANEL],
        "additional_cases": [], "release_recommendation": None,
    }


def safe_text(value):
    # Source text is data, never executable HTML or Markdown directives.
    text = str(value).replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    for character in ("\\", "`", "*", "_", "[", "]", "|", "#", "+", "-", ".", "=", "!"):
        text = text.replace(character, "\\" + character)
    return text.replace("\n", " / ")


def render(packet):
    lines = [
        "# English/German thesaurus — independent linguistic review", "",
        "**Status: not reviewed. All decisions are intentionally blank.**", "",
        "This packet preserves the 15 observed queries and all returned meanings from a native",
        "report. Each displayed source record was checked against the current pack manifest",
        "and shard hashes. Exporting the packet does not execute the provider or establish",
        "browser, desktop, linguistic or whole-corpus acceptance.", "",
        "Reviewer: ______  Date: ______  Language expertise: ______", "",
        "For each case, record **accept / issue / not assessed**, cite sense and term IDs,",
        "and explain any issue. Assess meaning separation, literal spelling, part of speech,",
        "register/region labels, examples and usefulness. Try a relevant sentence before",
        "judging a replacement; automatic agreement, reinflection and contextual sense",
        "selection are outside scope. Related concepts are not selectable synonyms.", "",
        "Add regional, domain and unfamiliar-word cases of your own. This small panel cannot",
        "establish vocabulary-wide suitability. Review `Jänner`, `Oheim` and `colour` in the",
        "application to assess the separately verified regional/historical labels.", "",
        "The companion JSON retains the exact observations, full verified source records,",
        "hashes and blank decisions. Term notes below come from those source records;",
        "term relations and source IDs are retained in JSON. These extra fields were",
        "not all serialized by the observed native report.", "",
        "## Evidence binding", "",
        "Native report SHA-256: `" + packet["report"]["sha256"] + "`", "",
        "Recorded native run: " + safe_text(packet["report"]["started_at_utc"]), "",
    ]
    for locale, pack in packet["packs"].items():
        lines += ["- " + locale + ": `" + pack["identity"] + "`; " + safe_text(pack["license"])]
    lines += ["", "Original attributions and licenses remain in the bundled notices; see the",
              "`packs` object in the JSON for their exact paths and hashes.", ""]
    for number, query in enumerate(packet["queries"], 1):
        lines += [f"## {number}. {safe_text(query['text'])} ({query['language']})", "",
                  f"Observed status: **{query['status']}**. Returned meanings: {len(query['senses'])}.", "",
                  "Decision: ______  Sense/term IDs: ______  Notes: ______", ""]
        if query["matches"]:
            lines += ["Lookup matches: " + "; ".join(
                safe_text(m["text"]) + " (" + safe_text(m["reason"]) + ")"
                for m in query["matches"]), ""]
        if query["language"] == "de-CH":
            lines += ["Review focus: the shared German corpus preserves ß; no Swiss spelling conversion is promised.", ""]
        if query["text"] in {"children", "dogs", "Häusern"}:
            lines += ["Review focus: lemma lookup preserves ambiguity; replacement inserts the literal selected source term.", ""]
        for observed in query["senses"]:
            source = packet["source_records"][observed["id"]]
            lines += ["### " + observed["id"], "",
                      "Source: " + safe_text(observed["source"]) + "; POS: " + safe_text(observed["pos"] or "not supplied"), ""]
            if observed["gloss"]:
                lines += [safe_text(observed["gloss"]), ""]
            if observed["labels"]:
                lines += ["Meaning labels: " + "; ".join(map(safe_text, observed["labels"])), ""]
            for example in observed["examples"]:
                lines += ["- Source example: " + safe_text(example)]
            lines += ["", "| Literal term | Term ID | Labels / source note |", "| --- | --- | --- |"]
            for term in source["terms"]:
                annotation = "; ".join(term.get("labels", []) + ([term["note"]] if term.get("note") else []))
                lines.append("| " + " | ".join(map(safe_text, [term["text"], term["id"], annotation])) + " |")
            lines += [""]
            if observed["relations"]:
                lines += ["Related concepts: " + "; ".join(
                    safe_text(r["type"]) + " → " + safe_text(r["target"])
                    for r in observed["relations"]), ""]
    lines += ["## Reviewer additions and recommendation", "",
              "Additional query / locale / sentence / outcome / source IDs: ______", "",
              "Unresolved issues and required follow-up: ______", "",
              "Release recommendation and its bounded scope: ______", "",
              "Reviewer sign-off: ______", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--packs", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    packet = make_packet(args.report, args.packs)
    require(not args.output.exists(), "Choose a new output directory; completed review must not be overwritten")
    args.output.mkdir(parents=True)
    (args.output / "linguistic-review.json").write_text(
        json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.output / "linguistic-review.md").write_text(render(packet), encoding="utf-8")
    print(json.dumps({"review_status": packet["review_status"], "queries": len(packet["queries"]),
                      "source_records": len(packet["source_records"]),
                      "report_sha256": packet["report"]["sha256"]}, indent=2))


if __name__ == "__main__":
    main()
