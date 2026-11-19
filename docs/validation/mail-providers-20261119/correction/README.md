# Corrective qualification and accepted matrix

**The qualified matrix passes: 994 tests, 0 failures, and 0 skips.** This
combines the unaffected passing gates from the preserved
[complete frozen run](../final/README.md) with a replacement run of the entire
22-case language-ID unit/synthetic cohort after its one-line fixture correction.
The earlier cohort's 21 passes and 1 failure are superseded together; they are
not added to the accepted total.

The corrective run used published source
`34153224a63112de3006335ae36cf9b2f744f513` (tree
`d7491007d718299e4b9e90bfecf8cba34c62cb5a`) on 2026-11-19 from
14:49:37 to 14:49:55 UTC. It passed all three requested gates:

| Corrective gate | Result | Evidence |
| --- | --- | --- |
| Changed unit-test file formatting | Clean | [Result](strict-corrected-format/result.json) |
| Strict language-ID library and selected test analysis | No warnings or informational diagnostics | [Result](strict-language-id-analysis/result.json) |
| Entire language-ID unit and synthetic native transport cohort | 22 passed, 0 failed, 0 skipped | [Cases](language-id-synthetic/test-cases.json) |

## Why the original failure needed a fixture correction

The original full run at
`e3212327954ac144847a7c06b5d2420f00debab3` had one failing test: an invalid-result
fixture returned four valid, descending-probability candidates and expected the
identifier to reject them. That fixture implicitly relied on a three-candidate
default. The incoming calibration change had intentionally raised the
production default to five candidates, so accepting four was correct.

The correction inserts only `topK: 3,` in that existing invalid-result loop.
It makes the fixture's requested limit explicit, preserves the overflow check's
intent, and keeps the production five-candidate default and
`answer.length > topK` guard intact. No production code was changed for this
correction. See the exact [one-line diff](source-diff.patch) and the
[per-file hash delta](source-delta.json).

## Basis for reusing the unaffected gates

The corrective runner checks the complete source-input manifest, not only the
package being retested. Across 4,334 recorded product/test/configuration/asset
inputs, the **only** change from the original frozen run is
`packages/quds_language_id/test/language_id_unit_test.dart`. All production,
mail, Studio, compiler-entry, dependency, native-fixture, and other test inputs
are byte-identical.

Every recorded runtime input also matches the original full run. The source,
runtime, lockfile, and HEAD stayed unchanged during the corrective run. The
original failed receipt's SHA-256 stayed unchanged. The replacement cohort has
exactly the same test-file/name/platform identities as the original cohort.
These checks justify retaining the unaffected passing gates without rerunning
the entire matrix for this one fixture change. The runner refuses continuation
if another source input or recorded runtime differs.

| Integrity check | Recorded value |
| --- | --- |
| Original source commit | `e3212327954ac144847a7c06b5d2420f00debab3` |
| Corrected source commit before and after | `34153224a63112de3006335ae36cf9b2f744f513` |
| Corrected canonical source manifest before and after | `13bbce663ea3da2c587bf17126b899d419d3a8a199f6212ebe596ecdbc910ec1` |
| Canonical runtime manifest, equal to original run | `89a4c7bd995379bdeffda84184393345b1081ccfac4f9109aabb609e90ba6549` |
| Root dependency lockfile before and after | `72a5a52654a1484f4df646c631b4d1ea47e96025a671beff045eecf2b9e78e82` |
| Unmodified original failed receipt | `1ffe927c4f9b15b2c7ea5206e0c2fe1f6cd540a83ecddf46a6d6a3effe736240` |
| Executed corrective runner | `3895d3b68c9cfd7bf69fea6dbccbbbde07c395e333f4494daf3cdb195fc9b436` |

The corrected test file changed from SHA-256
`7da0d70077cf244762e9e7e40c653f8e84b4907e1046555ab534a8b0893f9ec3`
to `52c87b431ae251cfdbf968ef07c06a297031b0b036b66399f4b906398b9ae65f`.
All other entries are identical. Canonical manifest digests hash sorted compact
JSON; individual file hashes and sizes are included in
[source before](source-before.json), [source after](source-after.json),
[runtime before](runtime-before.json), and [runtime after](runtime-after.json).

