# Native Zotero annotation insertion — locally qualified

## Result

**All final local gates pass on application commit
[`ff06e5544673ce7f70be983299241bcdcef780d3`](https://github.com/CrispStrobe/quds_office_suite/commit/ff06e5544673ce7f70be983299241bcdcef780d3),
tree `ee23dc2179d4b3e26eabf3b35e7aa13f95a7963d`.** The frozen run completed at
**06:42:09 CET on 19 November 2026** with **1,611 application cases across 98 test
files**, plus **66 Python accounting tests counted separately**.

This continuation is saved on
[`codex/zotero-word-parity-20261118`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-word-parity-20261118)
in [PR #173](https://github.com/CrispStrobe/quds_office_suite/pull/173). The
publication follow-up adds documentation and evidence only: application code,
tests, qualification plan and runner remain byte-identical to the qualified
source. Source checkpoints used non-forced expected-head updates, verified
remote reads and `[skip ci]`. **GitHub Actions were neither queried nor awaited.**

## What writers can do

With **Zotero 9 or later** running, place a supported collapsed body caret outside
an existing field and choose **Insert → References → Add Zotero annotation**, or
**Zotero → Document → Add annotation from Zotero…**. Zotero's own picker lets you
select one or more text annotations without first creating an intermediate
library note. This follows the native
[Add Annotation workflow](https://www.zotero.org/blog/zotero-9/#add-annotation).

| Workflow | Delivered behavior |
| --- | --- |
| Insert quoted passages and comments | Import text annotations, comments, supported formatting and links supplied by Zotero. |
| Keep citations active | Preserve linked source identity, locators and inline/footnote/endnote placement, with the correct document reading order for later refresh and bibliography work. |
| Undo or redo the whole insertion | Text, active fields, new notes and document preferences apply as one operation; surrounding prose and the resulting caret are retained. |
| Save and reopen | Quds DOCX serialization/reopening preserves the annotation text, linked fields, locators and note placement. |
| Cancel and return to writing | A cancelled native picker discards staged preferences and temporary fields. Direct commands return focus to the current document caret. |
| Handle unavailable or older Zotero | Keep a recoverable error and the Zotero 9+ requirement visible, with no automatic retry or fallback to a different picker. |
| Keep existing workflows | Add Note, native lists, citation/style/refresh/bibliography commands and Notes editing retain the preceding behavior. |

The new `ZoteroCitingCommand.insertsNoteText` predicate shares insertion preflight
and cancelled-picker handling between Add Note and Add Annotation. Body/Notes
composition, selection, ownership, protection, revision and stale-target guards
remain in place. The change adds no endpoint, credential store or web fallback.

## Recent work integrated first

Integration [`f3b7dc3bf4a994781e40fa89e076ebe485ce3d0d`](https://github.com/CrispStrobe/quds_office_suite/commit/f3b7dc3bf4a994781e40fa89e076ebe485ce3d0d)
preserves the supplied Zotero checkpoint `0abd0e59` and merges:

- Notes/document review: `840362cd74a3d4b4365cf2bc9a2ae326225009c3`.
- Thesaurus: `7e4adc08fce78fb95524f304962f9c1804e18691`.
- Mail: `086e15b7c059edd09cc77dea721f489b5ef97fa9`, already an ancestor of both.

The bounded **06:21:50 CET on 19 November** inventory contains **391 refs**:
212 fork branches, 175 PR heads and four upstream branches. The complete fresh
audit on qualified source verifies **363 ancestors + 28 historical equivalents,
zero unaccounted refs**, with all 14 historical proofs recomputed. Historical
equivalents remain non-ancestors. This describes the captured inventory, not
future ref updates.

The integration combines stable Review layout and Notes subtree identity,
document-level Notes keyboard history, composition safeguards and the Zotero
RTL field-reveal regression. Incoming IME tests retain both tracking modes and
undo assertions. Feature edits began only after integration. A separate source
review confirms no manifest/lock changes and byte-identical composition,
header/footer identity and numbering transaction safeguards.

- [Captured remote refs](reconciliation/remote-snapshot-20261119.json)
- [Audit on qualified application source](reconciliation/final-source-audit.json)
- [Integration and local/remote tree equivalence](reconciliation/published-source-audit.json)
- [Fresh-clone replay audit](reconciliation/published-replay-audit.json)
- [Merge-resolution review](reconciliation/merge-resolution-review.md)
- [Preserved safeguards and dependency inputs](reconciliation/final-feature-safety-review.json)

## Final local qualification

| Gate | Distinct test files | Passed application cases |
| --- | ---: | ---: |
| Engine | 36 | 644 |
| Editor | 48 | 773 |
| Studio | 7 | 99 |
| Mail core | 1 | 9 |
| Mail store | 5 | 75 |
| Mail UI | 1 | 11 |
| **Total** | **98** | **1,611** |

The qualification runner's **32** Python regressions and the current Mail
runner's **34** Python regressions pass separately. They are not application
cases. All **11 gates** pass. There are zero failed/skipped cases, reporter
errors, unfinished cases, duplicate completions or requested-suite discrepancies.
Earlier development runs contribute no cases to these totals.

Strict analysis uses `--fatal-infos`; all **33** selected Dart analysis/format
targets pass. The plan's whitespace baseline is the published integration
checkpoint, with zero exceptions. Integration application/tool whitespace was
checked separately against `0abd0e59`.

The independent auditor does not import the runner parser or execute tests. It
recounts raw events, verifies the exact commands and suite selections against
the committed plan, and checks raw/compressed/detail hashes. All **1,748 source
inputs** match both the clean checkout and the qualified commit's Git blobs.
Before/after source, runtime and dependency fingerprints and all **five
environment receipts** remain identical.

- [Final result summary](final/summary.json)
- [Independent count/hash/source audit](final/independent-audit.json)
- [Complete raw results and source snapshots](final/complete-results.tar.gz)
- [Archive and member hashes](final/archive.json)
- [Independent auditor](final/independent_gate_audit.py)
- [Frozen plan](plan.json) and [reused runner](../zotero-word-parity-20261118/run_local.py)

## Runtime

The verified runtime is Flutter **3.47.8** / Dart **3.13.7**. The official SDK
archive SHA256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
All **176** hosted package archives in the locked union were hash-checked.
SDK-tool and workspace resolution used `--offline --enforce-lockfile`; all
**17 workspace manifest/lock inputs remained unchanged**. The workspace setup
receipt names local `b818ca30`, whose tree equals published integration `f3b7dc3`.
No native-runtime blockage occurred in final qualification.

[SDK receipt](runtime/sdk-receipt.json), [package receipts](runtime/prefetch.json),
[tool resolution](runtime/tools-ready.json), [workspace resolution](runtime/workspace-ready.json)
and the [recorded environment](runtime/env.sh) preserve setup identities. Adjust
recorded absolute paths when reproducing in a different workspace.

## Review findings and development diagnostics

Peer review found no blocking product-code issue. It corrected one documentation
claim: Quds can atomically reject unsupported returned content, including image
markup, but cannot inspect annotation types or content that Zotero has already
omitted or replaced with text. The [guide](../../zotero-support.md) and acceptance
scope below now state that boundary. The original review records its finding as
pending at review time; the separate resolution binds the corrected guide.

- [Feature review](review/final-review.json)
- [Documentation resolution](review/documentation-resolution.json)

An early workspace cancellation fixture incorrectly completed without deleting
its provisional field and was correctly rejected. The fixture now follows the
native cancellation sequence, including `Field.delete`, and passes without a
production-code change. Initial and corrected UI diagnostics are retained in
[their separate archive](diagnostics/ui-development.tar.gz), with
[member hashes and scope](diagnostics/archive.json). Two early controller test
expectations were also corrected to allow equal-style run coalescing and the
existing protected-document error type. Those exploratory outputs were not
persisted as raw logs and are not represented as final evidence.

## Replay

In a clean checkout of the qualified application commit, with the pinned SDK,
verified package cache and enforced locked resolution prepared, set
`FLUTTER_ROOT` and `PUB_CACHE` for that environment and run:

```bash
python3 docs/validation/zotero-word-parity-20261118/run_local.py \
  --repo "$PWD" \
  --expect-commit ff06e5544673ce7f70be983299241bcdcef780d3 \
  --plan docs/validation/zotero-annotations-20261119/plan.json \
  --output ../zotero-annotation-replay
```

The output directory must be new and outside the checkout. Optional repeated
`--environment-input` arguments bind the local setup receipts, as in the
published run. The runner requires a clean frozen commit before and after each
gate. The report/evidence follow-up is not a replacement source identity.

After fetching the captured branch and PR objects, the ref audit can be replayed
without the unreferenced local merge objects:

```bash
python3 docs/validation/zotero-annotations-20261119/reconciliation/audit_published_refs.py \
  --repo "$PWD" \
  --head ff06e5544673ce7f70be983299241bcdcef780d3 \
  --snapshot docs/validation/zotero-annotations-20261119/reconciliation/remote-snapshot-20261119.json \
  --prior-audit docs/validation/zotero-word-parity-20261118/continuation/reconciliation/final-source-audit.json \
  --output ../zotero-annotation-ref-audit.json
```

## Acceptance boundaries

This upgrade supports **text annotations** at a supported collapsed body caret
outside an existing field. Returned images, tables, nested lists,
multi-paragraph list items and unsupported formatting are atomically refused.
Image and ink annotations are outside the supported workflow. Zotero may
substitute a notice or omit unavailable content before returning a result;
Quds cannot recover content absent from that result.

Qualification covers local model/controller/widget and controlled-transport
behavior, including Quds DOCX save/reopen. It does not establish a fresh live
Zotero session, installed OS shortcut acceptance, or actual Microsoft Word or
LibreOffice reopening. The older-version error regression models the inspected
native STOP-error callback; it is not acceptance against an installed older
release.

[Verified source checkpoints](publication-checkpoints.json) preserve the
incremental publication history. The preceding
[native-list qualification](../zotero-word-parity-20261118/README.md) remains
available with its own source identity and results.
