# Explicit provider Archive — work and qualification record

## Baseline and source preservation

Started 22 November 2026 from fork main
`3f3cb8508663dde917e913867908dbfd6c3efcf0` on remote checkpoint branch
`work/mail-connected-workspace-20261122`.

The initial intake fetched all 37 fork branch tips and checked all open PRs plus
the 100 most recently updated PRs. Every fetched branch tip was already contained
in main; the open PR collection was empty. All four upstream branch tips were
also already contained in fork main. Exact fork refs and recent PR dispositions
are preserved in [intake.json](intake.json). No history was discarded or rewritten.

## Selected increment

Implement an explicit connected-mail Archive workflow through the existing
durable foreground command journal. Gmail removes only the INBOX label;
IMAP uses an authoritative unique selectable `\Archive` folder; Microsoft 365
resolves the ordinary well-known Archive folder. Folder-based actions freeze an
exact destination and reuse Move identity receipts. EWS and providers without
an authoritative ordinary Archive folder require an explicit reviewed destination.
Existing independent archive-copy workflows remain separate.

This is an organization increment on the existing workspace foundations.
Connected multi-account navigation, rules, body search, provider-side Drafts/Sent
reconciliation and live-provider/platform qualification remain open.

## Accepted Mail qualification before the final Office intake

The repository-pinned **Flutter 3.47.8 / Dart 3.13.7** ran the normal Dart and
Flutter test commands locally. The committed workspace lockfile stayed unchanged.
The five accepted, disjoint cohorts contain **2,878 passing cases**, with zero
failures, errors or skips. Earlier overlapping runs and hidden loader cases are
excluded from this total.

| Cohort | Passing cases | Accepted raw reporter stream |
| --- | ---: | --- |
| Core package | 648 | [core-tests.log.gz](logs/core-tests.log.gz) |
| Native transport package | 612 | [transport-tests.log.gz](logs/transport-tests.log.gz) |
| SQLite store, including migrations and actual SIGKILL recovery | 1,138 | [store-tests.jsonl.gz](logs/store-tests.jsonl.gz) |
| Studio organization, journal hosts, message loading and bulk provider behavior | 301 | [studio-tests.jsonl.gz](logs/studio-tests.jsonl.gz) |
| Shared message-list controls, organization, ranges and compatibility | 179 | [shared-ui-tests.jsonl.gz](logs/shared-ui-tests.jsonl.gz) |

[qualification.json](qualification.json) records exact commands, working
directories, result counts, exit-code attribution and source provenance.
[artifacts.json](artifacts.json) records original and compressed SHA-256 values
and byte counts. Every compressed file is read back and checked against its
original bytes. Compression uses an empty original filename and `mtime=0`.

The store receipt captures unchanged hashes of its core/store inputs before and
after the accepted full run. Core and transport have original expanded logs,
successful process completions reported by the executing agent, and matching Git
subtrees. Their hashes observed during packaging are **not** presented as
execution-time captures. The original Studio/shared-UI runs did not capture input
hash snapshots; new integration runs provide separate before/after receipts.

The 20 new store cases are included in the 1,138 total. They verify Archive
receipt/pending-operation persistence, uncertainty after interruption, refusal to
replay, account and intent guards, preservation of dated Inbox/other-label views,
and read-only membership evidence that does not rewrite historical outcomes.
Migration fixtures construct the released v15 schema from `schemaV1`–`schemaV15`,
preserve all tables and binary draft/Outbox payloads, and reject unexplained
pre-existing Archive intent with rollback. Strict analysis and read-only
formatting passed for the changed source/test cohorts.

## Latest intake and integrated qualification

The Mail-only final fixes were preserved at
`a886d7d79ae3d63e78f09a9caeb8569da81243c9`. Fresh main
`4621326a5a452da475f219353c298d0f9b12470e` and Zotero branch
`50895a7b9670058e27d3f081626defac9ea1aebc` were subsequently integrated without
changing the Mail-owned source paths. The remote integrated checkpoint is
`8280277cd27bcc276d66b61f8073eddf37ca6e5e`, tree
`7587dec4e385c015f81c62df7992af378642cfed`.

