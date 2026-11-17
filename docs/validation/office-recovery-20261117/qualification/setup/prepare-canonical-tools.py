#!/usr/bin/env python3
"""Expose canonical root tooling to the GECToR relative-import/corpus tests."""
from pathlib import Path
import datetime
import hashlib
import json
import subprocess

base = Path(__file__).resolve().parent
repo = base.parent / 'quds_office_suite'
workspace = base / 'quds'
target = workspace / 'tools'
assert not target.exists() and not target.is_symlink()
assert (repo / 'tools').is_dir()
target.symlink_to(repo / 'tools', target_is_directory=True)
receipt = {
    'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_head_at_setup': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
    'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'prior_setup_receipt_sha256': hashlib.sha256((base / 'receipts/canonical-workspace-setup.json').read_bytes()).hexdigest(),
    'link': str(target), 'source': str(repo / 'tools'),
    'reason': 'GECToR incremental_quality_test.dart imports ../../../tools and locates both frozen corpora under tools/proofing/german_model.',
    'production_files_modified': False, 'tests_run': False,
}
(base / 'receipts/canonical-tools-link.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt))
