# Proofing continuation reconciliation — 16 November 2026

## Inputs and ancestry

The starting continuation was `81f4b77a9e77b0f08439ab13c2799ed1ee3e8efd`.
The audit at **2026-11-16 14:07:59 UTC** covered **55 branches and 64 PRs**.
PR #63 (Zotero capabilities) was the only open PR. PR #64 is included in main
`47aa74ab2c45a5ce514343b44296a1a14fa3ae95`, first saved here in
`611204fca81d1cd233fcbeb9d0c6e6b267d3fd22`.

The integration retains `c0403890fc00f38c0ee6e1d533f6fef549c6fc03`,
`9de43669088c3719d541c9fe1c7dcb3ffbf86df3` and
`2e92a49c2cf39128a79d2c037c3e07bbace1d1ae` as merge parents.
Six remaining heads are patch-equivalent to main; their histories are retained
as additional parents with no duplicate source changes. The exact refs and
PR inventory are in [remote-audit.json](remote-audit.json).

The original proofing and continuation histories have four merge bases.
The 42 commits following original source `f4d52e5` contain documentation and
validation evidence only. A single-base API comparison overstates new code.

## Reconciliation decisions

- Keep the continuation's standalone proofing session API, explicit provider
  outcomes, source snapshots, grapheme checks, generated-field exclusions,
  tracked insertion guards and story-aware correction history.
- Retain the complete original proofing [final evidence](../final/README.md),
  including original compressed source/bundle manifests and complete logs.
  Retain the continuation's earlier records alongside it. These are historical
  results for the exact sources named in their receipts.
- Preserve the current Zotero capability evidence and documentation, current
  main ODS changes, source aliases, dialog field-scan reuse and session backoff.
- Combine incoming RTL/zero-source presentation handling and hyphen caret
  endpoint ownership with the continuation's source-length selection and
  explicit discretionary-glyph fallback when display metadata is absent.
- Select only default header/footer paragraphs rendered on the target page,
  synchronize the final IME paragraph/selection, and use the session's half-open
  finding hit ranges without creating paragraphs in an empty document.
- Keep Harper source/artifact hash checks before host installation, build source
  stability checks, bounded startup/cleanup, packaging tests and dynamic
  upstream notice validation.
- Integrate dialog input ownership and metric ruler settings. Also rebind input
  ownership when a mounted editor receives a different controller, and reject
  stale selector traffic as well as text/action callbacks.

## Validation status at the integration checkpoint

This checkpoint is saved before new combined Dart/Flutter verification.
The environment exhausted its shared filesystem while preparing Dart and
dependency resolution. Subsequent sandbox processes, including cleanup,
could not start. An escalation request to remove an optional task-owned runtime
asset was rejected because escalated shell execution is disabled.

The exact combined source has **not** inherited passing status from either
previous session. New Dart/Flutter source and regression tests must be run
against this checkpoint or a later recorded source.

Before disk exhaustion, the five Harper Python packaging/license tests passed,
the five Harper Python tools parsed, and the scoped diff check passed. These
checks cover packaging logic, not native library execution.

No GitHub Actions, workflow, check-run or commit-status endpoints were queried.
The experimental German model remains disabled; its retained evaluation was
not rerun. Browser/CSP, mobile dictionaries and non-Linux native acceptance
remain separate platform checks.

## Additional checking fixes

The next checkpoint fixes standalone soft-hyphen/mark tokenization, apostrophes
inside quoted words, lowercase `ich ist` / `du ist` agreement, comparison
phrase false positives, and uppercase replacement preservation. Built-in
spelling, writing and terminology providers omit pattern matches whose endpoints
split a grapheme, preserving ordinary findings elsewhere in the paragraph.
They do not widen replacements over adjacent combining marks or joiners.

Eleven new German-core regression tests cover these cases through the real
provider/service contract. Six caret ownership tests (four inherited and two
new), four navigation tests, and five input-ownership widget tests accompany
the integrated editor work. Added tests have not been executed in this session.

The executor subsequently disconnected and is explicitly **unavailable**.
Dart 3.13.7 was installed and identified, but dependency resolution failed with
ENOSPC before producing a runnable test configuration. No new Dart analysis,
Dart tests, Flutter tests or builds are reported as passing.

Source and test changes were saved through GitHub's Git-data API with expected
branch heads and without force updates. GitHub Actions remain unused.

## Bounded late incoming update

A subsequent inventory, acquired between 14:21:39 and 14:26:47 UTC, covered
**58 branches and 66 PRs**. It is pinned in
[late-remote-audit.json](late-remote-audit.json). Before final validation the
continuation also incorporates:

- Main `90024d5`: PR #65 ODS filter comparisons and PR #66 documentation.
- Zotero `2480f09`: a historical qualification checkpoint with explicit raw-log
  limitations; its test totals are not attributed to this continuation.
- The original documentation/feature/vendor filter-operator histories, whose
  source patches are already represented by main.

The incoming source paths matched the previous main blobs byte for byte in the
continuation, so this update does not overlap the new proofing code. The source
is then frozen for local validation rather than following concurrent pushes.
The inherited ODS tests establish their stated numeric-comparison/export scope;
empty/not-empty semantics were not qualified by this proofing work.

A fresh execution environment became available after the earlier disconnect.
Validation is being rebuilt from the saved remote source. The failure record
above is preserved; a later source-bound receipt records any successful checks.

## Ancestry confirmation and final review

The independent final inventory at **14:27:44 UTC** still showed 58 branches
and 66 PRs. Its exact ref and blob equality evidence is preserved in
[remote-refresh-142744.json](remote-refresh-142744.json). GitHub comparison of
each observed head against `bfb24bf57d5efd52f00ab7079b4ac8968259a478` confirmed
that **all 58 heads are ancestors**, with no exceptions; see
[ancestry-verification.json](ancestry-verification.json).

Final review adds two bounded fixes before testing. The editor reconciles IME
attachment when the route becomes current even if its FocusNode never changed.
It performs this only for route identity/current-state changes, avoiding
unrelated MediaQuery updates reopening the keyboard. Body proofing navigation
clears equation, visual, frame and table selection using the existing
controller helpers before selecting the target text. The focus test now
requires automatic reattachment, and two additional navigation tests exercise
actual equation and visual/frame editing targets.
