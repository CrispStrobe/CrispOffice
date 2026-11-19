# Office continuation and final main reconciliation — 19 November 2026

## Continuation scope

The supplied unfinished handoff was published as `a4b73fe40387d62c27477bb640f14a2694d031d8`
on `codex/office-current-reconciliation-20261119` and is already an ancestor of
captured main `b070e228a749e22cc8ce2098029a76ab5fb8eccb`.
Its 801-execution qualification remains historical evidence at its recorded
source. This continuation preserves newer main, including the functional
IMAP/SMTP Studio client, Arabic T2 rules and native Camel Morph integration.

The user requested complete recent-reference reconciliation, incremental remote
checkpoints and a final merge to main. No GitHub Actions run, job, status or
queue is queried, dispatched or awaited. Existing release acceptance boundaries
remain explicit; local tests do not establish external-service or installed-app
acceptance.

## Bounded reference capture

The [initial immutable audit](reconciliation/reference-audit-current-main.json)
accounts for 459 actual references: 228 fork branches, 190 fork PR heads,
17 fork tags, four upstream branches, four upstream PR heads and 16 upstream
tags. Seven peeled-tag advertisements are excluded. At captured main there are
429 ancestors, 28 freshly verified historical equivalents and exactly two
unmerged references:

| Branch | Captured head |
| --- | --- |
| `codex/office-main-integration-20261119` | `c63558c0b3bc713361771cc29b0d89ecf2fa09a7` |
| `codex/office-main-sync-20261119` | `1b6d280b6ed41a1e01736a88f6d02431057c8611` |

All 14 historical equivalence proofs were recomputed through exact complete-tree
or complete changed-path mode/type/blob identity. The saved union audit is a
graph projection only. An actual integrated-head audit and fresh local
qualification will be recorded before completion.

## Reviewed integration decisions

- Keep main's functional IMAP/SMTP client. Adapt lifecycle and dismissal checks
  to that client; obsolete saved-message UI tests are not valid acceptance for
  the current dialog.
- Preserve newer Arabic T1/T2 tables, native morphology wiring, Unicode script
  detection and established two-slot Word language controls.
- Retain incoming semantic-mark regressions and prevent phrase matching from
  deleting combining maddah and hamza spelling content.
- Preserve both branches' complete historical qualification records and failed
  attempts with their original source attribution. Their case counts are not
  added together or relabelled as fresh validation of this source.

The combined source is being frozen for fresh qualification. This checkpoint
is not yet an accepted qualification result.


## Remote checkpoints and validation plan

The first merge is saved at `004b2ad6342cae7b2fe2750dbba5a9fdcebd3413`.
It retains the complete `c63558c0` history and adapts its Mail lifecycle controls
to main's current IMAP/SMTP UI. The second merge retains `1b6d280b` and preserves
main's newer public language and native lifecycle contracts.

The remaining source changes prevent token-interior Arabic phrase matches,
keep separately formatted complex-script Word runs separate, preserve multiple
findings from the same provider, honor dictionary cancellation at the final
progress callback, and distinguish paused, scheduled and partial Review results
from a completed clean check. Studio Settings/Notes and review fixtures use the
current UI. The AyaSpell builder's executable AST and pinned constants are
unchanged; only its generated card and corresponding wording assertions differ.

The [native plan](native-plan.json) selects 33 affected test files; the
[Node plan](node-plan.json) repeats seven portable engine files. Strict analysis
and formatting cover every changed application/test Dart path. Three separately
compiled C ABI libraries expose native lifecycle counters; they contain no real
Hunspell dictionary. The native web-host tests use controlled HTTP clients and
do not claim actual browser execution. Offline publisher and packaging controls
are run separately from application test counts.

The [independent saved-evidence audit](review/saved-evidence-independent-audit.json)
verified all ten incoming archives and 828 members, including rejected attempts.
It recounts the historical host run as 1,285 executions / 979 distinct cases and
the historical sync run as 1,026 executions / 634 distinct cases. Those results
remain attached to `9833831a` and `5c18db77`, respectively.
