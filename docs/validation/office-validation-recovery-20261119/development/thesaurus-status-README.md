# Thesaurus, proofing status and incoming Studio evidence

This separate capture preserves the later review of incoming main and PR199.
The earlier development and language-host archives remain unchanged. These are
source-bound baseline and unfrozen development observations, not aggregate
acceptance.

## Results and interpretation

| Record | Passed | Failed | Skipped | Scope |
| --- | ---: | ---: | ---: | --- |
| Incoming thesaurus subset | 1 | 3 | 0 | Delayed relation reads after reset, with an optional-label control |
| Repaired thesaurus VM suite | 28 | 0 | 0 | Complete affected engine suite |
| Repaired thesaurus Node suite | 28 | 0 | 0 | Same complete portable suite |
| Incoming Word summary subset | 1 | 1 | 0 | Report-level completeness and valid language-specific coverage |
| Repaired Word session suite | 33 | 0 | 0 | Complete affected editor session suite |
| Incoming PR199 Studio suite | 3 | 1 | 0 | Original four incoming assertions |
| Adjusted PR199 Studio suite | 4 | 0 | 0 | Same four cases with fixed public feedback expectation |

The thesaurus now checks its epoch when optional relation loading fails and
after relation resolution finishes. A reset invalidates the entire obsolete
lookup, preventing it from returning ready or replacing a newer cached result.
An unavailable optional label still leaves the verified main entry usable.

Word summary completion requires each text snapshot's report to contain a
successful checker. The ordinary session already kept mixed supported and
unsupported paragraphs partial through its checked-paragraph count. The
reproduced defect was in the public summary accepting full-coverage counts that
contradicted its reports. The regression also verifies that language-specific
checkers can complete the document while irrelevant unsupported-provider
warnings remain hidden.

The incoming Studio suite expected a native-library diagnostic from the host.
Its assertion now matches the existing fixed public message, `Automatic
language detection is unavailable.` No host product change was made. Model
hash, settings, routing, language application, Undo and license assertions
remain present.

All five changed Dart targets pass strict analysis with fatal infos, formatting
and whitespace checks. Final tested bytes are unchanged from the passing runs;
no later source adjustment was necessary. Each run records its exact relevant
source copies and hashes, command, exit code, raw stdout/stderr and integration
HEAD. The thesaurus runs preceded the secure-storage runtime extension but
import no new plugin; Flutter runs used the completed extension, whose evidence
is separately retained by the integration owner.

Two raw stderr records preserve ordinary Flutter startup-lock waits during
concurrent package test startup. No case was retried, no original log was
rewritten, and no GitHub Actions run, job, queue or status was queried or awaited.
These counts are not combined into a final acceptance claim. Fixtures do not
qualify a complete thesaurus corpus; controlled Studio routing and deliberate
native unavailability do not qualify real providers, browser execution or an
installed platform.

## Archive and verification

The archive contains **60 members: 59 regular files and one directory**, totaling
**789,410 original file bytes**. It includes every raw reporter, stderr and
receipt, incoming and tested source copies, strict output, exact changes,
capture/check scripts and the detailed case index.

- Compressed file: `thesaurus-status-evidence.tar.xz`, **43,668 bytes**.
- Compressed SHA-256: `8f0d59e5e3a57522bddf64873714ea2439d7a74c66baf49ff1490c22e03923fb`.
- Decompressed tar SHA-256: `b08448ab5d01251b606e6aacbcc0ec7d8b5548150cf1bcc0bd2eeeea8e8cc3ef`.
- [Complete archive index](thesaurus-status-evidence.index.json).
- [Original-byte and reconstruction verification](thesaurus-status-evidence.verification.json).

The tool verified every original file byte, the exact member set, each size and
hash, permission modes and nanosecond timestamps. A second complete archive build
was byte-identical, and reconstruction was verified. At less than 1 MiB this
archive needs no splitting.

From the repository root, verify the committed artifact:

```bash
python3 docs/validation/office-validation-recovery-20261119/development/archive_development.py verify \
  --index docs/validation/office-validation-recovery-20261119/development/thesaurus-status-evidence.index.json
```

While the original source directory is available, compare its exact bytes too:

```bash
python3 docs/validation/office-validation-recovery-20261119/development/archive_development.py verify \
  --index docs/validation/office-validation-recovery-20261119/development/thesaurus-status-evidence.index.json \
  --source thesaurus-status-development=/workspace/scratch/1db61dbeed56/thesaurus-status-development
```

To rebuild in a new empty destination, use the tool's `pack` command with that
source mapping and `--name thesaurus-status-evidence`. Original paths may be
remapped explicitly while preserving indexed file metadata. The exact replay
commands and their working directories are also stored in each receipt.
