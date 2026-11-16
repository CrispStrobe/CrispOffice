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
