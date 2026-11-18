"""Run source checks with an installed genuine Dart SDK; keep actual output."""

import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
DART = shutil.which("dart")
if not DART:
    raise SystemExit("Put the qualified Dart SDK on PATH first.")

TARGETS = [
    "packages/quds_office_engine/lib/src/zotero/zotero_models.dart",
    "packages/quds_office_engine/lib/src/zotero/zotero_client.dart",
    "packages/quds_office_engine/test/zotero_item_details_test.dart",
    "packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart",
    "packages/quds_office_editor/lib/src/embed/word_zotero_library.dart",
    "packages/quds_office_editor/test/word_zotero_library_details_test.dart",
]


def inventory():
    result = {}
    for name in TARGETS:
        data = (ROOT / name).read_bytes()
        result[name] = {
            "sha256": hashlib.sha256(data).hexdigest(),
            "git_blob_sha1": hashlib.sha1(
                b"blob " + str(len(data)).encode() + b"\0" + data
            ).hexdigest(),
        }
    return result


before = inventory()
commands = [
    ("analyze", [DART, "analyze", "--fatal-infos", *TARGETS]),
    (
        "format",
        [
            DART,
            "format",
            "--language-version=3.12",
            "--output=none",
            "--set-exit-if-changed",
            *TARGETS,
        ],
    ),
    ("whitespace", ["git", "diff", "--check", "2292548eb69de2dbb5240ab9da59256f362137c6"]),
]
results = []
for name, command in commands:
    with (HERE / f"{name}.log").open("wb") as output:
        run = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    results.append({"name": name, "command": command, "cwd": str(ROOT), "exit_code": run.returncode})
after = inventory()
summary = {
    "targets": TARGETS,
    "checks": results,
    "source_unchanged": before == after,
    "source": after,
    "all_passed": before == after and all(row["exit_code"] == 0 for row in results),
}
(HERE / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps({"all_passed": summary["all_passed"], "checks": results}, indent=2))
sys.exit(0 if summary["all_passed"] else 1)
