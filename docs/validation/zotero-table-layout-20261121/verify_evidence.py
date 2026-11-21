#!/usr/bin/env python3
"""Verify retained archives, accepted JSON test logs and exact Git source binding.

No archive members are extracted and no network or CI service is contacted.
An archive-only copy can use --skip-source-check; its result explicitly reports
that production source binding was not checked.
"""

import argparse
import hashlib
import io
import json
import posixpath
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
from urllib.parse import unquote, urlsplit


class VerificationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def safe_path(value):
    require(isinstance(value, str) and value and "\\" not in value and
            "\0" not in value and not PurePosixPath(value).is_absolute() and
            not re.match(r"^[A-Za-z]:", value) and
            all(part not in ("", ".", "..") for part in value.split("/")),
            f"Unsafe relative path: {value!r}")
    return value


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify_bytes(data, record, label):
    require(type(record["bytes"]) is int and record["bytes"] >= 0 and
            len(data) == record["bytes"], f"Byte count mismatch: {label}")
    require(isinstance(record["sha256"], str) and
            re.fullmatch(r"[0-9a-f]{64}", record["sha256"]) and
            digest(data) == record["sha256"], f"SHA-256 mismatch: {label}")


def archive_members(data, record, wanted):
    verify_bytes(data, record, record["path"])
    expected = {}
    for item in record["members"]:
        name = safe_path(item["path"])
        require(name not in expected, f"Duplicate indexed member: {name}")
        expected[name] = item
    retained = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
        members = archive.getmembers()
        require(len(members) == len(expected) and
                {member.name for member in members} == set(expected),
                f"Archive member list mismatch: {record['path']}")
        for member in members:
            name = safe_path(member.name)
            require(member.type in (tarfile.REGTYPE, tarfile.AREGTYPE) and
                    member.sparse is None, f"Nonregular archive member: {name}")
            require(member.size == expected[name]["bytes"],
                    f"Tar member size mismatch: {name}")
            content = archive.extractfile(member).read()
            verify_bytes(content, expected[name], name)
            if name in wanted:
                retained[name] = content
    return retained


def suite_path(value, package_root, recorded_root):
    require(isinstance(value, str) and value, "Missing suite path")
    if value.startswith("file:"):
        uri = urlsplit(value)
        require(uri.netloc in ("", "localhost") and not uri.query and
                not uri.fragment, f"Unsupported suite URI: {value}")
        value = unquote(uri.path)
    value = posixpath.normpath(value)
    if PurePosixPath(value).is_absolute():
        root = posixpath.normpath(recorded_root).rstrip("/") + "/"
        require(value.startswith(root), f"Suite outside recorded repository: {value}")
        value = value[len(root):]
    else:
        value = posixpath.normpath(posixpath.join(package_root, value))
    return safe_path(value)


def test_run(data, run, recorded_root):
    package_root = safe_path(run["package_root"])
    suites, tests, completed, visible = {}, {}, set(), set()
    passed = hidden = 0
    done = False
    for number, line in enumerate(data.decode("utf-8").splitlines(), 1):
        if not line.strip():
            continue
        require(not done, f"Events after done: {run['name']}:{number}")
        event = json.loads(line)
        kind = event["type"]
        require(kind != "error", f"Error event: {run['name']}:{number}")
        if kind == "suite":
            suite = event["suite"]
            require(suite["id"] not in suites, "Duplicate suite ID")
            suites[suite["id"]] = suite_path(
                suite["path"], package_root, recorded_root)
        elif kind == "testStart":
            test = event["test"]
            require(test["id"] not in tests and isinstance(test["name"], str),
                    "Duplicate test ID or invalid test name")
            tests[test["id"]] = test
        elif kind == "testDone":
            test_id = event["testID"]
            require(test_id in tests and test_id not in completed,
                    "Missing or duplicate test completion")
            require(event["result"] == "success" and event["skipped"] is False,
                    f"Failed or skipped test: {run['name']}:{test_id}")
            require(type(event["hidden"]) is bool, "Invalid hidden flag")
            test = tests[test_id]
            require(test["suiteID"] in suites, "Unknown test suite")
            completed.add(test_id)
            if event["hidden"]:
                hidden += 1
            else:
                passed += 1
                visible.add(test_id)
        elif kind == "done":
            require(event["success"] is True, f"Unsuccessful run: {run['name']}")
            done = True
    require(done and completed == set(tests), f"Incomplete run: {run['name']}")
    # Preserve separate parameter instances sharing a display name. Number only
    # visible cases in testStart order, independent of completion order; hidden
    # loading/setup successes never consume an occurrence ordinal.
    occurrences, identities = {}, set()
    for test_id, test in tests.items():
        if test_id in visible:
            name = (suites[test["suiteID"]], test["name"])
            occurrences[name] = occurrences.get(name, 0) + 1
            identities.add((*name, occurrences[name]))
    paths = set(suites.values())
    for field, actual in (("expected_suites", len(paths)), ("expected_passed", passed)):
        require(type(run[field]) is int and run[field] >= 0 and run[field] == actual,
                f"{run['name']} {field}: expected {run[field]}, observed {actual}")
    return {"name": run["name"], "suites": len(paths), "passed": passed,
            "distinct_cases": len(identities), "distinct_case_names": len(occurrences),
            "hidden_successes_omitted": hidden}, identities, paths


