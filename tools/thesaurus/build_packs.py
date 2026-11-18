#!/usr/bin/env python3
"""Compile pinned, separately licensed lexical sources into offline Quds packs.

Independent MIT implementation. It never executes SQL or fetches network data.
Source bytes, original notices and lineage live in engine/third_party/thesaurus.
Python 3.11+ standard library only. See README.md for regeneration/qualification.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import re
import tarfile
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "packages/quds_office_engine/third_party/thesaurus"
DEFAULT_OUTPUT = ROOT / "packages/quds_office_editor/assets/thesaurus"
SQL_TABLES = {
    "category", "category_link", "language", "link_type", "tag", "term_tag",
    "synset", "synset_link", "term", "term_level", "term_link", "term_link_type",
}


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def encoded(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def normalize(text: str) -> str:
    return " ".join(text.replace("\u00ad", "").split()).lower()


def shard(text: str) -> str:
    value = 0xC5
    for byte in text.encode("utf-8"):
        value = ((value ^ byte) * 0x93) & 255
    return f"{value:02x}"


def safe_term(text: str) -> bool:
    return (isinstance(text, str) and 0 < len(text) <= 2048 and text.strip() == text
            and not any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in text))


def require(condition: bool, message: str):
    if not condition:
        raise ValueError(message)


def checked_source(name: str, source_manifest: dict) -> Path:
    path = DATA / "sources" / name
    expected = source_manifest["inputs"][name]
    value = path.read_bytes()
    require(len(value) == expected["size"] and digest(value) == expected["sha256"],
            f"Input digest/size mismatch: {name}")
    return path


def read_oewn(path: Path) -> tuple[dict, dict, dict]:
    """Preserve synsets, lexical sense IDs, all typed relations and Form aliases."""
    with gzip.open(path, "rb") as stream:
        lexicon = ET.parse(stream).getroot().find("Lexicon")
    require(lexicon is not None and lexicon.get("id") == "oewn"
            and lexicon.get("version") == "2025" and lexicon.get("language") == "en",
            "Expected regular OEWN 2025 English WN-LMF")
    senses, terms_by_synset, aliases = {}, defaultdict(list), defaultdict(list)
    sense_labels = {}
    for entry in lexicon.findall("LexicalEntry"):
        lemma = entry.find("Lemma")
        require(lemma is not None, f"Missing lemma {entry.get('id')}")
        text, pos = lemma.get("writtenForm"), lemma.get("partOfSpeech")
        require(safe_term(text), f"Unsafe OEWN lemma {entry.get('id')}: {text!r}")
        for sense in entry.findall("Sense"):
            sid, synset = sense.get("id"), sense.get("synset")
            require(sid and synset and sid not in sense_labels, "Invalid/duplicate OEWN sense ID")
            sense_labels[sid] = text
            term = {"id": sid, "text": text, "sourceIds": [entry.get("id"), sid]}
            relations = [{"type": r.get("relType"), "target": r.get("target")}
                         for r in sense.findall("SenseRelation")]
            if relations:
                term["relations"] = relations
            terms_by_synset[synset].append(term)
        for form in entry.findall("Form"):
            value = form.get("writtenForm")
            require(safe_term(value), f"Unsafe OEWN form {entry.get('id')}")
            aliases[normalize(value)].append({"lemma": text, "pos": pos, "reason": "oewn-source-form"})
    for node in lexicon.findall("Synset"):
        sid = node.get("id")
        require(sid and sid not in senses, "Invalid/duplicate OEWN synset")
        terms = terms_by_synset.pop(sid, [])
        require(terms, f"OEWN synset has no terms: {sid}")
        for term in terms:
            labels = sorted({sense_labels[r["target"]] for r in term.get("relations", [])
                             if r["type"] in {"exemplifies", "domain_region", "domain_topic"}
                             and r["target"] in sense_labels})
            if labels:
                term["labels"] = labels
        definitions = ["".join(x.itertext()) for x in node.findall("Definition")]
        require(definitions, f"Missing OEWN definition {sid}")
        record = {"id": sid, "source": "oewn", "pos": node.get("partOfSpeech"),
                  "gloss": "\n".join(definitions), "terms": terms}
        examples = ["".join(x.itertext()) for x in node.findall("Example")]
        if examples:
            record["examples"] = examples
        relations = [{"type": r.get("relType"), "target": r.get("target")}
                     for r in node.findall("SynsetRelation")]
        if relations:
            record["relations"] = relations
        senses[sid] = record
    require(not terms_by_synset, "OEWN has unresolved synset memberships")
    require(len(senses) == 107519, f"Unexpected regular OEWN 2025 sense count: {len(senses)}")
    return senses, aliases, {"lexicalEntries": len(lexicon.findall("LexicalEntry")),
                            "sourceForms": len(lexicon.findall("LexicalEntry/Form"))}


def sql_values(text: str) -> list:
    """Parse a single mysqldump value tuple without executing any SQL."""
    require(text.startswith("("), "Expected SQL tuple")
    values, i = [], 1
    while True:
        while i < len(text) and text[i].isspace():
            i += 1
        require(i < len(text), "Unclosed SQL tuple")
        if text[i] == "'":
            i += 1
            chars = []
            while i < len(text):
                char = text[i]
                i += 1
                if char == "\\":
                    require(i < len(text), "Truncated SQL escape")
                    chars.append({"0": "\0", "b": "\b", "n": "\n", "r": "\r", "t": "\t", "Z": "\x1a"}.get(text[i], text[i]))
                    i += 1
                elif char == "'":
                    if i < len(text) and text[i] == "'":
                        chars.append("'")
                        i += 1
                    else:
                        break
                else:
                    chars.append(char)
            else:
                raise ValueError("Unclosed SQL string")
            value = "".join(chars)
        else:
            start = i
            while i < len(text) and text[i] not in ",)":
                i += 1
            token = text[start:i].strip()
            if token == "NULL":
                value = None
            elif re.fullmatch(r"0x[0-9A-Fa-f]+", token):
                value = int(token, 16)
            elif re.fullmatch(r"-?\d+", token):
                value = int(token)
            elif re.fullmatch(r"-?\d+\.\d+", token):
                value = float(token)
            else:
                raise ValueError(f"Unsupported SQL value: {token!r}")
        values.append(value)
        require(i < len(text), "Unclosed SQL tuple")
        if text[i] == ")":
            require(text[i + 1:].strip() in {",", ";"}, "Unexpected text after SQL tuple")
            return values
        require(text[i] == ",", "Invalid SQL delimiter")
        i += 1


def read_sql_tables(path: Path) -> tuple[dict, str]:
    with tarfile.open(path, "r:bz2") as archive:
        stream = archive.extractfile("openthesaurus_dump.sql")
        require(stream is not None, "Missing OpenThesaurus SQL dump")
        text = stream.read().decode("utf-8")
    columns = {table: re.findall(r"^  `(\w+)`", body, re.M)
               for table, body in re.findall(r"CREATE TABLE `(\w+)` \((.*?)\) ENGINE", text, re.S)}
    require(SQL_TABLES <= columns.keys(), "Missing required OpenThesaurus tables")
    tables = {name: [] for name in SQL_TABLES}
    table = None
    # SQL escapes physical LF/CR in strings; Unicode line separators remain
    # literal text and must not be mistaken for statement boundaries.
    for line in text.split("\n"):
        insert = re.fullmatch(r"INSERT INTO `(\w+)` VALUES", line)
        if insert:
            table = insert[1]
        elif line.startswith("(") and table is not None:
            if table in tables:
                values = sql_values(line)
                require(len(values) == len(columns[table]), f"Wrong column count in {table}")
                tables[table].append(dict(zip(columns[table], values)))
            if line.endswith(";"):
                table = None
    exported = re.search(r"^-- export date: (.+)$", text, re.M)
    require(exported is not None, "Missing OpenThesaurus export timestamp")
    return tables, exported[1]


def read_openthesaurus(path: Path) -> tuple[dict, dict, dict]:
    tables, exported = read_sql_tables(path)
    by_id = {name: {row["id"]: row for row in values} for name, values in tables.items()
             if values and "id" in values[0]}
    for table, values in by_id.items():
        require(len(values) == len(tables[table]), f"Duplicate IDs in {table}")
    languages = {row["id"] for row in tables["language"] if row["short_form"] == "de"}
    visible = {row["id"]: row for row in tables["synset"] if row["is_visible"] == 1}
    senses = {f"ot-{sid}": {"id": f"ot-{sid}", "source": "openthesaurus", "terms": []}
              for sid in visible}
    aliases, terms = defaultdict(list), {}
    labels = defaultdict(set)
    for row in tables["term_tag"]:
        tag = by_id["tag"].get(row["tag_id"])
        if tag and tag["is_visible"] != 0:
            labels[row["term_tags_id"]].add(tag["name"])
    for row in tables["term"]:
        if row["language_id"] not in languages or row["synset_id"] not in visible:
            continue
        text = row["word"]
        require(safe_term(text), f"Unsafe OpenThesaurus term {row['id']}: {text!r}")
        tid, sid = f"ot-term-{row['id']}", f"ot-{row['synset_id']}"
        term = {"id": tid, "text": text, "sourceIds": [tid]}
        level = by_id["term_level"].get(row["level_id"])
        if level:
            labels[row["id"]].add(level["level_name"])
        if labels[row["id"]]:
            term["labels"] = sorted(labels[row["id"]])
        if row["user_comment"]:
            term["note"] = row["user_comment"]
        terms[row["id"]] = term
        senses[sid]["terms"].append(term)
        # Source normalized_word columns fold umlauts and ß, so never use them.
        # Removing/unwrapping optional parenthetical material is lookup-only.
        if "(" in text and ")" in text:
            for alias in (re.sub(r"\([^()]*\)", " ", text), text.replace("(", "").replace(")", "")):
                if normalize(alias) and normalize(alias) != normalize(text):
                    aliases[normalize(alias)].append({"lemma": text, "reason": "openthesaurus-parenthetical"})
    empty = [sid for sid, sense in senses.items() if not sense["terms"]]
    for sid in empty:
        del senses[sid]
    for row in tables["category_link"]:
        sid = f"ot-{row['synset_id']}"
        category = by_id["category"].get(row["category_id"])
        if sid in senses and category and category["is_disabled"] != 1:
            senses[sid].setdefault("labels", []).append(category["category_name"])
    for row in tables["synset_link"]:
        sid, target = f"ot-{row['synset_id']}", f"ot-{row['target_synset_id']}"
        kind = by_id["link_type"].get(row["link_type_id"])
        if sid in senses and target in senses and kind:
            senses[sid].setdefault("relations", []).append({"type": kind["link_name"], "target": target})
            senses[target].setdefault("relations", []).append({"type": kind["other_direction_link_name"], "target": sid})
    for row in tables["term_link"]:
        source, target = terms.get(row["term_id"]), terms.get(row["target_term_id"])
        kind = by_id["term_link_type"].get(row["link_type_id"])
        if source and target and kind:
            source.setdefault("relations", []).append({"type": kind["link_name"], "target": target["id"]})
            target.setdefault("relations", []).append({"type": kind["other_direction_link_name"], "target": source["id"]})
    return senses, aliases, {"exportTimestamp": exported, "sourceSynsets": len(tables["synset"]),
                            "visibleSynsets": len(visible), "emptyVisibleSynsetsExcluded": len(empty),
                            "sourceTerms": len(tables["term"]), "tablesImported": sorted(SQL_TABLES),
                            "wordMappingImported": False, "foldedSourceAliasesImported": False}


def unique_sorted(values: list) -> list:
    return [json.loads(value) for value in sorted({json.dumps(x, ensure_ascii=False, sort_keys=True) for x in values})]


def compile_pack(locale: str, senses: dict, aliases: dict, metadata: dict,
                 source_manifest: dict, output: Path) -> dict:
    index = defaultdict(lambda: {"senseIds": [], "aliases": []})
    for sid, sense in sorted(senses.items()):
        sense["terms"].sort(key=lambda t: t["id"])
        if "labels" in sense:
            sense["labels"] = sorted(set(sense["labels"]))
        if "relations" in sense:
            sense["relations"] = unique_sorted(sense["relations"])
        for term in sense["terms"]:
            if "relations" in term:
                term["relations"] = unique_sorted(term["relations"])
            index[normalize(term["text"])]["senseIds"].append(sid)
    for key, values in aliases.items():
        index[key]["aliases"] = unique_sorted(values)
    for value in index.values():
        value["senseIds"] = sorted(set(value["senseIds"]))
    pack_dir = output / locale
    pack_dir.mkdir(parents=True, exist_ok=True)
    files = {}
    logical_total, packed_total = 0, 0

    def write_file(name: str, value: bytes, compress: bool = True):
        nonlocal logical_total, packed_total
        info = {"sha256": digest(value), "size": len(value)}
        logical_total += len(value)
        if compress:
            codec = zlib.compressobj(level=9, wbits=-15)
            packed = codec.compress(value) + codec.flush()
            info.update(compression="deflate-raw", compressedSha256=digest(packed), compressedSize=len(packed))
            target = pack_dir / (name + ".deflate")
        else:
            packed, target = value, pack_dir / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(packed)
        packed_total += len(packed)
        files[name] = info

    for name, mapping in [("index", index), ("senses", senses)]:
        shards = {f"{i:02x}": {} for i in range(256)}
        for key, value in sorted(mapping.items()):
            shards[shard(key)][key] = value
        for key, value in shards.items():
            write_file(f"{name}/{key}.json", encoded(value))
    configuration = source_manifest["packs"][locale]
    notices = configuration["notices"]
    for name in notices:
        write_file(f"notices/{name}", (DATA / "notices" / name).read_bytes(), compress=False)
    if locale == "en":
        # Independent transcription of the documented Princeton WordNet morphy
        # suffix table. Every resulting lemma must occur with compatible POS.
        rules = {"n": [("s", ""), ("ses", "s"), ("xes", "x"), ("zes", "z"),
                       ("ches", "ch"), ("shes", "sh"), ("men", "man"), ("ies", "y")],
                 "v": [("s", ""), ("ies", "y"), ("es", "e"), ("es", ""),
                       ("ed", "e"), ("ed", ""), ("ing", "e"), ("ing", "")],
                 "a": [("er", ""), ("est", ""), ("er", "e"), ("est", "e")]}
        write_file("morphology.json", encoded({"source": "princeton-wordnet", "version": "3.0",
                   "rules": [{"pos": pos, "suffix": suffix, "ending": ending}
                             for pos, values in rules.items() for suffix, ending in values]}))
    counts = {"meaningGroups": len(senses), "terms": sum(len(s["terms"]) for s in senses.values()),
              "indexKeys": len(index), "aliasKeys": len(aliases), "logicalBytes": logical_total,
              "packedBytesExcludingManifest": packed_total,
              "maxLogicalFileBytes": max(f["size"] for f in files.values()),
              "labels": sum(len(t.get("labels", [])) for s in senses.values() for t in s["terms"]),
              "relations": sum(len(s.get("relations", [])) + sum(len(t.get("relations", []))
                              for t in s["terms"]) for s in senses.values())}
    manifest = {"schemaVersion": 1, "locale": locale, "normalization": "lower-whitespace-v1",
                "shardAlgorithm": "fnv1a32-utf8-low8", **{k: configuration[k] for k in
                ["packId", "version", "source", "name", "license", "sourceUrl", "attribution"]},
                "noticePaths": [f"notices/{name}" for name in notices], "files": files,
                "counts": counts, "sourceMetadata": metadata,
                "sourceManifestSha256": digest((DATA / "sources.json").read_bytes()),
                "compilerSha256": digest(Path(__file__).read_bytes()), "zlibVersion": zlib.ZLIB_VERSION}
    manifest_bytes = encoded(manifest)
    (pack_dir / "manifest.json").write_bytes(manifest_bytes)
    return {"manifestSha256": digest(manifest_bytes), **counts,
            "packBytes": packed_total + len(manifest_bytes)}


def build(output: Path, constants: Path | None = None) -> dict:
    source_manifest = json.loads((DATA / "sources.json").read_text())
    for name, pin in source_manifest["noticeFiles"].items():
        value = (DATA / "notices" / name).read_bytes()
        require(digest(value) == pin["sha256"] and len(value) == pin["size"], f"Notice changed: {name}")
    reports = {}
    for locale, reader, name in [("en", read_oewn, "english-wordnet-2025.xml.gz"),
                                 ("de", read_openthesaurus, "openthesaurus_dump.tar.bz2")]:
        senses, aliases, metadata = reader(checked_source(name, source_manifest))
        reports[locale] = compile_pack(locale, senses, aliases, metadata, source_manifest, output)
        print(locale, json.dumps(reports[locale], sort_keys=True), flush=True)
    if constants:
        constants.parent.mkdir(parents=True, exist_ok=True)
        constants.write_text("// Generated by tools/thesaurus/build_packs.py; do not edit.\n"
                             "const Map<String, String> bundledThesaurusManifestSha256 = {\n"
                             + "".join(f"  '{locale}': '{report['manifestSha256']}',\n" for locale, report in reports.items())
                             + "};\n")
    return reports


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--constants", type=Path, default=ROOT / "packages/quds_office_editor/lib/src/thesaurus/bundled_thesaurus_manifest.dart")
    args = parser.parse_args()
    build(args.output, args.constants)
