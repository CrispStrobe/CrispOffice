# Foreground bulk mail actions: local acceptance

This increment adds checked multi-message read/unread/flag/unflag operations to
the connected IMAP, EWS, Gmail and Microsoft 365 hosts. The
[behavior contract](../../roadmaps/mail/bulk-actions.md) defines selection,
identity, cancellation, provider evidence, outcomes and the remaining scope.
The durable remote-command journal remains the next milestone.

## Acceptance boundary

The completed source intake is bound to published checkpoint
`4772d52492076241c39fdee0990c950c92367b1f`. The evidence archive binds the exact
qualified working files, including the subsequently committed import ordering
in the visual test. No mail production source changed after its accepted runs.

The publication check subsequently found main commit
`e975cec13b289fe067ef406cd3044701ecc44744`, which changes Word layout,
deserialization and system-font filename aliases. That separate reconciliation
must be qualified and recorded before merge; the original acceptance archive
will remain immutable. It is not a claim that an unseen later main is tested.

GitHub Actions, workflow runs, checks and status endpoints were **neither queried
nor awaited**. The user authorized local acceptance, incremental remote saves
and the final merge to main.

## Accepted cohorts

| Cohort | Accepted result | Evidence within the archive |
| --- | ---: | --- |
| Mail core, Dart VM | 181 passed | `core-converged-tests-vm.log` |
| All three portable bulk suites, JavaScript/Node | 87 passed | `core-converged-tests-node.log` |
| Mail transport, Dart VM | 415 passed | `transport-converged-tests-vm.log` |
| Portable cloud/unsupported-provider tests, Node | 107 passed | `transport-converged-tests-node.log` |
| Complete shared mail UI package | 161 passed | `ui-converged-receipt.json` |
| Six complete Studio mail host suites | 352 qualified, no failures/skips | `host-consolidated-validation.json` |
| Localized visual probes | 8 passed; 21 inspected PNGs | `visual-final-receipt.json`, `visual-inspection.json` |
| Reconciled Word suites, VM | 771 qualified, no failures/skips | `intake-local-word-combined-cohorts.json` |
| Reconciled portable Word suites, Node | 725 qualified, no failures/skips | Same combined cohort record |
| Three committed BAS examples | VM/Node passed; parsed JSON equal | `intake-local-word-final-validation.json` |

These cohorts overlap. They must not be added into a unique-test total.
Core/transport and UI strict analysis and formatting passed. Eight distinct
host analyzer targets and the visual test passed strict analysis. Word strict
analysis/formatting and the focused captured-tip reruns passed as recorded.

The host total is an explicit consolidation: four unchanged complete green
suites from a mixed run (263 cases), plus clean complete reruns of both corrected
fixture suites (89 cases). The mixed run remains a failed run with 348 passes
and four failures. One test tapped before a filter rebuild; three incoming
tests used a retired selection key. The two fixture-only changes preserve the
intended assertions and leave product source unchanged. All 1,002 qualified
inputs were checked against the final acceptance snapshot.

The Word totals are assembled from the broad 757-case VM and 712-case Node
runs, replacing the prior named-suite results with complete expanded reruns
(171 VM and 160 Node). The captured Word branch adds thirteen compiler cases
and one integration case. Only those two test files changed; the other 367
scoped inputs were identical. The
[Word reconciliation summary](intake-local-reconciliation-summary.md) and
[combined cohort record](intake-local-word-combined-cohorts.json) give the exact
case names and published-source proof. These totals do not describe single
771-case or 725-case invocations.

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

Every PNG was directly inspected. Action labels, checked/busy states, one
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

[evidence.tar.gz](evidence.tar.gz) contains 264 files (3,021,830 bytes), including
raw logs, receipts, source reviews, validation runners, 21 PNGs, bootstrap
receipts and runtime configuration. Its SHA-256 is
`5ff4d171e28d83ea8804b5e112efe31725b7e9c83c2b81230223c09b3bfa6121`.
The [manifest](evidence-manifest.json) records every member hash/size and 1,107
unique qualified source/configuration paths. Its groups overlap: 268
core/transport, 1,002 host, 59 UI, 1,006 visual and 369 Word paths.

All accepted execution used Flutter 3.47.8 / Dart 3.13.7 and 202 verified locked
dependency archives. The workspace lock SHA-256 remained
`0d64a732cd7f6c7cc4e1e01255276f081b59e6f43039636c3d36f6785a958ce2`.
The official SDK archive SHA-256 was
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The genuine Flutter-generated native-assets map and locked SQLite asset hash
are retained; no library, dependency or SDK substitution was used.

Exact commands, working directories, exit codes, terminal test events and
source hashes are in the receipts. Each runner is included. To inspect or
rebuild the archive from the same runtime evidence directory:

```bash
python3 docs/validation/mail-bulk-actions-20261120/build_evidence.py \
  --runtime /absolute/path/to/quds-mail-work-20261120/runtime --inventory
python3 docs/validation/mail-bulk-actions-20261120/build_evidence.py \
  --runtime /absolute/path/to/quds-mail-work-20261120/runtime
```

The builder rejects missing/unfinished acceptance, changed qualified files,
image-hash mismatch, or concurrent edits during packing. Archive ordering and
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
