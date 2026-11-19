# Frozen Office continuation qualification — 19 November 2026

**Accepted: 1,898 passing application executions, 1,327
distinct case identities and 68 distinct suite paths.**
There are zero failures or skips. The native/VM selection and its Node repeats
ran against the same frozen source and plans. Historical and development
executions contribute zero to these totals.

| Binding | Exact identity |
| --- | --- |
| Qualified source | `0bd53e3e2b0d75ae48a4d7807dcddd123ab477f9` |
| Qualified tree | `37d9017ca00c5abe491819af3373e83b80a4da98` |
| Captured main | `b070e228a749e22cc8ce2098029a76ab5fb8eccb` |
| Remote integration branch | `codex/office-final-union-20261119` |
| Run interval | 19 November 2026, 12:50:59–13:00:00 CET |
| Runtime | Flutter 3.47.8 / Dart 3.13.7; Node v24.22.3 |

The source checkpoint was published and read back before testing. This evidence
publication changes only reports and retained evidence; it leaves the full
qualified product, configuration, test, harness and plan input set unchanged.
The final PR/merge outcome is established by Git history and remote readback,
not by predicting a future merge SHA in this report.

> **Subsequent main:** `76fe761f1c97c31ca8d8add405aa54c436a336aa` arrived
> after this source was frozen. Its modular Mail and other changes require
> separate reconciliation and validation; the counts here qualify `0bd53e3e` only.

## Fresh results

| Group | Suite executions | Passed cases |
| --- | ---: | ---: |
| `office-proofing-engine-vm` | 17 | 725 |
| `english-proofing-contracts-vm` | 3 | 29 |
| `office-proofing-editor` | 20 | 332 |
| `studio-functional-host-integration` | 24 | 213 |
| `hunspell-provider-vm` | 3 | 19 |
| `arabic-morphology-contracts-vm` | 1 | 9 |
| `arabic-language-node` | 6 | 551 |
| `hunspell-contracts-node` | 1 | 11 |
| `arabic-morphology-contracts-node` | 1 | 9 |
| **Native / Flutter VM subtotal** | **68** | **1,327** |
| **Node subtotal** | **8** | **571** |
| **Combined** | **76** | **1,898** |

All 571 Node case identities repeat native cases.
They increase execution coverage across runtimes, not the distinct-case count.
Strict analysis with fatal infos/warnings and formatting passed for
**37 selected Dart paths**. Whitespace checks passed in both phases.
Node execution does not establish browser behavior.

The [independent qualification audit](review/qualification-audit-accepted.json)
reconstructs counts from complete raw reporter events, checks exact nonempty
suite coverage, starts/completions, terminal success, error/skip absence,
duplicate identities, raw/compressed log hashes and case/error records. Its
[case inventory](review/qualification-audit-accepted-cases.json) records every
execution. The [auditor controls](review/auditor-controls.json) contain 16
controls, including rejected incomplete, skipped, failed and duplicate streams;
they contribute zero product cases.

Both phases bind all **5,164 source inputs**, with no sparse
omissions and unchanged bytes before/after. The native phase binds
11,165 runtime records and Node binds
11,162; their union is 11,165. The audit also
rechecks the 11,142 retained runtime files, 176 locked archive receipts, resolved
133-package mapping, test launcher, Node binary and native asset bindings.
These are bounded input checks, not an operating-system snapshot.

