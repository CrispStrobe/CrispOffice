#!/usr/bin/env python3
"""Verify exact source/workspace continuity without relabelling prior test results."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

PRIOR = "0669ac119da05f5eb777c8cfdbce32e0261df647"
MAIN = "b655b8a37fddc874bd42a453c371eed6253e82d8"
HUNSPELL = "packages/quds_proofing_hunspell/"
MACOS = "packages/quds_office_editor/example/macos/"
REPORT = "docs/validation/office-main-sync-20261119/"


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("repo", "runtime", "evidence", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--source", required=True)
    args = parser.parse_args()
    repo, runtime, evidence = args.repo.resolve(), args.runtime.resolve(), args.evidence.resolve()
    issues: list[str] = []

    def check(condition: bool, message: str) -> None:
        if not condition:
            issues.append(message)

    def read(name: str) -> dict:
        return json.loads((evidence / name).read_bytes())

    def git(*values: str) -> bytes:
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(repo), *values])

    def tree(source: str) -> dict[str, tuple[str, str]]:
        rows = {}
        for item in git("ls-tree", "-r", "-z", source).split(b"\0"):
            if item:
                metadata, path = item.split(b"\t", 1)
                mode, kind, blob = metadata.decode().split()
                check(kind == "blob", "Unexpected non-blob source entry: " + path.decode())
                rows[path.decode()] = (mode, blob)
        return rows

    def blob(source: str, path: str) -> bytes:
        return git("show", source + ":" + path)

    source = git("rev-parse", "--verify", args.source + "^{commit}").decode().strip()
    old, incoming, current = tree(PRIOR), tree(MAIN), tree(source)
    for base in (PRIOR, MAIN):
        check(subprocess.run(["git", "--no-replace-objects", "merge-base", "--is-ancestor", base, source], cwd=repo).returncode == 0,
              "Required integration ancestry: " + base)
    check(git("rev-parse", "HEAD").decode().strip() == source, "Current checkout source identity")
    check(not git("status", "--porcelain=v1", "--untracked-files=no").strip(), "Clean tracked source checkout")
    prior_execution, prior_summary = read("prior-execution.json"), read("prior-independent-summary.json")
    check(prior_execution["status"] == "PASS" and prior_execution["source_commit"] == PRIOR, "Original completed gate source")
    check(prior_summary["passed"] is True and prior_summary["source_commit"] == PRIOR
          and prior_summary["application_case_executions"] == 1372 and prior_summary["separate_python_controls"] == 90,
          "Original independent 1372/90 evidence identity")
    prior_source, prior_runtime = read("prior-source-before.json"), read("prior-runtime-before.json")
    current_source, current_runtime = read("source-before.json"), read("runtime-before.json")
    protected = {
        REPORT + "final-run-validation.py", REPORT + "final-native-plan.json", REPORT + "final-node-plan.json",
        "docs/validation/document-review-notes-20261118/run_checks.py",
        "docs/validation/document-review-notes-20261118/test_run_checks.py",
        "docs/validation/document-review-notes-20261118/runtime/restore_runtime.py",
        "docs/validation/document-review-notes-20261118/runtime/test_restore_runtime.py",
        "tools/mail/check_store.py", "tools/mail/check_reader.py", "tools/mail/test_check_store.py",
    }
    exact_incoming = {
        "packages/quds_mail_transport/lib/src/configuration.dart",
        "packages/quds_office_editor/example/analysis_options.yaml",
        "packages/quds_mail_store/README.md", "pubspec.yaml",
        "docs/validation/mail-uid-pagination-20261119/run_validation.py",
    }
    bundle = {"tools/proofing/ayaspell/" + name for name in (
        "build_bundle.py", "test_build_bundle.py", "test_build_bundle_incoming.py",
        "test_build_bundle_reproducibility.py")}
    changes, unchanged_existing_product = [], []
    for path in sorted(old):
        check(path in current, "Existing source must not disappear: " + path)
        if path not in current:
            continue
        if old[path] == current[path]:
            if path.startswith(("packages/", "apps/", "third_party/")):
                unchanged_existing_product.append(path)
            continue
        if path in protected:
            category = "FORBIDDEN prior qualification harness change"
            check(False, category + ": " + path)
        elif path in exact_incoming:
            category = "reviewed exact incoming identity"
            check(current[path] == incoming.get(path), "Exact incoming source differs: " + path)
        elif path in bundle:
            category = "Arabic bundle delta; requires fresh seventeen controls"
        elif path.endswith(".md") and (path == "README.md" or path.startswith("docs/")):
            category = "documentation with exact changed bytes recorded"
        elif path.startswith("docs/validation/"):
            category = "historical evidence or incoming validation data"
            check(current[path] == incoming.get(path), "Unreviewed historical evidence change: " + path)
        else:
            category = "UNEXPECTED existing source change"
            check(False, category + ": " + path)
        changes.append({"path": path, "category": category, "before_mode": old[path][0], "before_blob": old[path][1],
                        "after_mode": current[path][0], "after_blob": current[path][1],
                        "before_sha256": digest(blob(PRIOR, path)), "after_sha256": digest(blob(source, path))})
    additions = []
    for path in sorted(set(current) - set(old)):
        allowed = path.startswith((HUNSPELL, MACOS, "docs/")) or path == "tools/proofing/ayaspell/test_build_bundle_reproducibility.py"
        check(allowed, "Unreviewed new source path: " + path)
        check(current[path][0] in {"100644", "100755"}, "New source must be a regular file: " + path)
        additions.append({"path": path, "mode": current[path][0], "git_blob": current[path][1]})
    check(current["pubspec.lock"] == old["pubspec.lock"] == incoming["pubspec.lock"], "Exact original/incoming dependency lock")
    check(blob(source, "tools/proofing/ayaspell/test_build_bundle_reproducibility.py") == blob(PRIOR, "tools/proofing/ayaspell/test_build_bundle.py"),
          "Original five bundle controls preserved byte-for-byte under explicit filename")
    # Existing Dart implementations and tests may only change by the exact
    # incoming documentation comment. No token-stripping equivalence is used.
    old_dart = {p for p in old if p.endswith(".dart") and p.startswith(("packages/", "apps/", "third_party/"))}
    dart_delta = sorted(p for p in old_dart if current.get(p) != old[p])
    check(dart_delta == ["packages/quds_mail_transport/lib/src/configuration.dart"], "Existing Dart source/test continuity except exact incoming comment")
    bound_changes = []
    for path, original_hash in prior_source.items():
        check(digest(blob(PRIOR, path)) == original_hash, "Original bound Git source: " + path)
        check(path in current_source, "Original bound input retained in new envelope: " + path)
        if path in current_source:
            check(digest(blob(source, path)) == current_source[path] == digest((repo / path).read_bytes()), "Current frozen/materialized bound input: " + path)
            if original_hash != current_source[path]:
                bound_changes.append({"path": path, "before_sha256": original_hash, "after_sha256": current_source[path]})
    previous = read("prior-resolution/receipt.json")
    for path, expected in previous["files"].items():
        raw = (evidence / "prior-resolution" / path).read_bytes()
        check(digest(raw) == expected["sha256"] and len(raw) == expected["bytes"], "Original preserved resolution bytes: " + path)
    before_config_raw = (evidence / "prior-resolution/.dart_tool/package_config.json").read_bytes()
    after_config_raw = (evidence / "package_config.json").read_bytes()
    check(digest(before_config_raw) == prior_runtime["workspace/package_config.json"], "Prior package mappings bind exact 0669 runtime")
    check(digest(after_config_raw) == current_runtime["workspace/package_config.json"] == digest((repo / ".dart_tool/package_config.json").read_bytes()), "Current package mappings bind current gate and materialized runtime")
    before_config, after_config = json.loads(before_config_raw), json.loads(after_config_raw)
    before_rows = {row["name"]: row for row in before_config["packages"]}
    after_rows = {row["name"]: row for row in after_config["packages"]}
    check(len(before_rows) == len(before_config["packages"]) == 131 and len(after_rows) == len(after_config["packages"]) == 132, "Exact distinct 131-to-132 package mapping inventory")
    check(set(after_rows) - set(before_rows) == {"quds_proofing_hunspell"} and not set(before_rows) - set(after_rows), "Only optional Hunspell workspace package added")
    check(all(after_rows.get(name) == row for name, row in before_rows.items()), "All 131 prior package mappings unchanged")
    check({k: v for k, v in before_config.items() if k != "packages"} == {k: v for k, v in after_config.items() if k != "packages"}, "Package resolver/runtime metadata unchanged")
    check(after_rows.get("quds_proofing_hunspell") == {"name": "quds_proofing_hunspell", "rootUri": "../packages/quds_proofing_hunspell", "packageUri": "lib/", "languageVersion": "3.12"}, "Exact new local package mapping")
    old_graph, new_graph = read("prior-resolution/.dart_tool/package_graph.json"), read("package_graph.json")
    old_nodes, new_nodes = ({row["name"]: row for row in value["packages"]} for value in (old_graph, new_graph))
    check(set(new_nodes) - set(old_nodes) == {"quds_proofing_hunspell"} and all(new_nodes.get(name) == row for name, row in old_nodes.items()), "All prior dependency graph nodes unchanged")
    check(set(new_graph["roots"]) - set(old_graph["roots"]) == {"quds_proofing_hunspell"} and set(old_graph["roots"]) <= set(new_graph["roots"]), "Only new workspace graph root")
    runtime_changes = []
    for path, expected in prior_runtime.items():
        check(path in current_runtime, "Prior runtime input retained: " + path)
        if path in current_runtime and current_runtime[path] != expected:
            runtime_changes.append(path)
    check(runtime_changes == ["workspace/package_config.json"], "Only declared runtime package-config delta")
    runtime_receipt = json.loads((runtime / "runtime.json").read_bytes())
    check(digest((runtime / "runtime.json").read_bytes()) == prior_summary["runtime_receipt_sha256"] == current_runtime["runtime/runtime.json"], "Original runtime bootstrap receipt retained unchanged")
    check(set(runtime_receipt["workspace_packages"]["resolved"]) == set(before_rows) and runtime_receipt["workspace_package_count"] == 131,
          "Original runtime receipt remains historical 131-package bootstrap")
    check(digest((repo / "pubspec.lock").read_bytes()) == runtime_receipt["workspace_lock_sha256"], "No locked dependency drift")
    inherited_licenses = []
    for name in ("COPYING.MPL", "license.hunspell", "license.myspell"):
        path = HUNSPELL + "licenses/upstream/" + name
        check(current[path] == incoming[path], "Inherited license bytes preserved: " + path)
        inherited_licenses.append({"path": path, "git_blob": current[path][1], "sha256": digest(blob(source, path))})
    entitlements = []
    for name in ("DebugProfile.entitlements", "Release.entitlements"):
        path = MACOS + "Runner/" + name
        raw = blob(source, path)
        value = plistlib.loads(raw)
        for key in ("com.apple.security.app-sandbox", "com.apple.security.network.client", "com.apple.security.files.user-selected.read-write"):
            check(value.get(key) is True, "Required macOS entitlement: " + path + ":" + key)
        entitlements.append({"path": path, "sha256": digest(raw), "plist": value})
    project = blob(source, MACOS + "Runner.xcodeproj/project.pbxproj").decode()
    check(project.count("CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.entitlements;") == 2
          and project.count("CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;") == 1,
          "Exact Debug/Profile/Release entitlement references")
    report = {"passed": not issues, "issues": issues, "audited_at_utc": datetime.now(timezone.utc).isoformat(),
              "method": "Exact immutable Git identities, preserved runtime/workspace inputs and source scopes; no test result is reassigned to another source.",
              "source_commit": source, "source_tree": git("rev-parse", source + "^{tree}").decode().strip(),
              "prior_qualified_source": PRIOR, "incoming_main_source": MAIN,
              "prior_application_case_executions": 1372, "prior_separate_python_controls": 90,
              "prior_cases_added_to_current_delta": 0, "prior_controls_added_to_current_delta": 0,
              "prior_independent_summary_sha256": digest((evidence / "prior-independent-summary.json").read_bytes()),
              "prior_runtime_receipt_sha256": prior_summary["runtime_receipt_sha256"],
              "prior_bound_inputs": len(prior_source), "changed_prior_bound_inputs": bound_changes,
              "unchanged_existing_product_paths": len(unchanged_existing_product), "existing_dart_changed_paths": dart_delta,
              "changed_existing_source": changes, "new_paths": additions,
              "runtime_changed_paths": runtime_changes, "workspace_before": sorted(before_rows), "workspace_after": sorted(after_rows),
              "workspace_before_count": len(before_rows), "workspace_after_count": len(after_rows),
              "new_workspace_mapping": after_rows.get("quds_proofing_hunspell"),
              "workspace_package_config_before_sha256": digest(before_config_raw), "workspace_package_config_after_sha256": digest(after_config_raw),
              "workspace_all_prior_rows_unchanged": all(after_rows.get(name) == row for name, row in before_rows.items()),
              "inherited_license_identities": inherited_licenses, "whitespace_base": MAIN,
              "macos_entitlements_static_check": entitlements,
              "limitations": ["The original 1372 executions apply to 0669, not this new source.", "Fresh delta execution is required for the new package, preserved-fix merge paths and seventeen bundle controls.", "Linux native qualification and browser compilation do not establish macOS execution or a real WebAssembly worker session."],
              "script_sha256": digest(Path(__file__).read_bytes())}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in ("passed", "issues", "source_commit", "workspace_before_count", "workspace_after_count")}))
    return int(bool(issues))


if __name__ == "__main__":
    raise SystemExit(main())
