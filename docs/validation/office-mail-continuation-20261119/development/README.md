# Development attempts and preparation evidence

**Development evidence only. No result in this archive is accepted aggregate
qualification of the combined Office source.** Repeated and failed attempts
remain separate. Their passing cases contribute **zero** to the later accepted
qualification counts.

## Preserved originals

`development-evidence.tar.gz` contains **90 original files**, preserving
**5,681,435 bytes** of original content. The compressed archive is **1,230,952
bytes**, SHA-256:

```text
6135389d95388b8ec8fdff1b4ea403c74c570328145f5e26710a20929712f906
```

The selection includes Mail composition, post-submission behavior, exact-byte
message loading, scoped protocol logging, account discovery, saved-message and
session behavior, review/status merge diagnostics, SMTP probes and the failing
SMTP regression run, subsequent SMTP runs, and the completed Word synthesis
runs. It also includes runtime preparation/control logs and manifests, plus the
exploratory Flutter browser compiler logs and dependency lists.

`development-selection.json` records each original relative path, role and
source boundary. `development-index.json` records every archive member's byte
length and SHA-256, as well as descriptive observations from the raw Dart JSON
reporter streams. Empty stderr files are preserved. Existing diagnostic
summaries remain original files; they do not replace raw event streams.

Official runtime executables, native libraries, package archives and web SDK
members are excluded. The generated development kernel/JavaScript and the
separately pinned web SDK ZIP are omitted with their identities and reasons
recorded in the index. Final aggregate gate outputs are outside this selection.

## Source and execution boundary

These diagnostics ran while files were being edited or concurrent continuations
were being reconciled. They lack a complete, per-run before/after snapshot of
application source and runtime inputs. Each index entry therefore has
`exact_application_source_commit: null` and
`accepted_combined_source_result: false`. Neither a later committed tree nor a
passing aggregate result may be retroactively assigned to these executions.

The Word author reported a base of local merge `062150ac` plus uncommitted Word
synthesis. That identifies a starting point, while the exact complete execution
source remains unrecorded. The two retained probe source files contain their
bytes at evidence capture; earlier probe logs may reflect earlier edits.

Process exit codes or exact shell commands are not reconstructed when the
original files did not record them. Modification times are captured filesystem
observations, not asserted execution times. Embedded runtime preparation
identities have their own stated scope and do not bind application test source.

Historical dirty-tree test runs cannot be exactly reconstructed solely from
these logs. Fresh qualification from a committed source uses the source-bound
`../run_validation.py` driver and the replay instructions in the parent report.

## Raw reporter observations

The following table describes each retained JSONL stream. A reporter error can
occur during suite loading even when all visible cases shown in that stream
passed. The terminal reporter result is retained independently. Cases repeated
across attempts are listed per attempt and are never summed into accepted totals.

| Original JSONL | Visible successful completions | Visible failed/error completions | Reporter error events | Terminal result |
| --- | ---: | ---: | ---: | --- |
| `composer-narrow-review-1.jsonl` | 0 | 1 | 1 | failure |
| `composer-narrow-review-2.jsonl` | 1 | 0 | 0 | success |
| `loader-final-tests.stdout.jsonl` | 19 | 0 | 0 | success |
| `loader-tests-formatted.stdout.jsonl` | 19 | 0 | 0 | success |
| `loader-tests.stdout.jsonl` | 19 | 0 | 0 | success |
| `mail-compose-development-1.jsonl` | 39 | 10 | 10 | failure |
| `mail-compose-development-2.jsonl` | 47 | 2 | 2 | failure |
| `mail-compose-development-3.jsonl` | 49 | 0 | 0 | success |
| `mail-operation-final-tests.stdout.jsonl` | 7 | 0 | 0 | success |
| `mail-operation-tests.stdout.jsonl` | 7 | 0 | 0 | success |
| `mail-postsubmission-development.jsonl` | 33 | 0 | 0 | success |
| `smtp-acceptance-final.stdout.jsonl` | 45 | 0 | 0 | success |
| `smtp-acceptance-green.stdout.jsonl` | 45 | 0 | 0 | success |
| `smtp-acceptance-red.stdout.jsonl` | 4 | 9 | 9 | failure |
| `studio-discovery-development-1.jsonl` | 3 | 5 | 5 | failure |
| `studio-discovery-development-2.jsonl` | 8 | 0 | 0 | success |
| `studio-final-union-development.jsonl` | 8 | 0 | 1 | failure |
| `studio-incoming-mail-development-1.jsonl` | 7 | 15 | 29 | failure |
| `studio-incoming-mail-development-2.jsonl` | 22 | 0 | 0 | success |
| `studio-review-status-development-2.jsonl` | 13 | 0 | 0 | success |
| `studio-saved-development-1.jsonl` | 11 | 0 | 0 | success |
| `studio-saved-development-2.jsonl` | 11 | 0 | 0 | success |
| `word-synthesis-editor-first.stdout.jsonl` | 57 | 0 | 0 | success |
| `word-synthesis-engine-first.stdout.jsonl` | 69 | 0 | 0 | success |

All listed streams report zero skipped visible completions. Their raw loading,
error, test-completion and terminal events remain available for independent
inspection; this table is descriptive development evidence.

## Archive integrity and reproducibility

`development-originals-audit.json` records a separate verification implementation
comparing **all 90 archived members byte-for-byte with the original files**, with
zero mismatches, missing members, duplicate entries or unindexed members. It also
checks the archive and index hashes. This check executes no product code and
makes no network or GitHub Actions calls.

`development-replay-audit.json` records a second reconstruction: all original
members were materialized from this archive, then the builder generated another
archive using the explicit selection. The rebuilt archive is **byte-for-byte
identical**. Sorted members and normalized tar/gzip headers make the archive
reproducible; the original file contents are unchanged. The index creation time
and captured filesystem modification times can naturally differ during replay.

Verify the saved archive without the original workspace:

```sh
python verify_development_archive.py \
  --archive development-evidence.tar.gz \
  --index development-index.json \
  --output /tmp/office-development-archive-check.json
```

To additionally compare with surviving original files, add
`--original-root /path/to/original-workspace`. The recorded original comparison
used `/workspace/scratch/82189ef49fff`.

After a successful archive verification, reconstruct it from its retained
originals:

```sh
mkdir -p /tmp/office-development-originals
tar -xzf development-evidence.tar.gz -C /tmp/office-development-originals
python prepare_development_archive.py \
  --original-root /tmp/office-development-originals/originals \
  --selection development-selection.json \
  --output /tmp/office-development-rebuilt
```

The output directory must not already contain an archive or index. The rebuilt
`development-evidence.tar.gz` must have the SHA-256 shown above. This replay
reproduces the preserved evidence container; a fresh application qualification
has its own source identity, execution logs and acceptance record.
