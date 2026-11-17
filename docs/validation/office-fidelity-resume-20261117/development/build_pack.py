#!/usr/bin/env python3
"""Package selected development evidence without modifying the source checkout."""

import collections
import hashlib
import io
import json
import lzma
from pathlib import Path
import subprocess
import tarfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REPO = ROOT / "quds_office_suite"
FINAL = "07481e944799e282f15e6286192b926cff1165df"
BASELINE = "fc44377279ced4589e637360e5f67501012e022c"
COMMENTS = "42efaad646c86391c7994efa714970ee433d5dea"
LINEAR = "9390c24f850f9b975fa252b99c20112f0e8318f9"
ROTATION = "b38003a42b2ce2b9e217aa9a1744400ebe0acf5a"
PART_BYTES = 90000
members = {}
origins = {}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(["git", "-C", str(REPO), *args])


def add_bytes(name, data, category):
    assert name not in members, name
    assert not name.startswith("/") and ".." not in Path(name).parts, name
    members[name] = (data, category)


def add_file(relative, category):
    path = ROOT / relative
    assert path.is_file() and not path.is_symlink(), path
    add_bytes(relative, path.read_bytes(), category)


def add_glob(pattern, category, expected=None):
    matches = sorted(ROOT.glob(pattern))
    if expected is not None:
        assert len(matches) == expected, (pattern, len(matches), expected)
    for path in matches:
        add_file(path.relative_to(ROOT).as_posix(), category)


def add_source(commit, relative, expected_hash=None):
    data = git("show", f"{commit}:{relative}")
    if expected_hash is not None:
        assert digest(data) == expected_hash, (commit, relative)
    member = f"source-snapshots/{commit}/{relative}"
    add_bytes(member, data, "source-snapshot")
    origins[member] = {"commit": commit, "repository_path": relative}


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True) + "\n").encode()


assert git("rev-parse", "HEAD").decode().strip() == FINAL
initial_status = git("status", "--porcelain=v1")
assert initial_status == b"", initial_status

comment_files = [
    "summary.json", "baseline-final.jsonl", "baseline-final.stderr",
    "baseline-final-source.json", "final-control-test.dart", "accepted-v2.jsonl",
    "accepted-v2.stderr", "node-v2.jsonl", "node-v2.stderr", "analysis.log",
    "format.log", "accepted-schema.json", "final-consumer-comparison.json",
    "baseline-libreoffice.log", "final-libreoffice.log", "docx-helper-check.json",
    "docx-helper-negative-controls.json", "linear-followup.json", "linear-vm.jsonl",
    "linear-vm.stderr", "linear-node.jsonl", "linear-node.stderr", "linear-probe.log",
]
for name in comment_files:
    add_file(f"comment-validation/{name}", "comment-development")
add_glob("comment-validation/accepted-fixtures/word-comments-*.odt", "comment-development", 10)
add_glob("comment-validation/final-lo/word-comments-*.docx", "comment-development", 10)
add_glob("comment-validation/baseline-fixtures/word-comments-*.odt", "comment-negative-control", 10)
add_glob("comment-validation/baseline-lo/word-comments-*.docx", "comment-negative-control", 9)

rotation_files = [
    "reviewed-vm-events.jsonl", "reviewed-node-events.jsonl",
    "qualified-node-events.jsonl", "baseline-events.jsonl", "baseline-stderr.log",
    "baseline-summary.json", "check-baseline.py", "probe.py",
    "old90.odp", "old90.pdf", "old90.png",
    "local-matrix90.odp", "local-matrix90.pdf", "local-matrix90.png",
]
for name in rotation_files:
    add_file(f"rotation-review/{name}", "rotation-development")
add_glob("rotation-review/baseline-source-fixtures/*.odp", "rotation-negative-control", 15)
for path in sorted((ROOT / "rotation-review/consumer-reviewed").rglob("*")):
    if path.is_file():
        assert not any(part in {"cache", "lo-profile", "user"} for part in path.parts), path
        add_file(path.relative_to(ROOT).as_posix(), "rotation-development-consumer")
