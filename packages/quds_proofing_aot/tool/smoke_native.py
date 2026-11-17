#!/usr/bin/env python3
"""Run finite, synthetic native worker checks against real AOT dictionaries."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", required=True, type=Path)
    parser.add_argument("--rml", type=Path)
    arguments = parser.parse_args()
    env = os.environ.copy()
    if arguments.rml:
        env["RML"] = str(arguments.rml.resolve())
    executable = str(arguments.executable.resolve())
    version = json.loads(subprocess.check_output([executable, "--version"], env=env, timeout=10))
    assert version["protocol"] == 1, version
    requests = [
        {"id": 1, "action": "syntax", "langua": "German", "query": "Der kleine Hund schläft."},
        {"id": 2, "action": "morph", "langua": "German", "query": "Hund", "withparadigms": True},
        {"id": 3, "action": "syntax", "langua": "German", "query": "Ich geht."},
        {"id": 4, "action": "syntax", "langua": "Russian", "query": "Я читаю книгу."},
        {"id": 5, "action": "morph", "langua": "Russian", "query": "книгу", "withparadigms": True},
        {"id": 6, "action": "morph", "langua": "English", "query": "children", "withparadigms": True},
        {"id": 7, "action": "syntax", "langua": "English", "query": "A child reads."},
        {"id": 8, "action": "morph", "langua": "German", "query": "Hund", "withparadigms": "false"},
        {"id": 9, "action": "morph", "langua": "German", "query": "x" * 32769},
        {"id": 10, "action": "morph", "langua": "German", "query": "😀" * 16385},
        {"id": 11, "action": "morph", "langua": "German", "query": "Hund\u0000x"},
    ]
    lines = [json.dumps(request, ensure_ascii=False) for request in requests]
    lines += ["{", "x" * (256 * 1024 + 1),
              '{"id":12,"id":13,"action":"morph","langua":"German","query":"Hund"}',
              json.dumps({"id": 14, "action": "morph", "langua": "German", "query": "Hund"})]
    start = time.monotonic()
    result = subprocess.run([executable], input="\n".join(lines) + "\n", text=True,
                            capture_output=True, env=env, timeout=150)
    elapsed = time.monotonic() - start
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    assert result.stderr == "", "Engine diagnostics must not expose document text"
    responses = [json.loads(line) for line in result.stdout.splitlines()]
    assert len(responses) == len(lines), (len(responses), len(lines))
    for index in range(6):
        assert responses[index]["id"] == index + 1, responses[index]
        assert "result" in responses[index], responses[index]
    german_words = [word["str"] for sentence in responses[0]["result"]
                    for clause in sentence for word in clause["words"]]
    assert german_words == ["Der", "kleine", "Hund", "schläft", "."], german_words
    russian_words = [word["str"] for sentence in responses[3]["result"]
                     for clause in sentence for word in clause["words"]]
    assert "книгу" in russian_words, russian_words
    for index, lemma in ((1, "hund"), (4, "книга"), (5, "child")):
        serialized = json.dumps(responses[index]["result"], ensure_ascii=False).lower()
        assert lemma in serialized, responses[index]
    expected_errors = ["unsupportedLanguage", "invalidRequest", "limit", "limit",
                       "invalidRequest", "invalidRequest", "limit", "invalidRequest"]
    for response, code in zip(responses[6:14], expected_errors, strict=True):
        assert response.get("code") == code and "result" not in response, response
    assert responses[-1]["id"] == 14 and "result" in responses[-1], responses[-1]
    invalid_env = env.copy()
    invalid_env["RML"] = str(arguments.executable.resolve().parent / "missing-data-for-smoke")
    missing = subprocess.run([executable], input=lines[0] + "\n", text=True,
                             capture_output=True, env=invalid_env, timeout=15)
    assert missing.returncode == 2 and missing.stderr == "", missing
    missing_response = json.loads(missing.stdout)
    assert missing_response["code"] == "unavailable", missing_response
    assert requests[0]["query"] not in missing.stdout, missing_response
    print(json.dumps({
        "worker": version,
        "cases": len(lines) + 1,
        "passed": len(lines) + 1,
        "failed": 0,
        "elapsedSeconds": round(elapsed, 3),
        "realEngine": True,
        "syntheticTextOnly": True,
        "coverage": ["German syntax", "German paradigm", "Russian syntax", "Russian paradigm",
                     "English paradigm", "unsupported language", "strict request types",
                     "UTF-16 text limits", "JSON-line byte limit and recovery", "NUL rejection",
                     "duplicate keys", "missing runtime data", "redacted errors", "clean EOF"],
        "limits": "Finite integration smoke; does not establish general grammar accuracy.",
    }, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
