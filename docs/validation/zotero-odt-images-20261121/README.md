# Zotero pictures through editable ODT — 21 November 2026

**Qualified increment:** bounded inline pictures from Zotero notes/annotations
can reopen as editable native ODT content and survive further ODT/DOCX saves.
The main-integration gate passed **1,688 tests, with no failures or skips**,
followed by **30 focused passes** after the last editor-only main update. An actual
LibreOfficeDev conversion retained both pictures and both active citations in
each PNG/JPEG fixture through three subsequent DOCX/ODT cycles.

Last directly qualified image-branch source: [`7086ad80266981d612615710610d66bf3fcfb5cf`](https://github.com/CrispStrobe/quds_office_suite/commit/7086ad80266981d612615710610d66bf3fcfb5cf),
tree `b76107b64e496820f5550b11d1f6b684f34aa5d3`.
The broad main-integration gate is bound to
`ef05b99ec9bbf1d539181c8519eb41455d182603`, tree
`ecbdd52a92fcba1f6bc1daf842faa8040ae9b380`.
The earlier image-only qualification remains bound to
`58fe5b978f63af282ccd3f3406f86e431e440030`, tree
`a2d9f9663c35caf6896a27c917384bfdf9bde7a4`.
Starting main: `4970f71f983535d045ce263e86835b499db4fda9`.
Remote checkpoint branch: `codex/zotero-roundtrip-20261121`.
This record adds evidence and documentation to that qualified source. It does
not claim installed Zotero-plugin, stable release-host, or Apache OpenOffice
acceptance. GitHub Actions were neither queried nor awaited.

## Final publication reconciliation

Before the final merge, remote main advanced to
`2058a434b2bcc76e7fc7e8a449ff6ce31488eb25`, the completed Mail integration.
It already contains this milestone's production commits `fac61ecd`, `81e478ca`
and `58fe5b97`, the subsequent Word and rendering work, and the other Zotero
ODT implementation through `3eac83d1`.

The final reconciliation retains that complete main tree. Its only differences
from `2058a434` are this milestone's documentation/evidence and the engine
changelog entry; **no production or test file differs from that main**. See
[the exact reconciliation](publication-reconciliation.json). The incoming
[Mail qualification](../mail-scheduled-send-20261121/README.md) and
[final renderer/Studio follow-up](../mail-scheduled-send-20261121/main-followup.md)
remain preserved with their own sources and results.

The receipts below remain attributed to the commits actually executed. The
then-pending Mail/Zotero observations in older intake records are historical
cutoffs; the completed incoming work is now retained by this reconciliation.
No runtime rerun is needed for the remaining documentation-only PR delta.

## Final editor-only main update

Remote main then advanced to `3440c90bc63f9d43edb7e64172bfec3d82036fee`,
including PR #335's proofing/selection path cache and its roadmap note. A normal
merge retained both changes. The sole new production file is
`packages/quds_office_editor/lib/src/editor_word/render_word_canvas.dart`.

On the clean `7086ad80` source, the affected checks passed: **13 proofing geometry,
10 selection painting and 7 ODT image-loading cases**; zero failures, skips or
errors. Both platform-variant selection golden cases executed. Renderer-only
format and fatal-info analysis also passed.

All **2,329 captured inputs** remained unchanged during these checks; **2,328
tracked blobs** match the published source. The renderer is the sole captured
delta from `ef05b99e`. Every other captured tracked blob and all **367 converter
inputs** are identical, so the retained engine and converter results still
apply. The 30 focused cases include overlap with the earlier gate and are not
summed into a new distinct-test total.

See the [publication summary](publication-paint/summary.json),
[receipt](publication-paint/receipt.json), and
[raw execution archive](publication-paint/execution.tar.gz) with its
[hash index](publication-paint/archive-contents.json).

## Earlier full current-main integration

During publication, remote main advanced to
`5c59a062e86e24d043ba06cfe8f0a69074c44f62`, containing the completed Word VBA
paragraph shading and Unicode text construction work. A normal two-parent
merge incorporated it without conflicts or changes to the incoming blobs.
The image history and all incoming main history remain ancestors of `ef05b99e`.

The combined-source checks include all earlier suites plus the four incoming
Word shading/text-construction suites:

| Gate | Final combined result |
|---|---:|
| Engine, including incoming Word suites | 1,603 passed |
| Editor | 44 passed |
| Studio | 41 passed |
| **Distinct test cases** | **1,688 passed; 0 failed; 0 skipped** |
| Formatter and fatal-info analyzer | Clean |

All 2,123 captured broad-gate inputs remained unchanged. A focused repeat of the
same 338 incoming Word cases additionally captures their BAS examples, portable
tool imports and CLI entry point; these cases overlap the broad gate and are
not counted twice. The combined manifests are checked against the published
Git blobs. The fresh converter run on this merged source again retains both
pictures/citations through three cycles, with all 367 converter inputs unchanged.

See the [integration summary](integration/summary.json),
[local receipts](integration/local-summary.json),
[supplemental Word receipt](integration/supplemental-word-receipt.json),
[compressed source binding](integration/source-binding.json.gz),
[converter receipt](integration/converter-receipt.json), and
[execution archive](integration/execution.tar.gz) with its
[hash index](integration/archive-contents.json). Earlier image-only results
below remain intact and separately attributable.

## Why this increment

The starting fork already supported Zotero note/annotation pictures in its
native Word model, but the native ODT reader refused every drawing frame. The
ODT writer also emitted the internal U+FFFC picture placeholder as literal text
beside its frame and omitted alternative descriptions. This left a practical
gap between note insertion and editable file interchange.

The implementation reuses the existing raster decoder, field ownership model,
asynchronous document loader and Zotero callbacks.

## Delivered behavior

| Area | Qualified behavior |
|---|---|
| Native ODT input | Complete character-anchored embedded PNG and upright RGB/YCbCr JPEG frames become independently owned picture runs, retaining raster bytes, physical size, hyperlinks, accessible title/description and supported run properties. |
| Citation ownership | A picture contributes exactly one UTF-16 position. Citation ranges after images and emoji remain correct; body, merged-cell, footnote and endnote owners survive local save cycles. Pictures inside citation/bibliography caches refuse. |
| Editable ODT output | Emits one frame without a duplicate literal placeholder, writes `svg:title`/`svg:desc`, retains supported image-run styling and validates picture ownership before export. |
| Drawing identities | Allocates unique names across stories. Duplicate/empty names receive deterministic names; reopening adopts those names. Accessible metadata and original source objects remain unchanged. |
| Ordinary ODT output | Receives the picture placeholder, accessible metadata, styling and naming fixes while retaining its existing cached Zotero citation behavior. |
| Editor lifecycle | Independent raw ODT fixtures exercise loading, real image painting, DOCX reopening, controlled refresh as one undoable transaction, selection restoration, failed-media atomicity, stale loads and disposal. |
| Guarded styles | Validates inherited LibreOffice bitmap-frame defaults. The visited-link style exemption applies only to validated picture-only links with no text, including no whitespace text nodes. |

Local lifecycle tests cover three ODT/DOCX cycles in body, merged-cell, footnote
and endnote owners, controlled refresh/unlink and note-image insertion. Actual
converter fixtures cover **body pictures and citations**; they do not establish
converted table, authored-note or bibliography fidelity.

### Defects exposed during qualification

**LibreOffice dropped a second picture when both frames had the same drawing
name.** The strict verifier detected the missing object. Unique drawing names
corrected the loss; original failing input/output files remain in diagnostics.

**Allocated names made identical header stories compare unequal.** The broad
gate caught two unwanted page-master changes. Story comparison now restores
authored names only in its temporary comparison tree; emitted names remain
unique. Existing geometry checks and a new suffix/empty-name collision
regression protect both behaviors.

One existing comment assertion was updated to verify the intentional styled
`text:span` around an inline frame, including preserved 18 pt bold properties.
Detached comment pictures still require direct paragraph ownership.

## Image checkpoint qualification

The [summary](final/summary.json), [command receipts](final/local-summary.json),
[source binding](final/source-binding.json) and
[execution archive](final/execution.tar.gz) retain exact commands, raw test
events, suite selection, timestamps, exit codes and source manifests.

| Gate | Result |
|---|---:|
| Engine: ODT fidelity, Zotero inventory/ownership, image decoding and citation lifecycle | 1,265 passed |
| Editor: ODT loading, merged tables, image loading/painting and note-image controller | 44 passed |
| Studio: ODT open/export, Zotero shortcuts and native transport | 41 passed |
| **Distinct executed test cases** | **1,350 passed; 0 failed; 0 skipped** |
| Formatter | Clean |
| Fatal-info analyzer | Clean |

This image-only gate ran on a clean checkout of `58fe5b97`. All **2,118
execution inputs** were unchanged before/after: **2,117 tracked inputs** match
the saved Git blobs; the remaining runtime input is the recorded
`.dart_tool/package_config.json`. All **366 converter inputs** independently
match that saved source. The archive has a verified
[member and archive SHA256 index](final/archive-contents.json).

Runtime: Flutter **3.47.8**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`, Dart **3.13.7**. The official SDK
archive and 204 locked package archives were hash-verified. Dependency resolution
retained the existing lockfile, whose SHA256 remained
`2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.
See [runtime receipt](runtime.json) and the archived dependency receipt.
Earlier focused 101-case and 133-case checks overlap this gate and are **not
added again** to the 1,350-case total.

## Actual LibreOffice conversion

Converter: **LibreOfficeDev 26.8.0.0.alpha0**, revision
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. The
[converter receipt](final/converter-receipt.json) records wrapper, launcher and
binary hashes. All commands exited zero, with empty stderr.

Each fixture contains two pictures, two separately identified citations with
identical visible caches, a picture hyperlink, accessible metadata, Arabic/emoji
text, preferences and unknown metadata members. Both initial pictures share
an authored object name. Expected results come from the original native model.

The tool creates original ODT files, performs an actual isolated LibreOffice
`writer8` save, then opens the **untouched returned bytes**. It checks raster
SHA256, picture positions/count, links, accessible title/description, citation
identity/ranges/editability, visible text and preferences, repeating after each
DOCX and ODT save. Only dimensions permit **0.03 pt quantization**; Quds ODT
output writes them to two decimals. This comparison does not claim exact
drawing-object names or every run property.

| Returned file | Pictures | Active citations | Further DOCX/ODT cycles | Result |
|---|---:|---:|---:|---|
| `png-citations.odt` | 2 | 2 | 3 | Matched |
| `jpeg-citations.odt` | 2 | 2 | 3 | Matched |

All 24 original, returned and cycle artifacts are hashed and retained in each
source-specific archive. Verification left the returned ODT bytes unchanged.
The integration archive repeats this converter qualification on `ef05b99e`.

The reusable generator/verifier is
[`odt_image_acceptance.dart`](../../../packages/quds_office_engine/tool/zotero/odt_image_acceptance.dart).
From the repository root with pinned dependencies available:

```bash
QUDS_IMAGE_CHECK=$(mktemp -d)
dart --packages=.dart_tool/package_config.json \
  packages/quds_office_engine/tool/zotero/odt_image_acceptance.dart \
  create "$QUDS_IMAGE_CHECK/original"
mkdir "$QUDS_IMAGE_CHECK/saved"
soffice --headless \
  "-env:UserInstallation=file://$QUDS_IMAGE_CHECK/profile" \
  --convert-to odt --outdir "$QUDS_IMAGE_CHECK/saved" \
  "$QUDS_IMAGE_CHECK/original/png-citations.odt" \
  "$QUDS_IMAGE_CHECK/original/jpeg-citations.odt"
dart --packages=.dart_tool/package_config.json \
  packages/quds_office_engine/tool/zotero/odt_image_acceptance.dart \
  verify "$QUDS_IMAGE_CHECK/saved" "$QUDS_IMAGE_CHECK/original" \
  "$QUDS_IMAGE_CHECK/cycles"
```

The archived Python runners record the exact original execution environment;
adjust their workspace locations when reproducing elsewhere.

## Bounds and remaining parity work

The document shares a budget of 32 pictures and 4 MiB of raster-file bytes,
with additional pixel and decompression limits. Displayed dimensions must be
1–4,000 pt. Package references must stay within `Pictures/` without traversal,
external authority or ambiguous separators.

Floating/adjusted graphics, SVG, OLE, alternate representations, animated PNG,
unsupported orientation/color modes, shared/hidden owners and pictures inside
field caches remain refused. Inherited styles must be representable or
demonstrably inactive for the admitted bitmap frame. See the
[input](../../roadmaps/zotero/native-odt-input.md) and
[output](../../roadmaps/zotero/native-odt-output.md) contracts for full limits.

A separate local probe preserved Amiri, 44 pt size and superscript around an
image. The generic `complexScript=true` flag still reimports as `null`; complete
script-state fidelity is not claimed. The probe observed no picture geometry
change.

The immutable starting-source converter probe documents bibliography section
and table-default refusals. Those retained files were never repaired or
normalized. Later section/note/table work through `3eac83d1` subsequently entered
main in the completed Mail reconciliation. Its original continuation records
and the incoming qualification above retain their own scope; the older
plan/pending observations are not descriptions of the final main tree.

Next priorities are those retained real-document cases, followed by identified
release versions of Zotero and actual Word/LibreOffice plugins: citation and
bibliography editing, style changes, refresh, unlink, note/annotation insertion
and repeated bidirectional saves. Apache OpenOffice remains a separately
versioned legacy target. This converter run cannot establish its compatibility.
The [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) tracks these
implementation and host-acceptance steps.

## Remote intake and incremental preservation

Before implementation, all advertised fork/upstream branches and PR heads were
fetched. All 378 captured refs were accounted for: 364 actual ancestors, ten
independently reverified patch equivalents and four API-confirmed squash
integrations checked by tree or aggregate blob equality. No captured completed
work required replay. See [intake accounting](intake/intake-accounting.json),
[review](intake/review.md) and [squash metadata](intake/pr-squash-metadata.json).

The later [publication audit](publication/review.md) accounts for 381
nonsymbolic refs and one alias at its explicit cutoff. Main remained unchanged,
with no open PRs. Three concurrent Word, Mail and Zotero implementation branches
remained in progress according to their exact-head evidence and were preserved
separately. The audit records their changes and overlapping Zotero files.
Subsequent frontier checks belong to the final publication record; this
snapshot does not predict future heads.

| Remote checkpoint | Saved work |
|---|---|
| `0fe53777c0bb1fe65950401b381cd6e18a6f4bd9` | Reconciled baseline, immutable intake and scope |
| `fac61ecd02829e617c60787d289233327213c044` | Image reader/exporter, lifecycle/editor tests and converter harness |
| `81e478ca0ffe249a908362cd233790b8920d439c` | LibreOffice style guards, unique names and independent tests |
| `58fe5b978f63af282ccd3f3406f86e431e440030` | Continuous-header correction, collision regression and precise contracts |
| `3c54b4f73fbcaf46dff8217c0410209f40848d58` | Source-bound image qualification, raw logs, untouched converter artifacts and diagnostic history |
| `ef05b99ec9bbf1d539181c8519eb41455d182603` | Normal merge of the completed current-main Word shading/Unicode work |
| `7a830c71a91e414b2fe02f64d6bc9422d6b41211` | Combined 1,688-case qualification, supplemental dependency binding and fresh converter evidence |
| `7086ad80266981d612615710610d66bf3fcfb5cf` | Normal merge of current-main proofing/selection paint caching |

Every update used the expected old remote head and verified Git blob/tree
identity. Implementation history is retained for the final main merge.

The [diagnostic record](diagnostics/README.md), [archive](diagnostics/execution.tar.gz)
and [hash index](diagnostics/archive-contents.json) retain failed routes and
intermediate checks. Final acceptance uses the qualified source and receipts
above.