add_file("rotation-review/consumer/rotation-consumer-report.json", "superseded-rotation-consumer")
add_glob("rotation-review/consumer/command-*.stdout", "superseded-rotation-consumer", 32)
add_glob("rotation-review/consumer/command-*.stderr", "superseded-rotation-consumer", 32)

for name in ["source-review.json", "verifier-self-test.stdout", "verifier-self-test.stderr", "comment_date_probe.dart"]:
    add_file(f"review-temp/{name}", "independent-development-review")
for name in ["engine-smoke.jsonl", "editor-smoke.jsonl"]:
    add_file(f"runtime/setup/{name}", "runtime-smoke-protocol-review")
for name in ["OpenDocument-v1.3-schema.rng", "OpenDocument-v1.3-manifest-schema.rng"]:
    add_file(f"validation-resume/schemas/{name}", "schema-reference")

odt_writer = "packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart"
comment_test = "packages/quds_office_engine/test/odt_comment_fidelity_test.dart"
odp_writer = "packages/quds_office_engine/lib/src/slide/serial/odp_presentation_writer.dart"
rotation_sources = [
    odp_writer,
    "packages/quds_office_engine/test/odp_transform_fidelity_test.dart",
    "packages/quds_office_engine/tool/fidelity/make_odp_rotation_fixtures.dart",
    "packages/quds_office_engine/tool/fidelity/verify_odp_rotation.py",
]
comment_summary = json.loads(members["comment-validation/summary.json"][0])
comment_baseline = json.loads(members["comment-validation/baseline-final-source.json"][0])
review = json.loads(members["review-temp/source-review.json"][0])
assert review["source_commit"] == FINAL
assert digest(members["review-temp/source-review.json"][0]) == "4a3ec44716d76c727f12bd3849f4d1412e279482bd2e7bd4b56bb2a0a35ecf77"
assert digest(members["comment-validation/final-control-test.dart"][0]) == comment_baseline["test_sha256"]
add_source(BASELINE, odt_writer, comment_baseline["writer_sha256"])
add_source(BASELINE, odp_writer)
for relative, expected_hash in comment_summary["qualified_sources"].items():
    add_source(COMMENTS, relative, expected_hash)
for relative in [odt_writer, comment_test]:
    add_source(LINEAR, relative)
for relative in rotation_sources:
    add_source(ROTATION, relative)
for relative, record in review["reviewed_files"].items():
    add_source(FINAL, relative, record["sha256"])

for row in review["existing_protocol_log_checks"]:
    relative = Path(row["log_path"]).relative_to(ROOT).as_posix()
    assert digest(members[relative][0]) == row["log_sha256"], relative
for stream in ["stdout", "stderr"]:
    assert digest(members[f"review-temp/verifier-self-test.{stream}"][0]) == review["auditor_self_test"][f"{stream}_sha256"]
assert digest(members["review-temp/comment_date_probe.dart"][0]) == review["findings"][0]["reproduction"]["probe_sha256"]

aliases = []
for fixture in sorted((ROOT / "comment-validation/final-fixtures").glob("word-comments-*.odt")):
    canonical = f"comment-validation/accepted-fixtures/{fixture.name}"
    assert fixture.read_bytes() == members[canonical][0], fixture
    aliases.append({"omitted_duplicate": fixture.relative_to(ROOT).as_posix(), "retained_as": canonical, "sha256": digest(members[canonical][0])})
assert len(aliases) == 10

rotation_report = json.loads(members["rotation-review/consumer-reviewed/rotation-consumer-report.json"][0])
assert rotation_report["passed"] is True
assert len(rotation_report["files"]) == 16
for state in ["source_before", "source_after"]:
    for relative, record in rotation_report[state]["files"].items():
        captured = members[f"source-snapshots/{ROTATION}/{relative}"][0]
        assert digest(captured) == record["sha256"], (state, relative)
