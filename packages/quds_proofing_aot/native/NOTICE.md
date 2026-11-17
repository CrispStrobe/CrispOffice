# Separately built AOT runtime

Quds' native worker calls the AOT/RML libraries directly. It does not start or
contain an HTTP server. `JVisualSynAnParamBuilder.cpp` is an upstream serializer;
its directory name does not imply that the `SynanDaemon` program is built or run.

The build script obtains these exact sources:

- AOT: https://github.com/sokirko74/aot at
  `0d591d972c7bb2729f4764d3bc32611ea6fd142a`.
- nlp_base: https://github.com/sokirko74/nlp_base at
  `244b3d1f9a09e4a81e75ea83c3b55b209c663503`.

The upstream engine and its data retain their own licenses and copyright
notices. AOT is licensed under the GNU Lesser General Public License 2.1. The
runtime includes AOT's `copying` text. These dependencies are built separately;
generated binaries and dictionaries are not committed to the Quds repository.
The Quds component license policy does not replace the upstream terms.

An explicit build-time change is made to a generated copy of upstream
`Source/synan/SimpleGrammarLib/Parser.cpp`: its unconditional
`text.SaveToFile("input.lem")` diagnostic is removed. The pinned source checkout
is not edited. The build validates the exact statement before removing it and
records the generated source hash. This prevents analysis from writing document
text into the host's working directory. The runtime smoke verifies that no files
are created there.

A second generated-copy patch changes `add_string("descr", m_strDescr)` to
`add_string_copy` in `JVisualSynAnParamBuilder.cpp`. The upstream serializer's
temporary per-clause groups die before the complete JSON is written; copying
their descriptions prevents dangling string references and corrupt labels.
A third generated-copy patch removes the `_DEBUG`-conditional `before.lem` and
`after.lem` dumps from `Source/synan/SynanLib/SyntaxHolder.cpp`, so alternate debug
builds do not write document text either. All exact replacements are checked
against the pinned sources and their generated source hashes are recorded in
the manifest.

If distributing a built worker or runtime, comply with the applicable upstream
licenses, including source and relinking obligations for linked LGPL code.
Keep the pinned upstream source checkout, the Quds worker/build sources, and the
runtime's `manifest.json` with your distribution/source offer. The manifest
records revisions and the worker binary hash; it is not a substitute for the
required source materials or license notices.

The build uses only AOT's non-GUI analysis libraries and dictionary generators.
It needs C++17, CMake 3.24+, flex (including `FlexLexer.h`), bison, and zlib development files. Qt, an HTTP
server, a listening port, and an internet connection are not runtime requirements.
