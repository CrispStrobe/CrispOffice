# Engine Zotero qualification — 18 November 2026

**Accepted: all 408 substantive tests passed across 20 suites, with zero skips or error events.** The process exited zero and emitted one final successful completion event. The 20 hidden suite-loading events are excluded from the substantive total. Earlier setup smokes are excluded.

The exact command, selected suite paths, timestamps, process exit, Git heads, package closure and artifact hashes are recorded in `summary.json`. This run uses the actual external workspace's unchanged 109-package graph and recorded exact dependency lock, with current engine/parser source exposed by links. The direct Dart SDK executable avoids Flutter CLI bootstrap races. The recorded invocation took 98.117 seconds; this is a local test-run duration, not an application performance measurement.

## Source and runtime guards

All selected inputs remained unchanged throughout execution:

- 416 engine/parser source, selected test, fixture and production-manifest files;
- 1714 consumed dependency files across the actual engine dependency closure;
- 1047 files in the complete genuine Dart SDK;
- 7 generated graph, lock, manifest and analysis inputs;
- the exact 20-file test selection.

The compressed before/after inventories bind every selected file by byte length and SHA-256. `workspace-inputs.json.gz` retains the exact text of all seven unchanged workspace inputs, checked again against the accepted post-run hashes before capture. The source maps identify the tested contents even when a concurrent documentation checkpoint advances the repository head. Runtime provenance and setup adaptations are preserved separately in `../runtime/`.

## Retained evidence

`events.jsonl.gz` is the complete unmodified JSON event stream. `stderr.log.gz` preserves the process stderr, including an empty stream if none was emitted. `cases.json.gz` lists each substantive test result and suite. `run_engine.py` is the exact runner; it writes a fresh output directory and refuses to overwrite an existing summary. The raw stream was replayed after completion, counts and successful termination were separately recomputed, every indexed artifact hash was checked, and all four before/after inventory pairs were compared again.

This cohort covers current `test/*zotero*_test.dart` engine tests, including the new catalog-query suite. Tests exercise local synthetic documents, fixtures and transport doubles; no live-account, Microsoft Word or LibreOffice acceptance is claimed. No GitHub Actions/status endpoint was used.