for row in rotation_report["files"]:
    stem = row["name"]
    for relative, expected in [
        (f"rotation-review/consumer-reviewed/fixtures/{stem}.odp", row["input_sha256"]),
        (f"rotation-review/consumer-reviewed/{stem}.pdf", row["pdf_sha256"]),
        (f"rotation-review/consumer-reviewed/{stem}.png", row["png_sha256"]),
    ]:
        assert digest(members[relative][0]) == expected, relative
for name, expected in rotation_report["schemas_sha256"].items():
    assert digest(members[f"validation-resume/schemas/{name}"][0]) == expected, name

test_runs = []
for relative in [
    "comment-validation/baseline-final.jsonl", "comment-validation/accepted-v2.jsonl",
    "comment-validation/node-v2.jsonl", "comment-validation/linear-vm.jsonl",
    "comment-validation/linear-node.jsonl", "rotation-review/baseline-events.jsonl",
    "rotation-review/reviewed-vm-events.jsonl", "rotation-review/reviewed-node-events.jsonl",
    "rotation-review/qualified-node-events.jsonl", "runtime/setup/engine-smoke.jsonl",
    "runtime/setup/editor-smoke.jsonl",
]:
    data = members[relative][0]
    events = []
    preamble = []
    for line in data.decode().split("\n"):
        if not line.strip():
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            assert relative == "runtime/setup/editor-smoke.jsonl" and not events
            assert line.startswith("[1/7] Gradle Wrapper"), line
            preamble.append(line)
    outcomes = collections.Counter(event["result"] for event in events if event.get("type") == "testDone" and not event.get("hidden"))
    terminals = [event for event in events if event.get("type") == "done"]
    test_runs.append({"path": relative, "sha256": digest(data), "visible_test_outcomes": dict(outcomes), "terminal": terminals, "non_json_preamble": preamble, "counts_are_final_qualification": False})

capture = {
    "classification": "development evidence only; excluded from final qualification totals",
    "final_source_context": FINAL,
    "source_snapshots": origins,
    "test_runs": test_runs,
    "duplicate_fixture_aliases": aliases,
    "comment_control": {"baseline": BASELINE, "cases": 31, "exact_test_source": "comment-validation/final-control-test.dart"},
    "rotation_control": {
        "baseline": BASELINE,
        "cases": 22,
        "exact_historical_test_source_saved": False,
        "limitation": "The 22-case baseline test source was not separately snapshotted. The baseline writer, driver, raw names and results are retained. The later 23-case source is bound to b38003a4 and must not be presented as the exact baseline test source.",
    },
    "rotation_consumer_source": {
        "reported_head": rotation_report["source_before"]["git_head"],
        "reported_sources_were_uncommitted": True,
        "before_and_after_file_hashes_verified_against_later_saved_commit": ROTATION,
        "fixtures": 16,
        "schema_parts": 64,
    },
    "date_probe_provenance": review["findings"][0]["reproduction"]["timing_provenance"],
    "omitted": [
        "Final fixed-source qualification logs and consumer outputs are outside this development archive.",
        "Scratch LibreOffice profiles, caches, runtime binaries and redundant exploratory attempts are excluded.",
        "Superseded rotation consumer rasters and PDFs are excluded; its failed report and command streams are retained.",
        "The intermediate passing 15-fixture rotation consumer attempt is redundant with the retained 16-fixture attempt.",
        "Comment final-fixtures duplicates are omitted with verified aliases to accepted-fixtures.",
    ],
    "github_actions_used": False,
}
add_bytes("capture-provenance.json", json_bytes(capture), "archive-provenance")
add_bytes("build_pack.py", Path(__file__).read_bytes(), "archive-tool")

