#!/usr/bin/env python3
"""Run finite, synthetic native worker checks against real AOT dictionaries."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
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
    began = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="quds-aot-smoke-") as working_directory:
        result = subprocess.run([executable], input="\n".join(lines) + "\n", text=True,
                                capture_output=True, env=env, timeout=150, cwd=working_directory)
        assert not list(Path(working_directory).iterdir()), "Analysis must not create document/log files"
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
    source_queries = [
        "Es ist schön, dir zu helfen.",
        "Wir versuchen, dir zu helfen.",
        "Äpfel sind süß.",
        "Ich gehe.\nWir gehen.",
        "Ich denke, dass du gehst.",
        "😀 Der kleine Hund schläft.",
    ]
    source_requests = [json.dumps({"id": index, "action": "syntax", "langua": "German", "query": query},
                                  ensure_ascii=False) for index, query in enumerate(source_queries)]
    with tempfile.TemporaryDirectory(prefix="quds-aot-source-smoke-") as working_directory:
        source_result = subprocess.run([executable], input="\n".join(source_requests) + "\n", text=True,
                                       capture_output=True, env=env, timeout=30, cwd=working_directory)
        assert not list(Path(working_directory).iterdir()), "Syntax must not create document/log files"
    assert source_result.returncode == 0 and source_result.stderr == "", source_result
    source_responses = [json.loads(line) for line in source_result.stdout.splitlines()]
    assert len(source_responses) == len(source_queries)
    for index, (query, response) in enumerate(zip(source_queries, source_responses, strict=True)):
        assert "result" in response, response
        words = [word for sentence in response["result"] for clause in sentence for word in clause["words"]]
        groups = [group for sentence in response["result"] for clause in sentence
                  for variant in clause["variants"] for group in variant["groups"]]
        assert all(all(ord(character) >= 32 for character in group["descr"]) for group in groups), groups
        if index == len(source_queries) - 1:
            assert all("sourceStart" not in word for word in words), words
            continue
        utf16 = query.encode("utf-16-le")
        cursor = 0
        for word in words:
            assert all(key in word for key in ("sourceStart", "sourceEnd", "sourceText")), word
            start, end = word["sourceStart"], word["sourceEnd"]
            assert start >= cursor and end > start, word
            assert not utf16[cursor * 2:start * 2].decode("utf-16-le").strip(), word
            assert utf16[start * 2:end * 2].decode("utf-16-le") == word["sourceText"], word
            cursor = end
        assert not utf16[cursor * 2:].decode("utf-16-le").strip(), words
        if index < 2:
            infinitives = [word for word in words if word["str"] == "zu-helfen"]
            assert len(infinitives) == 1 and infinitives[0]["sourceText"] == "helfen", words
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
        "cases": len(lines) + len(source_queries) + 1,
        "passed": len(lines) + len(source_queries) + 1,
        "failed": 0,
        "elapsedSeconds": round(time.monotonic() - began, 3),
        "realEngine": True,
        "syntheticTextOnly": True,
        "coverage": ["German syntax", "German paradigm", "Russian syntax", "Russian paradigm",
                     "English paradigm", "unsupported language", "strict request types",
                     "UTF-16 text limits", "JSON-line byte limit and recovery", "NUL rejection",
                     "duplicate keys", "missing runtime data", "redacted errors", "clean EOF",
                     "no document/log file writes", "exact original UTF-16 source spans",
                     "normalized German infinitives", "unsupported Unicode alignment abstention",
                     "owned syntax description strings"],
        "limits": "Finite integration smoke; does not establish general grammar accuracy.",
    }, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