def git(directory, *args):
    result = subprocess.run(["git", "-C", str(directory), *args],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result.returncode == 0, "Git source check failed: " +
            result.stderr.decode("utf-8", errors="replace").strip())
    return result.stdout


def verify(index_path, skip_source_check=False):
    index = json.loads(index_path.read_text(encoding="utf-8"))
    require(index["schema"] == 1, "Unsupported index schema")
    commit, tree = index["production_commit"], index["production_tree"]
    require(all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", value)
                for value in (commit, tree)), "Expected full production Git object IDs")
    recorded_root = index["repository_root_at_execution"]
    require(isinstance(recorded_root, str) and PurePosixPath(recorded_root).is_absolute(),
            "Recorded repository root must be absolute")
    wanted, run_names = {}, set()
    for run in index["test_runs"]:
        require(isinstance(run["name"], str) and run["name"] and
                run["name"] not in run_names, "Missing or duplicate run name")
        run_names.add(run["name"])
        wanted.setdefault(safe_path(run["archive"]), set()).add(safe_path(run["member"]))
    archives, member_count = {}, 0
    for record in index["archives"]:
        path = safe_path(record["path"])
        require(path not in archives, f"Duplicate archive: {path}")
        archive_path = index_path.parent / path
        require(archive_path.is_file() and not archive_path.is_symlink(),
                f"Archive must be a regular file: {path}")
        archives[path] = archive_members(archive_path.read_bytes(), record, wanted.get(path, set()))
        member_count += len(record["members"])
    summaries, identities, suite_paths = [], set(), set()
    for run in index["test_runs"]:
        require(run["archive"] in archives and run["member"] in archives[run["archive"]],
                f"Missing accepted event log: {run['name']}")
        summary, cases, paths = test_run(archives[run["archive"]][run["member"]], run, recorded_root)
        summaries.append(summary)
        identities.update(cases)
        suite_paths.update(paths)
    sources = index["tracked_sources"]
    require(isinstance(sources, dict) and sources, "Missing tracked source manifest")
    for path, expected in sources.items():
        safe_path(path)
        require(isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected),
                f"Invalid source hash: {path}")
    if not skip_source_check:
        repository = git(index_path.parent, "rev-parse", "--show-toplevel").decode().strip()
        require(git(repository, "rev-parse", commit + "^{commit}").decode().strip() == commit,
                "Production object is not the recorded commit")
        require(git(repository, "rev-parse", commit + "^{tree}").decode().strip() == tree,
                "Production tree mismatch")
        for path, expected in sources.items():
            require(digest(git(repository, "show", commit + ":" + path)) == expected,
                    f"Production source mismatch: {path}")
    executions = sum(run["passed"] for run in summaries)
    return {"verified": True, "production_commit": commit, "production_tree": tree,
            "source_check": {"checked": not skip_source_check,
                             "tracked_files": len(sources),
                             "status": "not checked (--skip-source-check)" if skip_source_check else "verified"},
            "archives_verified": len(archives), "members_verified": member_count,
            "runs": summaries, "accepted_executions": executions,
            "distinct_cases": len(identities), "distinct_suites": len(suite_paths),
            "distinct_case_names": len({(suite, name) for suite, name, _ in identities}),
            "repeated_executions": executions - len(identities),
            "case_identity": ["repository-relative suite path", "test name",
                              "visible occurrence ordinal within suite and name (testStart order)"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index", type=Path, default=Path(__file__).with_name("index.json"))
    parser.add_argument("--skip-source-check", action="store_true")
    args = parser.parse_args()
    try:
        result = verify(args.index.resolve(), args.skip_source_check)
    except (VerificationError, OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        print(f"Evidence verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
