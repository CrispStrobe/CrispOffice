# AOT integration — 17 November 2026

Work branch: `codex/aot-proofing-analysis-20261117`.

## Incoming source

The initial integration starts from main `7cf48a2f` and includes every captured
fork branch, PR head and upstream branch by ancestry. `incoming.json` records the
exact fixed snapshot; concurrent updates after that snapshot are separate work.
The latest captured German continuation is PR #114 at `62eafbe4`; Office #113 is
`104b239c`, fidelity #111 is `d1738017`, and the GECToR branch is `78cd772c`.
All prior source and validation archives remain in history.

Merge decisions:

- Retain the current ODP hyperlink assertion once, with transition assertions.
- Combine section-anchored ODT frame/table extraction with linked drawing frames,
  ruby-base handling and hidden note/annotation/soft-page-break exclusions.
- Preserve authored empty frame-anchor paragraphs. Update the older empty-box
  regression to that explicit policy; retain the newer empty-frame regression.
- Keep frame tables structured in generic extraction while retaining their text
  in search. Reconcile the older flattened-table test with both assertions.
- Keep the newer empty-document policy (default page geometry, no invented body
  paragraph), and reconcile the incoming older section test to that policy.
- Keep current page fields, paragraph shading and model-tool documentation.
- Preserve the prior `readOdfParagraphs` entry point as a forwarding alias.

## Delivered features

The optional `quds_proofing_aot` package implements typed AOT/RML syntax and
morphology analysis, a bounded HTTP transport, and an `OfficeProofingProvider`
with three conservative German grammar families. The Studio example supplies
Review → AOT analysis, selected-text/body snapshots, syntax variants and word
forms, and explicitly configured manual grammar checks through Check document/F7.
The JSON CLI supports syntax, morphology and checking. No native AOT engine or
language dictionaries are bundled.

Default transport is loopback form POST. Explicit GET compatibility exists for
older deployed daemons; no error triggers an automatic method fallback or remote
endpoint change. Grammar supports de-DE; analysis supports German/Russian syntax
and German/Russian/English morphology. Unknown forms, valid ambiguity, protected
text and unsafe source mappings cannot produce invented corrections.

Read [the package documentation](../../../packages/quds_proofing_aot/README.md)
for host installation, standalone use, the exact API and limits.

## Final local validation

Implementation checkpoint: `9e5314fb07a615e410a41d45fde6123ae93ce657`.
Flutter 3.47.8 / Dart 3.13.7; the resolved workspace lock and installed SDK metadata
are retained under `evidence/`. [validation.json](validation.json) records test
counts, source hashes and compressed event-log hashes. Loading-suite events are
excluded from test counts.

| Cohort | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| New AOT package, Dart VM | 99 | 0 | 0 |
| Same AOT tests, JavaScript/Node | 99 | 0 | 0 |
| Integrated Office and existing proofing | 707 | 0 | 0 |
| Word proofing integration | 97 | 0 | 0 |
| Studio analysis and configured workspace | 13 | 0 | 0 |

Node repeats the same package tests. Static analysis of the AOT package,
changed example/editor files and reconciled ODF source/tests reports no issues.
The Studio cohort includes the existing Word/Excel/PowerPoint smoke with a local
AOT endpoint configured; it does not require a running daemon or start automatic
requests. An earlier default-disabled Studio smoke also passed. The final
small follow-up adds readable ignored-rule labels and a brace-only lint fix;
these were included in final static analysis.

The meaningful rule review added regressions for adjective-degree preservation,
expletive `es`, compatible imperative readings and infinitive introducers.
Client tests include real pinned upstream `Mutter`/`VÖGEL` morphology fixtures,
strict nested syntax schemas, malformed results, backwards subject relations,
Unicode/grapheme alignment, HTTP/queue/size bounds, cancellation and disposal.
The initial environment lacked a temporary directory; tests ran successfully
with a workspace `TMPDIR`. The incoming merge's differing historical extraction
and empty-document expectations were reconciled as documented above; the final
complete selected cohort passed. No assertion was simply deleted to hide a
failure.

## Live daemon smoke

The production `AotHttpTransport`, `AotClient` and provider were exercised against
`https://aot.ru/synan-daemon/` with **11 synthetic snippets only**. The public
server's revision is unknown. It rejects form POST with HTTP 400 while its GET
interface works; the inspected current upstream source accepts both. The
production smoke therefore explicitly selected GET and allowed that remote
endpoint. A separate run exercised the delivered CLI's syntax mode.

| Input | Observed result |
| --- | --- |
| `Ich geht.` | `geht` → `gehe`, UTF-16 range 4–8 |
| `mit den Hund` | `den` → `dem`, range 4–7 |
| `Der kleines Hund schläft.` | `kleines` → `kleine`, range 4–11 |
| The three corrected counterparts | Success, no findings |
| `Es kommen Gäste.` / `Es sind viele Menschen hier.` | Success, no findings |
| `Du gehe nach Hause.` | Success, no findings |
| `um mir zu helfen` / `ohne dem Hund zu helfen` | Explicit incomplete-alignment failure, no findings |

The last two examples are a real compatibility limit: this daemon retains `zu`
and rewrites `helfen` as `zu-helfen`. Their analysis remains inspectable, but the
provider refuses guessed source positions. This is not reported as a grammar
error or as a clean successful check.

[live-daemon-results.json](live-daemon-results.json) retains all results;
[live-daemon-responses.json](live-daemon-responses.json) retains the 17 distinct
syntax/morphology responses. The smoke used a 45-second provider deadline and
cached identical raw requests between samples. It establishes those finite
correctness observations, not default-timeout performance, general grammar
accuracy, local native packaging or target-device acceptance. The upstream
native server was not built in this workspace.

## Reproduce local checks

From `packages/quds_proofing_aot` after workspace dependency resolution:

```sh
dart test
dart test --platform node --concurrency 2
dart analyze .
```

From `packages/quds_office_editor/example`:

```sh
flutter test test/studio_aot_test.dart test/widget_test.dart \
  --dart-define=QUDS_AOT_ENDPOINT=http://127.0.0.1:17018/ --no-pub
```

The engine cohort covers `test/proofing` and these files:
`odf_text_box_extraction_test.dart`, `odf_frame_extraction_test.dart`,
`odt_section_integration_test.dart`, `odt_section_continuation_test.dart`,
`odt_section_fidelity_test.dart`, `odt_document_writer_test.dart`, and
`odp_presentation_writer_test.dart`. The editor cohort covers
`word_manual_proofing_test.dart`, `word_proofing_session_test.dart`,
`word_proofing_correction_test.dart`, and `word_proofing_dialog_test.dart`.

## Remote checkpoints and CI

The work is saved incrementally on `codex/aot-proofing-analysis-20261117`:

1. `cab8a69c`: reconcile all 256 captured branch/PR/upstream references.
2. `18b73ccd`: add the typed client, grammar provider, analysis UI and CLI.
3. `9e5314fb`: preserve review fixes, GET compatibility, regression tests and usage.
4. Final follow-up: local evidence, live responses, readable ignored-rule labels
   and final documentation.

All checkpoint commits use `[skip ci]`. No GitHub Actions jobs, workflow runs,
check runs or commit-status endpoints were queried or awaited.
