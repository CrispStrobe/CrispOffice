#!/usr/bin/env python3
"""Prepare a plan, or explicitly finalize a deterministic evidence archive.

Default operation writes only a plan. Use --finalize only after the task owner
declares validation complete. Outputs stay in an existing staging directory;
this tool never creates directories, deletes evidence, or mutates Git state.
"""

import argparse
from collections import Counter
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile


HERE = Path(__file__).resolve().parent
WORKSPACE = Path('/workspace/scratch/f1082e82ac57')
REPOSITORY = WORKSPACE / 'quds_office_suite'
POLICY_PATH = HERE / 'mail-evidence-packaging-manifest.json'
POLICY = json.loads(POLICY_PATH.read_text())
ROOT = Path(POLICY['evidence_directory'])
PREFIX = POLICY['generated_prefix']
SHA40 = re.compile(r'^[0-9a-f]{40}$')
SHA64 = re.compile(r'^[0-9a-f]{64}$')
TOKEN = re.compile(rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-(?:proj-)?[A-Za-z0-9_-]{32,}|AKIA[0-9A-Z]{16})\b')
PRIVATE_KEY = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----')
AUTH_URL = re.compile(rb'https?://[^\s/:@]+:[^\s/@]+@')


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode()


def write_atomic(path, data):
    temporary = path.with_name(path.name + '.partial')
    with open(temporary, 'wb') as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, path)


def category(path):
    suffix = path.suffix.lower()
    if suffix in {'.py', '.c', '.dart', '.sh'}:
        return 'validation_helper_source'
    if suffix in {'.log', '.jsonl'}:
        return 'raw_log'
    if suffix == '.diff':
        return 'source_diff'
    if suffix == '.md':
        return 'report_or_limitations'
    return 'audit_or_metadata'


def exclusions(path):
    if path.is_symlink():
        return 'Symlink excluded; no traversal outside the selected evidence tree.'
    if path.name.startswith(PREFIX) or path.name.endswith('.partial'):
        return 'Generated packaging output; excluded to prevent recursive archives.'
    if path.name in POLICY['excluded_names']:
        return POLICY['excluded_names'][path.name]
    if path.suffix.lower() in POLICY['excluded_suffixes']:
        return 'Binary, generated archive, compiled cache or live lockfile.'
    if path.suffix.lower() not in POLICY['allowed_suffixes']:
        return 'Not an approved text-evidence suffix.'
    if '__pycache__' in path.parts:
        return 'Generated Python bytecode cache.'
    return None


def discover(extras):
    selected = {}
    excluded = []
    for path in sorted(ROOT.rglob('*')):
        if not path.is_file() and not path.is_symlink():
            continue
        relative = path.relative_to(ROOT).as_posix()
        reason = exclusions(path)
        if reason:
            excluded.append({'path': relative, 'bytes': path.lstat().st_size, 'reason': reason})
        else:
            selected['audit/' + relative] = path
    selected['packaging/' + Path(__file__).name] = Path(__file__).resolve()
    selected['packaging/' + POLICY_PATH.name] = POLICY_PATH
    for item in POLICY['extra_files'] + extras:
        path = Path(item)
        if not path.is_absolute():
            path = WORKSPACE / path
        if path.is_symlink():
            raise SystemExit(f'Extra evidence must not be a symlink: {path}')
        path = path.resolve()
        if not path.is_relative_to(WORKSPACE) or not path.is_file():
            raise SystemExit(f'Extra evidence must be an existing workspace file: {path}')
        reason = exclusions(path)
        if reason:
            raise SystemExit(f'Extra evidence is excluded: {path.name}: {reason}')
        if path in selected.values():
            continue
        archive_path = 'extra/' + path.relative_to(WORKSPACE).as_posix()
        selected[archive_path] = path
    missing = [name for name in POLICY['required_files'] if 'audit/' + name not in selected]
    if missing:
        raise SystemExit('Missing required evidence: ' + ', '.join(missing))
    return dict(sorted(selected.items())), excluded


def stable_read(path):
    with open(path, 'rb') as handle:
        before = os.fstat(handle.fileno())
        data = handle.read()
        after = os.fstat(handle.fileno())
    identity = lambda st: (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns)
    if identity(before) != identity(after) or len(data) != after.st_size:
        raise SystemExit(f'Evidence changed while reading; wait for writers: {path}')
    try:
        data.decode('utf-8')
    except UnicodeDecodeError:
        raise SystemExit(f'Selected evidence is not UTF-8 text: {path}')
    if b'\x00' in data:
        raise SystemExit(f'Selected evidence contains binary NUL bytes: {path}')
    if TOKEN.search(data) or PRIVATE_KEY.search(data) or AUTH_URL.search(data):
        raise SystemExit(f'Credential-shaped content requires review before packaging: {path.name}')
    return data


