#!/usr/bin/env python3
"""Strictly check every active changed Dart target and preserve two raw artifacts.

This is an explicit active-source gate. The separate all-110 run remains a
failed diagnostic attempt; the two exclusions are immutable, indexed historical
execution inputs, not application, test, or tool sources in the current build.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

BASE = 'a452efdadc9000c51a8e5e9ba2f16405d4979e2e'
MAIL_HEAD = '177f29d3f9450a58f41189b462b0814aad37e45c'
MAIL_EVIDENCE = 'docs/validation/mail-attachments-20261120/'
EXCLUSIONS = {
    MAIL_EVIDENCE+'arabic-composer/capture_mail_arabic_test.dart': {
        'sha256':'f1a7bbe3b9cd6bd8cd5261f2401171edb7afd092068ca44df91d8ffc9f73b31c',
        'git_blob_sha1':'2537c3b211914cd1895bae98bc40dfdb61f2dc8c',
        'context_receipt':MAIL_EVIDENCE+'arabic-composer/receipt.json',
        'reason':'Raw historical Arabic-composer capture harness. Its author receipt binds this exact source hash to a separate scratch invocation from the Studio package; it is retained as evidence, not current package code.',
    },
    MAIL_EVIDENCE+'attachment-core/attachment_mime_probe.dart': {
        'sha256':'35910df713469a7d37e467ce809b4d386d969e68214d54118f0944bbd33c7c1c',
        'git_blob_sha1':'cf7e5bce9a9f67c3fa93d0cb45e575d77a8f5450',
        'context_receipt':MAIL_EVIDENCE+'attachment-core/receipt.json',
        'reason':'Raw historical MIME probe. Its author receipt runs it from a separate scratch directory with an explicit package configuration. Reformatting or editing it would alter the indexed original execution input.',
    },
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--expected-head',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    out = args.output.resolve()
    script = Path(__file__).resolve()

    def git(*arguments):
        return subprocess.check_output(['git',*arguments],cwd=repo)

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    def record(path):
        data = (repo/path).read_bytes()
        return {'bytes':len(data),'sha256':sha(data),'git_blob_sha1':hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()}

    head = git('rev-parse','HEAD').decode().strip()
    assert head == args.expected_head
    all_paths = git('diff','--name-only','--diff-filter=ACMR',BASE,'HEAD','--','*.dart').decode().splitlines()
    assert len(all_paths) >= 110
    assert set(EXCLUSIONS) <= set(all_paths)
    selected = [p for p in all_paths if p not in EXCLUSIONS]
    assert len(selected) == len(all_paths)-2 and len(selected) >= 108
    before = {p:record(p) for p in all_paths}
    for path, entry in before.items():
        assert entry['git_blob_sha1'] == git('rev-parse',head+':'+path).decode().strip(),path
    author_index_path = repo/MAIL_EVIDENCE/'artifact-index.json'
    author_index = json.loads(author_index_path.read_text())
    author_files = {row['path']:row for row in author_index['files']}
    excluded = {}
    for path, context in EXCLUSIONS.items():
        entry = before[path]
        assert entry['sha256'] == context['sha256'] and entry['git_blob_sha1'] == context['git_blob_sha1']
        assert git('rev-parse',MAIL_HEAD+':'+path).decode().strip() == context['git_blob_sha1']
        historical = author_files[path[len(MAIL_EVIDENCE):]]
        assert all(historical[k] == entry[k] for k in ['bytes','sha256','git_blob_sha1'])
        receipt_path = repo/context['context_receipt']
        receipt = json.loads(receipt_path.read_text())
        excluded[path] = {**context,**entry,'incoming_mail_head':MAIL_HEAD,'artifact_index_entry':historical,
                          'context_receipt_sha256':sha(receipt_path.read_bytes()),'original_command':receipt['command'],
                          'original_cwd':receipt.get('cwd'),'original_source_head':receipt.get('source_head')}
    prior_path = script.parent.parent/'publication-final/static/receipt.json'
    prior = json.loads(prior_path.read_text())
    assert prior['head'] == 'a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1' and not prior['accepted']
    assert set(EXCLUSIONS) <= set(prior['paths'])
    assert all(prior['before'][path] == before[path]['sha256'] for path in EXCLUSIONS)
    out.mkdir(parents=True,exist_ok=False)
    dart = str(Path(os.environ['FLUTTER_ROOT'])/'bin/cache/dart-sdk/bin/dart')
    script_sha = sha(script.read_bytes())
    result = {'head':head,'base':BASE,'scope':f'All {len(selected)} active changed application/test/tool Dart targets; exactly two byte-preserved historical evidence inputs excluded.',
              'all_changed_dart_paths':all_paths,'paths':selected,'excluded_historical_artifacts':excluded,'before':before,'checks':{},
              'author_artifact_index_sha256':sha(author_index_path.read_bytes()),'selector_script_sha256':script_sha,
              'preserved_all_110_attempt':{'path':str(prior_path.relative_to(repo)),'sha256':sha(prior_path.read_bytes()),'accepted':False,'original_head':prior['head'],'original_target_count':len(prior['paths'])}}
    for label, flags in [('format',['format','--output=none','--set-exit-if-changed']),('analysis',['analyze','--fatal-infos'])]:
        command = [dart,*flags,*selected]
        started = time.monotonic()
        with (out/(label+'.log')).open('w') as log:
            execution = subprocess.run(command,cwd=repo,stdout=log,stderr=subprocess.STDOUT)
        result['checks'][label] = {'command':command,'exit_code':execution.returncode,'seconds':time.monotonic()-started}
        print(label,execution.returncode,flush=True)
    result['after'] = {p:record(p) for p in all_paths}
    result['head_after'] = git('rev-parse','HEAD').decode().strip()
    result['guards'] = {'all_changed_inputs_unchanged':result['after']==before,'source_head_unchanged':result['head_after']==head,
                        'selector_unchanged':sha(script.read_bytes())==script_sha,'original_110_attempt_unchanged':sha(prior_path.read_bytes())==result['preserved_all_110_attempt']['sha256']}
    result['accepted'] = all(result['guards'].values()) and all(c['exit_code']==0 for c in result['checks'].values())
    (out/'receipt.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'product_static':'passed' if result['accepted'] else 'failed','active_targets':len(selected),'preserved_historical_targets':len(excluded),'guards':result['guards']}),flush=True)
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
