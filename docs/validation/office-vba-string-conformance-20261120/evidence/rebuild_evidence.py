#!/usr/bin/env python3
"""Package the explicitly selected local qualification receipts; no tests or Git calls.

Run with the original scratch workspace, or an extracted/remapped equivalent:
  python rebuild_evidence.py --workspace-root /path/to/workspace
Verify the committed bundles without the original workspace:
  python rebuild_evidence.py --verify
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile


OUTPUT = Path(__file__).resolve().parent
INDEX = OUTPUT / "archive-index.json"

SPECS = {
    "macro-local": {
        "trees": ["qualification"],
        "files": ["run_validation.py", "run_macro_suite.py"],
        "notes": [
            "The 29-file macro selection accepted 901 cases at 403fec5f8b73752890a36579264ab010e6b12bc1; no retries, failures or skips.",
            "The receipt honestly reports a captured Studio UI change during the run. macro-input-classification.json identifies that exact delta outside the tested import closure; do not claim every captured input was unchanged.",
            "A later Word production guard was separately qualified in word-main-refresh and the fresh portable run. Whole-engine final analysis passed at 6b94e195ec4871d47c4ee0ffb81bcfe6ab8d7c74 with all captured inputs unchanged.",
            "Initial integration and analysis attempts are retained beside accepted receipts. These overlapping selections must not be summed.",
        ],
    },
    "portable": {
        "trees": ["portable-final"],
        "files": [],
        "notes": [
            "Authoritative acceptance is portable-final/final-source/qualification.json at 6b94e195ec4871d47c4ee0ffb81bcfe6ab8d7c74: six existing smoke programs plus the new string corpus compiled and executed as JavaScript; 69 cases matched the VM receipt byte for byte.",
            "All 945 guarded inputs were unchanged during the accepted fresh run. Subsequent addition of the separately qualified Word test to the workflow is documented by the parent source-bindings.json.",
            "Earlier attempts stopped on source changes and remain explicitly superseded by supersession.json and README.md. The Studio-only change was outside compiler dependencies; the Word change was in all six dependency graphs and required the fresh complete run.",
            "Every artifacts directory and generated JavaScript/source map is excluded. Exact artifact hashes and copied raw .js.deps dependency graphs remain included.",
        ],
    },
    "pptx": {
        "trees": ["pptx-validation"],
        "files": [
            "pptx-review.md", "pptx-independent-review.md",
            "connector-independent-review.md", "connector-independent-review-sources.json",
            "final-integration-review.md", "probe_pdf_numeric.dart",
            "probe_pdf_numeric_named_fonts.dart", "pptx-numeric-independent-probe.log",
            "pptx-numeric-independent-named-fonts.log",
        ],
        "notes": [
            "The final connector selections accepted 129 engine cases across eight files and 51 editor cases across four files; all 28 guarded paths remain bound to their recorded source. Strict analysis covered 14 files; formatting covered 11.",
            "Earlier 81/20, 92-case, focused probes and failed intermediate expectations are historical evidence and overlap the final selections; do not sum them.",
            "Independent reviews preserve incoming-source comparisons and the original entire dark-slide test file identity. final-integration-review.md binds the accepted presentation bytes through final reconciliation 50fb2ded700ffd765c8379c7757cbd8f298fc160.",
        ],
    },
    "word-main-refresh": {
        "trees": ["word-final"],
        "files": ["main-refresh-review.md"],
        "notes": [
            "Accepted Word qualification at canonical 6b94e195ec4871d47c4ee0ffb81bcfe6ab8d7c74 consists of the 32-case revision/macro selection plus two exact native boundary tests (34 total), strict analysis, and unchanged captured inputs.",
            "attempt-01-unreachable-save-guard preserves the failed initial fixture and reporter output. The accepted fixture uses ordinary authored native settings and reaches the actual serializer guard without weakening protection.",
            "main-refresh-review.md mentions temporary merge 0c0d6ff7; its tree is identical to canonical 6b94e195. The final integration review in the PPTX bundle records the later source rebinding.",
        ],
    },
    "runtime": {
        "trees": [],
        "files": [
            "runtime/bootstrap_runtime.py", "runtime/env.sh", "runtime/runtime.json",
            "runtime/pub-cache-receipt.json", "runtime/archive-members.json",
            "runtime/logs/flutter-tools-pub-get.log", "runtime/logs/flutter-version.log",
            "runtime/logs/workspace-pub-get.log", "runtime/bin/dart", "runtime/bin/flutter",
        ],
        "notes": [
            "Pinned runtime receipts and exact bootstrap/wrapper scripts identify Flutter 3.47.8, Dart 3.13.7 and Node 24.22.3, verified hosted package archives, and the unchanged repository lockfile.",
            "The SDK, pub cache, downloaded archives and unrelated runtime state are deliberately excluded. The archive-member inventory and checksum receipts identify the original runtime inputs.",
            "Scripts and raw receipts preserve their original workspace paths. Reproduction in another location requires mapping those paths and acquiring the pinned runtime; unpacking this bundle does not install the SDK.",
        ],
    },
    "vba-focused": {
        "trees": [],
        "files": [
            "vba-independent-review.md", "probe_surrogate.dart", "build_vba_conformance.py",
            "vba-conformance-analysis.log", "vba-conformance-cases.log",
            "vba-conformance-compile-js.stderr", "vba-conformance-compile-js.stdout",
            "vba-conformance-final.log", "vba-conformance-initial.log",
            "vba-conformance-js.stderr", "vba-conformance-js.stdout",
            "vba-conformance-vm.stderr", "vba-conformance-vm.stdout",
            "vba-conformance-verification.json", "vba-conformance.js.deps",
            "vba-conformance-utf16-boundary-analysis.log",
            "vba-conformance-utf16-boundary-compile-js.stderr",
            "vba-conformance-utf16-boundary-compile-js.stdout",
            "vba-conformance-utf16-boundary-final.log",
            "vba-conformance-utf16-boundary-js.stderr",
            "vba-conformance-utf16-boundary-js.stdout",
            "vba-conformance-utf16-boundary-vm.stderr",
            "vba-conformance-utf16-boundary-vm.stdout",
            "vba-conformance-utf16-boundary-verification.json",
            "vba-conformance-utf16-boundary-program.js.deps",
            "vba-string-analysis-final.log", "vba-string-analysis.log",
            "vba-string-focused-direct.log", "vba-string-focused-surrogates.log",
            "vba-string-focused.log", "vba-string-lossless-boundary-analysis.log",
            "vba-string-lossless-boundary-final-tests.log",
            "vba-string-lossless-boundary-tests.log",
        ],
        "notes": [
            "Accepted focused boundary results are 102 compiler tests and 113 conformance/schema tests around the final 69-case corpus. These overlap the broad macro selection and are not additional independent totals.",
            "Earlier 62-case/106-test and 85/86-test candidates, compile/schema failures, and a corrected ClearContents expected location are retained as superseded development evidence.",
            "Internal UTF-16 slicing remains supported; malformed UTF-16 emitted to native plans is refused. The prior native JSON-only lone-surrogate roundtrip did not establish lossless XLSX publication and was superseded after a concrete loss probe.",
            "probe_surrogate.dart is the exact source of that prior-candidate probe; no separate raw stdout was persisted, and none is invented here. build_vba_conformance.py is the historical initial generator and does not reproduce the later manually revised canonical 69-case fixture.",
            "No actual Microsoft Office host was available. Corpus provenance distinguishes specification-derived expectations from explicit dialect contracts; these local runs are not Office-host observations.",
        ],
    },
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def permitted(path):
    return not ({"artifacts", ".git", "node_modules", "__pycache__"} & set(path.parts)) and not path.name.endswith((".js", ".map", ".pyc"))


def selected(root, spec):
    paths = set()
    for name in spec["trees"]:
        directory = root / name
        if not directory.is_dir():
            raise ValueError(f"Missing selected directory: {directory}")
        for path in directory.rglob("*"):
            relative = path.relative_to(root)
            if permitted(relative) and path.is_file():
                paths.add(relative)
    paths.update(Path(name) for name in spec["files"])
    result = []
    for relative in sorted(paths, key=lambda value: value.as_posix()):
        path = root / relative
        if path.is_symlink() or not path.is_file() or not permitted(relative):
            raise ValueError(f"Unsafe or missing selected file: {path}")
        data = path.read_bytes()
        result.append((relative.as_posix(), data, 0o755 if path.stat().st_mode & 0o111 else 0o644))
    return result


def build_bundle(root, name):
    spec = SPECS[name]
    contents = selected(root, spec)
    destination = OUTPUT / f"{name}.tar.gz"
    temporary = destination.with_suffix(".tmp")
    with temporary.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for path, data, mode in contents:
                    item = tarfile.TarInfo(path)
                    item.size, item.mode, item.mtime = len(data), mode, 0
                    item.uid = item.gid = 0
                    item.uname = item.gname = ""
                    archive.addfile(item, io.BytesIO(data))
    temporary.replace(destination)
    return {
        "archive": destination.name,
        "sha256": sha(destination.read_bytes()),
        "bytes": destination.stat().st_size,
        "fileCount": len(contents),
        "uncompressedFileBytes": sum(len(data) for _, data, _ in contents),
        "selection": {"trees": spec["trees"], "files": spec["files"]},
        "notes": spec["notes"],
        "files": [{"path": path, "sha256": sha(data), "bytes": len(data), "mode": oct(mode)} for path, data, mode in contents],
    }


def verify(index):
    for name, entry in index["bundles"].items():
        path = OUTPUT / entry["archive"]
        if path.stat().st_size != entry["bytes"] or sha(path.read_bytes()) != entry["sha256"]:
            raise ValueError(f"Archive integrity failure: {path.name}")
        expected = {item["path"]: item for item in entry["files"]}
        seen = set()
        with tarfile.open(path, "r:gz") as archive:
            for item in archive:
                if not item.isfile() or item.name in seen or item.name not in expected:
                    raise ValueError(f"Unexpected archive member: {item.name}")
                data = archive.extractfile(item).read()
                wanted = expected[item.name]
                if len(data) != wanted["bytes"] or sha(data) != wanted["sha256"] or oct(item.mode) != wanted["mode"]:
                    raise ValueError(f"Member integrity failure: {item.name}")
                seen.add(item.name)
        if seen != set(expected) or len(seen) != entry["fileCount"]:
            raise ValueError(f"Member inventory mismatch: {name}")
        print(f"{name}: {entry['fileCount']} files, {entry['bytes']} bytes, SHA-256 {entry['sha256']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace-root", type=Path, default=Path(__file__).resolve().parents[5])
    parser.add_argument("--only", choices=sorted(SPECS), action="append")
    parser.add_argument("--verify", action="store_true", help="Verify existing archive/index bytes without rebuilding")
    args = parser.parse_args()
    if args.verify:
        verify(json.loads(INDEX.read_text()))
        return
    previous = json.loads(INDEX.read_text()) if INDEX.exists() and args.only else {}
    bundles = previous.get("bundles", {})
    for name in args.only or SPECS:
        bundles[name] = build_bundle(args.workspace_root.resolve(), name)
    index = {
        "schemaVersion": 1,
        "milestone": "office-vba-string-conformance-20261120",
        "rebuildScriptSha256": sha(Path(__file__).read_bytes()),
        "archiveFormat": "Sorted regular-file tar entries; preserved executable bit; uid/gid/mtime zero; gzip filename empty and mtime zero; compression level 9.",
        "pathConvention": "Original scratch-workspace-relative paths; raw receipt/script contents are preserved byte for byte.",
        "scope": "Source-bound local qualification evidence, including explicitly superseded attempts; not a claim about future remote main or Microsoft Office-host behavior.",
        "exclusions": ["Every artifacts directory", "SDK and package caches", "Downloaded SDK/package archives", "Generated JavaScript and source maps", "Git internals", "Checkpoint plumbing", "Unrelated runtime state"],
        "bundles": dict(sorted(bundles.items())),
    }
    INDEX.write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n")
    verify(index)


if __name__ == "__main__":
    main()
