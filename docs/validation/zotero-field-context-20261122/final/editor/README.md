# Final integrated editor and Studio gate

Accepted source: commit `67677aa7e16ea5e4eff3bcd06ffa6e27c5907246`,
tree `9409113e6440e62f73c3db00ab84b4505bc3bcd2`.

The final execution completed on 22 November 2026 at 05:41 UTC. All 1,086
captured production, dependency, selected test and manifest file hashes remained
identical before and after the gate. The commit and tree also stayed unchanged.
Concurrent edits to the parent validation README were documentation only and are
recorded in the run provenance.

| Gate | Final result | Evidence |
| --- | --- | --- |
| Sixteen selected editor suites | 309 passed, zero failed, zero skipped | [Run receipt](editor.run.json), [complete log](editor.log) |
| Four Studio suites | 55 passed, zero failed, zero skipped | [Run receipt](studio.run.json), [complete log](studio.log) |
| Strict changed-source analysis | All 15 changed editor/Studio production and test Dart paths clean with `--fatal-infos` | [Run receipt](analyze.run.json), [complete log](analyze.log) |

The [summary](summary.json), [provenance](provenance.json), [plan](plan.json),
[before hashes](source-hashes-before.json) and [after hashes](source-hashes-after.json)
record the accepted source and commands. The runtime is the previously verified
Flutter 3.47.8 / Dart 3.13.7 toolchain. Commands source the recorded runtime
environment, including `CI=true`, and run with `--no-pub --concurrency=2`.
No GitHub Actions result is used.

## Bounded regression coverage

The editor selection includes the 105-case context/citing/writing-position/transfer
controller gate and nine context-render raster cases. The other suites exercise
direct native commands, existing workspace and citing dialogs, transfer dialogs,
explicit citation and source navigation, Notes selection and composition,
document actions, and the existing 1,000-citation scan check. They cover the
temporary presentation's lifecycle and distinguish it from explicit navigation.

The four Studio suites cover Zotero shortcuts, shortcut host ownership, citing
transport and ODT export. They exercise body/Notes targeting, application changes,
covering dialogs, duplicate activation, cancellation, loopback transport rules,
and detached export/persistence.

The new 21-case selected-context dialog suite and engine/Word gates have separate
owners and receipts. Their counts are not included here. Checkpoint runs, the
focused reproduction below and the failed first attempt must not be added to the
accepted totals.

## First attempt and correction

The first integrated run at `c6941f9ae82c74bf0f8d8a2a15d2a7a2c47c9f4f` passed
308 editor cases and failed the existing Web API pagination case. Its `Next page`
control was clipped: a loose flex wrapper around a short connection message
reserved space that the tab did not receive. The first attempt's logs, commands,
hashes and 55-case Studio result are preserved unchanged under
[attempt-1](attempt-1/summary.json); that attempt is not acceptance evidence.

The parent restored the message banner's original natural-height bounded scroll
box while retaining flex for active selected context and bounded instructions.
The corrected dialog's SHA-256 is
`9aa0579efae61cf4ef922541ef706529cb211aa32a02b5a40c671d804ad7ad8d`.
The [focused pagination reproduction](pagination-focus.run.json) then passed.
All sixteen editor suites, all four Studio suites and strict analysis were rerun
on the corrected published source, producing the accepted results above.
