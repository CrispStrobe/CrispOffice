#!/usr/bin/env python3
"""Finite local Word table-cell qualification; never queries GitHub Actions."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["regressions", "incoming", "static", "portable"])
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--engine", type=Path, required=True,
                        help="Resolved engine workdir; canonical or a source-symlink harness")
    parser.add_argument("--dart", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    engine = args.engine.absolute()
    canonical = repo / "packages/quds_office_engine"
    out = args.out.resolve() / args.phase
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CI="true", DART_SUPPRESS_ANALYTICS="true",
               FLUTTER_SUPPRESS_ANALYTICS="true")
    records = []

    def sources():
        roots = [canonical / "lib", canonical / "test", canonical / "tool/macros",
                 canonical / "example/macros", repo / "packages/legacy_doc_parser/lib"]
        paths = {p for root in roots for p in root.rglob("*")
                 if p.is_file() and p.suffix in {".dart", ".json", ".bas"}}
        paths.update(p for p in (canonical / "test/fixtures").rglob("*") if p.is_file())
        paths.update(p for p in (repo / "packages/quds_office_editor/fonts").glob("*")
                     if p.is_file())
        paths.update(repo / name for name in ["pubspec.lock", "pubspec.yaml", ".fvmrc",
                     "analysis_options.yaml", ".github/workflows/office-macros.yml"])
        return {str(p.relative_to(repo)): digest(p) for p in sorted(paths)}

    def command(name, argv, cwd=engine, reporter=False):
        directory = out / name
        directory.mkdir(parents=True, exist_ok=True)
        before = sources()
        write(directory / "source-before.json", before)
        write(directory / "command.json", {"argv": argv, "cwd": str(cwd),
              "environment": {k: env.get(k) for k in ["CI", "DART_SUPPRESS_ANALYTICS",
                   "FLUTTER_SUPPRESS_ANALYTICS", "TMPDIR", "PUB_CACHE"]}})
        started = time.monotonic()
        with (directory / "stdout.log").open("w") as stdout, \
                (directory / "stderr.log").open("w") as stderr:
            result = subprocess.run(argv, cwd=cwd, env=env, stdout=stdout, stderr=stderr)
        after = sources()
        write(directory / "source-after.json", after)
        record = {"name": name, "exitCode": result.returncode,
                  "seconds": round(time.monotonic() - started, 3),
                  "sourceUnchanged": before == after,
                  "sourceFileCount": len(before)}
        if reporter:
            starts = {}
            done = []
            for line in (directory / "stdout.log").read_text().splitlines():
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if event.get("type") == "testStart":
                    starts[event["test"]["id"]] = event["test"]
                if event.get("type") == "testDone" and not event.get("hidden"):
                    test = starts.get(event["testID"], {})
                    if test.get("name", "").endswith(("(setUpAll)", "(tearDownAll)")):
                        continue
                    done.append({"name": test.get("name"), "suiteID": test.get("suiteID"),
                                 "result": event["result"], "skipped": event.get("skipped", False)})
            write(directory / "cases.json", done)
            record["cases"] = len(done)
            record["passed"] = sum(x["result"] == "success" and not x["skipped"] for x in done)
            record["failed"] = sum(x["result"] != "success" and not x["skipped"] for x in done)
            record["skipped"] = sum(x["skipped"] for x in done)
            record["suites"] = len({x["suiteID"] for x in done})
        write(directory / "result.json", record)
        records.append(record)
        write(out / "summary.json", records)
        print(json.dumps(record), flush=True)
        if result.returncode or before != after:
            raise SystemExit("Local qualification failed; inspect " + str(directory))
        return directory

    if args.phase == "regressions":
        tests = set(canonical.glob("test/office_macro*_test.dart"))
        tests.update(canonical.glob("test/office_vba*_test.dart"))
        tests.update(canonical / ("test/" + name + "_test.dart") for name in [
            "office_operations", "office_steps", "word_step_atomicity",
            "word_steps_vocabulary", "word_structure_steps", "table_grid_steps",
            "word_table_grid_addressing", "sheet_macro_preservation",
            "word_empty_formatted_run"])
        ordered = sorted(tests)
        write(out / "scope.json", [str(p.relative_to(canonical)) for p in ordered])
        # The Dart test loader keeps a kernel copy per suite. Small independent
        # batches bound scratch storage without dropping any selected suite.
        for start in range(0, len(ordered), 10):
            command(f"macro-batch-{start // 10 + 1:02d}",
                    [args.dart, "test", "--reporter=json", "--concurrency=2",
                     *(str(p.relative_to(canonical)) for p in ordered[start:start + 10])],
                    reporter=True)
    elif args.phase == "incoming":
        names = ["word_table_cell_margin_layout", "odt_table_padding",
                 "odt_zotero_position_guard", "odt_zotero_table_geometry",
                 "word_table_cell_margin", "word_table_nested_layout",
                 "word_table_vertical_merge_layout", "word_vertical_table_row_geometry",
                 "word_table_picture_pagination", "word_table_tall_frame_layout",
                 "word_table_tall_toc_layout", "odt_merged_table_zotero",
                 "odt_zotero_writer", "odt_zotero_export_lifecycle", "odt_reader_guards",
                 "odt_document_reader", "odt_document_writer"]
        tests = [f"test/{name}_test.dart" for name in names]
        missing = [name for name in tests if not (canonical / name).is_file()]
        if missing:
            raise SystemExit("Missing required incoming tests: " + repr(missing))
        command("incoming-engine", [args.dart, "test", "--reporter=json", "--concurrency=2",
                *tests], reporter=True)
    elif args.phase == "static":
        files = ["lib/src/automation/office_vba_language.dart",
                 "lib/src/automation/office_operations.dart",
                 "lib/src/automation/operations/word_steps.dart",
                 "lib/src/automation/operations/word_table_cell_text_steps.dart",
                 "lib/src/word/serial/word_deserializer.dart",
                 "test/office_macro_word_table_cells_test.dart",
                 "test/office_vba_word_table_cells_test.dart",
                 "test/office_vba_word_table_cells_conformance_test.dart",
                 "test/office_vba_word_table_cells_integration_test.dart",
                 "test/word_empty_formatted_run_test.dart",
                 "tool/macros/web_vba_word_table_cells_smoke.dart"]
        command("format", [args.dart, "format", "--language-version=3.12",
                "--output=none", "--set-exit-if-changed", *files])
        command("analysis", [args.dart, "analyze", "--fatal-infos", *files])
        command("whitespace", ["git", "diff", "--check"], cwd=repo)
    else:
        jobs = [("table-report", "WORD_TABLE_BAS_BASE64",
                 "example/macros/word_table_report.bas",
                 "tool/macros/web_vba_word_table_cells_smoke.dart")]
        for corpus in ["word_table_cells_v1", "word_paragraphs_v1", "word_numeric_intrinsics_v1"]:
            jobs.append((corpus, "VBA_CONFORMANCE_BASE64",
                         f"test/fixtures/vba_conformance/{corpus}.json",
                         "tool/macros/web_vba_conformance.dart"))
        parity = []
        for name, define, input_file, script in jobs:
            encoded = base64.b64encode((canonical / input_file).read_bytes()).decode()
            option = f"-D{define}={encoded}"
            vm = command(name + "-vm", [args.dart, option, script])
            js_file = out / (name + ".js")
            command(name + "-compile", [args.dart, "compile", "js", "-O1", option,
                    script, "-o", str(js_file)])
            js = command(name + "-node", ["node", "-e",
                         "globalThis.self=globalThis;require(process.argv[1])", str(js_file)])
            vm_bytes = (vm / "stdout.log").read_bytes()
            js_bytes = (js / "stdout.log").read_bytes()
            receipt = {"name": name, "equal": vm_bytes == js_bytes,
                       "inputSha256": digest(canonical / input_file),
                       "outputSha256": hashlib.sha256(vm_bytes).hexdigest(),
                       "javascriptSha256": digest(js_file)}
            parity.append(receipt)
            write(out / "parity.json", parity)
            if not receipt["equal"]:
                raise SystemExit("VM/JavaScript receipts differ: " + name)


if __name__ == "__main__":
    main()
