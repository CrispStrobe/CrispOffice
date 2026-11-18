# English and French local analysis — 18 November 2026

Branch `integrate/spacy-en-fr-20261118`, created from Quds `main`. Checkpoints
were pushed with `[skip ci]`; no GitHub Actions or status endpoint was queried
for Quds. Validation is local (Dart/Flutter tests and a real Hub install).

## 1. Incoming work taken in first

All origin branches were fetched and classified by ancestry, PR state and a
trial merge (`git merge-tree`) against this branch. The incoming stream was
still moving during the work, so a second pass ran before the final checkpoint.

| Source | Head merged | Decision | Reason |
| --- | --- | --- | --- |
| PR #168 `codex/zotero-wordlike-20261118` | `d82d25cc` (first pass) | **Merged** | Contained the heads of #164, #165, #169 (then), `zotero-citation-workflow` and `native-spelling-resume`. |
| `origin/main` | `4fbc8741` | **Merged** | Docs-only commit after the first pass. (PR #168 was later merged by its owner into the #162 branch, not into main.) |
| `codex/zotero-note-workflow-20261118` (no PR) | `fcb8a4b0` | **Merged** | Clean; reconciles review, Zotero, thesaurus and main. |
| PR #162 `codex/document-review-20261118` | `b5d4df51` | **Merged** (second pass) | In the first pass its one unique commit conflicted with `d82d25cc` in two test files (proofing-language inheritance); its owner then reconciled it on top of #168 and it merged cleanly. |
| PR #169 `codex/offline-thesaurus-20261118` | `1850c337` | **Deferred** | Conflicts with #162/zotero-note in `office_controller.dart` and `office_editors.dart`; its owner was committing reconciliations minutes apart. Resolving another agent's core editor conflicts here would risk silently choosing behavior. |
| `codex/mail-reader-20261118` (no PR) | `0e07d247` | **Deferred** | Same `office_editors.dart` conflict; in active development. |
| PRs #164, #165 | — | Included | Their heads are ancestors of the merged branches. |
| `feat/ods-time-period-conditions` | `7ef09f24` | No-op | Patch-equivalent commit already in main (`34dc6b68`, #151). |
| `integrate/office-union-148`, `integrate/office-union-150`, `integrate/odt-column-boundary-144`, `docs/ods-icon-sets`, `feat/ods-icon-sets` | — | No-op / superseded | Only merge commits or patch-equivalent content; later Office unions in main supersede them. |

## 2. Distribution (CrispEmbed side)

| Item | Value |
| --- | --- |
| English bundle | `cstr/crispembed-spacy-en-core-web-sm-3.8.0` at `eb659259b489593ddf29c747bc4562fbad5570f4` |
| French bundle | `cstr/crispembed-spacy-fr-core-news-sm-3.8.0` at `5e90593195cc4ecd20ceb864d932d7d7f5e3d762` |
| Publication | CrispEmbed run 44372635419 (main `e91b054d`): converted on hosted Linux from the pinned wheels, every pin checked, immutable tree and fresh empty-cache readback of every file |
| v2 runtime capsules | Built from CrispEmbed main `45b05770` by run 44369523105 and published in the German repository: linux-x86_64 `6e21ae15…` (revision `d143d26a`), linux-arm64 `21d15c1e…` (`fd75184d`), macos-arm64 `f3300152…` (`cf833ae5`). The Windows build failed its text-API controls and is not published. |
| Consumers | Same run: each published capsule + bundle downloaded, verified and installed; admission controls and a ctypes-only analysis vs original spaCy: EN 2,077/2,077 texts, 25,531 tokens, 1,876/1,876 entities; FR 416/416, 9,786 tokens, 469/469 (Linux x86-64, Linux arm64, macOS arm64) |

The French model is **LGPL-LR** (as the official `fr_core_news_sm` package),
not MIT; the setup view says so and installs the full license text.

## 3. What is wired

| Area | Files | Behavior |
| --- | --- | --- |
| Languages and bundles | `quds_proofing_spacy/lib/src/bundle.dart` | `SpacyLanguage` (German `de-DE` only, as qualified; English and French any region). `SpacyBundle.englishF32()` / `frenchF32()` with all five file pins; per-bundle capability masks (v1 15/31, v2 12/28). German statics unchanged. |
| Identity | `backend.dart`, `analysis.dart`, `worker_native.dart` | Identity validated against its own bundle; a result's locale must belong to the identity's bundle. The grammar planner still requires the exact German identity and library pin, so EN/FR can never reach grammar. |
| Catalog | `distribution.dart` | `spacyRuntimePackages` (v2 capsules above, `opensVersion2Bundles`, no grammar claim), `spacyEnglishDownload` / `spacyFrenchDownload` at immutable revisions with license and evidence. German packages and the grammar pin are unchanged. |
| Installer | `installer_io.dart` | `installLanguage` (explicit; bundle + runtime capsule when missing), `installLanguageBundle` (bundle only, for hosts that ship the library), `installedLanguage`, `removeLanguage`. Every file is SHA-256/length-checked before use; trees are published with one rename and fully re-verified on every open. |
| Native backend | `native_backend.dart` | Opens any pinned bundle. Enables the library with `crispembed_spacy_set_enabled` (flags only added, so one worker never disables another); `setenv` remains only as the fallback for libraries without that export. Linux arm64 and Windows x86-64 are loadable ABIs (no Windows package is offered). |
| Studio host | `studio_spacy_host*.dart`, `studio_spacy_config*.dart` | Per-language status (offered, installed, problem, bytes), `installLanguage`, `removeLanguage`, `openLanguageTransport`. The German path no longer calls `setenv` itself. |
| Studio UI | `studio_spacy_setup.dart`, `studio_linguistic_analysis.dart` | Setup lists English and French with source revision, file sizes and SHA-256, license and evidence; download only on click. The analysis view (“Text analysis”) uses the text's marked language or an explicit “Analyze as” choice and shows tokens, POS/tag, morphology, lemma, dependencies and entities. |

German manual grammar is unchanged: German-only and bound to the qualified
Linux build. No grammar is offered for English or French.

## 4. Local validation

| Check | Result |
| --- | --- |
| `quds_proofing_spacy` `dart test` | 95 passed (87 existing + 8 new in `test/language_catalog_test.dart`) |
| `quds_proofing_spacy` `dart analyze` | No new issues (9 pre-existing infos in `tool/consume_distribution.dart`) |
| Studio `flutter analyze` | No issues |
| Studio `flutter test` (all 17 files), first pass | 102 passed, 1 skipped |
| Studio `flutter test` (all files) after the second integration pass | 118 passed, 1 skipped |
| Real Hub install + Dart worker on Apple silicon | [Passed](hub-macos-arm64-en-fr-e2e.json): fresh empty root; macOS v2 capsule and both bundles through the app installer; real isolate workers; EN entities Apple/ORG, U.K./GPE, $1 billion/MONEY, Tim Cook/PERSON, London/GPE, Monday/DATE; FR Emmanuel Macron/PER, Renault/ORG, Paris/LOC; a de-DE request to an EN/FR worker is refused; German analyzed both by the unchanged German package (`918a069e…`) and by the v2 capsule (`f3300152…`). The process had no `CRISPEMBED_SPACY*` variable: enablement was `crispembed_spacy_set_enabled`. |
| Bundle-only install + locally built library | [Passed](local-library-bundle-only-smoke.json) (development check; the library was built locally from the same CrispEmbed source, not the published bytes) |

Toolchain: Flutter 3.44.4 / Dart 3.12.2 with a temporary `PUB_CACHE`.

## 5. Open risks and follow-ups

- **Windows:** the v2 Windows library fails one text-API control
  (`crispembed_spacy_create_with_resources` with a wrong model hash raises an
  MSVC C++ exception across the C ABI, `0xe06d7363`); reported to the CrispEmbed
  runtime owner. No Windows package is offered; the earlier Windows capsule
  (pre-v2) remains unwired in Quds.
- Two libraries can be loaded in one process on Linux x86-64 and macOS (German
  package + v2 runtime). Each is opened by its own full path in its own worker;
  verified on macOS above, not on Linux.
- English/French are not offered for iOS/Android (no app-embedded library
  wiring yet); `installLanguageBundle` is ready for that path.
- The French resources file is 35 MB; download is explicit and shows the size.
- German analysis could move to the v2 capsule on platforms without a German
  package (Linux arm64); not done, since it would change the German offering.
