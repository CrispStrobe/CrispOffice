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

If distributing a built worker or runtime, comply with the applicable upstream
licenses, including source and relinking obligations for linked LGPL code.
Keep the pinned upstream source checkout, the Quds worker/build sources, and the
runtime's `manifest.json` with your distribution/source offer. The manifest
records revisions and the worker binary hash; it is not a substitute for the
required source materials or license notices.

The build uses only AOT's non-GUI analysis libraries and dictionary generators.
It needs C++17, CMake 3.24+, flex (including `FlexLexer.h`), bison, and zlib development files. Qt, an HTTP
server, a listening port, and an internet connection are not runtime requirements.
