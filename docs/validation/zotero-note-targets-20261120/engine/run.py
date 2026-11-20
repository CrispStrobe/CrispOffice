import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


ROOT = Path('/workspace/scratch/d3ee9898a61b/quds_office_suite')
RUNTIME = ROOT.parent / 'runtime'
ENGINE = ROOT / 'packages/quds_office_engine'
HARNESS = ENGINE / 'tool/zotero/research_target_acceptance.dart'
STEM = RUNTIME / 'engine-acceptance-reviewed'
SUITES = [
    'word_zotero_research_target_test.dart',
    'word_zotero_add_note_test.dart',
    'word_zotero_note_insertion_test.dart',
    'word_zotero_citing_test.dart',
    'word_zotero_rich_edit_test.dart',
    'word_zotero_note_list_test.dart',
    'word_zotero_note_images_integration_test.dart',
    'word_zotero_bibliography_layout_test.dart',
    'word_zotero_preference_flow_test.dart',
    'word_zotero_style_preferences_review_test.dart',
    'slide_radial_opacity_test.dart',
]
SOURCES = sorted(set((ENGINE / 'lib').rglob('*.dart')) |
                 {ENGINE / 'test' / name for name in SUITES} | {HARNESS})
CACHE = ENGINE / '.dart_tool/test'
cache_before = set(CACHE.rglob('*')) if CACHE.exists() else set()
cache_existed = CACHE.exists()
temporary = Path(tempfile.mkdtemp(prefix='zotero-reviewed-', dir=RUNTIME / 'tmp'))
env = dict(os.environ, TMPDIR=str(temporary))
command = [
    'dart', '--packages=' + str(RUNTIME / 'package_config.json'),
    str(RUNTIME / 'pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart'),
    '--reporter=json', '--concurrency=1',
    str(HARNESS.relative_to(ENGINE)),
]


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def hashes():
    return {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in SOURCES
    }


receipt = {
    'started_utc': timestamp(),
    'wrapper_pid': os.getpid(),
    'cwd': str(ENGINE),
    'command': command,
    'temporary_directory': str(temporary),
    'suite_files': SUITES,
    'dart_version': subprocess.check_output(
        ['dart', '--version'], text=True, stderr=subprocess.STDOUT).strip(),
    'git_head_at_start': subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    'free_bytes_before': shutil.disk_usage(RUNTIME).free,
    'source_sha256_before': hashes(),
    'state': 'running',
}
manifest = Path(str(STEM) + '.receipt.json')
manifest.write_text(json.dumps(receipt, indent=2) + '\n')
process = None
returncode = 255


def interrupt(signum, frame):
    raise KeyboardInterrupt('Signal ' + str(signum))


signal.signal(signal.SIGTERM, interrupt)
signal.signal(signal.SIGINT, interrupt)
try:
    with Path(str(STEM) + '.jsonl').open('w') as stdout, \
            Path(str(STEM) + '.stderr.log').open('w') as stderr:
        process = subprocess.Popen(command, cwd=ENGINE, env=env,
                                   stdout=stdout, stderr=stderr,
                                   start_new_session=True)
        print(json.dumps({'state': 'started', 'pid': process.pid,
                          'sources_hashed': len(SOURCES),
                          'temporary_directory': str(temporary)}), flush=True)
        returncode = process.wait()
except BaseException as error:
    receipt['exception'] = repr(error)
finally:
    if process is not None and process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    shutil.rmtree(temporary)
    removed = []
    if CACHE.exists():
        for path in sorted(set(CACHE.rglob('*')) - cache_before,
                           key=lambda value: len(value.parts), reverse=True):
            if path.is_file() or path.is_symlink():
                path.unlink()
                removed.append(str(path.relative_to(ENGINE)))
            elif path.is_dir():
                path.rmdir()
        if not cache_existed:
            CACHE.rmdir()
    receipt.update({
        'finished_utc': timestamp(),
        'returncode': returncode,
        'source_sha256_after': hashes(),
        'removed_new_test_cache_files': removed,
        'temporary_directory_removed': not temporary.exists(),
        'free_bytes_after': shutil.disk_usage(RUNTIME).free,
        'state': 'completed' if returncode == 0 else 'failed',
    })
    receipt['source_hashes_unchanged'] = (
        receipt['source_sha256_before'] == receipt['source_sha256_after'])
    manifest.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in [
        'state', 'returncode', 'source_hashes_unchanged',
        'temporary_directory_removed', 'free_bytes_after',
    ]}), flush=True)
raise SystemExit(returncode)
