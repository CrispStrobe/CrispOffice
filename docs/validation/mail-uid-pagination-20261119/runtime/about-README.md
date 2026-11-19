# Final About workspace resolution

The last incoming Studio change adds About and German-string source files and
makes the already locked `url_launcher` package a direct Studio dependency.
Offline resolution retained the exact dependency lock, the same 132 package
names, and byte-identical `package_config.json`. Only the Studio entry in
`package_graph.json` changed to reflect its direct dependency. No SDK, package
version, native backend, lifecycle fixture, compiler, tool or dictionary input
was replaced.

The [operational runtime receipt](about-runtime.json) has SHA-256
`90198d020e2f412c4248ba9fc0c86b6bfee5d93f5e2f76395a3eb58a37b99f2c`.
It retains all 376 previously bound additional inputs and adds the preserved
prior receipt, new offline-resolution log, workspace comparison metadata and
actual package graph, for 380 additional inputs. The verified SDK and
hosted-package set remains 11,142 records. The earlier `final-runtime.json`,
final preparation archive and original logs are unchanged. The exact prior
operational receipt also remains at `runtime/runtime-before-about.json`.

The [preparation archive](about-preparation.tar.xz) is 25,292 bytes with SHA-256
`01f57656999e2fd14d62ddfe269f2fcc541b595701e0615afb7c20498697a6b5`.
Its [index](about-preparation.index.json) verifies all 11 members against their
retained source files: both runtime receipts, the refresh helper, before/after
workspace metadata and package graphs/configurations, and both command logs.

The strict plan now names all 150 analysis/format paths, including the two new
About/German-string files. Every one of the 64 changed Dart paths since the
historical `162f53c0` source is covered. The existing 23 Studio suites remain in
the 53-suite native tail plan, alongside the 64-suite Mail native replay and
19-suite Node plan. Core/store execution is separate. These are selected suite
counts; acceptance and substantive test totals come from the frozen gate's raw
terminal results.

## Session refresh

The [helper](refresh_about_runtime.py) validates the already prepared runtime
and retains its prior receipt. It does not install or download dependencies.
The session used a fresh preparation directory so earlier logs stayed intact:

```bash
source /workspace/scratch/ab196f483cec/runtime/env.sh
dart pub get --offline --enforce-lockfile \
  > /workspace/scratch/ab196f483cec/hunspell-about-preparation/workspace-pub-get.log 2>&1
python3 docs/validation/mail-uid-pagination-20261119/runtime/refresh_about_runtime.py \
  --repo /workspace/scratch/ab196f483cec/quds_office_suite \
  --runtime /workspace/scratch/ab196f483cec/runtime \
  --preparation /workspace/scratch/ab196f483cec/hunspell-about-preparation
```

The frozen gate uses `run_tail_validation.py --replay-mail` and the operational
receipt above. All Mail cohorts execute afresh; the earlier 953-case audited
subset remains historical evidence. The actual installed Linux Hunspell
backend, all three ownership fixtures, immutable dictionary download, four
Studio screenshots and gallery PDF/PNG rendering remain enabled. Complete
desktop binaries, other operating systems, and browser Worker/Wasm execution
remain outside this local qualification.
