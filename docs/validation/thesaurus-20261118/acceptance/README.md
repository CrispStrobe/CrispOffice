# Thesaurus acceptance continuation — 18 November 2026

**421 targeted cases passed; the corrected release web fixture compiled.** The
captured review, Mail, Zotero and spaCy work is reconciled on the thesaurus
branch. Actual offline-browser execution, installed native desktop/IME
acceptance and independent linguistic review remain open.

This continuation starts at `0e84dc951e7a9e923107d7895fa457cf29a7af71`.
Application integration is frozen at `813a7cdd7d55f2028e377393ae6bbc7388f5db73`;
the browser fixture is frozen at `7530f83a5503987dbee5b9678af56116ca98621f`.
The final exporter controls bind their exact source hashes separately. The
earlier [606-case report](../resume/README.md) remains historical evidence and
is not added to the fresh counts here. No GitHub Actions run was queried,
dispatched or awaited.

## Reconciled incoming work

The [captured audit](incoming/README.md) accounts for all **210 fork branches,
172 PR heads and four upstream branches**: 386 refs and 251 distinct heads.
There are no unexplained or missing heads in that captured inventory. The
28 historical equivalent refs were freshly rechecked rather than reapplied.

The review head `4600c0ebc9ac5e6acabd92935821d1c15315f2c1` is a descendant of
the supplied handoff and already includes the newest captured Zotero Notes and
spaCy work. The merge then includes the seven follow-up commits unique to Mail
head `2fef06f5fe9aefb07a48c75c0e762eee3edf26e1`. The exact two parents and
main/handoff ancestry are preserved in the [merge receipt](incoming/incoming_merged_ancestry.json).
This is a bounded capture, not a claim about publications after that inventory.

Four source conflicts were reviewed. The result preserves measured title/ribbon
sizes and protected-document inspection from review, and adds Mail's compact
navigation, separate compact PDF scrolling, flexible status text and explicit
over-limit reply feedback. The combined Arabic draft regression runs at 390
pixels with increased text size and exercises the navigation sheet. The
resolved keyboard/context guards retain Shift+F7 for thesaurus and the existing
writing-review shortcuts.

## Acceptance corrections

### One worker owns the offline fixture

The pinned Flutter default bootstrap can configure Flutter's own worker at the
same scope as the test worker. Its generated unregister/reload stub creates a
competing registration path. The fixture now compiles with
`--pwa-strategy=none`, and installation rejects a bootstrap that still supplies
worker settings. This removes that configuration from the compiled fixture;
actual browser lifecycle behavior remains unqualified in this environment.

### Browser results must belong to the compiled build

Installation and browser replay require `--compile-receipt`. The binding checks
the successful command, current fixture hashes, unchanged source inventory,
compiled-file inventory and original compile-log hashes. Installation first
verifies every original compiled byte, then permits only its explicit
`index.html` replacement and `offline-install.js` addition. A recomputed offline
manifest around different application bytes cannot qualify the build.

The receipt is replayable local evidence, not a signed attestation. Historical
receipts without this binding cannot qualify the current changed fixture.

### Cache readiness verifies identities and bytes

The worker checks the exact expected URLs, response sizes and SHA-256 values in
bounded batches. Equal-count substitution and post-install corruption fail.
Missing or damaged installed assets cannot be hidden by a network fallback.
The existing actual-origin shutdown, offline reload, fresh provider session,
explicit replacement/undo/redo and fresh-tab panel requirements remain. Browser
query output now also retains source examples.

These changes belong to acceptance infrastructure. They do not install or
qualify a production site's deployment, updates, storage quota or eviction policy.

## Fresh validation

| Cohort | Passed | Suites | Evidence |
| --- | ---: | ---: | --- |
| Native headless thesaurus, guarded replacement, review, keyboard/language regressions, real packs and visual fixtures | 208 | 14 | [Receipt](native/receipt.json), [event audit](native/native-test-audit.json) |
| Studio draft proofing, compact navigation, keyboard review and Zotero shortcuts | 36 | 4 | [Integration summary](integration/summary.json) |
| Complete Mail UI suite | 30 | 4 | [Integration summary](integration/summary.json) |
| Complete Mail core suite | 28 | 4 | [Integration summary](integration/summary.json) |
| Complete Mail MIME suite | 32 | 6 | [Integration summary](integration/summary.json) |
| Engine thesaurus and Zotero note insertion | 65 | 2 | [Integration summary](integration/summary.json) |
| Python/Node browser-harness controls | 15 | — | [Receipt](controls/harness/receipt.json), [raw results](controls/harness/harness.stderr) |
| Review exporter/source-integrity controls | 7 | — | [Receipt](controls/review-packet/receipt.json), [raw results](controls/review-packet/stderr.log) |
| **Total** | **421** | **34 Dart/Flutter suites** | **399 Dart/Flutter + 22 Python/Node cases** |

All substantive cases passed, with zero failed/skipped cases, complete event
streams and no layout-overflow or missed-tap diagnostics. Lifecycle/loading
events are excluded. The 15 lexical queries in the native panel count as one
test, not 15. The engine cohort contains 24 provider and 41 Zotero cases.
Repeated control runs are counted once. This is targeted validation, not the
entire repository suite or a fresh rerun of every historical cohort.

Strict analysis with fatal infos passed for the four conflict-resolution paths
and the changed Mail message view. Formatting and scoped whitespace checks
passed. The 2,878 native/build input records and 2,195 integration input records
remained unchanged through their respective runs. Integration began at
`813a7cdd`; HEAD advanced to the fixture/documentation checkpoint during the run,
without changing those inventoried application/runtime inputs.

