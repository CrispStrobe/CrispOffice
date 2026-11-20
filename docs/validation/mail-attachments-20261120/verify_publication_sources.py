#!/usr/bin/env python3
"""Verify that publication only adds evidence/docs to the qualified source."""
import argparse
import json
from pathlib import Path
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()

    def git(*values: str) -> str:
        return subprocess.check_output(['git', '-C', str(args.repo), *values]).decode().strip()

    changes = git('diff', '--name-only', args.source, args.candidate).splitlines()
    allowed_exact = {'README.md', 'packages/quds_office_editor/example/README.md'}
    unexpected = [path for path in changes
                  if not path.startswith('docs/') and path not in allowed_exact]
    result = {
        'status': 'passed' if not unexpected else 'failed',
        'qualified_source_commit': git('rev-parse', args.source),
        'qualified_source_tree': git('rev-parse', args.source + '^{tree}'),
        'publication_candidate': git('rev-parse', args.candidate),
        'publication_tree': git('rev-parse', args.candidate + '^{tree}'),
        'policy': 'Only docs/**, root README.md and the Studio example README may differ from the qualified source.',
        'changed_paths': changes,
        'unexpected_paths': unexpected,
        'qualified_product_test_asset_package_and_runtime_inputs_preserved': not unexpected,
        'no_test_execution_claimed': True,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'changed_paths'}))
    raise SystemExit(bool(unexpected))


if __name__ == '__main__':
    main()
