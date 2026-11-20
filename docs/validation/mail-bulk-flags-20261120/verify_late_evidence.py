#!/usr/bin/env python3
"""Read-only verification of the separately qualified late-main evidence.

The original bulk-mail archive is an immutable dependency.  The original late
cohorts qualify 00d44; peer-main cohorts qualify their separately recorded Git
checkpoint.  Neither a later checkout nor a documentation commit changes those
bindings.  --archive-only verifies bytes and receipt consistency without Git;
it deliberately does not establish source qualification.  No archive is ever
extracted, no subprocess from an archive is executed, and Git cannot lazy-fetch.
"""
from __future__ import annotations

import argparse
from collections import Counter
import difflib
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile

BASE = "3645e8a4db535fc0ab5ab0923ee7385e5c4e5195"
BASE_TREE = "0df4f1db0f920cf3adf3c5abcf8e22abdd8ee007"
LATE = "00d44a69d19de20cdb7754b754c4d32d86d078cc"
LATE_TREE = "83a5034ac7020c1cd7a2d1143144357fc26bf80c"
INCOMING = "698209aaa6e7f1350b6541df5eb192b7b233443d"
RUNTIME_CONFIG = ".dart_tool/package_config.json"
BASE_FILES = {
    "evidence.tar.gz": "63e9efefcf3eb36ef3ae06483cd1d8da622560265494a3c8de9e0f8713d65074",
    "evidence-members.json": "0e9e772f9ea3e7e7f2a9b76e8b92eb0f59c9310cfcee549aedcc14348d0750fd",
    "source-applicability.json": "6b1eac482c8bfb926de8e977cb019d3b35da1dfa7b2619127489ea94ada3f352",
    "verify_evidence.py": "af77727b7baec97e049dd0c55413823afdd0a7eb1e62e0348ea8a70420e17d18",
}
ACCEPTED_PREFIXES = ("final-mail/", "final-word/", "zotero/", "layout/continuous-final/", "final-checks/", "peer-main/")
REQUIRED = {
    **{f"final-mail/receipt.json#{n}": p for n, p in [
        ("hosts", 374), ("ui", 161), ("ui-visual", 5), ("studio-visual", 5),
        ("analysis", None), ("zotero-editor", 362), ("zotero-studio", 16),
        ("zotero-editor-analysis", None)]},
    **{f"final-word/{n}.json#{n}": p for n, p in [
        ("word-vm", 893), ("word-node", 751), ("word-analyze", None),
        ("word-format-check", None), ("measurements-driver-vm", None),
        ("measurements-driver-js-compile", None), ("measurements-driver-js-run", None),
        ("named_measurements-driver-vm", None), ("named_measurements-driver-js-compile", None),
        ("named_measurements-driver-js-run", None)]},
    **{f"layout/continuous-final/receipt.json#{n}": (148 if n == "tests" else None) for n in ["tests", "probe", "analysis", "format", "whitespace"]},
    **{f"zotero/{n}.json#{n}": p for n, p in [
        ("zotero-vm", 282), ("zotero-node", 175), ("zotero-analyze", None), ("zotero-format-check", None)]},
    **{f"final-checks/receipt.json#{n}": None for n in ["format", "whitespace"]},
}
REQUIRED_PEER = {
    **{f"peer-main/core/receipt.json#{n}": p for n, p in [
        ("core-vm", 214), ("transport-boundaries", 195), ("bulk-node", 120),
        ("unsupported-node", 6), ("core-analyze", None), ("transport-analyze", None),
        ("format", None), ("whitespace", None)]},
    **{f"peer-main/hosts/receipt.json#{n}": p for n, p in [
        ("hosts", 378), ("ui", 161), ("ui-visual", 5), ("studio-visual", 8),
        ("analysis", None), ("zotero-editor", 362), ("zotero-studio", 16),
        ("zotero-editor-analysis", None), ("font-tests", None), ("font-analysis", None)]},
    **{f"peer-main/word/{n}.json#{n}": p for n, p in [
        ("word-vm", 929), ("word-node", 787), ("word-analyze", None),
        ("word-format-check", None), ("focused-vm", 244), ("focused-analyze", None),
        ("focused-format-check", None), ("measurements-driver-vm", None),
        ("measurements-driver-js-compile", None), ("measurements-driver-js-run", None),
        ("named_measurements-driver-vm", None), ("named_measurements-driver-js-compile", None),
        ("named_measurements-driver-js-run", None)]},
    **{f"peer-main/zotero/{n}.json#{n}": p for n, p in [
        ("zotero-vm", 165), ("zotero-node", 117), ("zotero-analyze", None), ("zotero-format-check", None)]},
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe_name(name):
    p = PurePosixPath(name)
    require(isinstance(name, str) and name and not p.is_absolute() and ".." not in p.parts and str(p) == name and "\\" not in name, f"Unsafe path: {name!r}")
    return name


class Git:
    def __init__(self, repo):
        self.repo = Path(repo)
        self.env = os.environ | {"GIT_NO_LAZY_FETCH": "1", "GIT_TERMINAL_PROMPT": "0"}
        self.trees = {}
        self.blobs = {}

    def run(self, *args, check=True):
        p = subprocess.run(["git", "-C", str(self.repo), *args], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if check:
            require(p.returncode == 0, f"Git {' '.join(args)} failed: {p.stderr.decode(errors='replace').strip()}")
        return p

    def commit(self, revision):
        lines = self.run("show", "-s", "--format=%H%n%T%n%P", revision).stdout.decode().splitlines()
        return {"commit": lines[0], "tree": lines[1], "parents": lines[2].split() if len(lines) > 2 else []}

    def tree(self, revision):
        if revision not in self.trees:
            items = {}
            for raw in self.run("ls-tree", "-rz", revision).stdout.split(b"\0"):
                if not raw:
                    continue
                header, path = raw.split(b"\t", 1)
                mode, kind, blob = header.decode().split()
                items[path.decode()] = {"mode": mode, "type": kind, "blob": blob}
            self.trees[revision] = items
        return self.trees[revision]

    def preload(self, revision, paths):
        tree = self.tree(revision)
        ids = sorted({tree[p]["blob"] for p in paths if p in tree and tree[p]["type"] == "blob"} - self.blobs.keys())
        if not ids:
            return
        p = subprocess.run(["git", "-C", str(self.repo), "cat-file", "--batch"], input=("\n".join(ids) + "\n").encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env)
        require(p.returncode == 0, "Git batch read failed")
        stream = io.BytesIO(p.stdout)
        for oid in ids:
            header = stream.readline().decode().split()
            require(len(header) == 3 and header[0] == oid and header[1] == "blob", f"Missing blob {oid}")
            body = stream.read(int(header[2]))
            require(stream.read(1) == b"\n", "Malformed Git batch output")
            self.blobs[oid] = body

    def read(self, revision, path):
        self.preload(revision, [path])
        obj = self.tree(revision).get(path)
        require(obj is not None and obj["type"] == "blob", f"Missing source {revision}:{path}")
        return self.blobs[obj["blob"]]


def read_archive(data, manifest):
    require(len(data) == manifest["archive"]["bytes"] and sha(data) == manifest["archive"]["sha256"], "Archive byte length or SHA-256 mismatch")
    expected = {safe_name(x["path"]): x for x in manifest["members"]}
    require(len(expected) == len(manifest["members"]) == manifest["member_count"], "Duplicate or incorrect manifest member count")
    payloads = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            name = safe_name(member.name)
            require(member.isfile() and name not in payloads and name in expected, f"Unexpected/nonregular/duplicate archive member {name}")
            content = archive.extractfile(member).read()
            row = expected[name]
            require(member.size == len(content) == row["bytes"] and sha(content) == row["sha256"], f"Member content mismatch: {name}")
            require(f"{member.mode:04o}" == row["mode"], f"Member mode mismatch: {name}")
            payloads[name] = content
    require(set(payloads) == set(expected), "Archive member inventory differs from manifest")
    require(sum(map(len, payloads.values())) == manifest["uncompressed_member_bytes"], "Uncompressed byte count mismatch")
    return payloads


def related(payloads, owner, reference):
    require(isinstance(reference, str), f"Invalid reference in {owner}")
    if "/late-main-validation/" in reference:
        name = reference.split("/late-main-validation/", 1)[1]
    elif reference in payloads:
        name = reference
    else:
        name = str(PurePosixPath(owner).parent / reference)
    safe_name(name)
    require(name in payloads, f"Missing receipt dependency {owner} -> {name}")
    return name


def source_map(payloads, owner, raw, expected_hash=None):
    if isinstance(raw, str):
        member = related(payloads, owner, raw)
        require(expected_hash and sha(payloads[member]) == expected_hash, f"Source manifest hash mismatch: {member}")
        raw = json.loads(payloads[member])
    require(isinstance(raw, dict) and raw, f"Missing source hash map in {owner}")
    for path, digest in raw.items():
        safe_name(path)
        require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest), f"Invalid source hash {owner}:{path}")
    return raw


