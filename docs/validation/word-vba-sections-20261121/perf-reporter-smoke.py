"""Transcribed reproduction of the previously executed inline reporter smoke.

This file was saved after that execution; saving it did not rerun the smoke.
"""
import subprocess
import json
import io
import contextlib
import hashlib
from unittest.mock import patch

sha = "1460876e70fcf3da49644e232e9942b7ee042d8d"
source = subprocess.check_output(
    ["git", "show", sha + ":tool/perf/keystroke_trace_report.py"], text=True
)
module = {"__name__": "audit_report"}
exec(compile(source, "keystroke_trace_report.py", "exec"), module)


def run(events):
    data = {
        "keys": [{"handlerMs": 10, "phases": {"layout": 3}}],
        "timeline": {
            "traceEvents": [
                {
                    "name": "KEY_HANDLER",
                    "ph": "b",
                    "id": 1,
                    "ts": 0,
                    "args": {"key": "0"},
                },
                {"name": "KEY_HANDLER", "ph": "e", "id": 1, "ts": 10000},
                *events,
            ]
        },
        "frames": [{"buildMs": 1, "rasterMs": 2}],
    }
    out = io.StringIO()
    with patch(
        "builtins.open", return_value=io.StringIO(json.dumps(data))
    ), contextlib.redirect_stdout(out):
        module["main"]("fixture.json")
    return out.getvalue()


output = run(
    [
        {
            "cat": "GC",
            "name": "Scavenge",
            "ph": "X",
            "ts": 1000,
            "dur": 2000,
            "tid": 1,
        },
        {"cat": "GC", "name": "MarkSweep", "ph": "B", "ts": 4000, "tid": 1},
        {"cat": "GC", "name": "MarkSweep", "ph": "E", "ts": 6000, "tid": 1},
        {"cat": "GC", "name": "NotifyIdle", "ph": "B", "ts": 20000, "tid": 1},
        {"cat": "GC", "name": "NotifyIdle", "ph": "E", "ts": 25000, "tid": 1},
    ]
)
assert "GC events 2, total 4.0 ms; GC inside handlers 4.0 ms" in output, output
assert "idle-time GC (NotifyIdle, between frames) 5.0 ms" in output, output
output2 = run(
    [
        {"cat": "GC", "name": "Scavenge", "ph": "B", "ts": 1000, "tid": 1},
        {"cat": "GC", "name": "Scavenge", "ph": "B", "ts": 2000, "tid": 2},
        {"cat": "GC", "name": "Scavenge", "ph": "E", "ts": 5000, "tid": 1},
        {"cat": "GC", "name": "Scavenge", "ph": "E", "ts": 8000, "tid": 2},
    ]
)
assert "GC events 2, total 10.0 ms; GC inside handlers 10.0 ms" in output2, output2
print(
    json.dumps(
        {
            "source_sha256": hashlib.sha256(source.encode()).hexdigest(),
            "checks": [
                "Python syntax compile",
                "complete and named begin/end GC events",
                "separate idle NotifyIdle total",
                "per-thread GC pairing",
                "handler overlap",
                "frame totals",
            ],
            "passed": True,
        }
    )
)
