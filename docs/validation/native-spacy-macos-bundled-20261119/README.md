# App-bundled macOS spaCy library: analysis and manual grammar qualification — 19 November 2026

**Result: qualified.** The ad hoc signed macOS arm64 library that Studio ships
in `Contents/Frameworks/libcrispembed-spacy.dylib`,
SHA-256 `ccc96620e01164d18e8d2e46b9a383677e4430c8889833bedab5b56c16a1b40f`
(2,322,928 bytes), reproduces the recorded analysis parity and the recorded
Linux grammar results exactly. It is now listed in `spacyRecordedBuilds` with
analysis and manual de-DE grammar claims and in the planner's
`spacyGrammarNativeSha256s`. The Linux digest `ea89842e…` stays qualified.
Every other build, including a rebuild of the same source with another
toolchain, remains analysis-only or unrecorded.

## 1. Reproducibility and the pinned bytes

[reproducibility.json](reproducibility.json) records the details.

- **Before:** `tool/build.py --native` was not reproducible across checkout
  locations. Thirteen absolute source paths (`__FILE__` in ggml and PCRE2
  assertions) were compiled in, so each clone produced different bytes
  (for example `66d54a60…` in the earlier test app and `d85c3783…` from a
  fresh build). A digest-bound qualification could not survive a rebuild.
- **Fix:** `-ffile-prefix-map=<output>=/quds-spacy-build` for PCRE2 and the
  native library. The receipt records it, and older receipts are rebuilt
  rather than reused. `LC_UUID` is kept because ld derives it from the content.
  `-no_uuid` was not needed, and dyld loading is unchanged.
- **After:** three clean builds in three different directories gave identical
  unsigned bytes: `c7033059…` (2,318,264 bytes). None contains a host path.
  Building the test targets in the same tree does not change the library.
- **Signing:** `codesign --force --sign - --timestamp=none` is deterministic.
  The ad hoc identifier comes from the file name and `LC_UUID`. Re-signing is
  idempotent, so the app build's signing step yields `ccc96620…`.
- **Choice:** the build is reproducible, *and* the qualified signed bytes are
  pinned. Reproducibility makes the artifact auditable from source. It is still
  toolchain-bound: another Xcode/clang would produce different bytes and quietly
  lose grammar. `build_macos_app.sh` therefore downloads the exact qualified
  file by default. The file is at Hub `cstr/crispembed-spacy-de-core-news-sm-3.8.0`, immutable
  revision `2aa70083055073adf8d2ffbb0ff203cc4fcafd7e`, path
  `app-bundled/macos-arm64/<sha256>/libcrispembed-spacy.dylib`, with a
  `provenance.json`. The script verifies the SHA-256 and length before
  installing the file and checks that the digest is unchanged after signing.
  `--rebuild-spacy` builds from source instead and reports whether the result
  is the qualified build. A fresh-cache readback of the published file was
  byte-identical.

## 2. Analysis parity on the exact signed bytes

These are the same controls as the published macOS capsule record (hosted run
44302625032), run on Apple silicon (macOS 26.2) against `ccc96620…`. The
German bundle was downloaded from the pinned Hub revision `659dae33…`, and
all five file digests match `bundle.dart`. The frozen W1 development
references come from this repository (`tools/proofing/spacy/fixtures`).
CrispEmbed `tests/` came from source `45b05770`. No Python spaCy runtime was
used or installed.

| Check | Result | Capsule record |
| --- | --- | --- |
| ctest (pipeline, numeric, lexical, decode contracts) | 4/4 passed ([log](analysis/ctest.log)) | ctest passed |
| C text-API controls | 21/21 passed ([report](analysis/text-api.json)) | 21 |
| Process enable API controls | passed ([log](analysis/enable-api.log)) | passed |
| Prepared-feature parity | passed: 16 cases, 113 tokens, 1,201 trace stages, 244 parser states, 339 classifier decisions, 1,406,553 floats ([report](analysis/prepared-parity.json.gz)) | 16 / 113 / 1,201 |
| Text parity | passed: 16 cases, 113 tokens, 22 sentences, 1,201 numerical stages, 244 parser steps ([report](analysis/text-parity.json.gz)) | 16 / 113 / 22 / 1,201 |

