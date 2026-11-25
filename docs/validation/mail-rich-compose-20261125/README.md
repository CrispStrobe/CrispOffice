# Mail rich composition — validation and source record

Recorded **25 November 2026**. This record qualifies the rich-composition
continuation at source commit
[`46645673bc944d1bb518703108234ba6836afc91`](https://github.com/CrispStrobe/quds_office_suite/commit/46645673bc944d1bb518703108234ba6836afc91).
Later changes in this evidence checkpoint are documentation and receipts only.

**Result: 239 pure-Dart tests passed, with no failures or skips.** Strict
pure-Dart analysis passed on 20 production/dependency files and 7 test files,
whose inputs remained unchanged, plus the updated XML source and its test.
Separate genuine Flutter source analysis passed on 9 targets with zero errors,
warnings, infos or analyzer-server errors. Flutter widget assertions were
analyzed as source but were not executed.

## What this continuation changes

The Word composer previously retained only paragraph text when taking a draft
snapshot. Formatting could consequently disappear at autosave, recovery, MIME
construction or Outbox edit-copy. The continuation preserves a deliberately
bounded set of styles across that entire lifecycle:

- Immutable canonical paragraphs/runs, with matching plain text and HTML.
- Bold, italic, underline, strikethrough, safe links, alignment and direction;
  the fixed standard hyperlink-blue color also survives inherited typing.
- English/German/Arabic controls in the existing custom Word editing surface,
  formatting-only autosave, safe asynchronous link/paste operations, and
  supported empty-paragraph typing styles.
- Real SQLite draft recovery, immutable queued MIME/private envelopes,
  edit-copy into a new draft, and bounded inert formatted Outbox review.
- Signature/Quick Text preservation, explicit plain-template confirmation,
  refusal of corrupt or unsupported rich state, and legacy plain-draft
  save/recovery limits independent of submission limits.

The [implementation guide](../../roadmaps/mail/rich-composition.md) records
format limits, ownership rules, unsupported structures and remaining work.
No package versions, repository dependency manifests, lockfile or database
schema were changed by this continuation.

## Source reconciliation and incremental remote checkpoints

Work began on the existing identity/template/provider-search increment at
`938832e6dc337a880c15c609aeed95b643379da7` (PR #396). During this continuation,
that work and further integration reached main. Main
`20c36e5ac1f21add8d3d75420ab43f8fc527eefe` was merged before final qualification.
A final remote check found the later namespace-scanner refinement at main
`c37614eaca5778b22fcd15755b7a6dd20a20ca92`. That two-file XML change was merged
in `46645673bc944d1bb518703108234ba6836afc91`, and the complete selected suite
was rerun with its added namespace regression.
The incoming Word Enter, XML, Sent-copy reporting, Inbox polling and other
integration changes remain inherited source, rather than additional features
claimed by this continuation.

| Saved checkpoint | Purpose |
| --- | --- |
| `07fc535ede3e5b630cc1a7c6316cecadf6aaa25a` | Audit and end-to-end composition contract |
| `fad53768a79c3c680e51656816dbbe19f68c842d` | Canonical core model and Word conversion |
| `9ec34d783642b184219fa7130c559c333d474103` | Durable drafts, recovery, MIME and frozen Outbox |
| `57ebf9c8c54453a9306436e6deaf46521a6d8fd6` | Composer controls, inert review and regression source |
| `8f4d02e91b739a8cb3a8a4bcd2ebd3c0597d4f15` | Merge main `20c36e5a` without replacing concurrent work |
| `1bd81015ecd261708b2b8254d8f9a9ef57b94c37` | Paragraph-mark/Enter integration and 238-test source |
| `13f3427c92d7decb3878f1c4eca535060c7c7b89` | Initial merged-source qualification and evidence |
| `46645673bc944d1bb518703108234ba6836afc91` | Latest main XML integration and final 239-test source |

All eight checkpoints were confirmed on remote branch
[`codex/mail-rich-compose-20261125`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/mail-rich-compose-20261125).
This documentation/evidence checkpoint follows them. The final gate supersedes
the earlier 146-test and 238-test runs; those totals are not added together.

## Executed pure-Dart tests

| Suite | Passed |
| --- | ---: |
| Canonical rich body, grammar and bounds | 45 |
| Word conversion and supported document compatibility | 33 |
| Bounded rich preview data | 9 |
| Rich MIME, sender/signature and Outbox edit-copy | 10 |
| Real SQLite rich draft/recovery/Outbox persistence | 14 |
| Existing Studio submission compatibility | 19 |
| Existing Studio Outbox content/privacy compatibility | 28 |
| Incoming Word paragraph-mark formatting | 6 |
| Incoming XML reader | 9 |
| Incoming core Outbox | 16 |
| Incoming store codec | 39 |
| Incoming cache cleanup | 11 |
| **Total** | **239** |

The total comprises **111 new rich-composition tests**, **47 existing Studio
compatibility tests** and **81 incoming-main compatibility tests**. The final
run completed with exit code 0, no failed/skipped test events and no disk abort.
All **557** captured production, test and fixture fingerprints were unchanged
throughout execution. The exact command, group counts and log hashes are in
[latest_main_verification.json](latest_main_verification.json).

Real SQLite tests close and reopen the database. They cover formatting-only
revisions, corrupt HTML/plain mismatch, legacy unfinished plain drafts,
storage quotas preserving prior work, atomic queue/edit-copy, uncertainty,
frozen bytes and private Bcc recovery. New integration cases preserve accepted
Sent-copy receipts with `true`, `false` and legacy `null`; accepted work cannot
be retried. A filing receipt is not a recipient-delivery receipt.

### Runtime provenance and adaptations

Execution used official **Dart 3.13.7**, the Dart version associated with the
repository's **Flutter 3.47.8** pin. All **76** resolved hosted dependency
versions matched the repository lockfile. Production library source remained
real and unchanged; no Flutter API or runtime dependency was stubbed.

Selected Studio tests use the real `package:test` API in an isolated harness:
`flutter_test` imports are replaced, the real `package:test/fake.dart` helper is
imported where required, and equivalent synchronous assertions use `expect`.
[latest_main_test_copies.json](latest_main_test_copies.json) records original/adapted
hashes. The five incoming compatibility files and original font fixture were
copied unchanged.

The supported source compiler avoids large cached test kernels. Its source
isolates preload the actual SQLite **3.54.1** binary produced by sqlite3
**3.9.1**'s build hook; this supplies the package's real native implementation.
The binary SHA-256 is
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.
SDK, dependency and fixture provenance is in
[latest_main_environment.json](latest_main_environment.json).

The executor had a constrained disk budget. Temporary SDK/framework/cache
files were managed in phases; the final runtime retained at least 21,475,328
free bytes and did not trigger its disk guard. SDK binaries and caches are not
included in this change.

## Static analysis

**Pure Dart:** `dart analyze --fatal-infos analysis_root` passed with no issues.
The overlay holds exact-byte copies of 20 relevant production/dependency files
and the 7 selected tests with the documented test API adaptation. The
[analysis receipt](merged_analysis_verification.json) and
[production-copy manifest](analysis_root/source_manifest.json) define the
scope. These 27 input files were verified byte-identical at the final source.
The late XML reader and its test received a fresh strict analysis, also clean;
[latest_main_analysis_verification.json](latest_main_analysis_verification.json)
records both boundaries. This is not a claim that every repository package
was analyzed.

**Flutter source:** the official Dart AOT analyzer used actual upstream
Flutter **3.47.8**, commit `737ba8f885dc774b53b442759999a312c9461e4e`, matching
sky_engine at `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`, and real pinned
hosted package sources. Resolution covered 125 package roots and 4,120 imported
Dart files with no missing source paths. The 9 explicitly analyzed targets
were the composer/strings/converter, rich preview/data, Outbox review/strings,
and the two rich widget-test files.

The analysis completed with **0 errors, 0 warnings, 0 infos and 0 server
errors**. All 1,957 materialized tracked Dart sources retained the same
aggregate digest before and after the pass. Exact targets, source/package
hashes, analyzer protocol and completion gates are in
[flutter_source_analysis.json](flutter_source_analysis.json); the raw result is
[flutter_analysis_result.json](flutter_analysis_result.json).

That Flutter pass ran at `1bd81015`, before the late XML-only update. All nine
explicit target files remain byte-identical at the final source, verified in
[latest_main_ui_source_check.json](latest_main_ui_source_check.json). The
changed XML dependency has its separate strict check and complete pure-Dart
rerun; no additional Flutter pass or widget execution is claimed.

## Reproduction and evidence

[HARNESS_RECIPE.md](HARNESS_RECIPE.md) and
[create_validation_harness.py](create_validation_harness.py) provide a portable
pure-Dart setup for all 12 selected suites and the unchanged font fixture.
The executed live harness is bound separately by the exact source/test-copy
manifests and commands. The generator and both recorded analyzer scripts are
syntactically checked Python; the portable generator's expanded configuration
is not an additional test run and contributes no tests to the count above.

The original source-only Flutter scripts are retained as
[prepare_flutter_analysis.py](prepare_flutter_analysis.py) and
[analyze_flutter_sources.py](analyze_flutter_sources.py). They preserve the
executor's exact directory layout: adjust their `BASE` to a new validation
root containing `crispoffice`, `mail-harness` and `toolchain` when reproducing.
Restore the official Flutter/sky_engine sources at the pinned identities in
the receipt before preparation. With a full pinned Flutter installation, the
repository's normal `flutter analyze` and `flutter test` workflows are the
preferred next qualification route.

Additional evidence:

- [Full executed test log](logs/latest_main_pure_validation.log) and
  [original JSON test events](logs/latest_main_events.jsonl).
- [Retained strict pure-analysis log](logs/merged_final_pure_analysis.log) and
  [fresh XML analysis log](logs/latest_main_xml_analysis.log).
- [557 source/test/fixture fingerprints](latest_main_source_manifest.json).
- [Final runtime receipt](LATEST_MAIN_VALIDATION.md); the earlier
  [238-test receipt](MERGED_VALIDATION.md) is preserved as history.
- [Checksums for this evidence bundle](evidence_manifest.json).

## Remaining acceptance gates

The new Flutter widget scenarios are supplied and statically analyzed, but
**were not executed in this session**. Rendering, focus, gestures, IME,
platform clipboard/file-picker behavior, installed builds, browser persistence
and actual mail-client rendering remain open. No live mail was sent and no
provider account acceptance is claimed. Existing repository CI includes the
Studio Mail test glob; its status must be read independently on the PR.

Lists, tables, inline-image/CID authoring, arbitrary HTML import, rich-template
storage, provider Drafts synchronization, exact-message Sent reconciliation,
background delivery and simultaneous retained live accounts remain separate
work. The supported rich model rejects structures it cannot preserve.
