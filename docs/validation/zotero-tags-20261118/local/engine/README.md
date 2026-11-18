# Engine Zotero qualification — tag filtering

**Accepted: 422 substantive tests passed across 21 suites, with zero skips or
error events.** The process exited zero and emitted one successful final event.
The 21 hidden suite-loading events are excluded. The earlier 40 focused passes
overlap this cohort and are not added to its total.

The selected suites are exactly the preceding qualification's 20 engine Zotero
suites plus `zotero_tag_filter_test.dart`. All tested source inputs match product
commit **`ccb8135bac72818ad2a037e940f1cdf1b3c6b63c`** by Git blob identity.

The preserved `run_engine.py` invokes the genuine Dart 3.13.7 binary and the
locked `test` package's entry point with an explicit package configuration. It
does not invoke `pub`, alter manifests, or use GitHub CI. `run.json` records the
invocation and starting state; `summary.json` records the exit, exact results,
completion event, timestamps, source identities, guard results and artifact
hashes. No pass count is taken from the earlier report.

Before and after inventories cover engine/parser production source, all selected
tests and Zotero fixtures, the consumed dependency closure, the complete Dart
SDK, and the exact workspace graph, lock and manifests. All guards passed.
The generated workspace inputs are retained verbatim in compressed JSON.

`events.jsonl.gz` and `stderr.log.gz` contain the unmodified process streams.
`cases.json.gz` retains each substantive test ID, name, suite and outcome;
`excluded-events.json.gz` identifies the suite-loading events. The raw event
stream was independently replayed after completion, its totals and success were
recomputed, every indexed artifact hash was verified, and all four input
inventory pairs were compared again.

This run covers synthetic documents, fixtures and controlled transports. It
does not establish live-account behavior, full application compilation or new
Microsoft Word/LibreOffice acceptance.
