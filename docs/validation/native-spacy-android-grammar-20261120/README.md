# Android arm64 spaCy library: manual German grammar qualification — 20 November 2026

**Result: qualified for manual de-DE grammar.** The Android arm64-v8a library
that the Studio APK ships, `libcrispembed-spacy.so`, SHA-256
`ed730f629ce4eafe139885e9b1029a41fe05f3d5032fb992fb61eb834950f7ad`
(3,155,576 bytes), was replayed on an Android 16 (API 36) arm64 emulator on
all three consumed grammar panels, through the same Studio host worker that
the app uses for grammar. Every annotation matches the recorded Linux/macOS
results. W6 and W7 match case by case with zero differences. Grammar v2
differs only in seven planner rows, and those come from a source change
made after the v2 qualification, not from the library (see below). The
digest is now listed in `spacyGrammarNativeSha256s` and has a grammar claim
in `spacyRecordedBuilds`. Studio therefore offers **Manual German grammar
suggestions** on Android with this library. Everything else, including iOS,
is unchanged. This follows the same protocol as the
[macOS bundled qualification](../native-spacy-macos-bundled-20261119/README.md).

## Identity of the Android library

- An ELF shared object has no embedded signature. APK signing seals the
  archive, not the `.so` file. So the whole-file SHA-256 is the identity,
  and there is no code digest (unlike Mach-O, `machOCodeSha256`). The Studio
  host measures the SHA-256 of the extracted library it loads
  (`detectMobileBundledSpacyLibrary`). The native backend checks it again
  before every load, and the planner accepts only the identity that the
  worker reports (`spacyGrammarQualifiedIdentity`, `codeSha256` null).
- The Studio Android build stops Gradle from stripping this file
  (`keepDebugSymbols`) and keeps it extracted (`useLegacyPackaging`).
  `tool/build.py` already strips it, so the APK carries exactly these bytes.
  A build that strips or rewrites the file again has a different digest,
  and grammar is refused for it.
- **The build host matters.** The same pins built with the Linux-hosted NDK
  on GitHub gave a different x86_64 file (`415eb360…`) from the
  macOS-hosted receipt (`0372f77d…`). So the qualified arm64 bytes must be
  taken from the recorded macOS-hosted build and not rebuilt on CI. The
  workflow's `expected_sha256` input refuses any other bytes.
- **Reproduced byte-exact.** A fresh `tool/build.py --android --android-abi
  arm64-v8a --ios` from the pinned CrispEmbed `45b05770` / PCRE2 `b2bd4254`
  with NDK 28.2 gave `ed730f62…` again. It also gave the receipt's iOS
  digests (`2a0ca967…` device slice, `054c21e3…` simulator slice). The
  emulator ran that rebuilt file, installed into `jniLibs/arm64-v8a`.

## How the replay ran on the device

- The case loop and comparison moved unchanged into
  [`tool/grammar_replay_core.dart`](../../../packages/quds_proofing_spacy/tool/grammar_replay_core.dart).
  `replay_grammar_panels.dart` (W6/W7, desktop) and the new
  `replay_grammar_v2.dart` (v2, desktop) call it. So does the on-device
  test. Scoring is still `arm`/`summarize`/`finding` from
  `evaluate_grammar.dart`. The v2 loop and per-family summary are the ones
  in the sealed `evaluate_grammar_v2.dart`, which itself is unchanged.
- The device test is
  `packages/quds_office_editor/example/integration_test/mobile_spacy_grammar_replay_test.dart`.
  It opens `NativeStudioSpacyHost`, installs the pinned German bundle into
  the app sandbox, and calls `openGrammarTransport()`, the worker the
  grammar provider uses (no NER, capability mask 15). Then it replays W6,
  W7 and v2.
- The inputs are not packaged in the app. The host serves them with
  [`tools/proofing/spacy/grammar_replay_server.py`](../../../tools/proofing/spacy/grammar_replay_server.py)
  through `adb reverse`. The server and the test both check every file
  against the same pinned SHA-256, and the reports are uploaded back.