def parse_receipts(payloads):
    result = []
    for member, data in sorted(payloads.items()):
        if not member.endswith(".json"):
            continue
        document = json.loads(data)
        nested = next((key for key in ("runs", "checks") if isinstance(document, dict) and isinstance(document.get(key), list)), None)
        if nested:
            rows = [dict({k: v for k, v in document.items() if k != nested}, **row) for row in document[nested]]
            if nested == "checks":
                duplicate = str(PurePosixPath(member).parent / "checks.json")
                if duplicate in payloads:
                    require(json.loads(payloads[duplicate]) == document[nested], f"Checks receipt copies disagree: {member}")
        else:
            rows = document if isinstance(document, list) else [document]
        for index, row in enumerate(rows):
            if not isinstance(row, dict) or "exit_code" not in row or not ("command" in row or "argv" in row):
                continue
            keys = [k for k in ("source_hashes_before", "source_before", "source_hashes", "source_hashes_file") if k in row]
            if not keys:
                continue  # Source-free audit metadata is preserved, never a qualified cohort.
            before_key = keys[0]
            before = source_map(payloads, member, row[before_key], row.get(before_key + "_sha256"))
            after_key = "source_hashes_after" if "source_hashes_after" in row else "source_after" if "source_after" in row else None
            after = source_map(payloads, member, row[after_key], row.get(after_key + "_sha256")) if after_key else before
            declarations = {k: row[k] for k in ("source_unchanged", "sources_unchanged", "source_hashes_unchanged") if k in row}
            require(declarations and all(isinstance(v, bool) for v in declarations.values()), f"Missing/invalid stability declaration: {member}")
            stable = all(declarations.values()) and before == after and not row.get("changed_paths", [])
            require(not all(declarations.values()) or before == after, f"Receipt falsely declares paired manifests stable: {member}")
            digest = row.get("log_sha256")
            require(digest, f"Missing log digest: {member}")
            if row.get("log"):
                log = related(payloads, member, row["log"])
            else:
                candidates = [p for p, body in payloads.items() if p.endswith(".log") and PurePosixPath(p).parent == PurePosixPath(member).parent and sha(body) == digest]
                preferred = str(PurePosixPath(member).parent / (row.get("name", "") + ".log"))
                log = preferred if preferred in candidates else (sorted(candidates)[0] if candidates else "")
            require(log in payloads and sha(payloads[log]) == digest, f"Missing/mismatched log: {member}")
            name = row.get("name", PurePosixPath(member).stem)
            command = row.get("command", row.get("argv"))
            require(isinstance(command, list) and all(isinstance(x, str) for x in command), f"Invalid recorded command: {member}")
            log_text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", payloads[log].decode(errors="replace")).rstrip()
            parsed = re.findall(r"\+(\d+)(?: ~(\d+))?: All tests passed!", log_text)
            passed = int(parsed[-1][0]) if parsed else None
            skipped = int(parsed[-1][1] or 0) if parsed else None
            test_command = "test" in command or any(arg.endswith("/test.dart") for arg in command)
            terminal_success = bool(re.search(r"\+\d+(?: ~\d+)?: All tests passed!$", log_text)) if test_command else None
            if row.get("passed") is not None:
                require(row["passed"] == passed, f"Passed-count disagreement with log: {member}")
            if row.get("skipped") is not None:
                require(row["skipped"] == skipped, f"Skipped-count disagreement with log: {member}")
            metadata = {
                "id": f"{member}#{name}", "receipt": member, "receipt_sha256": sha(data),
                "row_index": index, "name": name, "command": command, "exit_code": row["exit_code"],
                "log": log, "log_sha256": digest, "source_count": len(before),
                "source_before_sha256": sha(json_bytes(before)), "source_after_sha256": sha(json_bytes(after)),
                "source_stability": "paired_manifests" if after_key else "recorded_single_manifest",
                "source_stable": stable, "recorded_changed_paths": row.get("changed_paths", []),
                "stability_declarations": declarations, "test_command": test_command,
                "terminal_test_success": terminal_success, "passed": passed, "skipped": skipped,
            }
            result.append((metadata, before))
    require(len({m["id"] for m, _ in result}) == len(result), "Duplicate cohort IDs")
    return result