The runtime was restored from the complete verified official SDK stream before
any extracted executable ran. Its archive SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`;
the workspace lock is
`35d1ef372908f4ab278973355ec6a957cd3240bea115d615056c5b9e398df974`.
The [indexed qualification archive](qualification-evidence.index.json) contains
the complete raw runs, before/after inventories, receipts and runtime provenance.
The [native receipt](native-verification.json) and
[Node receipt](node-verification.json) are also directly readable.

## Behavior completed

- **Studio Mail:** keep main's functional IMAP/SMTP client. Async connection,
  mailbox, message and compose completions must belong to the current mounted
  session before updating UI. Abandoned connection candidates are disconnected,
  cleanup errors are contained, and replaced readers are retired after the
  frame. The refreshed dialog/lifecycle tests include 28 cases and the complete
  English → German → Arabic → English label cycle.
- **Word language metadata:** edit each selected fragment's active DOCX language
  slot while retaining the inactive Latin/complex-script slot, East Asian
  metadata, styles, formatting and unselected text. Tests cover reset,
  inheritance, undo/redo and DOCX round trips; the selected language intentionally
  differs from the inactive slot to expose accidental overwrites.
- **Notes and Review:** Notes visibility participates in workspace config
  caching. The footer distinguishes complete, partial, paused, scheduled and
  active checking, including compact controls with useful tooltips. Controlled
  proofing providers are installed before Settings animations. Test viewport
  repair aligns actual view metrics with render constraints; it retains all
  seven wide-state cases and adds three compact-state controls.
- **About links:** Source Code and Website attempt an external launch directly.
  A capability-query rejection can no longer suppress a valid launch attempt.
- **Arabic matching:** preserve semantic hamza/madda marks and UTF-16 mapping.
  Phrase, date, implausible-year and double-future rules use the existing Unicode
  token boundary class so they cannot partially rewrite larger mixed-script
  tokens. The broad 65,848-byte word-table section and all 28 preexisting
  static constants/tables retain their captured identities.
- **Portable morphology:** finite plain-integer feature text receives its
  decimal suffix on JavaScript, preserving the existing `-99.0` contract.
  Fractions, exponents, negative zero and string values retain their meaning.
  Both original assertions remain; one added case covers these representations.
- **Dictionary setup:** retain the web cancellation guard and both incoming
  installer cancellation suites. Documentation now describes the implemented
  Studio setup dialog and provider registration accurately.

The [numeric source delta review](review/numeric-source-delta-0bd53e3e.json)
confirms that the final portability repair changes exactly two of 5,157
product/configuration records relative to `47ce5f72`; 5,155 are identical.
The [prior delta review](review/source-delta-review-47ce5f72.json) records the
earlier Arabic boundary and fixture repairs at their own source revision.

## Reconciliation and preserved history

The [actual final recovery audit](review/recovery-audit-0bd53e3e.json) accounts
for the fixed capture of **460 actual refs**: 436 fork refs (229 branches,
190 PR heads, 17 tags) and 24 upstream refs (four branches, four PR heads,
16 tags). It verifies 432 ancestors and 28 historical dispositions through
14 freshly recomputed exact equivalence proofs. HEAD and peeled tag
advertisements are excluded. The earlier 459-ref audit remains historical;
the current capture includes the additional saved continuation branch
`codex/office-continuation-20261119`.

Both complementary continuations are present through the union of `004b2ad6`
and `10bd0cc4`, checkpointed as `911d8f43`, then corrected at `47ce5f72` and
`0bd53e3e`. The old resume branch moved concurrently to `409258f9`; a guarded
update refused to overwrite it, so this work continued on its own branch.
Its alternate conflict resolutions were reviewed rather than merged wholesale;
the reproducible token-boundary defect was repaired while newer metadata
preservation and compact footer behavior were retained. Subsequent unrelated
branch activity is outside the fixed capture.

All **132 retained historical evidence files**, ten archives and **828 archive
members** from the two continuation records remain byte-identical. Their test
counts retain their original source attribution:

| Historical record | Qualified source | Executions / distinct cases / suites |
| --- | --- | ---: |
| [Host integration](../../office-main-integration-20261119/host-final/README.md) | `9833831a013c98a8ce5c3f5e6f45de36593cb7df` | 1,285 / 979 / 56 |
| [Main synchronization](../../office-main-sync-20261119/README.md) | `5c18db77505f876bf70bf7e89c49e8c3b617e0d4` | 1,026 / 634 / 38 |

The [Mail continuity review](review/mail-continuity-0bd53e3e.json) independently
verifies 395 package/configuration records against captured main and rechecks
all 394 historical manifest records. This is preservation evidence. The fresh
Studio consumer tests are reported above; old Mail/backend/native qualification
is never relabeled as a new run of those unchanged libraries.

## Failed attempts retained unchanged

- [First combined attempt](first-attempt.md), source `911d8f43`: 1,312
  executions, 1,303 passes and nine failures. Two legacy expectations conflicted
  with the active-language-slot contract; seven footer fixtures supplied render
  size without the view metrics used by MediaQuery. Original raw failures and
  receipts remain in the indexed archive.
- [Portability attempt](portability-attempt-47.md), source `47ce5f72`: the
  native selection passed 1,326 cases. Node passed 569 and failed one original
  morphology assertion because `-99.0` became `-99`. The combined auditor
  correctly rejected 1,896 executions with one failure.
- The separate development archives preserve nine reproduced Arabic failures
  plus two passing controls, their green run, language/footer checks and the
  morphology VM/Node preflight. Development and failed-run counts contribute
  zero to final accepted totals.

## Reproduce the selected gates

Use a separate worktree at the exact source above and an empty output location.
The published auditor lives in this report's `review/` directory; point
`OFFICE_AUDIT` to that published copy while testing the frozen worktree.
The [runtime restorer](../../document-review-notes-20261118/runtime/restore_runtime.py)
requires Python, PyYAML, the pinned download hosts and an installed Node;
it creates an external runtime directory and enforces locked resolution.

```bash
OFFICE_REPO=/absolute/path/to/qualified-worktree
OFFICE_RUNTIME=/absolute/path/to/verified-runtime
OFFICE_RESULTS=/absolute/path/to/new-results
OFFICE_AUDIT=/absolute/path/to/published-checkout/docs/validation/office-resume-main-20261119/final/review

