# Foreground bulk mail actions: local acceptance

This increment adds checked multi-message read/unread/flag/unflag operations to
the connected IMAP, EWS, Gmail and Microsoft 365 hosts. The
[behavior contract](../../roadmaps/mail/bulk-actions.md) defines selection,
identity, cancellation, provider evidence, outcomes and the remaining scope.
The durable remote-command journal remains the next milestone.

## Publication acceptance

The final accepted product/test source is published at
`79e10ef8375aa9950d624eb9702ba1ff19a19e8c`. It incorporates the latest captured
main `698209aa`, the completed foreground Mail feature and the corrected Word
rendering/font update from `e975cec1`. Final evidence-only checkpoints and the
remote merge/tree consistency checks are recorded on
[PR #273](https://github.com/CrispStrobe/quds_office_suite/pull/273).

The [publication reconciliation](publication-reconciliation.md) and
[source applicability proof](publication-source-applicability.json) distinguish
fresh combined-source gates from retained unchanged scopes. All 222 tracked
Mail package files and the overlapping 211 Mail Dart feature files retain
identical paths, modes and blobs through both later main reconciliations.

GitHub Actions, workflow runs, checks and status endpoints were **neither queried
nor awaited**. The user authorized local acceptance, incremental remote saves
and the final consistent merge to main.

## Qualification used for publication

| Cohort | Accepted result | Source/applicability record |
| --- | ---: | --- |
| Mail core, Dart VM | 181 passed | Original receipt; all 268 core/transport inputs unchanged |
| All three portable bulk suites, JavaScript/Node | 87 passed | Same unchanged core scope |
| Mail transport, Dart VM | 415 passed | Same unchanged transport scope |
| Portable cloud/unsupported-provider tests, Node | 107 passed | Same unchanged transport scope |
| Complete shared mail UI package | 161 passed | All 59 inputs unchanged |
| Six complete Studio mail host suites | 352 passed, no failures/skips | Fresh publication run; 1,002 stable inputs |
| Two complete Zotero editor/controller suites | 114 passed, no failures/skips | Fresh publication run; 1,011 stable inputs |
| Six Zotero engine suites | 282 qualified, no failures/skips | Five unchanged suites plus clean protocol rerun; 431 inputs |
| Localized visual probes | 8 passed; 21 PNGs | Fresh run; 1,006 stable inputs; exact image identity |
| Font loader/aliases | 9 passed | All 28 scoped inputs unchanged |
| Word rendering/VBA at corrected e975 checkpoint | 961 VM / 758 Node passed | Fresh 26-suite VM / seven-suite Node runs at `3f9d3647` |
| Three committed BAS examples at that checkpoint | VM/Node passed; semantic JSON equal | Source-bound Word receipt |

These cohorts overlap and must not be added into a unique-test total. All
required scoped strict analysis and formatting gates are clean.

The final Zotero engine total retains 234 cases from five unchanged complete
suites and replaces the protocol suite with a clean 48-case rerun after a
braces-only test correction. The exact transformation and identical case names
are verified. The earlier analyzer and receipt-parser failures remain historical.

The complete Word runs occurred before the final Zotero merge. Of their 492
inputs, 488 remain identical; exactly four Zotero libraries changed and are
qualified by the fresh engine/editor gates. The corrected layout/deserializer,
VBA parser, selected Word tests and BAS/portable drivers are unchanged. The old
full Word map is not relabeled as current, and no full 961/758 rerun after Zotero
is claimed. See the [rendering reconciliation](main-reconciliation.md),
[Word summary](final-main-word-summary.md) and
[final publication explanation](publication-reconciliation.md).

The earlier assembled 771 VM / 725 Node Word cohorts and consolidated 352-case
host cohort remain in the original archive, with their diagnostic history.
They were superseded by the later fresh runs, not added to them.

## What the mail checks establish

- A copied, bounded plan freezes 1–1,000 unique identities in one account,
  provider and mailbox. IMAP also freezes mailbox/UIDVALIDITY/UID identity.
- Sequential, single-use execution preserves one ordered receipt for every
  identity: confirmed, definitely failed, uncertain or not attempted. Unknown
  transport outcomes are never turned into success or a safe retry.
- Cancellation, uncertainty, stale scope and certified rate limits stop later
  dispatch. An in-flight request keeps its actual result. No automatic retry
  or detached background replay is introduced.
- An open popup carries its original checked identities and generation.
  Refresh, filtering, selection changes, account/folder transitions, reconnect
  and disposal cannot repurpose an old callback for a new scope.
- Only confirmed target flags are projected into the current view. Unknown
  independent flags remain unknown; open-reader state is retained, and bulk
  actions do not synthesize a complete cached observation.
- Typed provider mutation evidence survives the native loader and cloud/EWS
  adapters. Existing send throttling behavior remains compatible. The
  [provider review](provider-certainty-review.md) records primary sources and
  the provider-specific inference behind certified HTTP 429 rejection.
- The list respects visible loaded rows, search editing shortcuts, keyboard
  cursor identity and read-only cached hosts. English, German and Arabic
  controls, counts and per-message details are covered.

## Visual qualification

Actual Flutter rendering uses bundled Latin, Arabic and icon fonts at 1.4 text
scale. English/German/Arabic portrait probes use 440×850 logical pixels;
German/Arabic compact probes use 320×260. Five list variants each produce
selected, action-menu and working captures. Three completed-receipt variants
each produce a summary and details capture, for 21 PNGs.

Every original PNG was directly inspected; both later sets match those bytes
exactly. Action labels, checked/busy states, one
reachable Stop control, translated outcomes, refresh guidance and RTL placement
were legible, with no overflow/error indicators or missing glyphs. Compact
headers intentionally scroll, long message text uses ellipsis, and receipt
details scroll beyond the initially captured rows. The manual record includes
each inspected image hash and these limits.

## Frozen source intake

The [accepted audit](intake-local-accepted.md) and its exact offline replay
cover 38 fork branches, 274 fork PR heads, four upstream branches and four
upstream PR heads: **320 captured references, zero uncovered**. The cutoff is
the dedicated fetch completed at 20:57:12 UTC on 20 November 2026; the immutable
manifest was recorded at 21:08:35 UTC.

297 references are actual ancestors. The remaining 23 resolve through fourteen
independently recomputed historical equivalents: thirteen complete-tree
identities and one exact 37-path ODT replacement. The older failed audits are
preserved. Concurrent mail work, Word named measurements and regressions, the
workflow-removal history and Zotero history/evidence are reconciled explicitly
in the [source summary](intake-local-reconciliation-summary.md). The Zotero
[equivalence proof](intake-zotero-equivalence.md) verifies unchanged product
files; no additional Zotero runtime run is claimed here.

## Reproducible evidence

Three immutable archives preserve each completed acceptance boundary:

| Evidence | Members | Bytes | Manifest |
| --- | ---: | ---: | --- |
| [Original mail acceptance](evidence.tar.gz) | 264 | 3,021,830 | [Member hashes and original bindings](evidence-manifest.json) |
| [Word rendering/font reconciliation](evidence-final-main.tar.gz) | 121 | 2,614,173 | [Member hashes and corrected-source bindings](evidence-final-main-manifest.json) |
| [Final Zotero/publication reconciliation](evidence-publication.tar.gz) | 70 | 1,143,658 | [Member hashes and 1,244 current bindings](evidence-publication-manifest.json) |

The archive SHA-256 values are respectively:

- `5ff4d171e28d83ea8804b5e112efe31725b7e9c83c2b81230223c09b3bfa6121`
- `ed060f4d17229239a05c64d33c7b14a4fdab134175af97d1823bcde4440ba205`
- `ac2606e994cb91ca4d37eb099fb374d6a0d76902542f47a37d8c910837f3e814`

The compact final archive references the original 21 PNG members after proving
all fresh images are byte-identical, avoiding duplicate image data. Each pack
contains its actual logs, receipts, source decisions and reproduction runners.
The original archives and historical failures are never overwritten.

All accepted execution used Flutter 3.47.8 / Dart 3.13.7 and 202 verified locked
dependency archives. The workspace lock SHA-256 remained
`0d64a732cd7f6c7cc4e1e01255276f081b59e6f43039636c3d36f6785a958ce2`.
The official SDK archive SHA-256 was
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The genuine Flutter-generated native-assets map and locked SQLite asset hash
are retained; no library, dependency or SDK substitution was used.

Exact commands, working directories, exit codes, terminal test events and
source hashes are in the receipts. Each runner is included. To inspect or
rebuild an archive from its exact accepted source and runtime evidence directory:

```bash
python3 docs/validation/mail-bulk-actions-20261120/build_evidence.py \
  --runtime /absolute/path/to/quds-mail-work-20261120/runtime --inventory
python3 docs/validation/mail-bulk-actions-20261120/build_evidence.py \
  --runtime /absolute/path/to/quds-mail-work-20261120/runtime
```

The builders reject missing/unfinished acceptance, changed qualified files,
image-hash mismatch, or concurrent edits during packing. Use the corresponding
`build_final_main_evidence.py` or `build_publication_evidence.py` for the later
boundaries. Earlier builders deliberately reject subsequently changed sources.
Archive ordering and
metadata are deterministic, and every member is reopened and verified.
Inherited previous-milestone receipts, SDK/cache content, native binaries and
compiled JavaScript are excluded.

Earlier, failed, interrupted, superseded and mixed runs remain under `history/`.
This includes the provisional throttle classification, the direct-Dart
native-assets setup failure, host fixture failures, a Word declaration-order
fixture correction and tool-context interruptions without terminal results.
They are not counted as final passes. The final transport rerun used the
supported package:test native-assets mapping and passed all 415 VM cases.

## Scope limits and next increment

This qualifies foreground operations in the tested local runtime. It does not
claim live-account integration, real sends, installed platform release testing,
native browser/WASM execution, or a screen-reader usability study. Cached mail
stays read-only. Receipts do not survive closing the view or restarting the
application.

The next ordered increment is durable sessions and a remote-command journal:
persist intent and exact identity before dispatch, record acknowledgement,
reconcile uncertainty after restart/reconnect, and define cancellation/conflict
handling. Archive/move/delete and offline rules should build on that foundation.
Account-wide/unified search, saved views, conversations, richer authoring and
provider-specific calendar/people/security work remain subsequent milestones.