readme = """# Development evidence archive — 17 November 2026

This archive preserves development work for the Quds Office continuation. **None of its test counts, reviewer self-tests, timing observations, schema checks, or application checks belongs in the final qualification total.** The fixed source used for the separate final qualification is `07481e944799e282f15e6286192b926cff1165df`; final results are deliberately absent here.

Historical filenames and JSON fields containing `accepted`, `final`, or `qualified` are preserved verbatim. They describe stages of development, not qualification of the final combined source. Counts below overlap across revisions and must not be added together.

## Contents and provenance

- `comment-validation/`: the 31-case negative control against integration `fc443772` (20 failures, 11 successes), its exact test source, the accepted 73-case VM and 34-case Node development logs, strict analysis/format output, and later 35-case VM/Node logs after linear date trimming. The 73-case run includes 34 comment cases plus existing related cases. `summary.json` binds the initial implementation to `42efaad6`; `linear-followup.json` records `9390c24f`.
- Comment consumer evidence retains ten accepted ODT fixtures, ten reopened DOCX files, ten baseline ODT files, nine baseline DOCX files, forty accepted schema-part checks, and the comparison reports. The baseline note fixture failed to load, recorded in `baseline-libreoffice.log`. Ten positive DOCX helper checks and four rejected baseline controls are preserved. The omitted `final-fixtures` comment ODTs were byte-identical to the retained `accepted-fixtures`; `capture-provenance.json` records each verified alias.
- `rotation-review/`: the 22-case negative control (3 successes, 17 failures, 2 errors), pinned baseline writer, driver and fifteen baseline ODP fixtures; accepted 51-case VM and 23-case Node development logs; and the complete reviewed consumer run with sixteen ODP/PDF/PNG sets, sixty-four schema-part checks, and command logs. The 51-case VM run includes the 23 rotation cases and existing related cases.
- The historical 22-case rotation test source was **not separately snapshotted**. Its raw names/results and baseline writer are retained, but no exact historical test-file hash is claimed. The later 23-case test and reviewed production/generator/checker sources are snapshotted from `b38003a4`.
- The reviewed rotation consumer report was written before its changes were committed: it reports HEAD `fc443772` and changed source files. Its recorded before/after source hashes match the later saved `b38003a4` files; this binding is verified by the packaging script. It is not a clean-HEAD final qualification receipt. An earlier failed consumer report and command logs explain the detected frame-growth issue and checker expectation adjustments. Redundant superseded rasters are omitted. The initial `old90` and `local-matrix90` probes retain their ODP, PDF and PNG evidence.
- `review-temp/`: an independent source review binding eleven files to `07481e94`, the date-complexity probe source, and receipt-verifier self-test stdout/stderr. The baseline date timings were transcribed from observed tool output; no original baseline stdout was saved. The fixed probe stdout is retained in `comment-validation/linear-probe.log`. These are development observations, with no performance threshold asserted by regression tests.
- `runtime/setup/` retains the 13-case engine and 12-case editor smoke logs referenced by the independent protocol review. The older 22-case rotation Node log is retained because that review references its exact hash. These smoke/protocol observations and the verifier's synthetic self-tests are excluded from product totals.
- `source-snapshots/` contains immutable Git blobs for the baseline writers, comment revisions, reviewed rotation revision, and eleven independently reviewed final-source files. `validation-resume/schemas/` contains the exact two ODF schemas referenced by the consumer evidence.

## Consumer limits retained by the evidence

The comment changes preserve point annotations; they do not reconstruct source ranges or threads. Main visible-body references take precedence over auxiliary-story references. Missing or ambiguous comment definitions do not attach an arbitrary body. Nested comment references terminate, and note references inside comments retain marks without consuming the note body.

In the measured LibreOffice conversion, visible main-body comments retain metadata, formatting, line breaks, simple hyperlink text/destination and list text. Pictures and tabs inside comments, and unique header/footer/note annotations, are omitted by that consumer even though the original ODF retains them and passes the checked schemas. Rotation evidence covers the selected fixtures and consumer, including grouped text-frame export for rotated tables; it is not universal office-application parity.

## Reconstruction and integrity

`development-evidence.index.json` gives the ordered parts, full archive SHA-256, and every member path, byte size and SHA-256. Join the numbered `.part-NNN` files in the listed order to reconstruct `development-evidence.tar.xz`. Each part is at most 90,000 bytes. The archive uses sorted members, mode 0644, zero UID/GID/mtime, empty owner names, and deterministic XZ compression. `build_pack.py` preserves the exact selection and verifies source/fixture bindings before packaging. Rebuilding it requires the original selected development files and Git objects.

The packaging verification reconstructs the archive from parts, reads every tar member, verifies every member hash/size and canonical metadata, and rebuilds the archive to confirm identical bytes. Scratch profiles/caches and final qualification outputs are excluded. No GitHub Actions job, check, or commit-status query is part of this evidence.

Some retained early NDJSON logs include a literal U+2028 in JSON string values. Parse records on literal LF (`\\n`), not a general Unicode line-splitting operation.
"""
add_bytes("README.md", readme.encode(), "archive-provenance")


