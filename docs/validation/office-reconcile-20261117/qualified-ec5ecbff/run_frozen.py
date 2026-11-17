#!/usr/bin/env python3
"""Execute qualification only for a specifically prepared immutable commit."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

from prepare_workspace import HERE, environment

WORK = Path('/home/agent/.codex/skills/remote-skills/.quds-gector-work')
MODEL_HASH = '549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b'
LIBRARY_HASH = '9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--plan-only', action='store_true')
    args = parser.parse_args()
    setup = json.loads((HERE / f'workspace-{args.source_commit}.json').read_text())
    assert setup['status'] == 'ready' and setup['source_commit'] == args.source_commit
    env = environment()
    pack = WORK / 'assets/native-development-pack-v1'
    env.update(CRISPEMBED_GECTOR='1',
               GECTOR_TEST_LIBRARY=str(pack / 'native' / LIBRARY_HASH / 'libcrispembed-gector.so'),
               GECTOR_TEST_LIBRARY_SHA256=LIBRARY_HASH,
               GECTOR_TEST_MODEL=str(pack / 'model' / MODEL_HASH / 'gector-de-mixed-q4_k.gguf'),
               GECTOR_TEST_MODEL_SHA256=MODEL_HASH)
    command = [str(WORK / '.venv/bin/python'), str(HERE / 'run_qualification.py'),
               '--repo', setup['frozen_source'], '--source-commit', args.source_commit,
               '--flutter-root', str(HERE / 'flutter-sdk'), '--workspace', setup['workspace'],
               '--output', str(args.output.resolve())]
    if args.plan_only:
        command.append('--plan-only')
    raise SystemExit(subprocess.run(command, env=env).returncode)


if __name__ == '__main__':
    main()