def walk(value, pointer=''):
    yield pointer, value
    if isinstance(value, dict):
        for key, item in sorted(value.items()):
            escaped = str(key).replace('~', '~0').replace('/', '~1')
            yield from walk(item, pointer + '/' + escaped)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from walk(item, pointer + '/' + str(index))


def evidence_metadata(payload):
    commands, refs, sources = [], {}, []
    for archive_path, data in payload.items():
        text = data.decode('utf-8')
        for match in re.finditer(r'^HARNESS source=(.+) sha256=([0-9a-f]{64})$', text, re.MULTILINE):
            sources.append({'evidence': archive_path, 'field': 'HARNESS source',
                            'source': match.group(1), 'sha256': match.group(2)})
        if not archive_path.endswith('.json'):
            continue
        try:
            obj = json.loads(text)
        except json.JSONDecodeError as error:
            raise SystemExit(f'Invalid selected JSON evidence {archive_path}: {error}')
        for pointer, value in walk(obj):
            if not isinstance(value, dict):
                continue
            ref = value.get('ref')
            sha = value.get('sha') or value.get('commit')
            if isinstance(ref, str) and isinstance(sha, str) and SHA40.fullmatch(sha):
                refs.setdefault((ref, sha), set()).add(archive_path)
            for key, item in sorted(value.items()):
                if key in {'command', 'cmd', 'commands'} and isinstance(item, (str, list)):
                    commands.append({'evidence': archive_path, 'field': pointer + '/' + key, 'value': item})
                if key in {'sha256', 'source_sha256', 'files_sha256', 'final_files_sha256'} and isinstance(item, dict):
                    for source, digest in sorted(item.items()):
                        if isinstance(digest, str) and SHA64.fullmatch(digest):
                            sources.append({'evidence': archive_path, 'field': pointer + '/' + key,
                                            'source': source, 'sha256': digest})
    return {
        'recorded_command_fields': commands,
        'named_ref_observations': [{'ref': ref, 'sha': sha, 'evidence': sorted(documents)}
                                   for (ref, sha), documents in sorted(refs.items())],
        'source_attestations': sources,
    }