| Input | SHA-256 | Source |
| --- | --- | --- |
| W6 panel | `52bede2f…` | `docs/validation/native-spacy-w6-20261117/qualification-panel.json` |
| W6 retained result (Linux `ea89842e…`) | `2e85b972…` | `…/native-spacy-w6-20261117/qualification-first.json` |
| W7 panel | `92338ceb…` | `…/native-spacy-macos-bundled-20261119/w7-extension-panel/panel.json` |
| W7 retained result (Linux `ea89842e…`) | `a6546bb6…` | Hub `cstr/crispembed-spacy-de-core-news-sm-3.8.0` @ `4d3f24b3…`, `retained-w7-evidence/…/44262982569/new-panel-result.json` |
| v2 protocol / panel / clean corpus | `6412ccf4…` / `80997c7e…` / `c9e037ee…` | `…/native-spacy-grammar-v2-20261120/` |
| v2 recorded qualification (macOS `ccc96620…`) | `c3336e43…` (uncompressed) | `…/native-spacy-grammar-v2-20261120/qualification-macos.json.gz` |

Commands (emulator driven from the CLI only; temporary AVD from the system
image `android-36;google_apis_playstore;arm64-v8a`, device `pixel_6`):

```sh
python3 packages/quds_proofing_spacy/tool/build.py --android --android-abi arm64-v8a \
  --install-android packages/quds_office_editor/example/android/app/src/main/jniLibs/arm64-v8a
python3 tools/proofing/spacy/grammar_replay_server.py --port 8765 --reports <new dir> &
adb reverse tcp:8765 tcp:8765
cd packages/quds_office_editor/example
flutter test integration_test/mobile_spacy_grammar_replay_test.dart -d <emulator> \
  --dart-define=QUDS_GRAMMAR_REPLAY_URL=http://127.0.0.1:8765
```

## Results on Android (`ed730f62…`)

| Panel | Rows | Annotations compared | Native exact | Combined exact | Baseline exact | Valid / guard findings | Differences vs retained result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| W6 sealed, 86 cases | 86 | 108 | 22/30 | 22/30 | 5/30 | 0 / 0 | **0** case, **0** summary |
| W7 extension, 96 cases | 96 | 120 | 24/40 | 24/40 | 14/40 | 0 / 0 | **0** case, **0** summary |
| v2 sealed panel (244) + GSD test corpus (977) | 1,221 | 1,283 annotation digests | see families | | | 0 / 0 (qualified families) | **0** annotation; 7 planner rows, all pinned source differences |

W6/W7: the merge suppressed 5 and 14 proposals, as in the originals. There
were 22 and 24 corrected rechecks with no native findings, and no
operational failures. Reports: [android/w6-replay.json.gz](android/w6-replay.json.gz)
and [android/w7-replay.json.gz](android/w7-replay.json.gz).

Grammar v2 per family on Android. The values are identical to the recorded
qualification except for the subject-person controls, as explained below:

| Family | Native exact by the rule | Combined exact | Deterministic | Valid / guard findings | Clean-corpus findings | Recorded |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| np-agreement (qualified) | 13/24 | 15 | 4 | 0 / 0 | `test-s60`, `test-s250` (the two judged genuine errors) | identical |
| preposition-case (qualified) | 18/24 | 18 | 12 | 0 / 0 | none | identical |
| verb-position (qualified) | 9/24 | 11 | 4 | 0 / 0 | none | identical |
| subject-person (experimental, off) | 18/24 | 18 | 10 | 0 / 0 | none | recorded had 1 valid finding (`sp-valid-07`) and 1 non-exact proposal (`sp-error-14`) |

Overall on the 244 panel cases there were 59 native proposals, of which the
merge suppressed 26. The combined arm added 32 exact corrections and lost
none. All 62 rechecks gave 0 findings, there were 0 operational failures,
and the 4 unsupported locales were reported as unsupported. On the corpus,
the deterministic baseline flags 10 of 977 sentences, and there were 0
operational failures. Report: [android/v2-replay.json.gz](android/v2-replay.json.gz).

### The seven v2 differences come from the source, not the library

The sealed v2 qualification ran at Quds `b7f04f12`. After it, a guard was
added to the experimental subject-person family. The guard abstains with
`possible-coordinated-subject` when a nominal plus "und/oder" directly
precedes the pronoun. The grammar v2 README documents it as output-informed
and not qualified. Because of it, `sp-error-14` and `sp-valid-07` no longer
get a proposal (decisions, model and combined arms differ). In
`corpus:test-s256` the decision reason changes from `compatible-reading` to
the new abstention, with no finding either way.

These differences were measured **first on the qualified macOS library**
(`ccc96620…`, from Hub `2aa70083…`, same source, same tool), before Android
ran. The list was pinned in the test and in
[v2-source-differences.json](v2-source-differences.json). The Android
replay had to produce exactly this list and nothing else, and no annotation
digest was allowed to differ. That is what happened.

