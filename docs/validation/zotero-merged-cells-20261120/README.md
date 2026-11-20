# Zotero main reconciliation

Main `698209aaa6e7f1350b6541df5eb192b7b233443d` (PR #276) was reconciled with
the qualified Word/Mail checkpoint `cf25a0a3d80ee18d2550161af182bacc4e49d18f`.
The incoming four Zotero implementation files, their tests, acceptance tools
and usage documentation are retained. The existing Word compiler, native
layout/import repairs, canonical eight-, nine- and thirteen-operation macro
families, and reconciled Mail implementation keep their qualified bytes.

## Historical incoming evidence

The [incoming checkpoint report](incoming-main-698-checkpoint.md) and
[incoming qualification receipt](incoming-main-698-qualification.json) retain
the continuation's exact source attribution. Its
[raw archive](local-validation.tar.gz) and [recount script](audit_results.py)
remain available. Those executions belong to the identified earlier source;
their totals must not be added to later reruns or presented as a new combined
qualification.

The [reconciliation account](reconciliation-698.md) records the initial source
preservation and focused scope. The combined qualification is now accepted at
published source `c62338c65571aa399da5592455b651fa5c6a9317`, after the subsequent
main `0a2afc41` reconciliation. The
[final Word/Zotero report](../word-final-integration-20261120/README.md) binds the
470 engine and 257 editor Zotero case identities to that source: 188 engine
and 143 editor cases ran fresh, while 282 engine and 114 editor cases retain
independently audited incoming raw results and exact relevant source inputs.
These are identity-preserving populations, not totals to add to earlier runs.

The earlier `80e240ec` attempt remains historical and unaccepted: its test
commands passed, but a collector path-resolution interruption required a
recount of the original events, and strict analysis then found a missing-braces
lint in the protocol test. The final report preserves that failed receipt and
collector history. Incoming main supplied the braces correction; the final
whole-engine and selected editor fatal-info analyses pass.

## Scope and boundaries

The focused local gate covers Zotero's note/table model, citation protocol,
stale-result guards, native DOCX interoperation, and editor transactions,
including undo/redo. It selects fourteen engine Zotero suites and nine editor
Zotero suites. Previously accepted compiler, Mail and unrelated layout counts
retain their own source attribution.

Horizontal spans and native adjacent-citation Refresh remain bounded to the
contracts described in [the usage guide](../../zotero-support.md). Vertical
merges, nested research tables, active ODT citation transfer, and new installed
Zotero/Word/LibreOffice acceptance remain outside this local qualification.