def source_binding(git, commit, hashes):
    tree = git.tree(commit)
    git.preload(commit, hashes)
    differences = []
    runtime = {}
    tracked = 0
    for path, digest in sorted(hashes.items()):
        if path == RUNTIME_CONFIG:
            require(path not in tree, "Runtime package config unexpectedly tracked")
            runtime[path] = digest
            continue
        tracked += 1
        actual = sha(git.read(commit, path)) if path in tree else None
        if actual != digest:
            differences.append({"path": path, "recorded_sha256": digest, "qualified_sha256": actual})
    return {"qualified_commit": commit, "tracked_source_count": tracked, "runtime_untracked_hashes": runtime, "source_exact": not differences, "differences": differences}


def disposition(row):
    return (
        "diagnostic_failure" if row["exit_code"] != 0 else
        "diagnostic_source_transition" if not row["source_stable"] else
        "diagnostic_unbound_source" if row["tracked_source_count"] == 0 else
        "diagnostic_incomplete_test_log" if row["test_command"] and not row["terminal_test_success"] else
        "accepted" if row["receipt"].startswith(ACCEPTED_PREFIXES) and row["source_exact"] else
        "historical_source_difference" if not row["source_exact"] else "historical_exact_source")


def compile_cohorts(payloads, git, peer_source=None):
    cohorts = []
    for meta, hashes in parse_receipts(payloads):
        commit = peer_source if meta["receipt"].startswith("peer-main/") else LATE
        require(commit, f"--peer-source required for {meta['receipt']}")
        row = meta | source_binding(git, commit, hashes)
        row["disposition"] = disposition(row)
        cohorts.append(row)
    return cohorts


def baseline_payloads(folder):
    files = {}
    for name, digest in BASE_FILES.items():
        data = (folder / name).read_bytes()
        require(sha(data) == digest, f"Immutable baseline changed: {name}")
        files[name] = data
    manifest = json.loads(files["evidence-members.json"])
    archive = manifest["archive"]
    # The baseline manifest uses the same member schema, but its archive record
    # may be only a name; the independently pinned byte metadata is authoritative.
    if not isinstance(archive, dict):
        manifest = dict(manifest, archive={"name": "evidence.tar.gz", "bytes": 2472242, "sha256": BASE_FILES["evidence.tar.gz"]})
    return files, manifest, read_archive(files["evidence.tar.gz"], manifest)


