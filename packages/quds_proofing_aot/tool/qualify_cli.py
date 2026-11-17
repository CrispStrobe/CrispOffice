#!/usr/bin/env python3
"""Run a finite, synthetic local qualification of the compiled production CLI.

Build the native runtime, compile tool/aot.dart with `dart compile exe`, then
pass --cli and --worker. No daemon, server, external endpoint, or CI is used.
This small regression panel does not estimate general grammar accuracy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", required=True, type=Path)
    parser.add_argument("--worker", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    options = parser.parse_args()
    cli, worker = options.cli.resolve(), options.worker.resolve()
    results: list[dict[str, object]] = []
    options.output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="quds-aot-cli-") as directory:
        cwd = Path(directory)

        def run(name: str, args: list[str], *, text: str | None = None,
                expected_exit: int = 0) -> dict[str, object]:
            command = [str(cli), "--executable", str(worker), *args]
            if text is not None:
                command.append("--stdin")
            started = time.monotonic()
            process = subprocess.run(command, input=text, text=True, encoding="utf-8",
                                     capture_output=True, cwd=cwd, timeout=70)
            record: dict[str, object] = {
                "name": name, "input": text, "arguments": args,
                "exitCode": process.returncode,
                "elapsedSeconds": round(time.monotonic() - started, 6),
            }
            record["response"] = json.loads(process.stdout if process.stdout.strip()
                                           else process.stderr)
            results.append(record)
            # Keep the actual observation even if a later assertion fails.
            options.output.write_text(json.dumps({"status": "in-progress", "results": results},
                                                indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            if process.returncode != expected_exit:
                raise AssertionError(f"{name}: unexpected exit code {process.returncode}")
            if list(cwd.iterdir()):
                raise AssertionError(f"{name}: engine wrote a file into the working directory")
            return record["response"]  # type: ignore[return-value]

        for language in ("German", "Russian", "English"):
            result = run(f"doctor-{language}", ["--mode", "doctor", "--language", language])
            assert result["status"] == "ready" and result["backend"] == "local"
            assert result["dictionaryReadings"] > 0 and result["inflectedForms"] > 0
            assert result["syntax"] == ("unsupported" if language == "English" else "verified")

        for source, original, replacement in (
            ("Ich geht.", "geht", "gehe"),
            ("mit den Hund", "den", "dem"),
            ("Der kleines Hund schläft.", "kleines", "kleine"),
        ):
            result = run(f"grammar-{original}", ["--mode", "check"], text=source)
            findings = result["findings"]
            assert result["status"] == "success" and len(findings) == 1
            assert findings[0]["original"] == original
            assert replacement in findings[0]["replacements"]
            assert source[findings[0]["start"]:findings[0]["end"]] == original

        clean = (
            "Ich gehe.", "mit dem Hund", "Der kleine Hund schläft.",
            "Es kommen Gäste.", "Sie gehen.", "Wir gehen.",
            "Er versucht zu helfen.", "Ich versuche zu helfen.",
        )
        for index, source in enumerate(clean):
            result = run(f"clean-{index + 1}", ["--mode", "check"], text=source)
            assert result["status"] == "success" and result["findings"] == []

        result = run("normalized-infinitive-source", ["--mode", "syntax"],
                     text="Er versucht zu helfen.")
        tokens = [word for sentence in result["sentences"]
                  for clause in sentence for word in clause["words"]]
        assert result["fullyAligned"] is True
        normalized = [word for word in tokens if "analysisText" in word]
        assert any(word["text"] in ("helfen", "zu helfen") and word["analysisText"] == "zu-helfen"
                   for word in normalized)
        assert all("Er versucht zu helfen."[word["start"]:word["end"]] == word["text"]
                   for word in tokens)

        for language, word in (("German", "Häuser"), ("Russian", "кошки"), ("English", "dogs")):
            result = run(f"morphology-{language}",
                         ["--mode", "morphology", "--language", language], text=word)
            assert result["word"] == word and result["language"] == language
            assert any(reading["found"] and reading["forms"] for reading in result["readings"])

        result = run("unsupported-english-syntax", ["--language", "English"],
                     text="Dogs run.", expected_exit=2)
        assert result["code"] == "unsupportedLanguage"
        result = run("unsupported-regional-grammar", ["--mode", "check", "--language", "de-CH"],
                     text="Ich geht.", expected_exit=2)
        assert result["status"] == "unsupported"
        result = run("bounded-stdin", [], text="x" * 32769, expected_exit=2)
        assert result["code"] == "limit"
        result = run("conflicting-backends", ["--endpoint", "http://127.0.0.1:17018/"],
                     text="private input", expected_exit=2)
        assert result["status"] == "error" and "private input" not in json.dumps(result)
        result = run("doctor-rejects-document", ["--mode", "doctor"],
                     text="private input", expected_exit=2)
        assert result["status"] == "error" and "private input" not in json.dumps(result)

    output = {
        "scope": "Synthetic production CLI/native regression; not general grammar accuracy",
        "cliSha256": hashlib.sha256(cli.read_bytes()).hexdigest(),
        "workerSha256": hashlib.sha256(worker.read_bytes()).hexdigest(),
        "passed": len(results), "failed": 0, "noRuntimeFilesWritten": True,
        "results": results,
    }
    options.output.parent.mkdir(parents=True, exist_ok=True)
    options.output.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"passed": len(results), "failed": 0, "output": str(options.output)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
