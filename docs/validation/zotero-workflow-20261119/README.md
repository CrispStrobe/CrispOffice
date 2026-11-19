# Zotero workflow extension — 19 November 2026

Completed local qualification for [PR #218](https://github.com/CrispStrobe/quds_office_suite/pull/218),
on `codex/zotero-workflow-20261119`. The accepted runs contain **1,808 distinct
application tests**, with no failed, skipped, error or unfinished cases.

Qualified product source: **`780422316b4e37989e01ac871dd2956fbd2c8908`**.
Later source changes only normalize formatting in three incoming Mail files;
their before/after parsed Dart output is identical. Documentation and evidence
commits follow qualification without changing Zotero, PPTX or VBA behavior.

## Completed workflows

**Search options → Browse tags…** opens a searchable, paginated tag browser for
the connected library or collection. Selections persist across searches and
pages. Apply restarts the last submitted reference search while keeping selected
references and unfinished input. Cancel retains the existing filters. The API
preserves exact tag names and separate manual/automatic records, validates
metadata and query bounds, and uses the correct online and desktop routes.
Unsupported literal filter names stay visible with an explanation. Usage counts
are labeled as Zotero-reported counts because collection results can contain
library-wide counts. The 20-filter bound remains in place.

**Document → Cited references… → Show citations → Go to citation** lists each
distinct citation field for a stored source, including cached text and document
location. Navigation supports body text, footnotes and endnotes, works offline
and in selecting mode, preserves source aliases, and rejects a changed document
or target before moving the caret. Back retains the source-picker search and
draft selection. Choosing a location does not apply a staged source selection.
Unsupported destinations remain visible without an active navigation action.

The **59 new Zotero regression tests are included once** in the totals below.
They cover routes, queries, manual/automatic tag records, pagination, staged
selection, pending requests, stale sessions, small-screen LTR/RTL layouts at
doubled text size, identity aliases, distinct occurrences, read-only navigation,
body and native notes, and stale document/caret protection.

See [Zotero user and API documentation](../../zotero-support.md).

## Incoming work and history preservation

Work starts from fork main `2170791c9250d72c9df31a065408365f9b50abaa`.
The initial new PPTX head `5c3f9d7fd4531dfac7c0e49fba1827c39e17caf6` was
brought in first by fast-forward. The initial inventory reviewed 16 branches,
all 216 PR heads and upstream refs: 202 PR heads were ancestors and 14
historical equivalents were independently checked by complete delta/blob or
tree identity. The bounded refresh captured 19 branches and no open PRs.

All three new heads from that refresh are preserved as ancestors through
ordinary merges, retaining their original commits:

| Incoming branch | Preserved head | Work included |
| --- | --- | --- |
| `integrate/recent-pptx` | `a5ae56c8e3e7f950c37ef491b17b5c32fcd0e13d` | PPTX fidelity and PDF tab-stop alignment |
| `codex/vba-dynamic-arrays-20261119` | `1580807e1eb99a40d6c8620e93ebd039b9a01132` | Bounded dynamic arrays, ReDim/Preserve, Erase and Option Base |
| `work/mail-continuation-20261119` | `275f8a346bf3aef00a736e6441c79244b84994c6` | To/Cc/Bcc composition and Reply all |

The CHANGELOG merge preserves both Zotero and VBA entries. Incoming PPTX
regression repairs make scalar edits invalidate stale rich-text snapshots;
align painting and hit testing for anchored text; inherit master/theme
backgrounds; retain explicit plain runs; fall back to shape size/ink for missing
rich-run properties; and preserve the existing 16 pt default.

[Initial reconciliation](initial-reconciliation.json) and
[bounded refresh with integration results](final-reconciliation.json) record
the exact refs and historical-equivalence proofs. These are fixed snapshots,
not a claim about later work on other branches. Main is checked again immediately
before publication, and remote checkpoints use non-forced expected-head leases.
The incremental branch is retained.

## Accepted local validation

| Cohort | Selected files | Passed application tests |
| --- | ---: | ---: |
| Zotero engine | 28 | 602 |
| Zotero editor | 40 | 584 |
| PPTX engine | 5 | 23 |
| PPTX editor | 2 | 10 |
| Incoming Mail host | 7 | 219 |
| Incoming Mail transport, focused selection | 3 | 6 |
| Incoming VBA, including real CLI subprocesses | 8 | 364 |
| **Distinct total** | **93** | **1,808** |

All accepted commands exit zero. Raw-event reconciliation excludes loader,
setup and teardown pseudo-tests and verifies requested suite coverage, terminal
success, errors, skips and unfinished cases. Development reruns and failed
diagnostic attempts are excluded from the total.

The [independent core audit](independent-audit.json) verifies all 75 Zotero/PPTX
files and all 2,048 source/dependency inputs against the qualified source.
Mail records 229 relevant inputs. VBA records 372 inputs across engine source,
tests, macro tools/examples and dependencies. No recorded inputs changed during
their accepted runs. The later core receipt at `30bf6125` and VBA receipt across
`30bf6125` → `400fffd0` differ only in documentation commits within the relevant
source scope. The [independent VBA audit](independent-vba-audit.json) recounts
the complete genuine-VM run, checks input hashes and independently reconciles
the disjoint combined total.

Strict analysis passes for all **40 changed Dart targets**. After formatting
three incoming Mail files, strict analysis is repeated for those three and the
formatter passes all 40 with zero changes. Parsed Dart output is equal before
and after normalization; byte hashes and the verification script are recorded in
[format-normalization.json](format-normalization.json). `git diff --check` also
passes. The initial formatting failure is retained as diagnostic evidence.

### Runtime and execution limits

Tests use official **Flutter 3.47.8 / Dart 3.13.7** with verified archive and
executable hashes, existing manifests and enforced locked dependency resolution.
Framework and SDK source are unmodified. The harness links the real repository
source and tests. Exact versions, manifest identities and fingerprints are in
[runtime.json](runtime.json).

An early concurrent Flutter startup collided on the SDK cache stamp. Later
compiler attempts also failed while other compilation was active. Those
attempts remain archived separately. The accepted editor run executes all 40
files with concurrency 1. Separate invocations in the same package are serialized
to avoid sharing the non-atomic Flutter test cache.

VBA CLI tests run under the genuine Dart VM: they launch subprocesses through
`Platform.resolvedExecutable`, which is `flutter_tester` under Flutter. The first
genuine-VM attempt under concurrent load timed out in CLI cases. The accepted
isolated eight-file run passes **364/364 in 194 seconds**, with concurrency 1,
original case timeouts and no test/source changes.

**No GitHub Actions, workflow, check or commit-status endpoint was queried or
awaited.** Incremental commits use `[skip ci]`. This establishes local
model/controller/widget, serializer and controlled-transport behavior. It does
not add installed-device, live Zotero/account, full application build or actual
Word/LibreOffice interoperability acceptance.

## Evidence and reproduction

Each `*-receipt.json` records exact selected files and commands. Matching
`.jsonl.gz` files contain complete raw reporter events. `source-inputs.json.gz`
holds core hashes; Mail receipts and `vba-inputs.json.gz` hold scoped hashes.
The unabridged VBA receipt is also saved as `vba-final-receipt.json.gz`.
Strict analysis and formatting logs accompany before/after static-check receipts.
Files prefixed `startup-attempt`, `compiler-attempt`, `vba-flutter-attempt` and
`vba-vm-attempt` are diagnostics only and are excluded from acceptance.

With the recorded SDK and locked packages available, run each Flutter cohort
from the package named in its receipt. This example replays one core cohort
from a checkout root; change the receipt name for the other three:

```sh
python3 - <<'PY'
import json
import subprocess
from pathlib import Path
root = Path.cwd()
receipt = json.loads((root / 'docs/validation/zotero-workflow-20261119/zotero-engine-receipt.json').read_text())
subprocess.run(receipt['command'], cwd=root / receipt['package'], check=True)
PY
```

Mail host and transport selections are in `mail-final-receipt.json` and
`mail-transport-receipt.json`. VBA uses the Dart SDK executable, the resolved
workspace package config and `package:test`'s `bin/test.dart`, followed by
`--reporter json --concurrency 1` and the eight files listed in its receipt.
Adapt recorded absolute harness/SDK paths to the local checkout. Run these
cohorts sequentially on constrained hosts. The source fingerprint and formatting
receipt distinguish exact tested bytes from the final normalized successor.