## Accepted per-suite counts

“Reused” below means an unaffected passing gate from the immediately preceding
frozen full run, justified by the exact input/runtime comparison above. It does
not refer to development or historical runs.

| Gate | Passed | Failed | Skipped | Evidence origin |
| --- | ---: | ---: | ---: | --- |
| Mail core, complete VM suite | 54 | 0 | 0 | Reused |
| Mail MIME, complete VM suite | 32 | 0 | 0 | Reused |
| Mail storage, complete VM suite | 118 | 0 | 0 | Reused |
| Mail transport, complete VM suite | 373 | 0 | 0 | Reused |
| Transport Node boundaries and EWS configuration | 13 | 0 | 0 | Reused |
| Mail UI, complete widget suite | 33 | 0 | 0 | Reused |
| Studio mail and saved mail, all 14 suites | 209 | 0 | 0 | Reused |
| Language-ID unit and synthetic native transport | 22 | 0 | 0 | Replaced by this run |
| Engine language identification and calibration | 36 | 0 | 0 | Reused |
| Engine thesaurus | 25 | 0 | 0 | Reused |
| Editor proofing/session/thesaurus widgets | 75 | 0 | 0 | Reused |
| Studio language identification | 4 | 0 | 0 | Reused |
| **Qualified total** | **994** | **0** | **0** | Complete cohort replacement |

The full run's strict formatting and five analysis gates, synthetic C++ fixture
build, macOS entitlement assertions, actual Flutter web frontend/backend
compilation, native-import exclusions, and generated-JavaScript syntax check
also remain accepted on unchanged inputs. This correction adds strict
language-ID analysis and the explicit fixture-file format check.

## Raw evidence and replay

[receipt.json](receipt.json) records the corrected source, unchanged original
receipt hash, reused gate names, replaced cohort, exact counts, before/after
integrity results, and count policy. Each corrective gate preserves exact argv,
environment overrides, exit code, timestamps, raw stdout/stderr, and their
hashes. The test gate additionally preserves parsed individual cases.

The [corrective runner](run_correction.py) imports the preserved full runner,
checks its recorded hash, and requires the same local runtime/native fixture as
the original attempt. It never queries GitHub Actions, resolves dependencies,
or retries a failing test. The frozen source commits predate these evidence
files, so preserve the runner in a separate evidence checkout. A continuation
on the original runtime uses the original source worktree path at the corrected
freeze and the preserved evidence directory:

```bash
python3 /path/to/evidence-checkout/docs/validation/mail-providers-20261119/correction/run_correction.py \
  --repo /path/to/original-source-worktree \
  --previous /path/to/preserved-original-evidence \
  --output /path/to/new-empty-correction-evidence \
  --freeze 34153224a63112de3006335ae36cf9b2f744f513
```

The original manifests contain the source, package-resolution, and native
fixture paths, so that continuation also requires those original paths and
matching runtime files. On a different machine, source worktree, or runtime,
perform a complete fresh run using a separate evidence checkout and a clean
worktree at the corrected source commit:

```bash
python3 /path/to/evidence-checkout/docs/validation/mail-providers-20261119/final/run_final.py \
  --repo /path/to/frozen-source \
  --scratch /path/to/scratch-build \
  --output /path/to/new-empty-evidence \
  --freeze 34153224a63112de3006335ae36cf9b2f744f513
```

Prepare `FLUTTER_ROOT`, `PUB_CACHE`, resolved source-worktree dependencies,
native SQLite, and the other tools as described in the
[full-run replay guide](../final/README.md#replay). A narrow reuse audit is
accepted only when its recorded inputs match exactly.

## Acceptance limits

The qualified counts retain the original scope exclusions. No live provider
credentials were supplied, so real Gmail, Microsoft 365, EWS, or IMAP/SMTP
acceptance remains unverified. The language-ID native transport uses the
tracked synthetic lifecycle/allocation fixture; acceptance against the real
external native language-ID library is excluded. Installed OS credential-store
integration, a live system-browser OAuth callback, a signed macOS application,
and browser runtime interaction were not exercised. Browser evidence covers
actual compilation, native-import isolation, and JavaScript syntax. Explicit
platform exclusions are recorded in the full run and are not counted as skipped
executions.