**The 2,878 cases above ran before that final Office intake.** They are not a
claim that the combined tree was rerun in full. The following normal-runner
integration gates ran on checkpoint `8280277` and captured unchanged input hashes
before and after execution.

| Integrated cohort | Passed | Failed | Process exit | Evidence |
| --- | ---: | ---: | ---: | --- |
| Eight engine suites: Word VBA, Zotero formatting, style cascade and BiDi | 487 | 0 | 0 | [Engine receipt](integration/engine-receipt.json.gz) |
| Studio: 301 Archive/organization cases and 24 composer cases | 325 | 0 | 0 | [Studio receipt](integration/studio-receipt.json) |
| Shared message-list controls and compatibility | 179 | 0 | 0 | [Shared UI receipt](integration/shared-receipt.json) |
| Editor direction, Zotero controllers/rendering and Word golden | 23 | 1 | 1 | [Editor receipt](integration/editor-receipt.json) |

These integration commands have **1,014 passing cases and one failing golden
case**, with no skips. The engine receipt captures 1,383 input hashes. Each Flutter
receipt links the complete 5,891-file before/after input maps, including package
sources and root manifests. Raw reporter and stderr streams are retained.

Across the latest result for each distinct cohort, the qualification contains
**3,412 passes: 2,902 Mail cases and 510 incoming Office behavior cases**, plus
the one existing golden failure. This uses Core 648, transport 612 and store
1,138 from the earlier Mail phase, integrated Studio 325 and shared UI 179,
engine 487, and editor behavior 23. It does not add the overlapping earlier
301/179 UI runs, diagnostic reruns, loader events or setup smokes.

Final strict analysis and read-only formatting passed for all **67 changed Dart
files**. The initial format check correctly exited 1 on two incoming Zotero
files. The pinned formatter normalized layout and one optional trailing comma;
no behavior was edited. The [exact diff](integration/incoming-format-normalization.diff.gz),
[initial static receipt](integration/static-initial-receipt.json.gz), and
[final static receipt](integration/static-final-receipt.json.gz) distinguish these
post-test formatting changes from the test-qualified source. Tests were not
rerun after that formatter-only normalization.

The final intake found Zotero merge commit
`168297fea2df1f49cb1362f8ac21002edd222ac4`, which incorporates the integrated
checkpoint and has the **identical complete tree**
`7587dec4e385c015f81c62df7992af378642cfed`. The Mail branch advanced to retain that
ancestry. This adds no source change. [late-intake.json](late-intake.json)
records all 40 fork branches, four upstream branches and the latest PR review.
GitHub Actions queue completion is not an acceptance dependency, as requested.

### Open inherited Word golden mismatch

The editor command remains a failed command. Its existing Word import/reopen
golden differs in **3,378 of 896,000 pixels (0.3770089%)**. A clean detached
checkout of the pre-intake Mail checkpoint `a886d7d`, using the same pinned SDK
and an enforced locked offline dependency restore, reproduces exactly the same
failure mask. The actual and expected pixels within that mask are identical
before and after the intake. Running the integrated golden test alone also
produces byte-identical comparison images, ruling out the five-suite cohort as
the cause of this mismatch.

The incoming Zotero highlight change affects a separate 1,522-pixel region and
appears equally in actual and expected images. The failed region is disjoint
from that change. The isolated difference PNG SHA-256 in all three runs is
`259667dd068dc3b6fcd46d2c3f264b3bca75b8ba17319dbb8518f9b0e5a9dd06`.
For this fixture under the pinned Linux runtime, the Office intake introduces
no additional mismatch. The existing failure stays open; no golden baseline
was refreshed and no failing case is counted as passing.