### Android equals the qualified macOS library on the same source

[`tools/proofing/spacy/compare_replay_rows.py`](../../../tools/proofing/spacy/compare_replay_rows.py)
compared every field of every row of the Android reports with the macOS
control reports in [macos-control/](macos-control/). Only the build digest
is normalized:

| Panel | Rows | Fields compared | Differences |
| --- | ---: | ---: | ---: |
| W6 | 86 | 796 | **0** ([android-vs-macos-w6.json](android-vs-macos-w6.json)) |
| W7 | 96 | 888 | **0** ([android-vs-macos-w7.json](android-vs-macos-w7.json)) |
| v2 | 1,221 | 14,958 | **0** ([android-vs-macos-v2.json](android-vs-macos-v2.json)) |

The macOS control on current source also reproduces W6 and W7 against the
original Linux results with 0 differences. This also checks the refactor of
`replay_grammar_panels.dart` onto the shared core.

## What changed

- `grammar_planner.dart`: `spacyAndroidArm64BundledSha256` added to
  `spacyGrammarNativeSha256s`. The identity must still be the exact default
  German profile with capability mask 15. The code-digest set is unchanged
  and still holds Mach-O only.
- `distribution.dart`: the Android `SpacyBuildQualification` now has a
  grammar claim (manual de-DE, panels above). The mobile platform reason
  text is updated.
- Studio: no host code change was needed. The **Manual German grammar
  suggestions** switch follows `qualification.grammarQualified`, so it is
  now offered on Android with this library. The mobile gate
  (`mobile_native_proofing_test.dart`) now also turns grammar on through
  the host and checks a W6 and a v2 sentence on the grammar worker. For a
  build without a grammar claim, it checks that grammar is refused.
- Tools: `grammar_replay_core.dart`, `replay_grammar_v2.dart`,
  `grammar_replay_server.py`, `compare_replay_rows.py`.

## What ran where

| Run | Where | Library | Outcome |
| --- | --- | --- | --- |
| W6, W7 and v2 replay (`mobile_spacy_grammar_replay_test.dart`) | Local Apple-silicon Mac, Android 16 arm64 emulator (temporary AVD) | `ed730f62…` arm64-v8a | **passed** (the qualification above) |
| macOS controls (W6, W7, v2) | Local Mac, `dart run` | `ccc96620…` | W6/W7 0 differences; v2 exactly the 7 source differences |
| Mobile gate with the new grammar step (`mobile_native_proofing_test.dart`) | Local arm64 emulator | `ed730f62…` | **not completed**. The Mac was overloaded (load about 60–80) and the owner moved emulator work off the machine, so the Gradle build was stopped before the test ran. The earlier gate in [native-proofing-mobile-20261120](../native-proofing-mobile-20261120/README.md) passed on these bytes, but without the grammar step. |
| `/dev/kvm` probe | GitHub `ubuntu-24.04-arm` ([run 44704041243](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44704041243)) | — | no `/dev/kvm` and no Android SDK, so no arm64 emulator on GitHub-hosted runners |
| Mobile gate, workflow [`android-spacy-grammar.yml`](../../../.github/workflows/android-spacy-grammar.yml) (`abi=x86_64 replay=false gate=true`) | GitHub `ubuntu-latest`, API 36 x86_64 emulator with KVM ([run 44708075168](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44708075168)) | x86_64 library built there, `415eb360…` | **7/7 passed** ([ci-x86_64-gate.json](ci-x86_64-gate.json)). Development parity is exact (113 tokens, 22 sentences, 2,571 fields). The new grammar step took the refusal path: the build is unrecorded, Studio does not offer the option and enabling it throws. This is **no claim**: these are x86_64 bytes, and the Linux-hosted NDK gives `415eb360…` where the macOS-hosted receipt gives `0372f77d…`, so the bytes depend on the build host. |
| First CI attempt ([run 44704735862](https://github.com/CrispStrobe/quds_office_suite/actions/runs/44704735862)) | GitHub `ubuntu-latest` | — | failed before the emulator: the Harper Rust target went into the wrong toolchain. Fixed in the workflow. |

## iOS

See [ios.md](ios.md).

## Scope

This covers manual de-DE grammar only, on these exact bytes, inside the
Studio APK, on an arm64 **emulator** (no physical device was attached). It
is a finite authored panel replay plus one clean corpus, not a population
estimate. The numerical stage traces, ctest and C text-API controls were
not run on Android. The x86_64 Android library stays unrecorded. Caller
cancellation still does not interrupt native compute.
