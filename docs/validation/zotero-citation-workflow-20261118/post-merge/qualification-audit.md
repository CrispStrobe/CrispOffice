# Independent post-merge qualification audit

**Passed**, bound to the combined source `8002b6748deec2be7b7527d2bab8810d8ec54d05`. This audit reads saved raw events, input inventories and Git blobs; it executes no tests.

| Fresh accepted cohort | Suites | Passed | Failed / skipped | Flutter process exit |
| --- | ---: | ---: | ---: | ---: |
| Complete editor Zotero | 26 | 348 | 0 / 0 | 0 |
| Incoming editor review and proofing | 20 | 278 | 0 / 0 | 0 |
| **Disjoint total** | **46** | **626** | **0 / 0** | |

The totals are independently recounted from the fresh [Zotero events](zotero-editor/events.jsonl.gz) and [incoming events](incoming-editor/events.jsonl.gz). The suite sets are disjoint, and the Zotero set covers every current `word_zotero*_test.dart` suite. Both runs began and ended at the exact combined source. Every started case finished exactly once: **374** starts/finishes for Zotero and **310** for incoming, excluding **26** and **32** lifecycle cases from the pass totals. Flutter process notifications are also excluded. Both streams contain one successful final event, with no failures, skips, parser errors, error events, overflow or missed-tap diagnostics; captured stderr is empty.

All **562 Zotero inputs** and **552 incoming inputs** match the frozen Git tree and current files. Their union contains **583 distinct paths**; the **531 shared records** agree exactly. Source, runtime, dependency and workspace before/after digests match with empty change lists. Current runtime/workspace records and all **41 external dependency inventories** were independently recomputed and match. All **11 manifests** match the validation workspace, the combined source and the original baseline.

All **17 distinct strict-analysis and nonmutating-format targets** pass, split **8 Zotero + 9 incoming**, with the exact target sets and strict flags checked. Both executed-runner hashes, the raw gzip artifact hashes and both runner-log receipts match their summaries. Inspected runner code captures the direct Flutter subprocess `wait()` return value as `actual_process_exit`; these receipts report **0** for both runs. Shared runtime records match across runs; incoming additionally inventories the MaterialIcons font.

The original **617 passes / 44 suites** remain historical acceptance for `40e92e5222a26db132f8be05126df285b4227a86` and contribute **zero** cases to the new total. All **48 original evidence payloads**, including both original qualification audit files and the fixed 377-ref audit, remain byte-identical to `82224f23`. Earlier failed attempts, focused development, engine, Studio and spelling cohorts are also excluded.

The [complete audit](qualification-audit.json) contains per-suite counts and every source, guard, runtime, artifact, static-target and exclusion check. The [targeted reconciliation](reconciliation.md) explains the merged base and retained conflict assertions. These local editor tests do not establish installed-application or live-account interoperability with Zotero, Word or LibreOffice. No additional remote request, repository-wide frontier refresh, or GitHub Actions query was made by this auditor.