The [controlled baseline receipt](diagnostics/pre-intake-golden-receipt.json),
[pixel comparison](diagnostics/golden-baseline-comparison.json),
[isolated integrated receipt](diagnostics/golden-alone-receipt.json), and
[image index](diagnostics/image-index.json) preserve the diagnosis. PNGs are
stored once per exact byte hash; original names map to those unchanged binaries.

## Preserved unsuccessful attempts

- The first full store run had 1,137 passes and one stale test that still called
  schema 16 a future version. The test now checks versions 17 and 18; the complete
  rerun passed all 1,138 cases. Both reporter streams and source receipts remain.
- The first Studio run had 300 passes and one offscreen picker-tap failure. The
  test explicitly scrolls the target into view, and the same 301-case cohort
  passed on rerun. The overlapping 20-case dialog rerun is retained separately.
- Initial new store fixtures exposed FTS tables without `rowid`, a mistaken
  assertion equating a retained view with authoritative sync membership, and a
  deliberately corrupt row stopped by its CHECK constraint. The fixtures were
  corrected; all 20 cases then passed and also passed in the full store gate.
- Initial runtime setup had a Flutter shell-wrapper temporary-file collision and
  a diagnostic timeout during SDK package resolution, before cases executed.
  Direct bundled Dart and verified locked SDK package restoration allowed the
  ordinary runners to proceed. No dependency implementation or test runner was
  replaced to conceal a failure.

The exact available failed logs are compressed under [attempts](attempts), and
the machine-readable dispositions are in `qualification.json`.

## Runtime provenance and practical scope

[runtime.json](runtime.json) records the official SDK release and archive hash,
locked dependency restoration and the exact SQLite native asset. The SDK archive
SHA-256 is `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The unchanged root lockfile SHA-256 is
`2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.
The locked SQLite asset SHA-256 is
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.

The SDK tool cache required 67 additional exact package archives beyond the
workspace cache. Each matched the SDK lockfile's SHA-256 before extraction;
standard `dart pub get --offline --enforce-lockfile` then completed successfully.
The [archive receipt](runtime/sdk-package-archives.json) preserves each result.
These setup smokes and overlapping focused runs are not added to product totals.

Qualification uses controlled Linux VM/widget fixtures, real SQLite and real
child-process interruption. It does not establish live IMAP/EWS/Gmail/Microsoft
365 service behavior, installed-platform integration, background execution or
complete Outlook/Thunderbird/eM Client parity. No real mail was sent.

## Remote source checkpoints

- `9d8758e5552f74ceb418b181d009e1ba96009350`: initial intake and typed Archive
  intent, before qualification.
- `dd00d169b8763994adda707ca16cd54c2f93c395`: provider implementation, receipt
  restoration, schema-16 journal support and protocol/workflow documentation.
- `a61f7c0746219f1fc82d44b5e9e9b3c6cdb13dd1`: Archive UI/provider host workflows,
  translations and the new persistence/migration tests.
- `a886d7d79ae3d63e78f09a9caeb8569da81243c9`: four tested final corrections,
  including IMAP mailbox aliases, the migration-version expectation and the
  offscreen picker test.
- `60ad22bd87bc578234f2062855fe730d86263f4d`: recent Word/main integration.
- `8280277cd27bcc276d66b61f8073eddf37ca6e5e`: combined Zotero/main integration
  used by the separately recorded integration gates.
- `168297fea2df1f49cb1362f8ac21002edd222ac4`: subsequent Zotero merge preserving
  the same complete integrated tree and adding its latest branch ancestry.

The CLI has no GitHub write credential in this executor. Authorized source
checkpoints therefore use the connected GitHub Git-data API: each uploaded blob
SHA and the resulting complete tree SHA are compared with the staged local Git
objects; the remote branch is advanced with an expected-head lease and no force.
The exact remote commit is fetched back before continuing. No token is copied,
no source history is discarded, and ordinary local validation uses the checkout.

The final publication receipt records the merged remote head and source
continuity after the integration gates finish.