python3 "$OFFICE_REPO/docs/validation/document-review-notes-20261118/runtime/restore_runtime.py" \
  --repo "$OFFICE_REPO" --runtime-root "$OFFICE_RUNTIME" --node-tests
source "$OFFICE_RUNTIME/env.sh"
cd "$OFFICE_REPO"

python3 -B docs/validation/document-review-notes-20261118/run_checks.py \
  --head 0bd53e3e2b0d75ae48a4d7807dcddd123ab477f9 --base b070e228a749e22cc8ce2098029a76ab5fb8eccb \
  --plan docs/validation/office-resume-main-20261119/final/plan.json \
  --runtime "$OFFICE_RUNTIME" --output "$OFFICE_RESULTS/main"
python3 -B docs/validation/document-review-notes-20261118/run_checks.py \
  --head 0bd53e3e2b0d75ae48a4d7807dcddd123ab477f9 --base b070e228a749e22cc8ce2098029a76ab5fb8eccb \
  --plan docs/validation/office-resume-main-20261119/final/node-plan.json \
  --runtime "$OFFICE_RUNTIME" --output "$OFFICE_RESULTS/node"
python3 -B "$OFFICE_AUDIT/audit_qualification.py" \
  --repo "$OFFICE_REPO" --source 0bd53e3e2b0d75ae48a4d7807dcddd123ab477f9 \
  --plan docs/validation/office-resume-main-20261119/final/plan.json \
  --output-dir "$OFFICE_RESULTS/main" \
  --plan docs/validation/office-resume-main-20261119/final/node-plan.json \
  --output-dir "$OFFICE_RESULTS/node" --report "$OFFICE_RESULTS/audit.json"
```

## Acceptance boundaries

This is bounded local integration qualification. Actual browser rendering,
offline/CSP/storage behavior and performance, installed app/OS/real IME use,
broader platform packaging, live mail providers, live Zotero, external
Word/LibreOffice interoperability and independent English/German linguistic
judgment remain separate acceptance work. Fresh morphology/provider contracts
do not establish a newly downloaded live language model or native/Wasm backend
on this host. Earlier such evidence remains preserved at its recorded source.

No GitHub Actions runs, jobs or queues were queried, dispatched or awaited.
