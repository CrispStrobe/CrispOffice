# French analysis model: observed source boundary

Reviewed 2026-11-18 after integration of document-review head
`b9728ea1ec835cb589b266cfe9fc98507eb7acfa`. This is a repository/source inspection
and local synthetic-test report. No remote model, native library or license
file was downloaded for this check.

## What the merged source contains

The new French support consists of original Dart adapter behaviour and
compiled catalog metadata: model identity, language, repository/revision,
artifact names, SHA-256 digests, byte counts and a user-visible license summary.
The adapter package retains its
[`MIT LICENSE`](../../../../packages/quds_proofing_spacy/LICENSE).
Its [`NOTICE`](../../../../packages/quds_proofing_spacy/NOTICE) identifies the
native runtime and models as separately installed components. That notice
still names the original German model; the new English/French declarations
appear in the expanded catalog.

The incoming 120-file delta contains **no added GGUF model, `resources.json`
model payload, native shared library or Python wheel**. Its one added runtime
setup archive contains restoration scripts, dependency records and logs;
inspection of the archive member list found no model or native library.
All 23 checked Mail library source files contain no reference to
`quds_proofing_spacy`, `fr_core_news_sm` or `spacyFrenchDownload`.
There are no tracked `apps/quds_office` files in this checked tree, so this
inspection does not claim qualification of a standalone application archive.

## What is optional and separately installed

[`SpacyBundle.frenchF32`](../../../../packages/quds_proofing_spacy/lib/src/bundle.dart)
describes `fr_core_news_sm` version **3.8.0**, converted to a version-2 bundle.
[`spacyFrenchDownload`](../../../../packages/quds_proofing_spacy/lib/src/distribution.dart)
points to the separate repository
`cstr/crispembed-spacy-fr-core-news-sm-3.8.0` at immutable revision
`5e90593195cc4ecd20ceb864d932d7d7f5e3d762`.

The source declares the model **LGPL-LR**, a conversion of the original
linguistic resource. Its displayed summary names additional training-source
notices for UD French Sequoia (LGPL-LR), WikiNER (CC BY 4.0), and spaCy lookups
(MIT), and says corpus text is not included. These are declarations present
in the checked source; this review has not independently read the remote
license/notices artifacts or approved a product's redistribution terms.

The five separately installed files total **48,226,946 bytes**:

| Artifact | Bytes | SHA-256 pinned in Dart |
| --- | ---: | --- |
| `model.gguf` | 12,780,352 | `8b8f9ab4aa322191faa1735d1b7d53e0e744e18f4025290fe37242faa9a8e53e` |
| `resources.json` | 35,391,368 | `bbdd7b6a51478abcc8e6d6e9cfad0d70e3a3f44a76de6ed4be4fdbb699825f8d` |
| `LICENSE` | 4,424 | `fcfeb5f3a67aa25d659d1162b4f4a9c52a92171d4df68a11d87c52e3af982a17` |
| `LICENSES_SOURCES` | 28,874 | `21ea31093799e954757d62505687652dfd059d8685f97266d1a442f8a39fcdde` |
| `manifest.json` | 21,928 | `986d620edc745624198c56d3494fa30f3b649786c1d93a29db76fe55196f2264` |

[`installLanguageBundle`](../../../../packages/quds_proofing_spacy/lib/src/installer_io.dart)
downloads these five files into staging, checks their compiled-in digests and
lengths, and verifies the installed tree. `installLanguage` can additionally
install a separately pinned version-2 native runtime if it is absent. The
bundle-only method supports hosts that already ship that runtime.

In the Office example's
[`analysis setup screen`](../../../../packages/quds_office_editor/example/lib/studio_spacy_setup.dart),
the user can inspect source, files, sizes, hashes and license metadata, then
activate a specific **Download French** button. The
[`native host`](../../../../packages/quds_office_editor/example/lib/studio_spacy_host_native.dart)
checks installation status and verifies files before opening a worker. Its
open path reports unavailable when the language is not installed; it does
not invoke the installer automatically.

## Local test scope

The requested language-catalog, analysis, bundle, distribution and worker
cohort passed **51 tests**. Full adapter `lib` analysis passed with no issues.
Current commands, elapsed times, source hashes before/after and output digests
are recorded in the adjacent `late-spacy-*-receipt.json` files and `.txt` logs.
All recorded source inputs were unchanged during both runs.

Installer failure tests use synthetic loopback HTTP responses and temporary
directories. Worker tests use synthetic backends and real isolate protocol
messages. They do not establish native French model accuracy or reproduce
the imported model's earlier inference evidence. The language test named
“wrong bundle bytes” rejects the synthetic runtime archive before fetching
the language bundle; its result is not proof that all five French artifacts
were fetched or individually exercised here. Per-artifact verification was
also inspected in the installer source.

The observed boundary is therefore an optional, explicitly installed
linguistic resource described by the broader Office adapter. No French
model payload or LGPL-LR implementation was added to the Mail packages or
to a standalone application package by this merge.
