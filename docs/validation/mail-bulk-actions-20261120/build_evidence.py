#!/usr/bin/env python3
"""Pack this milestone's explicit evidence inventory, without rerunning tests.

Run from any directory:
  python3 docs/validation/mail-bulk-actions-20261120/build_evidence.py \
    --runtime /absolute/path/to/quds-mail-work-20261120/runtime

Use --inventory to inspect the allowlist without writing an archive. A normal
build requires completed current receipts, matching source bindings, the visual
inspection record and exactly 21 verified PNGs. Historical diagnostics are
preserved under history/ and never promoted to successful final acceptance.
Only Python's standard library is required; no network or GitHub calls occur.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile


RUNTIME_SETUP = (
    "runtime-ready.json", "sdk-archive.json", "env.sh",
    "bootstrap_pub_cache.py", "pub-cache-bootstrap-manifest.json",
    "bootstrap-current-locks.log", "flutter-tools-pub-offline.log",
    "workspace-pub-offline.log", "flutter-version.log",
    "runtime-core-smoke.log", "runtime-flutter-smoke.log",
)
ROOT_RUNNERS = (
    "run_host_validation.py", "run_word_final_validation.py",
    "run_word_cutoff_validation.py",
)
RECORD_RUNNERS = (
    "run_core_validation.py", "run_converged_mail_validation.py",
    "run_ui_convergence.py", "run_bulk_visual_validation.py",
)
CURRENT_RECORDS = (
    "converged-mail-validation-receipt.json",
    "converged-mail-validation-summary.json",
    "core-convergence-equivalence.json",
    "host-consolidated-validation.json",
    "runtime-sqlite-asset.json", "transport-direct-native-assets-setup.json",
    "bulk-host-converged-review.json", "bulk-ui-host-review-followup.json",
    "provider-certainty-review-final.json", "visual-inspection.json",
)
HISTORY_RECORDS = (
    "core-bulk-validation-receipt.json", "core-analyze.log", "core-format.log",
    "core-tests-vm.log", "core-bulk-tests-node.log",
    "diagnostic-initial-core-analyze.log", "diagnostic-initial-core-format.log",
    "diagnostic-initial-core-bulk-validation-receipt.json",
    "converged-mail-harness-initial-diagnostic.json",
    "pre-rate-limit-converged-mail-validation-receipt.json",
    "bulk-ui-host-review-initial.json", "provider-certainty-review.json",
    "ui-baseline-tests.log", "ui-bulk-initial-analyze.log",
    "ui-bulk-initial-tests.log", "ui-convergence-analyze.log",
    "ui-initial-analyze.log",
)
FORBIDDEN_RECORDS = frozenset((
    "core-validation-receipt.json", "mail-ui-validation-receipt.json",
    "mail-host-input.json", "runtime-integrity-final.json",
    "bootstrap_pub_cache.py", "pub-cache-bootstrap-manifest.json", "env.sh",
    "build_mail_evidence.py",
))
CONFIGS = (
    ".dart_tool/package_config.json", ".dart_tool/native_assets.yaml",
    "packages/quds_office_editor/example/build/native_assets/linux/native_assets.json",
)
STEP_FILES = ("receipt.json", "format.log", "format.stderr", "analyze.log",
              "analyze.stderr", "tests.log", "tests.stderr")
HEX_SHA256 = re.compile(r"[0-9a-f]{64}\Z")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()


@dataclass(frozen=True)
class Member:
    path: Path
    name: str
    category: str
    source: str


def inventory(repo: Path, runtime: Path, validation: Path):
    members: dict[str, Member] = {}
    missing: list[str] = []

    def add(path: Path, name: str, category: str, source: str, required=True):
        if not path.exists():
            if required:
                missing.append(source)
            return
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Evidence must be a regular file, not a symlink: {source}")
        if name.startswith("/") or ".." in Path(name).parts or name in members:
            raise ValueError(f"Unsafe or duplicate archive member: {name}")
        members[name] = Member(path, name, category, source)

    def record(relative: str, category: str, required=True):
        if Path(relative).name in FORBIDDEN_RECORDS:
            raise ValueError(f"Inherited record explicitly excluded: {relative}")
        prefix = "history/" if category.startswith("history") else ""
        add(runtime / "records" / relative, prefix + "runtime/records/" + relative,
            category, "runtime/records/" + relative, required)

    for name in RUNTIME_SETUP:
        add(runtime / name, "runtime/setup/" + name, "runtime-setup",
            "runtime/" + name)
    for name in ROOT_RUNNERS:
        add(runtime / name, "reproduction/runtime/" + name, "runner",
            "runtime/" + name)
    for name in RECORD_RUNNERS:
        record(name, "runner")
    for name in CURRENT_RECORDS:
        record(name, "current-receipt-or-review")
    for name in HISTORY_RECORDS:
        record(name, "history-earlier-or-diagnostic", required=False)
    for prefix in ("core-converged", "transport-converged"):
        for stage in ("format", "analyze", "tests-vm", "tests-node"):
            record(f"{prefix}-{stage}.log", "current-raw-log")
            record(f"pre-rate-limit-{prefix}-{stage}.log", "history-superseded", False)
    for prefix in ("ui-converged", "visual-final"):
        for suffix in STEP_FILES:
            record(f"{prefix}-{suffix}", "current-ui-or-visual")
    for suffix in STEP_FILES:
        record(f"diagnostic-interrupted-ui-converged-{suffix}", "history-interrupted", False)
        record(f"pre-final-ui/ui-converged-{suffix}", "history-superseded-ui", False)

    # The mixed host run remains failed. Its four unchanged passing suites are
    # used only through the explicit consolidated receipt; no totals are added.
    host_groups = {
        "host-initial": "history-failed-host-attempt",
        "host-corrected": "history-failed-host-attempt",
        "host-merged-analysis": "history-failed-host-analysis",
        "host-final": "history-mixed-host-run",
        "host-fixtures-final": "current-requalified-host-suites",
    }
    for prefix, category in host_groups.items():
        pattern = re.compile(re.escape(prefix) + r"-(?:receipt\.json|(?:analyze-\d+|tests)\.(?:log|stderr))\Z")
        found = [p for p in (runtime / "records").iterdir() if pattern.fullmatch(p.name)]
        for path in sorted(found):
            record(path.name, category)
        if not found:
            missing.append(f"runtime/records/{prefix}-*")
        if prefix in {"host-final", "host-fixtures-final"}:
            count = 8 if prefix == "host-final" else 2
            required = [f"{prefix}-receipt.json", f"{prefix}-tests.log", f"{prefix}-tests.stderr"]
            required += [f"{prefix}-analyze-{i}.{suffix}"
                         for i in range(count) for suffix in ("log", "stderr")]
            missing += ["runtime/records/" + name for name in required
                        if not (runtime / "records" / name).is_file()]

    # This dedicated validation directory contains only this milestone's intake
    # records. Its Word logs are often gitignored, so use the filesystem rather
    # than git ls-files; never include JavaScript/compiler outputs or archives.
    for path in sorted(validation.iterdir()):
        if not path.name.startswith("intake") or path.suffix not in {".json", ".md", ".py", ".log"}:
            continue
        diagnostic = any(word in path.name for word in ("diagnostic", "interrupted", "initial"))
        historical_word = path.name.startswith("intake-local-word-") and not any(
            word in path.name for word in ("word-final", "word-cutoff", "word-merges"))
        category = "history-intake-or-word" if diagnostic or historical_word else "intake-or-word-qualification"
        prefix = "history/" if category.startswith("history") else ""
        add(path, prefix + "validation/" + path.name, category,
            str(path.relative_to(repo)))
    for name in ("intake-local-word-final-validation.json", "intake-local-word-cutoff-validation.json"):
        if not (validation / name).is_file():
            missing.append(str((validation / name).relative_to(repo)))
    for name in ("provider-certainty-review.md", "build_evidence.py"):
        add(validation / name, "reproduction/" + name if name.endswith(".py") else "validation/" + name,
            "builder" if name.endswith(".py") else "primary-source-review", str((validation / name).relative_to(repo)))
    for relative in CONFIGS:
        add(repo / relative, "configuration/" + relative, "runtime-configuration", relative)
    pngs = sorted((runtime / "records/bulk-visuals").glob("*.png"))
    for path in pngs:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.png", path.name):
            raise ValueError(f"Unexpected visual filename: {path.name}")
        record("bulk-visuals/" + path.name, "qualified-visual")
    if len(pngs) != 21:
        missing.append(f"exactly 21 bulk-visual PNGs (currently {len(pngs)})")

    selected = {member.path for member in members.values()}
    omitted = sorted(str(path.relative_to(runtime)) for path in (runtime / "records").rglob("*")
                     if path.is_file() and path not in selected)
    return sorted(members.values(), key=lambda member: member.name), missing, omitted


def load_json(path: Path):
    return json.loads(path.read_text())


def require(condition: bool, message: str):
    if not condition:
        raise ValueError(message)


def current_bindings(repo: Path, runtime: Path, validation: Path):
    records = runtime / "records"
    core = load_json(records / "converged-mail-validation-receipt.json")
    require(len(core["steps"]) == 8 and all(step["exit_code"] == 0 for step in core["steps"]),
            "Core/transport acceptance is incomplete or failed")
    require(all(core["source_unchanged"].values()), "Core/transport inputs changed during acceptance")
    hosts = load_json(records / "host-consolidated-validation.json")
    require(hosts["success"] and hosts["failed"] == 0 and not hosts["current_inputs_differ_from_qualified"],
            "Consolidated host acceptance is not complete")
    ui = load_json(records / "ui-converged-receipt.json")
    visual = load_json(records / "visual-final-receipt.json")
    for label, receipt in (("UI", ui), ("visual", visual)):
        require(len(receipt["steps"]) == 3 and all(step["exit_code"] == 0 for step in receipt["steps"]),
                f"{label} acceptance is incomplete or failed")
        require(receipt["inputs_unchanged"], f"{label} source changed during acceptance")
        terminal = receipt["steps"][-1].get("terminal_done", [])
        require(terminal and terminal[-1].get("success") is True,
                f"{label} acceptance has no successful terminal test event")
    require(visual["success"] and len(visual["images"]) == 21, "Visual qualification is incomplete")
    for name, observation in visual["images"].items():
        require(bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.png", name)),
                f"Unsafe visual receipt filename: {name}")
        path = records / "bulk-visuals" / name
        require(path.is_file() and digest(path.read_bytes()) == observation["sha256"]
                and path.stat().st_size == observation["bytes"], f"Visual hash/size mismatch: {name}")
    require(set(visual["images"]) == {path.name for path in (records / "bulk-visuals").glob("*.png")},
            "Visual receipt and PNG inventory differ")
    # Inspection is a human/model review record, not a test-total source.
    load_json(records / "visual-inspection.json")
    word = load_json(validation / "intake-local-word-cutoff-validation.json")
    require(word["status"] == "PASS", "Final captured Word cutoff is not qualified")
    setup = load_json(runtime / "runtime-ready.json")
    packages = load_json(runtime / "pub-cache-bootstrap-manifest.json")
    require(setup["dependency_archives_verified"] == 202 and setup["workspace_lock_unchanged"],
            "Pinned runtime setup receipt does not certify the locked dependencies")
    require(packages["complete"] and packages["installed_packages"] == 202 and not packages["failures"],
            "Fresh locked package bootstrap is incomplete")

    receipts = {
        "core-and-transport": core["source_inputs"],
        "hosts-consolidated": hosts["qualified_inputs"],
        "shared-ui": ui["inputs"],
        "visuals": visual["inputs"],
        "word-cutoff": word.get("source_sha256_after", word["source_sha256_before"]),
    }
    observed: dict[str, str] = {}
    changed = []
    for label, inputs in receipts.items():
        for relative, expected in inputs.items():
            require(not Path(relative).is_absolute() and ".." not in Path(relative).parts,
                    f"Source binding escapes the repository: {relative}")
            require(bool(HEX_SHA256.fullmatch(expected)), f"Invalid source digest: {relative}")
            path = repo / relative
            if relative not in observed:
                observed[relative] = digest(path.read_bytes()) if path.is_file() else "MISSING"
            if observed[relative] != expected:
                changed.append({"receipt": label, "path": relative,
                                "qualified_sha256": expected, "current_sha256": observed[relative]})
    require(not changed, "Current source differs from final qualification:\n" + json.dumps(changed, indent=2))
    git = lambda *args: subprocess.check_output(["git", *args], cwd=repo, text=True).strip()
    return {
        "head": git("rev-parse", "HEAD"), "tree": git("rev-parse", "HEAD^{tree}"),
        "qualification_inputs": receipts, "current_sha256": dict(sorted(observed.items())),
        "all_qualification_inputs_match_current": True,
        "note": "Historical receipts retain their original bindings and outcomes. No historical test totals are added to final acceptance.",
    }


def write_archive(path: Path, payloads: dict[str, bytes]):
    with path.open("wb") as raw:
        with gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0, compresslevel=9) as zipped:
            with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for name, data in sorted(payloads.items()):
                    entry = tarfile.TarInfo(name)
                    entry.size = len(data)
                    entry.mtime = 0
                    entry.mode = 0o644
                    entry.uid = entry.gid = 0
                    entry.uname = entry.gname = ""
                    archive.addfile(entry, io.BytesIO(data))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runtime", type=Path, required=True, help="Exact absolute current-turn runtime root")
    parser.add_argument("--inventory", action="store_true", help="Print selected/missing files; write nothing")
    args = parser.parse_args()
    require(args.runtime.is_absolute(), "--runtime must be an absolute path")
    runtime = args.runtime.resolve(strict=True)
    validation = Path(__file__).resolve().parent
    repo = validation.parents[2]
    members, missing, omitted = inventory(repo, runtime, validation)
    if args.inventory:
        print(json.dumps({"members": [{"source": m.source, "archive_path": m.name,
                                       "category": m.category} for m in members],
                          "missing_required": missing, "excluded_records": omitted}, indent=2))
        return
    require(not missing, "Missing required evidence:\n" + "\n".join(missing))
    bindings = current_bindings(repo, runtime, validation)
    payloads = {member.name: member.path.read_bytes() for member in members}
    payloads["source-bindings.json"] = json_bytes(bindings)
    payloads["EVIDENCE.md"] = (
        "# Current-turn mail bulk-actions evidence\n\n"
        "The adjacent evidence-manifest.json records every member digest and size, the archive digest, "
        "and final source bindings. Rebuild with the included build_evidence.py and the exact current-turn runtime.\n\n"
        "Files under history/ are earlier, interrupted, failed, superseded, or mixed attempts. Their original "
        "outcomes remain intact. In particular, host-final is a failed mixed run; the consolidated host receipt "
        "explicitly retains four unchanged complete suites and substitutes two complete clean reruns. "
        "No test totals are summed by this packer. Runtime smoke checks are setup evidence, not new feature acceptance.\n\n"
        "The fresh bootstrap script was reused from previously committed evidence and rerun against the current "
        "locks; runtime-ready.json and the fresh manifest record this provenance. Inherited records from the "
        "previous header-search archive, the SDK, dependency cache, downloaded archives, SQLite binaries and "
        "compiled JavaScript are excluded. Genuine native-assets mappings and library hashes are retained.\n"
    ).encode()
    member_rows = [{"path": m.name, "sha256": digest(payloads[m.name]), "bytes": len(payloads[m.name]),
                    "category": m.category, "source": m.source} for m in members]
    for name in ("source-bindings.json", "EVIDENCE.md"):
        member_rows.append({"path": name, "sha256": digest(payloads[name]), "bytes": len(payloads[name]),
                            "category": "generated-index", "source": "generated by build_evidence.py"})
    archive_path = validation / "evidence.tar.gz"
    manifest_path = validation / "evidence-manifest.json"
    archive_tmp = validation / ".evidence.tar.gz.tmp"
    manifest_tmp = validation / ".evidence-manifest.json.tmp"
    try:
        write_archive(archive_tmp, payloads)
        # A concurrently edited log/receipt or source must not be published as
        # the snapshot that was verified above.
        for member in members:
            require(member.path.read_bytes() == payloads[member.name],
                    f"Evidence changed while packing: {member.source}")
        require(current_bindings(repo, runtime, validation) == bindings,
                "Repository or qualification changed while packing")
        with tarfile.open(archive_tmp, "r:gz") as archive:
            actual = {entry.name: archive.extractfile(entry).read() for entry in archive.getmembers()}
        require(actual == payloads, "Archive round-trip verification failed")
        manifest = {
            "schema": 1, "scope": "mail-bulk-actions-20261120 current-turn evidence only",
            "runtime_root": str(runtime), "archive": {"path": archive_path.name,
                "sha256": digest(archive_tmp.read_bytes()), "bytes": archive_tmp.stat().st_size},
            "members": sorted(member_rows, key=lambda row: row["path"]),
            "member_count": len(member_rows), "categories": dict(sorted(Counter(m["category"] for m in member_rows).items())),
            "source_bindings": bindings, "excluded_record_files": omitted,
            "determinism": "Sorted PAX members, fixed mode/uid/gid/mtime, gzip mtime=0 and empty filename; no generated wall-clock timestamp.",
            "acceptance_note": "This archive verifies provenance and completeness, not a combined test count. Historical diagnostics remain historical.",
        }
        manifest_tmp.write_bytes(json_bytes(manifest))
        os.replace(archive_tmp, archive_path)
        os.replace(manifest_tmp, manifest_path)
    finally:
        archive_tmp.unlink(missing_ok=True)
        manifest_tmp.unlink(missing_ok=True)
    print(json.dumps({"archive": manifest["archive"], "members": len(member_rows),
                      "manifest": str(manifest_path), "source_bindings_match": True}, indent=2))


if __name__ == "__main__":
    main()
