"""Check tracked Dart input continuity of the separately retained Node cohort."""

import argparse
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import yaml

parser = argparse.ArgumentParser()
parser.add_argument("--repo", required=True, type=Path)
parser.add_argument("--head", required=True)
parser.add_argument("--output", required=True, type=Path)
args = parser.parse_args()
base = "5569c055a021c893e941fc54d40499ad9d96a5db"


def git(*command):
    return subprocess.check_output(["git", "-C", str(args.repo), *command])


def tree(ref):
    result = {}
    for row in git("ls-tree", "-rz", ref).split(b"\0"):
        if row:
            metadata, path = row.split(b"\t", 1)
            result[path.decode()] = metadata.decode()
    return result


trees = {ref: tree(ref) for ref in (base, args.head)}
packages = {}
for path in trees[base]:
    if path.endswith("/pubspec.yaml"):
        data = yaml.safe_load(git("show", base + ":" + path))
        if isinstance(data, dict) and isinstance(data.get("name"), str):
            # A package example may duplicate another package's name; only
            # root workspace packages and vendored package roots are needed.
            if len(PurePosixPath(path).parts) == 3 and path.startswith(("packages/", "third_party/")):
                packages[data["name"]] = str(PurePosixPath(path).parent)

plan_path = "docs/validation/office-main-completion-20261119/node-plan.json"
plan = json.loads(git("show", base + ":" + plan_path))
entries = [str(PurePosixPath(group["cwd"]) / test) for group in plan["groups"] for test in group["tests"]]
directive = re.compile(r"^\s*(import|export|part)\s+(['\"])(.*?)\2(.*?);", re.M | re.S)
conditions = re.compile(r"\bif\s*\(\s*(dart\.library\.[a-z_]+)\s*\)\s*(['\"])(.*?)\2")
platform_flags = {"dart.library.io": False, "dart.library.html": True, "dart.library.js_interop": True, "dart.library.ui": False}


def closure(ref, entry):
    pending = [entry]
    seen = set()
    external = set()
    selected_conditions = []
    package_manifests = set()
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        assert path in trees[ref], (ref, path)
        seen.add(path)
        text = git("show", ref + ":" + path).decode()
        for found in directive.finditer(text):
            uri = found[3]
            alternatives = list(conditions.finditer(found[4]))
            for alternative in alternatives:
                condition, target = alternative[1], alternative[3]
                assert condition in platform_flags, (path, condition)
                selected_conditions.append({"path": path, "condition": condition, "value": platform_flags[condition], "target": target})
                if platform_flags[condition]:
                    uri = target
                    break
            if uri.startswith("dart:"):
                external.add(uri)
            elif uri.startswith("package:"):
                package, tail = uri[len("package:"):].split("/", 1)
                if package in packages:
                    pending.append(str(PurePosixPath(packages[package]) / "lib" / tail))
                    package_manifests.add(packages[package] + "/pubspec.yaml")
                else:
                    external.add("package:" + package)
            else:
                resolved = (args.repo / PurePosixPath(path).parent / uri).resolve().relative_to(args.repo.resolve()).as_posix()
                pending.append(resolved)
    return {"paths": sorted(seen), "external": sorted(external), "conditional_decisions": selected_conditions, "package_manifests": sorted(package_manifests)}


checks = []
for entry in entries:
    before, after = closure(base, entry), closure(args.head, entry)
    assert before == after, entry
    bound = before["paths"] + before["package_manifests"] + ["pubspec.yaml", "pubspec.lock", "analysis_options.yaml", ".fvmrc", plan_path]
    changed = [path for path in bound if trees[base].get(path) != trees[args.head].get(path)]
    assert not changed, (entry, changed)
    checks.append({"entry": entry, "tracked_dart_inputs": len(before["paths"]), "tracked_paths": before["paths"], "package_manifests": before["package_manifests"], "external_dependencies": before["external"], "conditional_decisions": before["conditional_decisions"], "all_tracked_modes_and_blobs_identical": True})
report = {
    "historically_executed_source": base,
    "compared_source": args.head,
    "historical_node_cases": 35,
    "historical_node_suites": 7,
    "tracked_dart_closure_checks": checks,
    "new_node_execution": False,
    "added_to_fresh_case_totals": False,
    "method": "Tracked import/export/part closure comparison with the Node JavaScript target's conditional library choices, plus package manifests, root configuration and lock bytes. Hosted/SDK implementation bytes are outside this static check; the original runtime receipt remains attributed to its original execution.",
    "passed": True,
}
args.output.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"passed": True, "historical_node_cases": 35, "historical_node_suites": 7, "checks": [{"entry": row["entry"], "tracked_dart_inputs": row["tracked_dart_inputs"]} for row in checks]}, indent=2))
