# Independent qualification evidence audit

**Passed**, bound to source `40e92e5222a26db132f8be05126df285b4227a86`. The audit reads retained evidence and Git blobs; it executes no tests.

| Accepted final cohort | Suites | Passed | Failed / skipped | Process exit |
| --- | ---: | ---: | ---: | ---: |
| Complete editor Zotero | 26 | 348 | 0 / 0 | 0 |
| Incoming editor review and proofing | 18 | 269 | 0 / 0 | 0 |
| **Disjoint total** | **44** | **617** | **0 / 0** | |

The totals are independently recounted from the two compressed raw event streams. Hidden/loading/lifecycle cases and Flutter process notifications are excluded. All started cases finish exactly once, both streams have one successful final event, and neither contains an error, overflow or missed-tap diagnostic. Suite sets are disjoint. Failed attempts and focused development runs contribute no tests to this total.

All **562 Zotero inputs** match the original Zotero-tested source and this qualified source. The incoming cohort has **550 recorded inputs**. Their union contains **581 distinct paths**, all matching the qualified Git tree; shared records agree. Source, runtime, workspace and dependency before/after guards pass. All **15 distinct strict-analysis and nonmutating-format targets** pass, split 8 Zotero and 7 incoming.

Runner and raw artifact hashes match the receipts. The process exit codes are the direct Flutter subprocess return values captured by the inspected runners. The runtime/dependency/workspace records shared between cohorts match; the incoming runner additionally records the MaterialIcons font. This inventory extension does not represent a changed executable.

The [complete audit](qualification-audit.json) records per-suite counts, exclusions, source and artifact checks, runtime comparisons and retained failed-attempt locations. This audit adds no installed-application, live-account or Word/LibreOffice acceptance claim, and it performs no remote-frontier or GitHub Actions query.