def verify_inheritance(payloads, git):
    proof = json.loads(payloads["source-inheritance.json"])
    require(sha(payloads["source-inheritance.json"]) == "05701f5dd36fd0e8bac9d4568c85af807afa870e841775367ba4bdcdd062c63d", "Original 00d44 inheritance proof changed")
    commits = proof["commits"]
    for row in commits.values():
        require(git.commit(row["commit"]) == row, f"Commit/tree/parents mismatch: {row['commit']}")
    require(commits["qualified_baseline"]["commit"] == BASE and commits["incoming_main"]["commit"] == INCOMING and commits["final"]["commit"] == LATE, "Unexpected inheritance checkpoints")
    trees = {name: git.tree(row["commit"]) for name, row in commits.items()}
    before, incoming, final = trees["qualified_baseline"], trees["incoming_main"], trees["final"]
    for row in proof["ancestry"]:
        require(row["is_ancestor"] and row["exit_code"] == 0 and git.run("merge-base", "--is-ancestor", row["ancestor"], row["descendant"], check=False).returncode == 0, "Ancestry proof failed")
    def mail(path):
        return path.endswith(".dart") and (re.match(r"^packages/quds_mail[^/]*/", path) or (path.startswith("packages/quds_office_editor/example/") and PurePosixPath(path).name.startswith("studio_mail")))
    mail_before = {p: x for p, x in before.items() if mail(p)}
    mail_final = {p: x for p, x in final.items() if mail(p)}
    recorded = proof["mail_inheritance"]
    require(mail_before == mail_final and len(mail_before) == recorded["baseline_count"] == recorded["final_count"] == 298, "Mail source inheritance failed")
    require({r["path"] for r in recorded["files"]} == set(mail_before), "Mail path-set proof incomplete")
    for row in recorded["files"]:
        require(row["baseline"] == mail_before[row["path"]] == row["final"] and row["identical"], "Mail object proof mismatch")
    changes = {p for p in set(before) | set(final) if p.endswith(".dart") and before.get(p) != final.get(p)}
    delta = proof["dart_changes"]
    require(changes == {r["path"] for r in delta["files"]} and len(changes) == delta["changed_count"] == 20, "Dart delta inventory mismatch")
    for row in delta["files"]:
        path = row["path"]
        require(row["baseline"] == before.get(path) and row["incoming_main"] == incoming.get(path) and row["final"] == final.get(path), f"Dart object mismatch {path}")
        require(row["identical_to_incoming_main"] == (final.get(path) == incoming.get(path)), f"Incoming equality mismatch {path}")
        require(row["final_sha256"] == sha(git.read(LATE, path)), f"Dart SHA mismatch {path}")
    compiler = proof["compiler_inheritance"]
    paths = {p for p in final if p.startswith("packages/quds_office_engine/lib/src/automation/")}
    require(paths == {r["path"] for r in compiler["files"]} and len(paths) == 15, "Compiler inheritance inventory mismatch")
    for row in compiler["files"] + proof["lock_inheritance"]["files"]:
        path = row["path"]
        require(row["baseline"] == before.get(path) == row["final"] == final.get(path) and row["incoming_main"] == incoming.get(path), f"Compiler/lock object mismatch {path}")
    repairs = proof["final_repair_bindings"]
    for key in ("accepted_layout_receipt", "deserializer_qualification"):
        require(sha(payloads[repairs[key]]) == repairs[key + "_sha256"], f"Repair receipt changed: {key}")
    for row in repairs["files"]:
        require(row["final_blob"] == final[row["path"]]["blob"] and row["final_sha256"] == row["accepted_sha256"] == sha(git.read(LATE, row["path"])), "Repair source binding mismatch")
        member, sep, field = row["accepted_source_record"].partition(":")
        source = json.loads(payloads[member])
        source = source[field] if sep else source
        require(source[row["path"]] == row["accepted_sha256"], f"Repair receipt does not bind {row['path']}")
    return {"mail_files_unchanged": 298, "classified_dart_changes": 20, "compiler_files_unchanged": 15, "repair_bindings": len(repairs["files"])}


