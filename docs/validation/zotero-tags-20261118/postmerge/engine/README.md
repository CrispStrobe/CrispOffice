# Engine Zotero qualification after merging current main

**Accepted: 422 substantive tests passed across 21 suites, with zero skips or
error events.** The process exited zero and emitted one successful final event.
The 21 hidden suite-loading events are excluded. This is the final engine
cohort; earlier focused runs and the preceding complete engine cohort overlap
and are not added to this total.

The qualified product is **`4e06d42d20521f56164303aa6c135d5580ea0948`**, after
merging incoming main `1ffcf91a`. All 418 engine/parser source, test, fixture and
production-manifest inputs match that commit by Git blob identity, including
the newly incorporated German grammar part.

The selected suites are exactly the preceding qualification's 20 Zotero engine
suites plus `zotero_tag_filter_test.dart`. The preserved runner invokes genuine
Dart 3.13.7 and the exact locked test package with an explicit package
configuration. The updated workspace contains 110 packages. No package
resolution, dependency download or GitHub CI was invoked by this runner.

Before/after guards passed for all 418 source inputs, 1,714 consumed dependency
files, 1,047 Dart SDK files and seven workspace graph/lock/manifest inputs. The
exact generated workspace inputs are retained in compressed JSON. The previous
`local/engine` evidence remains an unchanged record of the earlier source.

`run.json` records the invocation and starting state. `summary.json` records
the process exit, completion event, counts, source identities, input guards and
artifact hashes. `events.jsonl.gz` and `stderr.log.gz` are the unmodified process
streams; `cases.json.gz` retains each substantive test ID, name, suite and
outcome. `excluded-events.json.gz` identifies the loading events excluded from
the total.

After completion, the raw event stream was independently replayed, outcomes
and completion recomputed, all 15 indexed artifact hashes verified, and all four
before/after inventory pairs compared again.

This run covers synthetic documents, fixtures and controlled transports. It
does not establish live-account behavior, full application compilation or new
Microsoft Word/LibreOffice acceptance.
