#!/usr/bin/env python3
"""Verify the exact five-file harness correction without widening source scope."""

import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess


parser = argparse.ArgumentParser()
parser.add_argument("--repo", type=Path, required=True)
parser.add_argument("--before", required=True)
parser.add_argument("--after", required=True)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
repo = args.repo.resolve()
engine_paths = [
    "packages/quds_office_engine/tool/zotero/incoming_word_acceptance.dart",
    "packages/quds_office_engine/tool/zotero/vertical_table_acceptance.dart",
]
editor_path = "packages/quds_office_editor/tool/zotero/vertical_table_acceptance.dart"
runner_path = "docs/validation/zotero-vertical-tables-20261120/run_acceptance.py"
auditor_path = "docs/validation/zotero-vertical-tables-20261120/audit_results.py"
allowed = {*engine_paths, editor_path, runner_path, auditor_path}
standalone = [
    ("embed_test.dart", "suite5"),
    ("word_header_footer_navigation_test.dart", "suite6"),
    ("office_system_fonts_test.dart", "suite7"),
]


def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=repo)


before = git("rev-parse", args.before).decode().strip()
after = git("rev-parse", args.after).decode().strip()
changed = sorted(
    value.decode() for value in git("diff", "--name-only", "-z", before, after).split(b"\0")
    if value
)
import_pattern = re.compile(
    r"^import\s+'([^']+)'(?:\s+as\s+([A-Za-z_$][A-Za-z0-9_$]*))?\s*;",
    re.MULTILINE,
)


def dart_signature(source):
    main_at = source.index("void main()")
    prefix = source[:main_at]
    imports = list(import_pattern.finditer(prefix))
    remaining = import_pattern.sub("", prefix)
    return {
        "imports": sorted((match[1], match[2] or "") for match in imports),
        "allParsed": len(imports) == len(re.findall(r"^import\b", source, re.MULTILINE)),
        "prefix": [line for line in remaining.splitlines() if line.strip() and not line.strip().startswith("//")],
        "main": source[main_at:],
    }


def dump(node):
    return ast.dump(node, include_attributes=False)


def function(tree, name):
    return next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == name)


def remove_exact(body, expected):
    matches = [index for index, node in enumerate(body) if dump(node) == dump(expected)]
    if len(matches) != 1:
        raise AssertionError(f"Expected one exact AST match; found {len(matches)}")
    return body.pop(matches[0])


records = []
for path in sorted(allowed):
    old = git("show", f"{before}:{path}").decode()
    new = git("show", f"{after}:{path}").decode()
    record = {
        "path": path,
        "beforeSha256": hashlib.sha256(old.encode()).hexdigest(),
        "afterSha256": hashlib.sha256(new.encode()).hexdigest(),
    }
    if path in engine_paths:
        a, b = dart_signature(old), dart_signature(new)
        record.update({
            "importsAndAliasesIdentical": a["imports"] == b["imports"],
            "allImportsParsed": a["allParsed"] and b["allParsed"],
            "entireMainBodyIdentical": a["main"] == b["main"],
            "otherExecutablePrefixIdentical": a["prefix"] == b["prefix"],
        })
    elif path == editor_path:
        a, b = dart_signature(old), dart_signature(new)
        expected_imports = list(a["imports"])
        expected_main = a["main"]
        for filename, alias in standalone:
            expected_imports.remove(("../../test/" + filename, alias))
            line = f"  group('{filename}', {alias}.main);\n"
            assert expected_main.count(line) == 1
            expected_main = expected_main.replace(line, "")
        record.update({
            "exactlyThreeOriginalSuiteImportsRemoved": expected_imports == b["imports"],
            "allImportsParsed": a["allParsed"] and b["allParsed"],
            "mainUnchangedExceptThreeSuiteCalls": expected_main == b["main"],
            "otherExecutablePrefixIdentical": a["prefix"] == b["prefix"],
        })
    elif path == runner_path:
        tree = ast.parse(new)
        extension = ast.parse('''if args.suite == "editor":
    command.extend(["test/embed_test.dart",
                    "test/word_header_footer_navigation_test.dart",
                    "test/office_system_fonts_test.dart"])
''').body[0]
        remove_exact(function(tree, "main").body, extension)
        record["onlyExecutableChangeIsExactThreeFileEditorExtension"] = dump(tree) == dump(ast.parse(old))
    elif path == auditor_path:
        old_tree = ast.parse(old)
        new_tree = ast.parse(new)
        body = function(new_tree, "count").body
        suite_paths = ast.parse('''suite_paths = {row["suite"]["id"]: row["suite"]["path"] for row in events
               if row["type"] == "suite"}
''').body[0]
        remove_exact(body, suite_paths)
        fallback = ast.parse('''if ".dart" in name:
    suite = name.split(".dart", 1)[0] + ".dart"
else:
    suite = Path(suite_paths[starts[test_id]["suiteID"]]).name
''').body[0]
        replacement = ast.parse('''suite = name.split(".dart", 1)[0] + ".dart" if ".dart" in name else name.split(" ", 1)[0]
''').body[0]
        replaced = 0
        for node in ast.walk(new_tree):
            if not isinstance(node, ast.For):
                continue
            for index, child in enumerate(node.body):
                if dump(child) == dump(fallback):
                    node.body[index] = copy.deepcopy(replacement)
                    replaced += 1
        record.update({
            "oneSuiteNameFallbackReplaced": replaced == 1,
            "onlyExecutableChangeIsSuitePathNaming": dump(new_tree) == dump(old_tree),
        })
    record["passed"] = all(value for value in record.values() if isinstance(value, bool))
    records.append(record)

raw = git("diff", "--raw", before, after).decode().splitlines()
unchanged_modes = all(line.split()[:2] == [":100644", "100644"] for line in raw)
paths_before = git("ls-tree", "-r", "--name-only", before).decode().splitlines()
passed = set(changed) == allowed and unchanged_modes and all(record["passed"] for record in records)
receipt = {
    "earlierExecutionCommit": before,
    "correctedExecutionCommit": after,
    "earlierTree": git("rev-parse", f"{before}^{{tree}}").decode().strip(),
    "correctedTree": git("rev-parse", f"{after}^{{tree}}").decode().strip(),
    "allowedChangedPaths": sorted(allowed),
    "actualChangedPaths": changed,
    "exactlyAllowedPathsChanged": set(changed) == allowed,
    "fileModesUnchanged": unchanged_modes,
    "allOtherTrackedFilesIdentical": set(changed) == allowed,
    "unchangedTrackedFiles": len(paths_before) - len(allowed),
    "originalTestFilesUnchanged": sum(path.endswith("_test.dart") for path in paths_before),
    "standaloneOriginalFlutterFiles": ["test/" + filename for filename, _ in standalone],
    "files": records,
    "passed": passed,
}
args.out.parent.mkdir(parents=True, exist_ok=True)
args.out.write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps({
    "earlierExecutionCommit": before,
    "correctedExecutionCommit": after,
    "changedFiles": len(changed),
    "passed": passed,
    "receipt": str(args.out),
}, indent=2))
raise SystemExit(int(not passed))
