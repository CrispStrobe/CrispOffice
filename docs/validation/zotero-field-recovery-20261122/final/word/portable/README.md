# Accepted Word VM and JavaScript routes

Product source: `6ba219a03a9933eded77980f9d7cdbd118183ee1`.
Workflow source: `45a1c0846f3fb78a203f2967e5b80a79fdca2ca9`,
`.github/workflows/office-macros.yml`.

The incoming Word tip changed documentation, validation evidence and the BAS
smoke comparison from bytewise `cmp` to parsed JSON equality. Its production
and test files were unchanged from the already integrated Word checkpoint.
The scripts here copy the exact newly added smoke commands and the exact
conformance loop body, selecting `word_cell_paragraphs_v1` from that loop.

Both routes passed on Dart 3.13.7 VM and JavaScript compiled with `-O1`, executed
using Node v24.22.3:

- **BAS example smoke:** the corrected parsed-JSON equality assertion passed.
  The real eight-step example preserves unrelated layout and parts, retains
  opaque VBA, validates without editing, survives two additional reopen cycles,
  and supports repeat execution and recording/replay. VM and JS report the same
  semantic state. Their raw JSON differs only because five paragraph-spacing
  values use `6.0`/`3.0` on VM and `6`/`3` on JS.
- **Versioned conformance:** all 32 fixture cases executed successfully on both
  runtimes, and their canonical JSON outputs are byte-identical. The exact
  workflow `cmp` command passed.

The original bytewise smoke comparison failure is retained at
`../../../attempts/word-portable-byte-comparison/`, including its raw outputs,
source snapshots and representation-only diagnosis. It is not counted as an
accepted run. The corrected smoke route was then rerun in full, followed by the
conformance route; no test or product implementation was changed to obtain a
pass.

`receipt.json` records exact revisions, command-script hashes, runtime versions,
exit codes, outputs and timings. Raw command output and result JSON are retained
as gzip files. Before/after snapshots show no source changes during either route.
The engine/Word applicability record in the parent final directory covers the
unchanged source/fixture/dependency inputs at integrated target `918e7dd1`.
These local runs do not claim installed Microsoft Office acceptance.
