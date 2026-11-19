import argparse
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
temp_root = args.output / 'temporary'
temp_root.mkdir()
tempfile.tempdir = str(temp_root)
helper = 'tools/proofing/ayaspell/build_bundle.py'
test_paths = ['tools/proofing/ayaspell/' + name for name in [
    'test_build_bundle.py', 'test_build_bundle_incoming.py',
    'test_build_bundle_reproducibility.py']]
source_paths = [helper, *test_paths]
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
before = {path: sha(args.repo / path) for path in source_paths}
suite = unittest.defaultTestLoader.discover(
    str(args.repo / 'tools/proofing/ayaspell'), pattern='test_build_bundle*.py')
with (patch('urllib.request.urlopen', side_effect=AssertionError('Network forbidden')) as network,
      patch('socket.create_connection', side_effect=AssertionError('Network forbidden')) as socket_network,
      (args.output / 'unittest.log').open('w') as log):
    result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
after = {path: sha(args.repo / path) for path in source_paths}
receipt = {
    'tests_run': result.testsRun,
    'failed': len(result.failures), 'errors': len(result.errors),
    'skipped': len(result.skipped),
    'failures': [test.id() for test, _ in result.failures],
    'error_cases': [test.id() for test, _ in result.errors],
    'passed': result.wasSuccessful(),
    'source_before': before, 'source_after': after,
    'source_unchanged': before == after,
    'helper_git_blob_from_incoming_main': '9257d987fc3a4307a33bc82465fcd03f777f7e28',
    'incoming_main': 'b655b8a37fddc874bd42a453c371eed6253e82d8',
    'network_attempts': network.call_count + socket_network.call_count,
    'network_or_real_publication_performed': False,
    'publication_api': 'Test-owned in-memory HfApi replacements',
    'raw_log_sha256': sha(args.output / 'unittest.log'),
    'script_sha256': sha(Path(__file__)),
    'counted_in_earlier_836_78_or_179_results': False,
    'historical_seven_fresh_directory_checks': 'Superseded by incoming whitelist behavior; not reexecuted',
}
(args.output / 'receipt.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
print(json.dumps({k: receipt[k] for k in ['tests_run', 'failed', 'errors', 'skipped', 'passed', 'source_unchanged', 'network_attempts']}))
raise SystemExit(0 if receipt['passed'] and receipt['source_unchanged'] and not receipt['network_attempts'] else 1)