def verify_aliases(git):
    prefix = "packages/quds_office_engine/"
    pairs = [
        ("example/macros/word_measurements_positional.bas", "example/macros/word_measurements.bas"),
        ("test/office_vba_word_measurements_positional_test.dart", "test/office_vba_word_measurements_test.dart"),
        ("test/office_vba_word_measurements_positional_integration_test.dart", "test/office_vba_word_measurements_integration_test.dart"),
        ("tool/macros/web_vba_word_measurements_positional_smoke.dart", "tool/macros/web_vba_word_measurements_smoke.dart"),
    ]
    for source, target in pairs:
        content = git.read(INCOMING, prefix + source)
        if source.endswith("_integration_test.dart"):
            content = content.replace(b"web_vba_word_measurements_positional_smoke.dart", b"web_vba_word_measurements_smoke.dart").replace(b"word_measurements_positional.bas", b"word_measurements.bas").replace(b"import '../tool/macros/web_vba_word_measurements_smoke.dart'\n    as portable;", b"import '../tool/macros/web_vba_word_measurements_smoke.dart' as portable;")
        require(content == git.read(LATE, prefix + target) == git.read(BASE, prefix + target), f"Historical alias equivalence failed: {source}")
        require(prefix + source not in git.tree(LATE), f"Duplicate alias unexpectedly restored: {source}")
    additions = {}
    for suffix, expected in [("test", 43), ("integration_test", 105)]:
        path = prefix + f"test/office_vba_word_named_measurements_{suffix}.dart"
        old = git.read(INCOMING, path).splitlines(keepends=True)
        new = git.read(LATE, path).splitlines(keepends=True)
        ops = difflib.SequenceMatcher(a=old, b=new, autojunk=False).get_opcodes()
        require(all(op in ("equal", "insert") for op, *_ in ops), f"Historical named fixture is not an additive superset: {path}")
        added = sum(j2 - j1 for op, i1, i2, j1, j2 in ops if op == "insert")
        require(added == expected and git.read(BASE, path) == git.read(LATE, path), f"Historical addition count mismatch: {path}")
        additions[path] = added
    return {"consolidated_aliases": 4, "retained_named_fixture_additions": additions}


