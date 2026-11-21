# Word VBA language controls — incremental work record

The work branch starts from main `2f90a0c8f21499d5a1113943971cb7379183885c`
and preserves the captured Mail continuation through
`0dd22723cbe2589b2d5009d9c077d18a1326716f` before Word implementation.

The accompanying `intake.json` proves coverage for all 305 existing fork PRs,
26 captured fork branch heads, four upstream branch heads and four upstream
PR heads. Thirteen historical PRs have identical integrated trees; PR 140 has
identical entries for all 37 changed paths. They are already integrated and
must not be replayed over newer source. No open PR was present at capture.

## Current checkpoint

The compiler, native language/font ownership implementation and source tests
are saved incrementally. Native and full transaction qualification are in
progress; this checkpoint does not claim final acceptance. The incoming Mail
conversation and search slice passed 110 focused local tests at its exact
captured commit. No GitHub Actions, workflow, check or status queue was queried
or awaited. The final record will identify accepted source and remaining limits.

## Local implementation checkpoint

The first remote code checkpoint is `521fb2c25c029ef92c94a73dc92f7379baee6c59`
([PR 308](https://github.com/CrispStrobe/quds_office_suite/pull/308)).
The corrected source suite passes 110 cases, end-to-end integration passes
11 cases, and the native/preservation gate passes 187 cases (59 new native
checks, 98 adjacent regressions and 30 typography integration checks).
Targeted analysis is clean. These are separate local cohorts, not GitHub CI.

Independent review found and corrected shared namespace-preservation defects
in small-caps/generated property writes and foreign same-name section metadata.
The actual BAS now compiles and runs through CLI and MCP, with input and
existing-output preservation on failure, inert DOCM project retention,
normal/complex/East Asian slot isolation, repeated save/reopen and record/replay.

The branch is also reconciling current main
`fcb2128884768553141f41c02bf804e2267f9dbb`, preserving the compact Mail reader,
keychain write probe and completed conversation-UI history (PRs 306, 307, 309).
The newly started rich-ODT branch is being independently qualified at its
captured head before any integration. Its status is not represented as complete.
Final combined-source regression and VM/JavaScript receipts follow separately.

## Incoming ODT preservation checkpoint

The captured ODT reader/style implementation at
`3b1625e58a50438d10652032ab8dc5cecc098e34` is retained on the working branch
with its original history. Its 360-case focused gate passed in an isolated
source overlay. Independent probes found additional table-style inheritance
and width cases requiring review; this preservation checkpoint is deliberately
not a final qualification or publication of those behaviors. Corrections and
final combined-source evidence must precede main publication.

The follow-up correction preserves sparse table/row inheritance and explicit
transparent cell backgrounds. It validates authored positive absolute table
widths against supported fixed column geometry within 0.00001 pt and refuses
unsupported used structural-style metadata or nested/duplicate property
content. Unused opaque style definitions remain accepted. The isolated corrected
ODT cohort passes 381 cases, including 21 new preservation regressions, with
clean targeted analysis. The combined checkout gate is the remaining acceptance
step; no editor-loader or installed Office/LibreOffice/Zotero qualification is
claimed by this intake.
