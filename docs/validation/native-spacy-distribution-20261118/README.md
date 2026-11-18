# Native spaCy distribution and Studio wiring — 18 November 2026

Branch `integrate/native-spacy-distribution-20261118`, created from Quds `main`
`1ffcf91a` (PR #155 merge). Checkpoints were pushed incrementally with
`[skip ci]`; no GitHub Actions or status endpoint was queried for Quds.

## 1. Incoming work taken in first

All origin branches with commits since 14 November were fetched (`origin` is the
only remote in the working clone) and classified by a trial merge into current
`main` (`git merge-tree`), by PR state and by ancestry.

| Source | Head | Decision | Reason |
| --- | --- | --- | --- |
| PR #157 `codex/native-spelling-quality-20261118` (open) | `9fc211f6` | **Merged** | Clean; shortlist/Unicode spelling guards and evidence. |
| PR #158 `codex/zotero-tags-20261118` (open) | `5dd3eb7c` | **Merged** | Two changelog conflicts (engine, editor); both entries kept. |
| `codex/office-continue-20261118` (no PR) | `e397671e` | **Merged as history + evidence** | Its 22 evidence files under `docs/validation/office-continue-20261118/` are retained. Its alternate direct-common `SectionFrame` ODT writer and the matching two frame tests/changelog line are **not** taken: main's reconciliation (`docs/validation/office-local-20261118/recovery-handoff.md`, `native-spelling-20261118/reconciliation.md`) explicitly supersedes it with the common-parent `QudsTextFrame` implementation and says not to replace it silently. |
| `codex/office-resume-20261118`, `codex/gector-office-resume-20261117`, `codex/office-union-resume-20261118` (#150 closed) | `8ad80eb2`, `205e913e`, `6d97fedc` | Included via office-continue | All three heads are ancestors of `office-continue`. |
| PR #153 `feat/native-spacy-w7-20261118` (open draft) | `2e013f26` | Already in main | 0 commits ahead of main. PR can be closed as superseded by this branch. |
| PR #139 `feat/native-spacy-reference-20261117` (merged) | `6df76a0d` | Already in main | Merge commit is an ancestor of main. |
| PRs #129–#156 merged since 17 Nov (ODS/ODT/ODP features, Office unions, Zotero, native spelling, local qualification) | — | Already in main | Each merge commit verified as an ancestor of main; leftover branch tips are identical to the merged PR heads. |
| `docs/ods-*`, `docs/aot-removal`, `integrate/odt-column-boundary-144` | — | No-op | Trial merge leaves main's tree unchanged (their content is in main). |

Deferred: nothing else had unmerged content. The remote was refreshed again
before the final checkpoint (see the PR description for the final heads).

## 2. What is wired

| Area | Files | Behavior |
| --- | --- | --- |
| Catalog | `packages/quds_proofing_spacy/lib/src/distribution.dart` | Immutable Hub revision `659dae33…`; Linux x86-64 capsule pins (archive `4e3b627a…`/7,808,129 B, manifest `e043af51…`, library `ea89842e…`); bundle-only download; per-platform availability with reasons; claims keyed by exact library digest. |
| Installer | `lib/src/installer_io.dart`, `lib/quds_proofing_spacy_install.dart` | Explicit download only; full SHA-256/length before parsing; closed canonical USTAR reader; private staging; single-rename publication; full closed-tree re-verification on every open; cancellation; optional verified mirror. |
| Native backend | `lib/src/native_backend.dart` | Loads Linux x86-64 and macOS arm64 libraries; `enableSpacyNativeGateForProcess()` sets `CRISPEMBED_SPACY=1` only after explicit opt-in. Grammar planner/provider sources are unchanged. |
| DTOs | `lib/src/analysis.dart` | Optional `LinguisticEntity` list (`entitiesAvailable`), validated on whole tokens; JSON unchanged when absent. Ready for the opt-in NER runtime; no NER UI yet. |
| Studio host | `example/lib/studio_spacy_host*.dart` | Platform status, verified-install discovery in the private app data directory, persisted default-off opt-ins, unchanged developer-environment precedence. |
| Studio UI | `example/lib/studio_spacy_setup.dart`, `studio_linguistic_analysis.dart`, `suite_workspace.dart` | **Review → Analysis setup** shows source URL, size, SHA-256, licenses; download only on click. Grammar switch only for a grammar-qualified exact build; enabled provider is registered with `configureManual` (Check document only) and released when switched off. |

No analysis-time network: workers open only verified local files. No Python in
the app. The provider remains default OFF.

## 3. Qualification is per exact build

| Build | Analysis | Manual grammar |
| --- | --- | --- |
| Linux x86-64/AVX2 `ea89842e…` (published capsule) | Qualified (native acceptance, W5) | Qualified for the W6/W7 manual de-DE panels only; enforced by `spacyGrammarNativeSha256` |
| macOS arm64 dev candidate `5cb67f00…` (unsigned, not offered) | Hosted component parity only (run 44262399612) | **Not qualified**; planner returns `runtime-mismatch` |
| Any build from the updated CrispEmbed runtime | Needs its own record | Needs its own record; never inherited |

## 4. Local validation (this branch)

| Check | Result |
| --- | --- |
| `quds_proofing_spacy` `dart test` | 86 passed (73 existing + 13 new) |
| `quds_proofing_spacy` `dart analyze` | No new issues (9 pre-existing infos in `tool/consume_distribution.dart`) |
| Studio `flutter analyze` | No issues |
| Studio tests: `widget_test`, `studio_linguistic_analysis_test`, new `studio_spacy_setup_test` | 33 passed |
| Studio `studio_sheet_navigation_test` | 1 failure, **pre-existing** on the merged base without these changes |
| Fresh-cache Hub install through the app installer | [Passed](hub-install-readback.json): capsule and bundle-only, closed trees re-verified; no native load |
| Real macOS arm64 Dart worker with the dev candidate | [Smoke](macos-arm64-candidate-smoke.json): analysis succeeded for two texts; grammar correctly refused the unqualified build |
| CrispEmbed v2 capsule -> Quds installer -> Dart worker (macOS arm64, loopback mirror) | [Passed](v2-capsule-cross-check.json): closed tree installed and re-verified; analysis succeeded. Confirms the Python builder and Dart reader share one contract |

Local toolchain: Flutter 3.44.4 / Dart 3.12.2 (the repository's recorded
qualification toolchain is Flutter 3.47.8 / Dart 3.13.7). Formatting was not
applied to unrelated files.

## 5. Remaining steps after the CrispEmbed runtime update merges

1. Dispatch `tools/ci-heavy/spacy_w7_platform_package.py --platform macos-arm64 --publish`
   from CrispEmbed `main` (PR #239 tooling). Success requires its two immutable
   commits, exact trees, fresh-cache readback and reinstall from downloaded bytes.
2. Add a `SpacyPlatformPackage` for `macos-arm64` to `distribution.dart` using the
   receipt's revision, archive/manifest/library digests and lengths, with the
   receipt's analysis claim and `grammar: null`.
3. Manual grammar on that build needs its own evaluation on the exact library and
   an explicit extension of the planner's build pin; it is not inherited.
4. Opt-in NER/senter: render `LinguisticEntity` spans in the analysis view only
   once the runtime reports them.

Hosted dry runs from CrispEmbed `main`+tooling (nothing uploaded) are recorded in
[v2-capsule-cross-check.json](v2-capsule-cross-check.json): macOS arm64 reproduced
library `5cb67f00…` byte for byte and passed all controls from the installed
capsule; a Linux build with static libstdc++ crashed (not used).

## 6. Platform status

- **Linux x86-64**: downloadable, verified install, analysis + qualified manual grammar.
- **macOS arm64**: code path ready and smoke-tested; no package offered until a
  package built from the updated CrispEmbed runtime is published with its own
  record. The Studio example has no macOS runner; a signed/hardened app needs
  library-validation handling (or must ship the library in the bundle).
- **Windows**: no native build or qualification.
- **iOS / Android**: the library must ship inside the signed app; only
  `installBundle()` (model files) may be downloaded. Not built or qualified.
- **Web**: unavailable by design.