def canonical_sha(value):
    return sha(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def verify_peer_inheritance(payloads, git, peer):
    proof = json.loads(payloads["final-peer-delta.json"])
    require(sha(payloads["final-peer-delta.json"]) == "f5be1d8f6ef5d99843df8853391487f8e875f6848596e3b844ada19e3abcff95", "Immutable 64da peer-delta proof changed")
    commits = proof["commits"]
    for row in commits.values():
        require(git.commit(row["commit"]) == row, "Peer-delta commit/tree/parents mismatch")
    first_peer = commits["final"]["commit"]
    require(commits["baseline"]["commit"] == LATE and first_peer == "64da231816b1b3ddab35e0e12d50d885bf24f75f" and commits["incoming_main"]["commit"] == "0a2afc41bae4e719b77657a7e2d8d3e7ec02849b", "Unexpected peer-delta source checkpoints")
    for row in proof["ancestry"]:
        require(row["is_ancestor"] and row["exit_code"] == 0 and git.run("merge-base", "--is-ancestor", row["ancestor"], row["descendant"], check=False).returncode == 0, "Peer-delta ancestry mismatch")
    require(sha(payloads[proof["prior_proof"]["path"]]) == proof["prior_proof"]["sha256"], "Prior inheritance proof binding mismatch")
    before, final, incoming = git.tree(LATE), git.tree(first_peer), git.tree(commits["incoming_main"]["commit"])
    paths = {p for p in set(before) | set(final) if p.endswith(".dart") and before.get(p) != final.get(p)}
    delta = proof["dart_changes"]
    require(paths == {r["path"] for r in delta["files"]} and len(paths) == delta["changed_count"] == 19, "Peer Dart-delta inventory mismatch")
    require(dict(Counter(r["classification"] for r in delta["files"])) == delta["classification_counts"] and not delta["unclassified_paths"], "Peer delta classifications incomplete")
    for row in delta["files"]:
        path = row["path"]
        require(row["baseline"] == before.get(path) and row["final"] == final.get(path) and row["incoming_main"] == incoming.get(path), f"Peer Dart object mismatch: {path}")
        require(sha(git.read(first_peer, path)) == row["final_sha256"] and row["identical_to_incoming_main"] == (final.get(path) == incoming.get(path)), f"Peer source digest/equality mismatch: {path}")
    def mail(path):
        return path.endswith(".dart") and (re.match(r"^packages/quds_mail[^/]*/", path) or (path.startswith("packages/quds_office_editor/example/") and PurePosixPath(path).name.startswith("studio_mail")))
    mail_before, mail_after = {p for p in before if mail(p)}, {p for p in final if mail(p)}
    mail_delta = proof["mail_delta"]
    require(mail_before == mail_after and len(mail_before) == mail_delta["baseline_count"] == mail_delta["final_count"] == 298, "Peer mail path set changed")
    require(sorted(p for p in mail_before if before[p] != final[p]) == mail_delta["changed_paths"] and mail_delta["changed_count"] == 12, "Peer mail delta incomplete")
    ui = {p for p in final if p.startswith("packages/quds_mail_ui/") and p.endswith(".dart")}
    require(ui == {r["path"] for r in mail_delta["shared_ui_files"]}, "Shared UI inheritance inventory incomplete")
    rows = mail_delta["shared_ui_files"] + proof["retained_contract_and_dispatch_files"] + proof["compiler_inheritance"]["files"] + proof["lock_inheritance"]["files"]
    for row in rows:
        require(row["baseline"] == before[row["path"]] == row["final"] == final[row["path"]] and row["identical"], f"Retained peer object changed: {row['path']}")
    compiler = {p for p in final if p.startswith("packages/quds_office_engine/lib/src/automation/")}
    require(compiler == {r["path"] for r in proof["compiler_inheritance"]["files"]}, "Peer compiler path-set proof incomplete")
    binding_ref = proof["core_qualification_binding"]
    require(sha(payloads[binding_ref["path"]]) == binding_ref["sha256"] and sha(payloads[binding_ref["receipt"]]) == binding_ref["receipt_sha256"], "Core qualification binding changed")
    binding = json.loads(payloads[binding_ref["path"]])
    require(binding["commit"] == first_peer and binding["tree"] == commits["final"]["tree"], "Core publication binding checkpoint mismatch")
    manifest_name = related(payloads, binding_ref["path"], binding["source_manifest"])
    require(sha(payloads[manifest_name]) == binding["source_manifest_sha256"], "Core source manifest binding changed")
    core_hashes = json.loads(payloads[manifest_name])
    require({r["path"] for r in binding["tracked_files"]} == set(core_hashes) - {RUNTIME_CONFIG}, "Core publication source-set incomplete")
    for row in binding["tracked_files"]:
        require(row["published"] == final[row["path"]] and row["receipt_sha256"] == row["published_sha256"] == core_hashes[row["path"]] == sha(git.read(first_peer, row["path"])), "Core publication object/hash mismatch")
    if peer["commit"] == first_peer:
        return {"source_delta": 19, "mail_delta": 12, "shared_ui_unchanged": len(ui), "core_bound_inputs": len(binding["tracked_files"])}
    follow = json.loads(payloads["fixture-applicability.json"])
    require(sha(payloads["fixture-applicability.json"]) == "3f7e2ccc28ed95ebce13b95192b21015f5c3d0b4c1fac5fcda83ee2f17fc3f87", "Immutable fixture applicability proof changed")
    require(follow["commits"]["baseline"] == commits["final"] and follow["commits"]["final"] == peer == git.commit(peer["commit"]), "Fixture applicability checkpoints mismatch")
    after = git.tree(peer["commit"])
    changed = sorted(p for p in set(final) | set(after) if final.get(p) != after.get(p))
    summary = follow["change_summary"]
    require(changed == summary["exact_changed_paths"] == ["packages/quds_office_editor/example/test/studio_mail_workspace_test.dart"] and set(final) == set(after), "Fixture checkpoint changes more than the one declared test")
    fix = summary["changed_file"]
    old_body, new_body = git.read(first_peer, fix["path"]), git.read(peer["commit"], fix["path"])
    require(fix["baseline"] == final[fix["path"]] and fix["final"] == after[fix["path"]] and fix["baseline_sha256"] == sha(old_body) and fix["final_sha256"] == sha(new_body), "Fixture source byte binding mismatch")
    title = b"'certified native quota stops the tail and keeps retry guidance without refresh'"
    a, b = old_body.index(title), new_body.index(title)
    old_start, new_start = old_body.index(b"      final browser = _BulkBrowser()", a), new_body.index(b"      final browser = _BulkBrowser()", b)
    old_end, new_end = old_body.index(b"      await _show(tester, browser);", a), new_body.index(b"      await _show(tester, browser);", b)
    require(old_body[:old_start] == new_body[:new_start] and old_body[old_end:] == new_body[new_end:] and sha(new_body[new_end:]) == fix["unchanged_assertion_suffix_sha256"], "Fixture repair changed test actions/assertions")
    for row in follow["ancestry"]:
        require(git.run("merge-base", "--is-ancestor", row["ancestor"], row["descendant"], check=False).returncode == 0 and row["is_ancestor"] and row["exit_code"] == 0, "Fixture ancestry mismatch")
    libraries = {p for p in final if p.startswith("packages/") and "/lib/" in p}
    inventory = [{"path": p, **final[p]} for p in sorted(libraries)]
    library_proof = follow["production_libraries"]
    require(libraries == {p for p in after if p.startswith("packages/") and "/lib/" in p} and all(final[p] == after[p] for p in libraries) and len(libraries) == library_proof["file_count"] == 816, "Fixture checkpoint changed production libraries")
    require(canonical_sha(inventory) == library_proof["baseline_inventory_sha256"] == library_proof["final_inventory_sha256"], "Library inventory digest mismatch")
    for item in follow["prior_proofs_preserved"]:
        require(item["unchanged"] and sha(payloads[item["path"]]) == item["sha256"], "Prior proof was rewritten")
    core_follow = follow["core_receipt_applicability"]
    for key in ("receipt", "source_manifest", "original_publication_binding"):
        require(sha(payloads[core_follow[key]]) == core_follow[key + "_sha256"], "Core follow-up metadata changed")
    require(source_binding(git, peer["commit"], core_hashes)["source_exact"], "Core input inheritance failed at fixture checkpoint")
    word_follow = follow["word_receipt_applicability"]
    require(sha(payloads[word_follow["qualification"]]) == word_follow["qualification_sha256"], "Word qualification binding changed")
    require(len(word_follow["receipts"]) == word_follow["accepted_receipt_count"] == 13, "Word applicability receipt inventory mismatch")
    for item in word_follow["receipts"]:
        require(sha(payloads[item["receipt"]]) == item["receipt_sha256"], "Word applicability receipt changed")
        receipt = json.loads(payloads[item["receipt"]])
        hashes = receipt["source_before"]
        require(receipt["exit_code"] == item["recorded_exit_code"] == 0 and canonical_sha(hashes) == item["source_manifest_sha256"], "Word applicability manifest mismatch")
        for commit in (first_peer, peer["commit"]):
            checked = source_binding(git, commit, hashes)
            require(checked["source_exact"] and checked["tracked_source_count"] == item["tracked_inputs"], "Word inputs changed across fixture-only repair")
    return {"source_delta_at_64da": 19, "mail_delta_at_64da": 12, "shared_ui_unchanged": len(ui), "fixture_only_paths_at_final": len(changed), "production_files_unchanged_by_fixture_fix": 816, "core_bound_inputs": len(binding["tracked_files"]), "word_receipts_inherited_across_fixture_fix": 13}


def verify_driver_comparisons(payloads, manifest):
    exclusions = {row["path"]: row for row in manifest["exclusions"]}
    verified = []
    for prefix in ("final-word/", "peer-main/word/"):
        for driver in ("measurements", "named_measurements"):
            member = prefix + driver + "-vm-js-comparison.json"
            if member not in payloads:
                require(not prefix.startswith("final-") and not any(path.startswith(prefix) for path in payloads), f"Missing driver comparison: {member}")
                continue
            record = json.loads(payloads[member])
            vm = json.loads(payloads[prefix + driver + "-driver-vm.log"])
            js = json.loads(payloads[prefix + driver + "-driver-js-run.log"])
            require(vm == js == record["vm_json"] == record["js_json"] and record["json_equal"] and record["vm_exit_code"] == record["js_exit_code"] == 0, f"VM/JavaScript driver outputs differ: {member}")
            for suffix in ("vm", "js-compile", "js-run"):
                receipt = json.loads(payloads[prefix + driver + "-driver-" + suffix + ".json"])
                require(receipt["exit_code"] == 0, f"Driver command failed: {member}:{suffix}")
                for field in ("driver", "bas"):
                    path = record[field].split("/quds_office_suite/", 1)[-1]
                    require(receipt["source_before"][path] == receipt["source_after"][path] == record[field + "_sha256"], f"Driver source comparison binding mismatch: {member}:{field}")
            generated = prefix + driver + ".js"
            require(generated in exclusions and exclusions[generated]["sha256"] == record["compiled_js_sha256"], f"Excluded compiled output digest mismatch: {member}")
            verified.append(member)
    return verified


def verify_bundle(folder, repo=None, archive_only=False, baseline_folder=None):
    folder = Path(folder)
    application_bytes = (folder / "late-source-applicability.json").read_bytes()
    application = json.loads(application_bytes)
    manifest_bytes = (folder / "late-evidence-members.json").read_bytes()
    require(sha(manifest_bytes) == application["manifest"]["sha256"] and len(manifest_bytes) == application["manifest"]["bytes"], "Late manifest binding mismatch")
    manifest = json.loads(manifest_bytes)
    require(manifest["archive"] == application["archive"], "Archive records disagree")
    payloads = read_archive((folder / "late-evidence.tar.gz").read_bytes(), manifest)
    require(sha(Path(__file__).read_bytes()) == application["verifier_sha256"], "Verifier byte binding mismatch")
    base_files, base_manifest, base_payloads = baseline_payloads(Path(baseline_folder) if baseline_folder else folder)
    require(application["baseline_files"] == {k: {"bytes": len(v), "sha256": sha(v)} for k, v in base_files.items()}, "Baseline artifact binding mismatch")
    expected = {row["id"]: row for row in application["cohorts"]}
    parsed = parse_receipts(payloads)
    require(set(expected) == {meta["id"] for meta, _ in parsed}, "Receipt cohort inventory mismatch")
    for meta, hashes in parsed:
        row = expected[meta["id"]]
        require(all(row.get(k) == v for k, v in meta.items()), f"Receipt metadata mismatch: {meta['id']}")
        require(row["runtime_untracked_hashes"] == ({RUNTIME_CONFIG: hashes[RUNTIME_CONFIG]} if RUNTIME_CONFIG in hashes else {}), "Runtime configuration receipt was lost")
        require(row["tracked_source_count"] == len(hashes) - len(row["runtime_untracked_hashes"]), "Tracked source count differs from receipt")
        require(row["source_exact"] == (not row["differences"]) and row["disposition"] == disposition(row), f"Receipt disposition is inconsistent: {meta['id']}")
        expected_source = application["peer_source"]["commit"] if meta["receipt"].startswith("peer-main/") else LATE
        require(row["qualified_commit"] == expected_source, f"Receipt relabeled to an incorrect source checkpoint: {meta['id']}")
    for name, passed in REQUIRED.items():
        require(name in expected and expected[name]["disposition"] == "accepted", f"Required accepted cohort missing: {name}")
        require(expected[name]["qualified_commit"] == LATE and expected[name]["exit_code"] == 0 and expected[name]["source_exact"], f"Required cohort is not qualified at 00d44: {name}")
        if passed is not None:
            require(expected[name]["passed"] == passed, f"Required pass count mismatch: {name}")
    require(expected["final-mail/receipt.json#zotero-editor"]["skipped"] == 8, "Editor skips changed")
    for name in application.get("required_peer_cohorts", []):
        require(name in expected and expected[name]["disposition"] == "accepted" and expected[name]["qualified_commit"] == application["peer_source"]["commit"], f"Required peer cohort missing: {name}")
    if application.get("peer_source"):
        require(set(REQUIRED_PEER) <= set(application["required_peer_cohorts"]), "Peer acceptance index omits required gates")
        for name, passed in REQUIRED_PEER.items():
            if passed is not None:
                require(expected[name]["passed"] == passed, f"Peer pass count mismatch: {name}")
        require(expected["peer-main/hosts/receipt.json#zotero-editor"]["skipped"] == 8, "Peer editor skips changed")
    inherited_visuals = {row["omitted_member"]: row for row in application["visual_inheritance"]}
    visual_exclusions = {row["path"]: row for row in manifest["exclusions"] if row["reason"] == "byte-identical image retained in immutable baseline archive"}
    require(len(inherited_visuals) == len(application["visual_inheritance"]) and set(inherited_visuals) == set(visual_exclusions), "PNG inheritance/exclusion inventory is not a bijection")
    for row in application["visual_inheritance"]:
        excluded = visual_exclusions[row["omitted_member"]]
        require(all(row[k] == excluded[k] for k in ("source", "bytes", "sha256")), "PNG exclusion metadata differs from its inheritance proof")
        require(row["baseline_member"] in base_payloads and sha(base_payloads[row["baseline_member"]]) == row["sha256"] and len(base_payloads[row["baseline_member"]]) == row["bytes"], f"PNG baseline binding mismatch: {row['source']}")
        require(row["omitted_member"] not in payloads, "Deduplicated image unexpectedly packed")
    inherited = application["baseline_core_inheritance"]
    require(sha(base_payloads[inherited["receipt"]]) == inherited["receipt_sha256"], "Inherited core receipt mismatch")
    inherited_rows = json.loads(base_payloads[inherited["receipt"]])
    for row in inherited_rows:
        require(row["exit_code"] == 0 and row["source_hashes_unchanged"], "Inherited core receipt is not accepted")
        log = str(PurePosixPath(inherited["receipt"]).parent / row["log"])
        require(sha(base_payloads[log]) == row["log_sha256"], "Inherited core log mismatch")
    result = {"status": "PASS", "mode": "archive-only" if archive_only else "Git-qualified", "archive_sha256": application["archive"]["sha256"], "members": len(payloads), "cohorts": len(parsed), "dispositions": dict(Counter(row["disposition"] for row in expected.values())), "deduplicated_pngs": len(application["visual_inheritance"]), "runtime_config": "Untracked .dart_tool/package_config.json is preserved in receipts and excluded only from Git comparisons."}
    result["equal_vm_javascript_driver_pairs"] = verify_driver_comparisons(payloads, manifest)
    probe = json.loads(payloads["layout/continuous-final/receipt.json"])
    require(sha(payloads["layout/continuous_section_probe.dart"]) == probe["probe_sha256"], "Continuous-section probe byte binding mismatch")
    if archive_only:
        result["source_qualification"] = "Not performed; no Git objects or current working-tree sources read."
        return result
    git = Git(repo)
    require(git.commit(BASE)["tree"] == BASE_TREE and git.commit(LATE)["tree"] == LATE_TREE, "Qualified checkpoint tree mismatch")
    peer = application.get("peer_source")
    if peer:
        require(git.commit(peer["commit"]) == peer, "Peer source commit/tree mismatch")
        require(git.run("merge-base", "--is-ancestor", LATE, peer["commit"], check=False).returncode == 0, "Peer source omits 00d44 ancestry")
    actual = compile_cohorts(payloads, git, peer["commit"] if peer else None)
    require(actual == application["cohorts"], "Cohort source qualification differs from the declared immutable checkpoints")
    result["original_late_source"] = {"commit": LATE, "tree": LATE_TREE}
    result["peer_source"] = peer
    result["source_inheritance"] = verify_inheritance(payloads, git)
    result["historical_aliases"] = verify_aliases(git)
    if peer:
        result["peer_source_inheritance"] = verify_peer_inheritance(payloads, git, peer)
    for row in inherited_rows:
        for commit in (BASE, LATE):
            binding = source_binding(git, commit, row["source_hashes"])
            require(binding["source_exact"], f"Inherited core source differs at {commit}: {row['name']}")
    result["core_baseline_cohorts_inherited_at_00d44"] = len(inherited_rows)
    artifact = application["incoming_artifact"]
    for commit in (INCOMING, LATE):
        body = git.read(commit, artifact["path"])
        require(sha(body) == artifact["sha256"] and len(body) == artifact["bytes"], "Incoming PR276 artifact binding mismatch")
    result["cached_git_blobs"] = len(git.blobs)
    result["tracked_receipt_hash_comparisons"] = sum(row["tracked_source_count"] for row in actual)
    result["runtime_config_occurrences"] = sum(bool(row["runtime_untracked_hashes"]) for row in actual)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--baseline-directory", type=Path, help="Defaults to the late archive directory")
    parser.add_argument("--archive-only", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(verify_bundle(args.directory, args.repo, args.archive_only, args.baseline_directory), indent=2, sort_keys=True))
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError, tarfile.TarError) as error:
        print(json.dumps({"status": "FAIL", "error": str(error)}, indent=2), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