The [independent evidence audit](peer-audit.json) reconstructs counts from raw
events and checks source/log hashes. [validation-summary.json](validation-summary.json)
provides the compact machine-readable result. Raw logs, before/after inventories,
commands, per-cohort audits and runners are preserved in the evidence archive.
The [read-only audit script](audit_final_validation.py) and
[substantive case inventory](substantive-cases.json.gz) are retained separately.
Its complete byte-level replay requires the recorded execution workspace,
runtime and compiled/installed build as well as the archived logs; `--task-root`,
`--repo` and `--runtime` identify those locations. The receipt records the audit
performed here, including archive-member comparisons against the original logs.

### Web compilation and actual browser attempt

Release compilation passed with CSP, local web resources and PWA worker settings
disabled: **1,155 files / 87,397,428 bytes**. The installed test inventory contains
**1,156 files / 87,398,019 bytes**, excluding its two generated metadata/worker
files. [Installation evidence](native/offline-installation.json) binds those
files to the successful compile. The build retains the SDK's PWA-option
deprecation warning and the wider library's missing CupertinoIcons font notice;
the thesaurus uses Material icons. Both original build logs are preserved.

The fresh [browser attempt](browser/browser-report.json) failed during Chromium
startup, before application execution: the sandbox rejected its required Unix
socket (`EPERM`). It completed **zero browser steps and zero requests**.
An empty CSP/error list therefore does not establish browser correctness.
No permission or routing workaround was used. Browser rendering, CSP enforcement,
offline interaction, performance and lifecycle acceptance remain open.

### Visual fixtures and data continuity

The fresh renders are [English desktop](native/visuals/english-desktop.png),
[German desktop](native/visuals/german-desktop.png) and
[narrow German with larger text](native/visuals/german-narrow-large-text.png).
These are native headless widget renders, not screenshots of an installed app.

The [pack continuity receipt](pack-continuity.json) proves the entire thesaurus
asset subtree is identical to the handoff. The existing 107,519 English and
50,264 German meaning groups, source archives, licensing and deterministic-build
evidence are retained. No additional full regeneration or broader vocabulary
qualification is claimed by this continuation.

## Ready for independent review

The [linguistic review packet](linguistic/linguistic-review.md) contains **15
actual queries and 109 distinct source-verified meaning records** from this
native run. It preserves examples, labels, literal terms, sense IDs and related
concepts. [Companion JSON](linguistic/linguistic-review.json) also retains full
source records, term notes, term relations and identities. Ten original source
notices are copied byte for byte beside the packet with attribution and hashes.

Every reviewer identity, decision and recommendation is blank; its status is
`not_reviewed`. The exporter rejects stale pack identities, modified source
observations and incomplete panels, escapes source text as data, writes UTF-8,
and refuses to overwrite an existing review directory. Exporting it is neither
a new provider run nor human approval.

The [release acceptance guide](../../../roadmaps/thesaurus/release-acceptance.md)
now gives concrete browser replay, installed Studio and real OS/IME checks,
evidence fields and a linguistic review procedure. The Word host is the editor's
Studio example with Linux/Windows runners; the separate Report Studio designer
is not the application being qualified here.

## Runtime, archive and replay

The fresh run used verified **Flutter 3.47.8 / Dart 3.13.7**. The official SDK
archive matched its recorded SHA-256 and release manifest. All 170 required
hosted package archives were verified; the incoming committed lock remained
unchanged during offline enforced-lock resolution. All 15 workspace manifests
matched the source checkout. [Runtime readiness](runtime/runtime-ready.json),
[independent setup checks](runtime/readiness-audit.json) and the
[setup archive index](runtime/index.json) preserve the details. The setup receipt
was created while the resolved merge was staged; final manifest/lock hashes
remain the ones used by the executed checks.

[evidence.tar.gz](evidence.tar.gz) retains 50 exact evidence members. Its
[index](evidence-index.json) records every byte size/hash and a successful
readback. Extract it beneath this directory to restore native/integration raw
logs and the paths used by the compact receipts. Compiled application binaries
are represented by the bound inventory, rather than checked in again.

```sh
tar -xzf evidence.tar.gz
```

The runtime setup archive contains the executed recovery scripts and original
logs. They retain the recorded task-root paths; relocate those consistently or
use an ordinary installation of the same pinned SDK and committed lock. The
native/build runner expects sibling `quds_office_suite`, `zotero-validation` and
`zotero-toolchain` paths; the latter two may be prepared workspace/toolchain
aliases as in this run. Always choose new output directories.

```sh
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/run_final_validation.py \
  --root "$PWD" --output "$PWD/new-thesaurus-validation"
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/install_offline.py \
  new-thesaurus-validation/browser-build \
  --compile-receipt new-thesaurus-validation/receipt.json
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/run_browser.py \
  new-thesaurus-validation/browser-build \
  --compile-receipt new-thesaurus-validation/receipt.json \
  --output new-thesaurus-browser-acceptance
```

## Open release checks

- Actual offline-browser acceptance on a host that can launch Chromium.
- Installed native Studio and real OS/IME acceptance. This environment lacks
  the required native compiler/GTK/display setup.
- Independent English/German linguistic review of the packet and application.

Literal replacements, bounded morphology, the shared German regional corpus,
and the absence of automatic agreement, reinflection or contextual sense
selection remain explicit product boundaries. PR #169 stays a draft.