def git_observation():
    def git(*args):
        result = subprocess.run(['git', *args], cwd=REPOSITORY, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        return result.stdout.rstrip('\n')
    refs = []
    for line in git('for-each-ref', '--format=%(refname) %(objectname)',
                    'refs/remotes/origin', 'refs/remotes/pull', 'refs/remotes/archive').splitlines():
        ref, sha = line.rsplit(' ', 1)
        refs.append({'ref': ref, 'sha': sha})
    return {
        'mode': 'Read-only local Git observation; no remote API or CI query.',
        'head': git('rev-parse', 'HEAD'),
        'branch': git('branch', '--show-current'),
        'tracked_worktree_status': git('status', '--porcelain=v1', '--untracked-files=no').splitlines(),
        'remote_tracking_refs': refs,
    }


def archive_bytes(payload):
    destination = io.BytesIO()
    with gzip.GzipFile(filename='', mode='wb', fileobj=destination, mtime=0, compresslevel=9) as gz:
        with tarfile.open(fileobj=gz, mode='w', format=tarfile.PAX_FORMAT) as archive:
            for path, data in sorted(payload.items()):
                info = tarfile.TarInfo(path)
                info.size = len(data)
                info.mode = 0o644
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ''
                archive.addfile(info, io.BytesIO(data))
    return destination.getvalue()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--finalize', action='store_true', help='Explicitly build the final snapshot after validation is settled.')
parser.add_argument('--extra', action='append', default=[], help='Exact additional workspace evidence file; may be repeated.')
parser.add_argument('--ref', action='append', default=[], metavar='NAME=SHA', help='Explicit qualified source/reference SHA; may be repeated.')
parser.add_argument('--context', help='Exact optional final release-context JSON file; also included as extra evidence.')
parser.add_argument('--staging-directory', default=POLICY['staging_directory'])
args = parser.parse_args()
staging = Path(args.staging_directory).resolve()
if not staging.is_dir() or not staging.is_relative_to(WORKSPACE):
    raise SystemExit('Staging directory must already exist inside this workspace')
extras = args.extra + ([args.context] if args.context else [])
selected, excluded = discover(extras)
plan = {
    'state': 'plan_only_no_archive_snapshot',
    'target_repository_directory': POLICY['target_repository_directory'],
    'included': [{'archive_path': name, 'source_path': str(path), 'bytes_now': path.stat().st_size,
                  'category': category(path)} for name, path in selected.items()],
    'excluded': excluded,
    'counts': {'planned_files': len(selected), 'excluded_files': len(excluded)},
    'counting_policy': POLICY['counting_policy'],
    'finalize_command_template': 'python3 package_mail_evidence.py --finalize --ref qualified_source=FULL_SHA [--extra EXACT_EVIDENCE_PATH ...]',
}
write_atomic(staging / (PREFIX + '-plan.json'), json_bytes(plan))
if not args.finalize:
    print(json.dumps({'state': plan['state'], 'planned_files': len(selected),
                      'excluded_files': len(excluded), 'plan': str(staging / (PREFIX + '-plan.json'))}))
    raise SystemExit(0)

explicit_refs = {}
for item in args.ref:
    name, separator, sha = item.partition('=')
    if not separator or not name or not SHA40.fullmatch(sha):
        raise SystemExit('--ref must be NAME=full lowercase 40-character Git SHA')
    if name in explicit_refs:
        raise SystemExit('Duplicate explicit ref name: ' + name)
    explicit_refs[name] = sha
payload = {name: stable_read(path) for name, path in selected.items()}
for name, path in selected.items():
    if stable_read(path) != payload[name]:
        raise SystemExit(f'Evidence changed during snapshot preparation: {path}')
metadata = evidence_metadata(payload)
observed_git = git_observation()
entries = [{'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'category': category(Path(name))} for name, data in payload.items()]
kind_counts = dict(sorted(Counter(entry['category'] for entry in entries).items()))
manifest = {
    'format_version': 1,
    'state': 'final_evidence_snapshot',
    'target_repository_directory': POLICY['target_repository_directory'],
    'files': entries,
    'excluded': excluded,
    'counts': {'payload_files': len(entries), 'payload_bytes': sum(entry['bytes'] for entry in entries),
               'categories': kind_counts, 'recorded_command_fields': len(metadata['recorded_command_fields']),
               'source_attestations': len(metadata['source_attestations']),
               'named_ref_observations': len(metadata['named_ref_observations']),
               'local_remote_tracking_refs': len(observed_git['remote_tracking_refs'])},
    'counting_policy': POLICY['counting_policy'],
    'explicit_refs': dict(sorted(explicit_refs.items())),
    'local_git_observation': observed_git,
    'metadata': metadata,
    'determinism': POLICY['determinism'],
    'harness_limitations_document': 'audit/temp-dir-pool-validation.md',
    'restoration_helper': 'audit/restore_temp_dir_pool.py',
}
payload['MANIFEST.json'] = json_bytes(manifest)
compressed = archive_bytes(payload)
# Verify the exact in-memory archive before publishing any snapshot artifact.
with tarfile.open(fileobj=io.BytesIO(compressed), mode='r:gz') as archive:
    members = archive.getmembers()
    if [member.name for member in members] != sorted(payload):
        raise SystemExit('Archive membership verification failed')
    for member in members:
        if not member.isfile() or archive.extractfile(member).read() != payload[member.name]:
            raise SystemExit('Archive byte verification failed: ' + member.name)
archive_name = PREFIX + '.tar.gz'
index_name = PREFIX + '-index.json'
archive_hash = hashlib.sha256(compressed).hexdigest()
index = dict(manifest, archive={'filename': archive_name, 'bytes': len(compressed),
                              'sha256': archive_hash, 'members': len(payload)},
             manifest_sha256=hashlib.sha256(payload['MANIFEST.json']).hexdigest())
index_data = json_bytes(index)
index_hash = hashlib.sha256(index_data).hexdigest()
checksums = (f'{archive_hash}  {archive_name}\n{index_hash}  {index_name}\n').encode()
write_atomic(staging / archive_name, compressed)
write_atomic(staging / index_name, index_data)
write_atomic(staging / (PREFIX + '-SHA256SUMS.txt'), checksums)
print(json.dumps({'state': 'final_evidence_snapshot', 'archive': str(staging / archive_name),
                  'index': str(staging / index_name), 'sha256sums': str(staging / (PREFIX + '-SHA256SUMS.txt')),
                  'archive_sha256': archive_hash, 'payload_files': len(entries), 'archive_bytes': len(compressed)}))
