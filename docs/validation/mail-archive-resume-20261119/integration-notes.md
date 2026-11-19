# Incoming source reconciliation decisions

The initial source at `596430dc` already contained main `caf378f4` and GUI
`2d7360a2`. Later preserved parents include VBA `f6b8638d` and GUI `8c6acd04`.
Further incoming fixes were integrated from VBA `61bb3ee4` and GUI `a2c144be`
(which includes `2dbd1c58`), preserving each original commit in the ancestry.

## Slide ink and rendering tests

Local qualification exposed two separate findings in the incoming dark-slide
test: a small-font raster assertion required too many fully opaque black pixels,
and DrawingML table-cell text colors were attached to the enclosing shape on
readback. The initial local correction routed cell ink to the active cell and
added three separate direct-XML/theme/PPTX-repeat regression cases. The newer
VBA contribution independently fixed the parser and added broader table-cell
regressions. Its parser version also retains the first explicit cell color and
was selected during reconciliation; the three local regression cases remain.

The final dark-slide test combines the two incoming test improvements. It keeps
VBA's fractional black coverage, pixel equality against unadapted authored ink,
wrong-light-ink and blank controls, and actual deserialized cell-color checks.
It also keeps GUI's contrast coverage on light/dark fills, authored-model checks
and independent checks of serialized XML text/fill colors. The obsolete GUI
comment treating the importer defect as still present is removed. The earlier
local tolerance adjustment is superseded by these stronger combined checks.

GUI ruler font selection/registration and all later Studio tab/header/footer
improvements are preserved. Local validation will qualify the combined source;
incoming historical reports are supporting evidence and are not fresh counts.

## Later publication frontier

A fresh remote advertisement after the first combined-source freeze found four
new heads. They were brought into the integration history before the next local
acceptance window; the earlier freeze is not represented as qualification of
these additional changes.

| Stream | Observed head | Incoming work |
| --- | --- | --- |
| Remote main | `9f41e0427734d815b19149eba5eabef202f78ba6` | Language review callbacks, explicit download management, optional NER removal and regressions |
| App gaps branch | `0e03878b028ec25ed3d84a790633433eafc3bede` | macOS bundled spaCy runtime, model-only setup, licence notices and build tooling |
| GUI / PR 211 | `ba51c40abc664758df3cfc846625bdeb81e3ac13` | Publication evidence and two mail restore compatibility corrections |
| VBA / PR 210 | `d8be43a408473da4b45059561dbc387f5b868d5b` | Final documentation, raw qualification evidence and release notes; no later runtime/test changes |

The [follow-up review](frontier-followup-review.json) retains the exact API
comparisons and changed path/blob identities. Incoming test counts are preserved
as historical evidence, not added to this milestone's fresh accepted counts.

### Mail restore compatibility

The GUI stream's restore write again emits `MailArchiveOperation.archive`,
preserving the existing completion observers used to cancel after a successful
commit. The receipt remains part of that same atomic archive transaction.
Existing adversarial tests explicitly observe this event; changing the operation
identity had prevented their post-commit cancellation callbacks from running.

The combined restoration loop distinguishes source/codec failures from failed
destination receipt lookups. A source/codec failure sanitized to `storageFailure`
is retained as one failed message, permitting other source files to be tried.
A destination receipt failure with `storageFailure` or `unavailable` terminates
the run after one failure. This combines the GUI source-failure correction with
the independently reviewed destination-unavailable correction. Quota and
permission errors retain their terminal behavior.

The incoming GUI merge also included an older copy of the dark-slide fixture.
Its file was unchanged between incorporated `a2c144be` and incoming `ba51c40a`,
so the stronger combined fixture described above was retained in full.
The intermediate GUI merge `8d9d1fe7` was independently proven to contain only
the already incorporated `a2c144be` and `85c8c551` trees; its complete-tree
reconstruction is in [post-freeze-gui-proof.json](post-freeze-gui-proof.json).

### Language downloads and bundled runtime

The Settings merge preserves the GUI theme and direction controls and adds
Language downloads using the current themed context. The new proofing callbacks,
download inventory, NER removal, app-owned model setup and their tests are kept.

Cross-review identified two semantic interactions between main and app gaps
that a text merge cannot resolve. Bundled and downloaded runtime hosts must
both propagate verified NER installation/error state, and stale opt-in settings
must never enable an absent or corrupt NER model. The German download inventory
must use the model-only byte count when the runtime ships inside the app.
Product checkpoint `7e13a48c` implements the shared NER verification and correct
byte counts, with five focused regression cases. The final source checkpoint
`ec6d527e` preserves those product bytes and adds only the documented raw-licence
whitespace exception. The corrections and regressions are covered by the final
acceptance record.

The macOS app build and its explicit
`studio_spacy_bundle_native_gate.dart` require an installed macOS app, signed
native library and actual verified models. Linux source, widget, installer and
build-script checks do not qualify that installed native configuration.

## Evidence whitespace

Three incoming raw captures (`before-source.diff`, `after-source.diff`, and
`incoming-context.diff`) contain a literal space on diff context blank lines.
Their bytes are preserved unchanged. The first preflight found the third capture
after formatting and analysis passed; no behavioral tests ran in that attempt.
The corrected whitespace command explicitly excludes only those three raw captures;
all product files and all other changed paths remain checked. This exception
does not alter formatting, analysis or behavioral test selection.

### Preserved licence-source whitespace

The imported `packages/quds_proofing_spacy/licenses/notices/de_core_news_sm-LICENSES_SOURCES` retains its source bytes, including final blank lines. Its SHA-256 is `0c3ab78745569d848b7c83a486183bce42b9643561084d6d6f67eb0229c79869`, identical to app-gaps commit `0e03878b028ec25ed3d84a790633433eafc3bede`. It is the fourth exact whitespace exception, alongside the three raw patch captures above. The source inventory and static licence verification still bind its complete bytes. No production Dart file is excluded. The pinned Dart formatter also normalized the incoming macOS-only native gate; that gate is analyzed but not executed on Linux.

### Linux ruler reference correction

The final combined editor run exposed two stale Linux selection reference PNGs:
they encoded placeholder Ahem blocks in the rulers. The incoming registered
ruler font renders readable digits. The old/master, current/test and isolated
pixel differences are preserved under `ruler-golden-review/`; each comparison
changes exactly 1,290 pixels (0.28%), all within the top/left 24-pixel rulers,
with zero changed document-body or selection pixels. Root and the runtime
reviewer inspected the images. The two references were copied byte-for-byte
from those captures; the comparator and test assertions were not changed.
The Linux provenance JSON retains its original record and identifies this
reference update. The complete final acceptance is rerun on the preserved
updated fixture source; older mail and incoming executions do not add to the
final accepted total.

The added spaCy qualification explicitly analyzes `lib` and `test` with fatal
infos/warnings. A broader exploratory package scan found nine inherited info
lints only in unchanged `tool/consume_distribution.dart` (Git blob
`644c0e686fc47e328eebb5b7705b2ee84827cf80`, identical to `caf378f4`). Its raw
diagnostic is retained as superseded; unrelated distribution-CLI edits are
outside this integration. All changed installer/backend code and its tests
remain under the strict final gate.