def build_archive():
    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for name, (data, _) in sorted(members.items()):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = 0
            archive.addfile(info, io.BytesIO(data))
    return lzma.compress(tar_buffer.getvalue(), format=lzma.FORMAT_XZ, preset=6)


archive_bytes = build_archive()
assert archive_bytes == build_archive(), "Archive generation was not deterministic"
archive_name = "development-evidence.tar.xz"
(HERE / archive_name).write_bytes(archive_bytes)
parts = []
for position, start in enumerate(range(0, len(archive_bytes), PART_BYTES), 1):
    name = f"{archive_name}.part-{position:03d}"
    data = archive_bytes[start:start + PART_BYTES]
    (HERE / name).write_bytes(data)
    parts.append({"path": name, "size": len(data), "sha256": digest(data)})
rejoined = b"".join((HERE / row["path"]).read_bytes() for row in parts)
assert rejoined == archive_bytes
with tarfile.open(fileobj=io.BytesIO(lzma.decompress(rejoined)), mode="r:") as archive:
    stored = archive.getmembers()
    assert [member.name for member in stored] == sorted(members)
    for info in stored:
        assert info.isfile() and info.mode == 0o644
        assert info.uid == info.gid == info.mtime == 0
        assert info.uname == info.gname == ""
        expected, _ = members[info.name]
        actual = archive.extractfile(info).read()
        assert actual == expected and info.size == len(expected), info.name

index = {
    "format_version": 1,
    "classification": "development evidence; no counts contribute to final product qualification",
    "source_context_commit": FINAL,
    "archive": {"path": archive_name, "size": len(archive_bytes), "sha256": digest(archive_bytes)},
    "part_size_limit": PART_BYTES,
    "parts": parts,
    "member_count": len(members),
    "member_bytes": sum(len(data) for data, _ in members.values()),
    "members": [{"path": name, "size": len(data), "sha256": digest(data), "category": category} for name, (data, category) in sorted(members.items())],
    "verified": {"member_readback": True, "part_reconstruction": True, "deterministic_rebuild": True, "canonical_tar_metadata": True, "selected_source_and_report_bindings": True},
}
index_bytes = (json.dumps(index, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n").encode()
assert len(index_bytes) <= PART_BYTES, len(index_bytes)
(HERE / "development-evidence.index.json").write_bytes(index_bytes)
(HERE / "README.md").write_text(readme)
(HERE / "capture-provenance.json").write_bytes(json_bytes(capture))
assert git("rev-parse", "HEAD").decode().strip() == FINAL
assert git("status", "--porcelain=v1") == initial_status
delivery = ["README.md", "capture-provenance.json", "build_pack.py", "development-evidence.index.json", *[row["path"] for row in parts]]
delivery_rows = [{"path": name, "size": (HERE / name).stat().st_size, "sha256": digest((HERE / name).read_bytes())} for name in delivery]
assert all(row["size"] <= PART_BYTES for row in delivery_rows)
(HERE / "publish-files.json").write_bytes(json_bytes(delivery_rows))
print(json.dumps({"archive": index["archive"], "members": index["member_count"], "uncompressed_member_bytes": index["member_bytes"], "parts": parts, "index_bytes": len(index_bytes), "publish_files": len(delivery_rows) + 1, "main_checkout_unchanged": True}, indent=2))
