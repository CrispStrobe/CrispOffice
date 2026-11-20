#!/usr/bin/env python3
"""Reproduce the bounded PR231 source/pin review without executing native code.

Reads immutable Git objects and the pinned SDK's local interop documentation.
Does not fetch refs, change source, resolve packages, or run tests/builds.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess

BASE = "43db439e1e605d6329a6eabe6817b04ca44ba1aa"
MAIN = "098412152fa1d64796eb3fb9c06699ced0f0c44d"
PREVIOUS = "a3373021b6cbe6ae333217417bd1615e88019f7d"
CANDIDATE = "f69e774fbb32a103260541e4a28fb17600bfc17e"
TREE = "1a45545ffa7f4c8548853a30c95bdb38309e3da9"
PRIMARY_SHA256 = "4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf"
ADAPTER_SHA256 = "c35ea5371e02ac0ccef93a5fccb9d500e3096a5718ed773574cad1fb6f608877"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--sdk", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    here = Path(__file__).resolve().parent

    def git(*argv: str) -> bytes:
        return subprocess.check_output(["git", "-C", str(repo), *argv])

    def source(path: str, revision: str = CANDIDATE) -> bytes:
        return git("show", f"{revision}:{path}")

    def oid(path: str, revision: str = CANDIDATE) -> str | None:
        result = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--verify", f"{revision}:{path}"],
            capture_output=True, text=True,
        )
        return result.stdout.strip() if result.returncode == 0 else None

    def record(path: str, revision: str = CANDIDATE) -> dict:
        data = source(path, revision)
        return {"path": path, "revision": revision, "blob": oid(path, revision),
                "bytes": len(data), "sha256": digest(data)}

    def text(path: str, revision: str = CANDIDATE) -> str:
        return source(path, revision).decode()

    paths = git("diff", "--name-only", BASE, MAIN).decode().splitlines()
    combined_paths = git("diff", "--name-only", PREVIOUS, CANDIDATE).decode().splitlines()
    changes = []
    for path in paths:
        changes.append({**record(path), "old_blob": oid(path, BASE),
                        "main_blob": oid(path, MAIN),
                        "candidate_equals_main": source(path) == source(path, MAIN)})

    morph = "packages/quds_arabic_morph"
    studio = "packages/quds_office_editor/example"
    build_path = f"{morph}/tool/build.py"
    assignments = {}
    for node in ast.parse(text(build_path)).body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id in {
                    "CRISPEMBED", "SOURCES", "DATA_NOTICES", "LIBRARY"
                }:
                    assignments[target.id] = ast.literal_eval(node.value)

    manifests = [f"{morph}/licenses/manifest.json",
                 f"{studio}/assets/licenses/arabic_morph/manifest.json"]
    manifest = json.loads(source(manifests[0]))
    notice_checks = []
    for name, (sha256, size) in assignments["DATA_NOTICES"].items():
        package_path = f"{morph}/licenses/data/{name}"
        studio_path = f"{studio}/assets/licenses/arabic_morph/{name}"
        package_bytes, studio_bytes = source(package_path), source(studio_path)
        notice_checks.append({"name": name, "expected_sha256": sha256,
                              "expected_bytes": size,
                              "package": record(package_path),
                              "studio": record(studio_path),
                              "copies_equal": package_bytes == studio_bytes,
                              "matches_pin": digest(package_bytes) == sha256 and len(package_bytes) == size})

    catalog_path = f"{morph}/lib/src/morph_catalog.dart"
    catalog = text(catalog_path)
    model = re.search(r"const camelMorphMsaDisambig = MorphBundleDownload\((.*?)\n\);", catalog, re.S).group(1)
    model_fields = {key: re.search(rf"\b{key}: '([^']+)'", model).group(1)
                    for key in ("id", "repository", "revision", "directory", "license")}
    model_fields["artifacts"] = [
        {"file": name, "sha256": sha256, "bytes": int(size)}
        for name, sha256, size in re.findall(
            r"MorphArtifact\(\s*'([^']+)',\s*'([0-9a-f]{64})',\s*(\d+),", model)
    ]
    model_fields["total_bytes"] = sum(a["bytes"] for a in model_fields["artifacts"])
    base_bundle_pattern = r"const camelMorphMsaProofingBin = MorphBundleDownload\((.*?)\n\);"
    base_bundle_unchanged = re.search(base_bundle_pattern, catalog, re.S).group(0) == re.search(
        base_bundle_pattern, text(catalog_path, BASE), re.S).group(0)

    macos_path = f"{studio}/tool/build_macos_app.sh"
    macos = text(macos_path)
    native_path = f"{morph}/lib/src/morph_transport_native.dart"
    worker_path = f"{morph}/web/arabic_morph_worker.mjs"
    cpp_path = f"{morph}/native/src/quds_arabic_morph.cpp"
    cmake_path = f"{morph}/native/CMakeLists.txt"
    spacy_backend = "packages/quds_proofing_spacy/lib/src/native_backend.dart"
    pubspec_path = f"{morph}/pubspec.yaml"
    pubspec_before, pubspec_after = text(pubspec_path, BASE), text(pubspec_path)
    remove_version = lambda value: re.sub(r"^version:.*$", "", value, flags=re.M)

    sdk_doc = args.sdk.resolve() / "bin/cache/dart-sdk/lib/js_interop/js_interop.dart"
    sdk_bytes = sdk_doc.read_bytes()
    sdk_text = sdk_bytes.decode()
    conversion_start = sdk_text.index("extension Uint8ListToJSUint8Array")
    conversion_end = sdk_text.index("external JSUint8Array get toJS;", conversion_start)
    conversion_doc = sdk_text[conversion_start:conversion_end + len("external JSUint8Array get toJS;")]
    web_host_path = f"{studio}/lib/studio_arabic_morph_host_web.dart"
    web_transport_path = f"{morph}/lib/src/morph_transport_web.dart"
    web_fixture_path = f"{studio}/test/studio_web_persistence_test.dart"

    selected = json.loads((here / "recommended-selection.json").read_text())["cohorts"]
    selection = {}
    for name, cohort in selected.items():
        selection[name] = {**cohort, "files": [
            record(f"{cohort['package']}/test/{relative}")
            for relative in cohort["additional"]
        ]}

    checks = {
        "exact_candidate_tree": git("rev-parse", f"{CANDIDATE}^{{tree}}").decode().strip() == TREE,
        "exact_merge_parents": git("show", "-s", "--format=%P", CANDIDATE).decode().strip().split() == [PREVIOUS, MAIN],
        "exact_38_path_main_delta": len(paths) == 38 and paths == combined_paths,
        "all_38_incoming_blobs_exact_main": all(item["candidate_equals_main"] for item in changes),
        "arabic_pubspec_version_only": remove_version(pubspec_before) == remove_version(pubspec_after),
        "root_lock_unchanged": source("pubspec.lock", PREVIOUS) == source("pubspec.lock"),
        "base_database_pin_unchanged": base_bundle_unchanged,
        "package_and_studio_manifest_equal": source(manifests[0]) == source(manifests[1]),
        "all_four_notice_pairs_equal_and_pinned": all(n["copies_equal"] and n["matches_pin"] for n in notice_checks),
        "manifest_commit_matches_builder": manifest["component"]["commit"] == assignments["CRISPEMBED"]["commit"],
        "manifest_source_hashes_match_builder": manifest["component"]["files"] == {p: v[0] for p, v in assignments["SOURCES"].items()},
        "macos_build_script_unchanged": source(macos_path, PREVIOUS) == source(macos_path),
        "native_abi3_adapter2_check_present": "if (abi() != 3 || adapter() != 2)" in text(native_path),
        "worker_abi3_adapter2_check_present": "_quds_arabic_morph_adapter_version() !== 2" in text(worker_path) and "_crispembed_ar_morph_abi_version() !== 3" in text(worker_path),
        "cpp_adapter2_present": "quds_arabic_morph_adapter_version() { return 2; }" in text(cpp_path),
        "arabic_separate_build_install_library": macos.count('"$PACKAGES/quds_arabic_morph/tool/build.py" --native') == 2 and "libquds_arabic_morph.dylib" in macos and "add_library(quds_arabic_morph SHARED" in text(cmake_path),
        "spacy_separate_abi_namespace": "crispembed_spacy_abi_version" in text(spacy_backend) and "libcrispembed-spacy.dylib" in macos,
        "primary_runner_pin_unchanged": digest((here.parent.parent / "run_validation.py").read_bytes()) == PRIMARY_SHA256,
        "arabic_adapter_pin_unchanged": digest((here / "run_arabic_followup.py").read_bytes()) == ADAPTER_SHA256,
    }
    review = {
        "schema_version": 1,
        "scope": "Bounded source review of merged PR231; immutable f69 source snapshot. No build, native execution, test run, ref fetch or CI query by this review.",
        "source": {"base_main": BASE, "incoming_main": MAIN, "previous_qualified_publication": PREVIOUS,
                   "candidate": CANDIDATE, "candidate_tree": TREE, "parents": [PREVIOUS, MAIN]},
        "metadata": "pr231-metadata.json",
        "changed_paths": changes,
        "path_counts": {"total": len(paths), "packages": sum(p.startswith("packages/") for p in paths),
                        "dart": sum(p.endswith(".dart") for p in paths), "roadmaps": sum(p.startswith("docs/roadmaps/") for p in paths)},
        "source_checks": checks,
        "source_checks_all_passed": all(checks.values()),
        "behavior": [
            "Engine context morphology extends the existing ArabicMorphology interface; contextual grammar is the default with minimum margin 0.9; allAnalyses remains selectable.",
            "Unavailable model, unsupported context morphology, malformed or failing contextual results use existing full-analysis fallback within the engine.",
            "Model-optional behavior assumes a compatible runtime. Native and Web Worker loaders require ABI 3 and adapter 2 even without a context model; old Arabic ABI 2 binaries are not accepted.",
            "The adapter enables the disambiguator only when opening a model, preserving any existing CRISPEMBED_AR_MORPH_DISAMBIG setting, including explicit 0.",
            "Studio adds a separately downloaded context model, removal controls, settings propagation, and model attribution copies."
        ],
        "source_pins": assignments,
        "model_pins": model_fields,
        "notice_checks": notice_checks,
        "manifest_checks": {"paths": [record(p) for p in manifests], "component_commit": manifest["component"]["commit"], "data_notices": manifest["data_notices"],
                            "scope": "Verifies local notice bytes and declared pins; not a legal determination or downloaded-model verification."},
        "package_constraints": {"old_version": "0.2.0", "new_version": "0.3.0", "sdk": "^3.12.0",
                                "dependencies_and_assets_unchanged": checks["arabic_pubspec_version_only"],
                                "root_lock_unchanged": checks["root_lock_unchanged"],
                                "dependency_reuse_proof": "dependency-reuse.json"},
        "macos_compatibility": {
            "conclusion": "No source-level conflict with pinned spaCy. Arabic and spaCy are separately built/packaged libraries with separate ABI namespaces.",
            "arabic_library": "libquds_arabic_morph.dylib", "arabic_runtime_required": {"abi": 3, "adapter": 2},
            "macos_builder_invokes_current_arabic_build_and_install": checks["arabic_separate_build_install_library"],
            "spacy_library": "libcrispembed-spacy.dylib",
            "spacy_bytes_sha256": re.search(r"^SPACY_PIN_SHA256=([0-9a-f]+)$", macos, re.M).group(1),
            "spacy_code_sha256": re.search(r"^SPACY_PIN_CODE_SHA256=([0-9a-f]+)$", macos, re.M).group(1),
            "records": [record(p) for p in [macos_path, build_path, cmake_path, native_path, worker_path, cpp_path, spacy_backend]],
            "boundary": "Source consistency only. Native builds, packaging/signing, real model execution and Wasm runtime acceptance were not performed by this review. Existing ABI 2 Arabic binaries must be rebuilt."
        },
        "author_qualification": {
            "source": "pr231-metadata.json; docs/roadmaps/arabic-proofing.md at incoming main",
            "claims_only": ["engine proofing tests", "Arabic package tests with pinned native library and real database/model", "Node Web Worker smoke with pinned Wasm", "Studio example suite with one unspecified baseline exception", "dart analyze packages apps: zero errors/warnings", "PUD and Wikipedia accuracy/rule A/B measurements"],
            "source_bound_raw_native_receipts_in_38_path_delta": False,
            "studio_exception": {"quoted_description": "Studio example suite (only the known baseline failure)", "test_name": None, "file": None, "trace": None,
                                 "disposition": "Unattributed author exception. It cannot classify any fresh combined-source failure as baseline."},
            "new_native_test_requirements": ["QUDS_ARABIC_MORPH_TEST_LIBRARY", "QUDS_ARABIC_MORPH_TEST_BUNDLE", "QUDS_ARABIC_MORPH_TEST_MODEL"]
        },
        "minimum_local_selection": selection,
        "selection_scope": "1 morph unit file, 4 engine Arabic files, 7 Studio integration files. Fixture support is not selected as a suite. Primary guards/timeouts/accounting remain unchanged. Native, live-download and Chrome suites are excluded from this narrow VM qualification.",
        "source_findings": [{
            "id": "arabic-web-remove-model-reuses-transferred-database",
            "status_at_f69": "Source-level lifecycle defect identified; no browser runtime reproduction in this environment.",
            "path": web_host_path,
            "observation": "_activate stores the same MorphDatabaseBytes in _database and passes it to the transport; removeModel disposes the loaded worker and calls _activate with that cached object. The transport transfers the original Uint8List ArrayBuffers. MorphDatabaseBytes.verified makes an unmodifiable map but does not copy its lists.",
            "consequence": "For JavaScript compilation, Uint8List.toJS casts without copying. Transferring detaches the retained buffers; reopening the base analyzer from those buffers after model removal can fail and lose base analysis. The session-only storage fallback cannot recover by reading persistent storage.",
            "evidence": [record(p) for p in [web_host_path, web_transport_path, catalog_path, web_fixture_path]],
            "local_sdk_documentation": {"path": str(sdk_doc), "sha256": digest(sdk_bytes), "excerpt": conversion_doc},
            "fresh_VM_tests_do_not_cover_this_browser_transfer_path": True,
            "resolution": "Requires an explicit source correction or disclosed browser limitation; not relabelled as an author baseline exception."
        }],
        "reproduction": "python3 review_incoming_arabic.py --repo <repo> --sdk <qualified-flutter-sdk> --output <new-output.json>",
        "review_script_sha256": digest(Path(__file__).read_bytes()),
    }
    args.output.write_text(json.dumps(review, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "candidate": CANDIDATE,
                      "paths": review["path_counts"], "source_checks_all_passed": all(checks.values()),
                      "failed_source_checks": [k for k, v in checks.items() if not v],
                      "source_findings": [f["id"] for f in review["source_findings"]]}))
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
