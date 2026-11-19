#!/usr/bin/env python3
"""Compare the preserved bare-call grammar using two committed compilers."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


COMPILER = "packages/quds_office_engine/lib/src/automation/office_vba_language.dart"
BASELINE = "cf59efa99232a3fd26cf21ce7f2382402e576f9b"
PROBLEM = "ac9de9e000274718145659da0abc7c8cadb9e8c3"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--dart", type=Path, required=True)
    parser.add_argument("--package-config", type=Path, required=True)
    parser.add_argument("--baseline", default=BASELINE)
    parser.add_argument("--candidate", default=PROBLEM)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    bindings = {}
    for label, revision in (("baseline", args.baseline), ("candidate", args.candidate)):
        raw = subprocess.check_output(["git", "-C", str(args.repo), "show", f"{revision}:{COMPILER}"])
        text = raw.decode()
        for name in ("office_macro_language.dart", "office_macro_model.dart", "office_operations.dart"):
            text = text.replace(f"import '{name}';", f"import 'package:quds_office_engine/src/automation/{name}';")
        target = args.output / f"{label}_compiler.dart"
        target.write_text(text)
        bindings[label] = {
            "revision": revision,
            "git_blob": subprocess.check_output(["git", "-C", str(args.repo), "rev-parse", f"{revision}:{COMPILER}"], text=True).strip(),
            "original_sha256": hashlib.sha256(raw).hexdigest(),
            "loaded_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "rewrite": "Only the three relative imports are rewritten to package URIs so both compilers share dependency type identities.",
        }
    probe = args.output / "probe.dart"
    probe.write_text('''import 'dart:convert';
import 'baseline_compiler.dart' as baseline;
import 'candidate_compiler.dart' as candidate;
import 'package:quds_office_engine/quds_office_automation.dart';

void main() {
  const source = "Sub Main()\\n  Helper (1) = 2\\nEnd Sub\\nSub Helper(ByVal flag As Boolean)\\n  Worksheets(1).Range(\\\"A1\\\").Value2 = flag\\nEnd Sub";
  for (final (name, language) in <(String, OfficeMacroLanguage)>[
    ('baseline', const baseline.OfficeVbaMacroLanguage()),
    ('candidate', const candidate.OfficeVbaMacroLanguage()),
  ]) {
    try {
      final macro = language.compile(OfficeMacroSource(language: 'vba-excel',
        source: source, format: OfficeMacroFormat.xlsx,
        moduleName: 'Probe', entryPoint: 'Main'));
      print(jsonEncode({'compiler': name, 'steps': macro.steps.map((step) => step.arguments).toList()}));
    } on OfficeMacroException catch (error) {
      print(jsonEncode({'compiler': name, 'error': error.toJson()}));
    }
  }
}
''')
    command = [str(args.dart), f"--packages={args.package_config}", str(probe)]
    result = subprocess.run(command, cwd=args.repo, capture_output=True, check=False)
    (args.output / "stdout.log").write_bytes(result.stdout)
    (args.output / "stderr.log").write_bytes(result.stderr)
    receipt = {"command": command, "cwd": str(args.repo), "exit_code": result.returncode,
               "bindings": bindings, "probe_sha256": hashlib.sha256(probe.read_bytes()).hexdigest(),
               "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
               "stderr_sha256": hashlib.sha256(result.stderr).hexdigest()}
    (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(result.stdout.decode(), end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
