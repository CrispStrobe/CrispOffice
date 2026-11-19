# Qualified modular Mail reconciliation checkpoint — 19 November 2026

**Accepted at `0f16754c278aa83cc79d5777e5b45d3f739e5469`:** 404 passing application executions,
395 distinct case identities and
28 distinct suite paths; zero failures or skips.
This bounded follow-up qualifies the integration of incoming main
`76fe761f1c97c31ca8d8add405aa54c436a336aa` with the previously qualified Office continuation.
The frozen tree is `83d24b0ef7a82f9dfb65dc4e0b2015ee743f237c`.

The earlier [full checkpoint](../final/README.md) passed 1,898 executions / 1,327
distinct cases at `0bd53e3e`, published as `fb402a5d`. That record remains intact
and contributes zero executions to the totals below. The current source also
retains the newer modular Mail, selected-fragment Word routing and cancellation
repairs that arrived on main during the earlier run.

> **Subsequent main:** `666e9a2ea46f7aeaaa1d01b60aabea0c2fe6f0fd` adds
> Reply, Forward and Mark read after this source was frozen. That two-file
> change is being reconciled separately; the results here qualify `0f16754c`.

## Fresh qualification

Run interval: **19 November 2026, 13:22:03–13:28:30 CET**.

| Group | Suite executions | Passed cases |
| --- | ---: | ---: |
| `studio-mail-modular` | 8 | 95 |
| `mail-send-transaction-vm` | 2 | 14 |
| `mail-bounded-reader-vm` | 1 | 69 |
| `word-routing-engine-delta` | 3 | 47 |
| `word-language-editor-delta` | 2 | 44 |
| `studio-settings-footer-delta` | 6 | 95 |
| `hunspell-cancellation-delta` | 2 | 9 |
| `morphology-portable-contract-vm` | 1 | 9 |
| `mail-transport-boundary-node` | 1 | 3 |
| `mail-mime-entry-node` | 1 | 1 |
| `mail-fork-mime-entry-node` | 1 | 9 |
| `morphology-portable-contract-node` | 1 | 9 |
| **Native / Flutter VM subtotal** | **25** | **382** |
| **Node subtotal** | **4** | **22** |
| **Combined** | **29** | **404** |

The independent [raw-event audit](review/qualification-audit-refresh.json)
reconstructs complete starts/completions and exact nonempty suite coverage.
It verifies terminal success, no errors/skips/duplicate identities or
layout/tap/disposal diagnostics, all raw/compressed log and case-record hashes,
and unchanged source/runtime inventories. The
[case inventory](review/qualification-audit-refresh-cases.json) records each
execution. There are 9 cross-platform repeats;
the distinct count deduplicates by suite path and case name. The Node Mail
boundary suites are separate cases, not browser executions.

Strict analysis with fatal infos/warnings and formatting passed on all
**45 selected Dart paths**. Whitespace checks passed.
Both phases bind **5,187 complete source records**; all were
materialized. Native binds 11,167 runtime records and Node
binds 11,164; the verified union contains
11,168. Flutter 3.47.8, Dart 3.13.7 and Node v24.22.3
retain the previously verified SDK/archive provenance and bounded runtime files.
These checks do not constitute an operating-system snapshot.

Locked offline resolution succeeded after Studio added its direct workspace
dependency on `quds_mail_transport`. The root lock and package configuration
remain byte-identical; the dependency graph reflects that direct relationship.
No new SDK, hosted package or SQLite input was required. The exact command,
before/after hashes and output are retained in development evidence.

Full raw output, receipts, input inventories, dependency metadata and runtime
receipts are in the [qualification archive](qualification-evidence.tar.xz),
with an [exact per-member index](qualification-evidence.index.json).
Directly readable receipts: [native](native-verification.json) and
[Node](node-verification.json).

## Resulting behavior

**Confirmed Mail submission remains confirmed.** Incoming Mail introduced a
typed exception for a failure after SMTP had already accepted a message. The
Studio handler previously treated that exception as an uncertain send and
retained a retryable draft. It now clears the submitted draft and uncertainty
flag, keeps the mounted/current-session guard, and uses the existing localized
message stating that the sending server accepted the message. Generic
unconfirmed failures retain their existing handling. No raw cleanup error is
shown. A new regression verifies one submission, a blank subsequent composer
and no retry acknowledgement. It fails against incoming main and passes with
the fix; both original streams remain in the
[development archive](development-evidence.tar.xz), separately from these totals.

**Numeric morphology features are portable.** The exact qualified decoder and
its original `-99.0` assertion survive the merge. Finite plain-integer text gets
the decimal suffix that JavaScript otherwise omits, while fractions, exponents,
negative zero and strings retain their representation. VM and Node both execute
the unit contract on this final frozen source.

