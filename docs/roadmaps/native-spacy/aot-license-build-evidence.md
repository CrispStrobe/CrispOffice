# Historical AOT build: license-audit evidence

Recorded **17 November 2026** by read-only inspection of the retained Linux
x86-64 Release worker from Quds commit
[`e37ccdb47c047f6a0250585cf5cb20efc17573b4`][quds-commit]. This receipt preserves
the inputs behind the [licensing assessment](licensing-and-distribution.md).
It records no new build or test run, and establishes neither redistribution
clearance nor support for Apple or other platforms. Current `main` excludes AOT;
this historical evidence does not reintroduce it.

## Identity and retained source evidence

The [published runtime manifest][manifest] records AOT revision
`0d591d972c7bb2729f4764d3bc32611ea6fd142a` and `nlp_base` revision
`244b3d1f9a09e4a81e75ea83c3b55b209c663503`. The retained executable still matches
its recorded hash. The [toolchain receipt][toolchain] identifies GCC 14.2.0,
CMake 4.4.5, Bison 3.8.2, Flex 2.6.4 and the Release configuration.

| Artifact | SHA-256 |
| --- | --- |
| `Bin/quds_aot_worker` | `d20a7a707736c05fb0e2143aa517769f0136a459cfef9c113af5ecfd375a0d0f` |
| Quds `native/worker.cpp` — manifest | `8d0647ce028c3d250381ddad2c0e33f787a1bb87d40ce2b6b50bd3ebd9a13c31` |
| Quds `native/CMakeLists.txt` — manifest | `79d26dc364ff8fd426b7bebf061d1ee2fae2b4503b741224a07eb0f2c51f66f3` |
| Worker `CMakeFiles/quds_aot_worker.dir/link.txt` — inspected | `db8893c97a69d7cc27b47efe3b95cbc2fbb159fcf05fcfe5466bb7dbb82ecd13` |
| Generated `Source/synan/SimpleGrammarLib/chunker_yacc.cpp` — inspected | `96bd687ee577648090680f3ccf9ae7264d1aded4a835516c9c9c0d7a8bb25ac3` |
| Pinned `nlp_base/common/utf8.cpp` — inspected | `b02c73c86207fbe4a6f5c278335ad6d6807a3aaa7fa306bd4e407de012d487eb` |
| Flex 2.6.4 `src/FlexLexer.h` — inspected | `ee9859d6b3027ed565f98f42744e438ab31b2cd2e9f797ddf870029ca2021686` |

The manifest also records the three generated upstream patch hashes. The
[historical CMake recipe][cmake] and [assembler][assembler] identify how those
sources and the installed file set were produced. Absolute build locations
affect the link-command file hash; the input inventory below is preserved
independently of those locations.

## Actual static and dynamic inputs

The worker's link command names **18 upstream archives plus system zlib**.
These are the complete archive arguments, in link order, relative to the build
directory except for the system archive:

```text
upstream/synan/SynanLib/libSynanLib.a
upstream/synan/RusSynanLib/libRusSynanLib.a
upstream/synan/GerSynanLib/libGerSynanLib.a
upstream/synan/EngSynanLib/libEngSynanLib.a
upstream/synan/SynCommonLib/libSynCommonLib.a
upstream/synan/GerPostMorph/libGerPostMorph.a
upstream/synan/MAPostLib/libMAPostLib.a
upstream/synan/SimpleGrammarLib/libSimpleGrammarLib.a
upstream/LemmatizerLib/libLemmatizerLib.a
upstream/nlp_base/lemmatizer_base_lib/liblemmatizer_base_lib.a
upstream/nlp_base/graphan/GraphanLib/libGraphanLib.a
upstream/nlp_base/morph_wizard/libmorph_wizard_lib.a
upstream/nlp_base/agramtab/libAgramtabLib.a
upstream/common/libaot_common.a
upstream/RmlThesLib/libRmlThesLib.a
upstream/nlp_base/dicts/StructDictLib/libStructDictLib.a
upstream/nlp_base/common/libmorphology_common.a
upstream/nlp_base/contrib/iconv_subset/libiconv_subset.a
/usr/lib/x86_64-linux-gnu/libz.a
```

`readelf -d` reports exactly these direct `NEEDED` entries:

```text
libstdc++.so.6
libgcc_s.so.1
libc.so.6
```

Compiler-generated dependency files identify the bundled `iconv_subset`,
RapidJSON and plog headers. Qt, httplib, doctest and libzip were absent from the
inspected worker link/dependency set. The generated Bison parser includes the
explicit parser-output exception; the inspected Flex header includes its
BSD-style notice. These observations do not substitute for a complete inventory
of runtime data or other platform builds.

## Installed notices and reproduction of the inspection

The retained runtime's `notices/` directory contains exactly:

```text
AOT-COPYING
QUDS-NATIVE-NOTICE.md
```

The assembler copies AOT's license, tries `nlp_base/LICENSE` then
`nlp_base/copying`, and continues if neither exists. Neither root file exists at
the inspected pin. The two-file inventory is evidence of incomplete notice
assembly, not evidence that the remaining dependencies need no notices.

The following read-only commands inspect the layout produced by the historical
builder. They require an existing build; they do not rebuild it:

```sh
cat .dart_tool/quds_aot_native/build/CMakeFiles/quds_aot_worker.dir/link.txt
readelf -d .dart_tool/quds_aot_native/runtime/Bin/quds_aot_worker
sha256sum .dart_tool/quds_aot_native/runtime/Bin/quds_aot_worker
sha256sum .dart_tool/quds_aot_native/build/CMakeFiles/quds_aot_worker.dir/link.txt
rg --files --hidden --no-ignore .dart_tool/quds_aot_native/runtime/notices
```

The original raw link command and executable were local generated artifacts;
this receipt preserves their selected inspection results and hashes. The
immutable source and manifest links below remain the durable provenance.

[quds-commit]: https://github.com/CrispStrobe/quds_office_suite/commit/e37ccdb47c047f6a0250585cf5cb20efc17573b4
[manifest]: https://github.com/CrispStrobe/quds_office_suite/blob/e37ccdb47c047f6a0250585cf5cb20efc17573b4/docs/validation/aot-daemon-free-20261117/evidence/native-runtime-manifest.json
[toolchain]: https://github.com/CrispStrobe/quds_office_suite/blob/e37ccdb47c047f6a0250585cf5cb20efc17573b4/docs/validation/aot-daemon-free-20261117/evidence/native-build-toolchain.json
[cmake]: https://github.com/CrispStrobe/quds_office_suite/blob/e37ccdb47c047f6a0250585cf5cb20efc17573b4/packages/quds_proofing_aot/native/CMakeLists.txt
[assembler]: https://github.com/CrispStrobe/quds_office_suite/blob/e37ccdb47c047f6a0250585cf5cb20efc17573b4/packages/quds_proofing_aot/tool/build_native.py
