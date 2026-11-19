#!/usr/bin/env python3
"""Run unchanged slide test assertions using direct production-file imports."""
import argparse
import datetime
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--repo", type=Path, required=True)
parser.add_argument("--dart", type=Path, required=True)
parser.add_argument("--package-config", type=Path, required=True)
parser.add_argument("--test-runner", type=Path, required=True)
args = parser.parse_args()
repo = args.repo.resolve()
base = repo / "packages/quds_office_engine/lib"
output = Path(__file__).resolve().parent
test_dir = output / "adapted_tests"
test_dir.mkdir(exist_ok=True)
imports = {
    "slide_import_fidelity_test.dart": [
        "src/opc/opc_archive.dart",
        "src/opc/content_types.dart",
        "src/opc/relationships.dart",
        "src/slide/model/pml_presentation.dart",
        "src/slide/serial/slide_serial.dart",
        "src/visual/office_visual.dart",
        "src/xml/namespaces.dart",
    ],
    "slide_rich_text_explicit_style_test.dart": [
        "src/opc/opc_archive.dart",
        "src/slide/model/pml_presentation.dart",
        "src/slide/serial/slide_serial.dart",
        "src/xml/namespaces.dart",
        "src/xml/xml_node.dart",
    ],
}
seen = set()
external = set()


def walk(path):
    path = path.resolve()
    if path in seen:
        return
    seen.add(path)
    for directive in re.findall(r"(?:import|export|part)\s+([^;]+);", path.read_text()):
        for ref in re.findall(r"[\"']([^\"']+\.dart)[\"']", directive):
            if ref.startswith("package:"):
                external.add(ref)
            elif not ref.startswith("dart:"):
                walk(path.parent / ref)


tests = []
for name, sources in imports.items():
    original = repo / "packages/quds_office_engine/test" / name
    adapted = test_dir / name
    text = original.read_text()
    barrel = "import 'package:quds_office_engine/quds_office_engine.dart';"
    assert text.count(barrel) == 1
    replacement = "\n".join("import '" + (base / path).as_uri() + "';" for path in sources)
    updated = text.replace(barrel, replacement)
    adapted.write_text(updated)
    diff = "".join(difflib.unified_diff(
        text.splitlines(True), updated.splitlines(True),
        fromfile=str(original.relative_to(repo)), tofile="adapted_tests/" + name,
    ))
    diff_path = output / (name + ".imports.diff")
    diff_path.write_text(diff)
    tests.append({
        "original": str(original.relative_to(repo)),
        "originalSha256": sha(original),
        "adapted": str(adapted.relative_to(output)),
        "adaptedSha256": sha(adapted),
        "importDiff": str(diff_path.relative_to(output)),
        "importDiffSha256": sha(diff_path),
        "testDeclarationCount": len(re.findall(r"\btest\s*\(", text)),
    })
    for path in sources:
        walk(base / path)

source_hashes = {str(path.relative_to(repo)): sha(path) for path in sorted(seen)}
source_graph_sha = hashlib.sha256(
    json.dumps(source_hashes, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()
command = [
    str(args.dart.resolve()), "--packages=" + str(args.package_config.resolve()),
    str(args.test_runner.resolve()),
    *(str(output / test["adapted"]) for test in tests), "--reporter", "expanded",
]
receipt = {
    "scope": "Fifteen existing repository test declarations; only the engine barrel import is replaced with direct file imports. Test assertions and all production sources are unchanged. No mocks or copied production implementation.",
    "baselineCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
    "uncommittedIncomingRichTextCommit": "780422316b4e37989e01ac871dd2956fbd2c8908",
    "tests": tests,
    "sourceHashes": source_hashes,
    "sourceGraphSha256": source_graph_sha,
    "sourceFileCount": len(source_hashes),
    "externalProductionImports": sorted(external),
    "testVersion": "1.31.1",
    "cryptoVersion": "3.0.7 (cached harness; full workspace lock has 3.0.8)",
    "runtime": subprocess.check_output([str(args.dart), "--version"], text=True, stderr=subprocess.STDOUT).strip(),
    "packageConfigSha256": sha(args.package_config),
    "reproductionScriptSha256": sha(Path(__file__)),
    "command": command,
    "commandWorkingDirectory": str(args.package_config.resolve().parent.parent),
    "formatQualification": "Incoming rich-text source already formatted; incoming explicit-style test normalized by Dart formatter. Lint configuration unavailable because package:lints/recommended.yaml cannot resolve.",
    "limitations": [
        "This executes the slide import/model and explicit-style serialization tests only. It does not execute MIME/mail, PDF, Flutter widgets, or the full engine barrel.",
        "The cached crypto version differs from the workspace lock; this is not a full workspace dependency qualification.",
        "Exact-import slide_text_fidelity_test.dart still reaches unavailable characters through OfficeIsolateSave and Word serialization/layout.",
        "Exact-import slide_render_fidelity_test.dart reaches unavailable characters and image through OfficePdfExport and PDF/Word layout.",
        "No GitHub Actions queried, awaited, or used as a gate.",
    ],
    "result": "pending",
}
receipt_path = output / "qualification.json"
receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
with (output / "tests.log").open("w") as log:
    result = subprocess.run(command, cwd=receipt["commandWorkingDirectory"], stdout=log, stderr=subprocess.STDOUT, timeout=180)
after_changed = [path for path, digest in source_hashes.items() if sha(repo / path) != digest]
test_changes = [test["original"] for test in tests if sha(repo / test["original"]) != test["originalSha256"] or sha(output / test["adapted"]) != test["adaptedSha256"]]
log_text = (output / "tests.log").read_text()
match = re.search(r"\+(\d+): All tests passed!", log_text)
passed = int(match.group(1)) if match else 0
receipt.update({
    "result": "passed" if result.returncode == 0 and passed == 15 and not after_changed and not test_changes else "failed",
    "exitCode": result.returncode,
    "passedTests": passed,
    "completedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "sourceHashVerificationAfterExecution": {"verified": len(source_hashes) - len(after_changed), "changed": after_changed},
    "testHashVerificationAfterExecution": {"changed": test_changes},
    "logSha256": sha(output / "tests.log"),
})
receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
print(log_text, end="")
print(json.dumps({"result": receipt["result"], "passedTests": passed, "sourceFiles": len(source_hashes), "sourceGraphSha256": source_graph_sha, "receiptSha256": sha(receipt_path)}))
raise SystemExit(0 if receipt["result"] == "passed" else 1)
