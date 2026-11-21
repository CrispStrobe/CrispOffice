#!/usr/bin/env python3
"""Run the bounded Zotero host/shortcut regression cohorts with raw receipts."""
import argparse, datetime, hashlib, json, os, pathlib, shutil, subprocess, time

STUDIO = [
    "test/studio_shortcuts_test.dart",
    "test/studio_settings_test.dart",
    "test/studio_shortcut_dispatch_test.dart",
    "test/suite_workspace_mail_shortcuts_test.dart",
    "test/studio_zotero_shortcuts_test.dart",
    "test/studio_zotero_citing_transport_test.dart",
    "test/studio_zotero_odt_export_test.dart",
    "test/studio_odt_open_test.dart",
]
EDITOR = [
    "test/word_zotero_dialog_test.dart",
    "test/word_zotero_citing_dialog_test.dart",
    "test/word_zotero_transfer_dialog_test.dart",
    "test/word_zotero_children_dialog_test.dart",
    "test/word_zotero_source_occurrences_dialog_test.dart",
    "test/word_zotero_stored_details_dialog_test.dart",
    "test/word_zotero_navigation_dialog_test.dart",
    "test/word_zotero_dialog_scaling_test.dart",
    "test/word_zotero_note_preview_test.dart",
]

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def git(repo, *args):
    return subprocess.check_output(["git", *args], cwd=repo, text=True).strip()

def snapshot(repo):
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0")
    return {
        p: digest(repo / p) for p in paths if p and (repo / p).is_file()
        and (p.startswith(("packages/", "third_party/", "apps/")) or p in ("pubspec.yaml", "pubspec.lock"))
    }

def parse_events(path, cwd, repo):
    suites, started, ended, errors, dones = {}, {}, {}, [], []
    for line in path.read_text(errors="replace").splitlines():
        try:
            e = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(e, dict):
            continue
        kind = e.get("type")
        if kind == "suite":
            suites[e["suite"]["id"]] = e["suite"]
        elif kind == "testStart":
            started[e["test"]["id"]] = e["test"]
        elif kind == "testDone":
            ended[e["testID"]] = e
        elif kind == "error":
            errors.append(e)
        elif kind == "done":
            dones.append(e)
    visible = []
    for key, end in ended.items():
        if end.get("hidden", False):
            continue
        start = started.get(key, {})
        suite = suites.get(start.get("suiteID"), {})
        raw = suite.get("path", "")
        p = pathlib.Path(raw) if raw else cwd
        if not p.is_absolute():
            p = cwd / p
        try:
            normalized = str(p.resolve().relative_to(repo.resolve()))
        except ValueError:
            normalized = str(p)
        visible.append({"suite": normalized, "name": start.get("name", ""),
                        "result": end.get("result"), "skipped": end.get("skipped", False)})
    return {"visible_tests": visible, "pass": sum(e["result"] == "success" and not e["skipped"] for e in visible),
            "fail": sum(e["result"] != "success" for e in visible), "skip": sum(e["skipped"] for e in visible),
            "errors": errors, "done": dones, "unfinished_ids": sorted(set(started) - set(ended))}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--phase", choices=["baseline", "studio", "editor", "all"], default="all")
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    sdk = pathlib.Path(os.environ["FLUTTER_ROOT"])
    dart = sdk / "bin/cache/dart-sdk/bin/dart"
    flutter = [str(dart), str(sdk / "bin/cache/flutter_tools.snapshot"), "--no-version-check"]
    before = snapshot(repo)
    (out / "source-inputs.before.json").write_text(json.dumps(before, indent=2) + "\n")
    record = {"phase": args.phase, "source_commit": git(repo, "rev-parse", "HEAD"),
              "source_tree": git(repo, "rev-parse", "HEAD^{tree}"),
              "initial_status": git(repo, "status", "--porcelain"),
              "started_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "source_input_count": len(before), "runs": []}
    def save():
        (out / "receipt.json").write_text(json.dumps(record, indent=2) + "\n")
    save()
    editor = repo / "packages/quds_office_editor"
    cohorts = []
    if args.phase == "baseline":
        cohorts.append(("baseline-delayed-host", editor / "example", [
            "test/studio_zotero_shortcuts_test.dart", "--plain-name",
            "invalidates a pending Zotero publication"]))
    if args.phase in ("studio", "all"):
        for suite in STUDIO:
            cohorts.append(("studio-" + pathlib.Path(suite).stem, editor / "example", [suite]))
    if args.phase in ("editor", "all"):
        for suite in EDITOR:
            cohorts.append(("editor-" + pathlib.Path(suite).stem, editor, [suite]))
    for name, cwd, tests in cohorts:
        private_tmp = out / ("tmp-" + name)
        private_tmp.mkdir(exist_ok=True)
        env = dict(os.environ, TMPDIR=str(private_tmp))
        command = flutter + ["test", "--no-pub", "--concurrency=2", "--reporter=json"] + tests
        log = out / (name + ".jsonl")
        print("START " + name, flush=True)
        start = time.monotonic()
        with log.open("wb") as f:
            result = subprocess.run(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.STDOUT)
        events = parse_events(log, cwd, repo)
        item = {"name": name, "cwd": str(cwd.relative_to(repo)), "command": command,
                "exit_code": result.returncode, "duration_seconds": round(time.monotonic() - start, 3),
                "log": log.name, "log_sha256": digest(log), **events}
        record["runs"].append(item)
        save()
        print(json.dumps({"name": name, "exit": result.returncode,
                          "pass": events["pass"], "fail": events["fail"], "skip": events["skip"],
                          "errors": len(events["errors"]), "unfinished": len(events["unfinished_ids"])}), flush=True)
        shutil.rmtree(private_tmp)
    after = snapshot(repo)
    (out / "source-inputs.after.json").write_text(json.dumps(after, indent=2) + "\n")
    record["source_inputs_unchanged"] = before == after
    record["final_status"] = git(repo, "status", "--porcelain")
    record["finished_at_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    record["accepted"] = args.phase != "baseline" and before == after and all(
        r["exit_code"] == 0 and r["pass"] > 0 and r["fail"] == 0 and r["skip"] == 0
        and not r["errors"] and not r["unfinished_ids"]
        and len(r["done"]) == 1 and r["done"][0].get("success") is True for r in record["runs"])
    save()
    print(json.dumps({"phase": args.phase, "accepted": record["accepted"],
                      "inputs_unchanged": before == after}), flush=True)
    return 0 if args.phase == "baseline" or record["accepted"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
