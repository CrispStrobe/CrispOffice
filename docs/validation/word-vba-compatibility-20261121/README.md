# Word VBA header/footer continuation — 21 November 2026

Work branch: `codex/word-vba-compatibility-20261121`.

## Scope

Extend the bounded Word source compiler to explicit existing header/footer
paragraphs, with all six primary/first-page/even-page variants. Preserve native
transaction, policy, recording and source resource limits. Reject unsupported
whole-story writes, linked/shared/opaque targets and nonbody list operations.
The exact supported source contract is in [VBA_WORD_MACROS.md](../../VBA_WORD_MACROS.md#existing-header-and-footer-paragraphs).

## Incoming work

[The intake audit](intake.md) and [machine-readable snapshot](intake.json) show
that baseline main `e2abbcda6d19f932bfbacc85e0dafd41a3c478f8` includes all captured
recent work. Forty-six fork heads and 100 recent PR heads are accounted for by
ancestry or independently replayed historical equivalence. All four upstream
branch heads and all four upstream PR heads are ancestors. The fork had no
open PRs at intake. No additional incoming feature merge was needed.

## Qualification status

This incremental checkpoint records implementation in progress. Final source
hashes, executed acceptance commands, counts and limitations will be added
after local qualification. GitHub Actions, jobs, checks and statuses are not
used as an acceptance gate and are not awaited.

The genuine Dart-only baseline environment uses official Dart 3.14.1 and the
repository's locked hosted dependencies. The two existing Word section suites
passed 97 visible tests before feature development. This baseline result does
not qualify the new implementation.

No installed Microsoft Word differential run or Flutter UI run is claimed.