**Current main's behavior is retained.** Native/browser Mail separation, saved
messages, shared composer, discovery, bounded exact-UID loading and sequential
submission/copy/cleanup remain present. Current fixture suites replace the
superseded monolithic assumptions. Word retains selected fragment boundaries
when language properties already match and only the script route changes.
Inactive language slots, history and DOCX-save assertions remain strong.
The footer suite keeps all ten prior state cases and adds the three incoming
English/German/Arabic scaling and action cases. Cancellation immediately after
a progress callback remains covered.

## Preservation and merge scope

The [main-reconciliation preservation audit](review/main-refresh-preservation-08336f71.json)
binds the intermediate merge `08336f71` and its actual parents. All 5,039 incoming
`packages/` and `third_party/` records are retained: 5,031 are exact and eight
are reviewed exceptions. Those exceptions are the decoder/test pair, the typed
Mail branch and regression, stronger Word assertions, the footer-test union,
the active-slot API comment, and formatter-only layout in Studio strings.
The controller implementation, Arabic rules and all other incoming package
records retain main's code at that merge.

The first frozen attempt at `08336f71` passed all 382 native cases but was
rejected by strict analysis; Node had not launched. The
[retained attempt](attempt-083.md) records one native-fixture import mismatch
and twenty intentional `print` probes flagged by the lint rule. The
[two-file repair audit](review/static-fixture-repair-0f16754c.json) verifies the
explicit native import and a documented file-local lint annotation, with no
application, executable assertion or plan changes. Final main therefore has
ten reviewed record differences: the eight above and these two test-only
repairs. The failed attempt and development preflight contribute zero cases to
the accepted run.

All 7,830 incoming validation/evidence records remain preserved: 7,828 at their
original paths, plus exact copies of the incoming
[overview](incoming-overview-76fe761f.md) and
[old final plan](incoming-final-plan-76fe761f.json). All 39 files of the earlier
published `final/` record remain byte-identical. The
[recovery audit](review/recovery-audit-0f16754c.json) also accounts for all 460
fixed captured refs through 432 ancestors and 28 historical dispositions from
14 exact equivalence proofs. Historical host/main-sync qualifications and
failed attempts keep their original source identities.

The final evidence publication changes only documentation and recorded
evidence. The tested product/configuration/test/harness/plan input set is checked
against the published commit before merging. Git history and the PR record the
actual final publication and remote-main merge identities.

## Replay

Use the [pinned runtime restoration instructions](../final/README.md#reproduce-the-selected-gates)
in a separate clean worktree at `0f16754c278aa83cc79d5777e5b45d3f739e5469`. Keep runtime and output directories
outside that worktree. The unchanged independent auditor is available at
`../final/review/audit_qualification.py` in the published checkout.

```bash
cd "$OFFICE_REPO"
python3 -B docs/validation/document-review-notes-20261118/run_checks.py \
  --head 0f16754c278aa83cc79d5777e5b45d3f739e5469 --base 76fe761f1c97c31ca8d8add405aa54c436a336aa \
  --plan docs/validation/office-resume-main-20261119/main-refresh/native-plan.json \
  --runtime "$OFFICE_RUNTIME" --output "$OFFICE_RESULTS/main"
python3 -B docs/validation/document-review-notes-20261118/run_checks.py \
  --head 0f16754c278aa83cc79d5777e5b45d3f739e5469 --base 76fe761f1c97c31ca8d8add405aa54c436a336aa \
  --plan docs/validation/office-resume-main-20261119/main-refresh/node-plan.json \
  --runtime "$OFFICE_RUNTIME" --output "$OFFICE_RESULTS/node"
python3 -B "$OFFICE_AUDIT/audit_qualification.py" \
  --repo "$OFFICE_REPO" --source 0f16754c278aa83cc79d5777e5b45d3f739e5469 \
  --plan docs/validation/office-resume-main-20261119/main-refresh/native-plan.json \
  --output-dir "$OFFICE_RESULTS/main" \
  --plan docs/validation/office-resume-main-20261119/main-refresh/node-plan.json \
  --output-dir "$OFFICE_RESULTS/node" --report "$OFFICE_RESULTS/audit.json"
```

## Acceptance boundaries

This qualification covers controlled local contracts and widget behavior.
`studio_mail_web_test.dart` runs on Flutter VM; actual browser rendering,
file-picker/offline/CSP/storage behavior and performance remain separate.
Installed application/OS/IME checks, broader native/Wasm packaging, live mail
providers, live Zotero, external Word/LibreOffice interoperability and independent
English/German linguistic judgment also remain separate. The real morphology
host suite requires its verified native library and language bundle; it is
retained and explicitly excluded from this controlled selection, not counted
as a skipped or executed backend test.

No GitHub Actions run, job or queue was queried, dispatched or awaited.
