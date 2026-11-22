# Reporter re-analysis of frozen source 9a371b61

All seven qualification commands completed with exit code zero on frozen source
`9a371b616ae0fa0dbbecaed04708837125694d7c`. The original summary nevertheless
reported `accepted: false` because its line decoder missed three test-start
records. The original run, summary, reporters and checksums remain unchanged.

The independent [re-analysis](merged-source-recovery-reanalysis/summary.json)
accepts **6,893 fresh unique cases across 238 suites**, plus **294 retained shared
Mail UI cases**, for **7,187 accepted cases on that source**. It invokes no Dart
or Flutter process and reads no mutable package source. Subsequent source changes
require their own qualification.

| Fresh gate | Suites | Passed cases | Started/completed lifecycles |
| --- | ---: | ---: | ---: |
| Incoming engine | 92 | 3,892 | 3,996 / 3,996 |
| Incoming editor | 30 | 653 | 705 / 705 |
| Incoming Mail store | 2 | 47 | 49 / 49 |
| Studio Zotero | 4 | 48 | 52 / 52 |
| Studio Mail | 110 | 2,253 | 2,377 / 2,377 |

The re-analysis found zero failed, skipped or incomplete cases and no missing,
orphaned or duplicate lifecycle records. Loader and fixture-hook lifecycles are
excluded from the case counts. The original strict analysis and formatter checks
covered 109 Dart paths and exited zero.

## Why three starts were missed

Python `str.splitlines()` recognizes Unicode NEL (`U+0085`), LINE SEPARATOR
(`U+2028`) and PARAGRAPH SEPARATOR (`U+2029`) as line boundaries. Those characters
are valid inside JSON strings. Three attachment tests deliberately use them in
unsafe filenames, and the JSON reporter emitted valid strings containing those
characters. Splitting those records inside their strings caused the original
decoder to discard their starts while retaining their successful completions.

The corrected decoder splits raw UTF-8 output only on LF bytes. The recovered
records are in `studio_mail_attachment_test.dart`:

| ID | Escaped filename in the test name | Physical LF-delimited line | Result |
| --- | --- | ---: | --- |
| 473 | `next\u0085line.txt` | 921 | Passed |
| 474 | `separator\u2028.txt` | 923 | Passed |
| 475 | `paragraph\u2029.txt` | 925 | Passed |

Their complete escaped names and exact raw-line hashes are retained in the
[Mail reporter re-analysis](merged-source-recovery-reanalysis/studio_mail-reanalysis.json).
The original reported Mail count was 2,250; decoding all three records restores
2,253. No case was rerun or inferred from an absent completion.

The normal `dart test` store invocation also printed two `Running build hooks...`
progress prefixes immediately before its reporter-start event. The re-analysis
records those exact prefixes separately and decodes the following start event.
This did not change the store's 47-case count.

## Evidence integrity

All 42 original artifact hashes were checked before and after re-analysis. The
eight captured source manifests agree on all 6,151 source inputs and generated
package configuration, and the captured inputs match the frozen source commit.
The original runner is archived byte-for-byte with SHA-256
`e0e1d208beae75dba5de37b4d0ce1f4a9c24ab72864ce5435b1c6e234bd04e85`.
The re-analysis script and its outputs have their own hashes; original evidence
was not rewritten.

[The exact-case comparison](original-failure-recovery-9a371b61.json) confirms that
all 18 cases that failed in the earlier `d53f30f1` execution passed in the captured
`9a371b61` execution. The earlier run also had three Unicode-name orphan records;
its historical summary remains unchanged and its 18 actual failures remain part
of the record.

This evidence covers the pinned Dart VM and Flutter widget scope. It does not
establish JavaScript/browser Split behavior, live-provider or installed-platform
operation, installed converter sessions, or complete desktop-mail parity.
