#!/usr/bin/env python3
"""Run one bounded CI process and retain its status even on timeout/failure."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def write(path: Path, report: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n")
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, required=True)
    parser.add_argument("--deadline-file", type=Path, required=True)
    parser.add_argument("--cwd", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.timeout_seconds < 1:
        parser.error("A command and a positive timeout are required")
    if not args.name or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-_" for c in args.name):
        parser.error("Stage name must be a safe filename")
    args.report_dir.mkdir(parents=True, exist_ok=True)
    status = args.report_dir / f"{args.name}.status.json"
    log = args.report_dir / f"{args.name}.log"
    report = {"schema_version": 1, "kind": "quds-gector-stage", "name": args.name,
              "status": "running", "command": command,
              "started_utc": datetime.now(timezone.utc).isoformat(),
              "requested_timeout_seconds": args.timeout_seconds}
    write(status, report)
    started = time.monotonic()
    process = None
    try:
        remaining = int(float(args.deadline_file.read_text()) - time.time())
        if remaining < 1:
            report["status"] = "blocked"
            report["error"] = "The declared overall execution budget is exhausted"
            return 124
        effective_timeout = min(args.timeout_seconds, remaining)
        report["effective_timeout_seconds"] = effective_timeout
        write(status, report)
        print(json.dumps({"stage": args.name, "timeout_seconds": effective_timeout}), flush=True)
        with log.open("wb") as output:
            process = subprocess.Popen(command, cwd=args.cwd, stdout=output,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=effective_timeout)
                report["status"] = "passed" if code == 0 else "failed"
                report["returncode"] = code
                return 0 if code == 0 else 1
            except subprocess.TimeoutExpired:
                report["status"] = "timed_out"
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
                report["returncode"] = process.returncode
                return 124
    except Exception as error:
        report["status"] = "failed"
        report["error"] = {"type": type(error).__name__, "message": str(error)}
        return 1
    finally:
        report["elapsed_seconds"] = time.monotonic() - started
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        try:
            import resource
            usage = resource.getrusage(resource.RUSAGE_CHILDREN)
            report["child_peak_rss_bytes"] = int(usage.ru_maxrss if sys.platform == "darwin"
                                                  else usage.ru_maxrss * 1024)
            report["child_user_cpu_seconds"] = usage.ru_utime
            report["child_system_cpu_seconds"] = usage.ru_stime
        except (ImportError, AttributeError):
            report["child_peak_rss_bytes"] = None
        write(status, report)
        print(json.dumps({"stage": args.name, "status": report["status"],
                          "elapsed_seconds": report["elapsed_seconds"]}), flush=True)
        if report["status"] != "passed" and log.exists():
            with log.open("rb") as source:
                source.seek(max(0, log.stat().st_size - 8000))
                print(source.read().decode("utf-8", errors="replace"), flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