## 3. Manual grammar: cross-binary replay of both consumed panels

Neither consumed panel was re-qualified or tuned. The new
[`tool/replay_grammar_panels.dart`](../../../packages/quds_proofing_spacy/tool/replay_grammar_panels.dart)
runs each panel's unchanged cases through the given exact library. It uses the
unchanged scoring code of `evaluate_grammar.dart` (`arm`, `summarize`,
`finding`) and the original document/configuration IDs. Each case is compared
with the **retained original Linux result**. For every case it compares the
complete annotation JSON (tokens, tags, POS, morphology, lemmas, dependencies,
heads, sentences), the planner decisions, the baseline, native and combined
arms, the merge suppression count, the operational status and the
corrected-text recheck (annotations, decisions and findings). The only field
allowed to differ is `identity.library_sha256`. The planner accepts the
candidate digest only because it is listed in `spacyGrammarNativeSha256s`. It
would have been removed again on any difference.

| Panel | Retained original | Native exact | Combined exact | Baseline exact | Valid / guard findings | Case differences | Summary differences |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| W6 sealed, 86 cases (30 error, 42 valid, 10 guard, 4 unsupported) | `qualification-first.json` (Linux `ea89842e…`) | 22/30 | 22/30 | 5/30 | 0 / 0 | **0** | **0** |
| W7 extension, 96 cases (40 error, 40 valid, 12 guard, 4 unsupported) | CrispEmbed run 44262982569 `new-panel-result.json`, SHA-256 `a6546bb6…` (Hub `4d3f24b3…`, fresh download) | 24/40 | 24/40 | 14/40 | 0 / 0 | **0** | **0** |

Both replays: zero operational failures. All 22 and 24 corrected rechecks
gave no native findings. The merge suppressed 5 and 14 proposals,
respectively, as in the originals. In total 182 case annotations and 46
recheck annotations are identical. Reports:
[W6](grammar/w6-replay.json.gz) and [W7](grammar/w7-replay.json.gz). The W7
input panel is copied unchanged from CrispEmbed
`docs/validation/native-spacy-w7-20261118/owner-execution/coverage-freeze/panel.json`
to [w7-extension-panel/panel.json](w7-extension-panel/panel.json) (SHA-256
`92338ceb…`, as in its freeze).

The real native editor gate (`studio_spacy_grammar_native_gate.dart`, now
accepting any build in `spacyGrammarNativeSha256s`) passes 10/10 with this
library ([log](grammar/editor-gate.log)), as the Linux build did in W6.

## 4. What changed in the code

- `grammar_planner.dart`: `spacyGrammarNativeSha256s` (Linux + app-bundled
  macOS). The identity must still be the exact default German profile with
  capability mask 15. A qualified build with NER attached (mask 31) is refused.
- `distribution.dart`: `spacyGrammarMacosBundledSha256` and its
  `SpacyBuildQualification` (analysis + grammar) in `spacyRecordedBuilds`.
  The catalog/planner consistency test now compares against the set.
- Studio: the grammar provider opens its worker with
  `openGrammarTransport()`, which leaves out NER. Without that, the opt-in
  named entities would have turned the grammar identity into mask 31. The
  bundle gate now also switches grammar on through the host and checks a W6
  sentence. A new test keeps the build script's pin equal to the qualified
  digest.
- `build.py` is reproducible, and `build_macos_app.sh` installs the pinned
  qualified bytes (`--rebuild-spacy` for a source build).

## Scope

Manual de-DE grammar only, on these exact signed bytes inside an app bundle,
on Apple silicon. This is a finite authored panel replay, not a population
estimate of German grammar quality. It is ad hoc signed, not notarized.
Caller cancellation still does not interrupt native compute.
