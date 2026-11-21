# Zotero active footnote separators — work record

This increment implements the native active-separator milestone in the
[Zotero parity roadmap](../../roadmaps/zotero/word-processor-parity.md).
The implementation, identified converter results and completed local
qualification are recorded below. Delivery is tracked in
[PR #348](https://github.com/CrispStrobe/quds_office_suite/pull/348); its merge
commit identifies publication to remote main.

## Final qualification and publication

The accepted sequential gates ran against commit
`a1b555979b25c5586f27915cf219a95e886febd7`, tree
`5bc178760195f03e809211913822fa6fac00ca04`. The
[qualification receipt](checks/qualification.json) and
[independent audit](checks/independent-audit.json) bind every accepted run to
the same unchanged source inputs. Later publication changes add documentation
and evidence only; the captured inputs were rechecked before publication.

The strengthened local runner snapshots **6,319 workspace inputs** (approximately
216 MiB), including tracked code, tests, fixtures, assets, examples, local
dependencies and configuration under
`.github/`, `apps/`, `packages/`, `third_party/`, `tool/` and `tools/`, all tracked
root files, the runner itself, and generated package configurations beside
tracked package manifests. Before/after snapshots retain initial paths so
deletion or untracking cannot hide a content change. All 6,318 tracked inputs
match the source commit; the sole expected generated input is the workspace
package configuration. The shared input-manifest SHA-256 is:

```text
5c4d7dd437d3e09f5a2aef6c4b61076945343d67253f12662cf91bfb334e2cb8
```

| Accepted gate | Scope | Passing cases / result |
| --- | --- | --- |
| [Engine](checks/engine-final/receipt.json) | 122 Zotero, ODT, note, persistence and directly related regression suites | 2,677 |
| [Editor](checks/independent-audit.json) | All 55 selected suites, in five disjoint batches of 11 | 1,022 |
| [Studio](checks/studio-final/receipt.json) | Three Zotero integration suites | 38 |
| [Legacy continued-notes golden](checks/legacy-golden/receipt.json) | Three pages, initially and after each of three DOCX exports | 1 |
| [Strict analysis](checks/analysis-final/receipt.json) | All 22 changed Dart files, fatal infos enabled | No issues |
| [Formatting](checks/format-final/receipt.json) | All 22 changed Dart files | Zero changes |

There are **3,738 unique passing test cases, zero failures, zero errors and zero
skips**. The total excludes 18 successful fixture hooks, 181 successful loader
completions and all earlier or repeated runs. The independent audit reconstructs
case identities from raw events and verifies complete lifecycles, declared
suite/group counts, exact editor selection coverage, archive hashes and source
identity. Every accepted process has empty stderr. The legacy golden performs
12 page-image comparisons; its baseline images were not changed.

The final engine gate also replays the six retained, untouched LibreOffice-saved
ODTs from the three active-citation presets through the current native
reader, controlled refresh and save/reopen implementation. The latest remote
main was freshly fetched as `cc797dc2e1921be0ee72f90799607af4d787d20b`, already
an ancestor of the qualified source; see
[prepublication main verification](intake/prepublication-main.json) and the
[final source intake replay](intake/final-source-replay.json).

The `checks/` directory retains exact commands, receipts, source manifests,
case identities and compressed raw output. The work branch is retained, and
publication uses an ordinary merge with an expected head, followed by remote
read-back and source-manifest comparison.

## Reconciled intake and remote checkpoints

Initial remote main was `52e72ca0b5677549f31742faae457f08df05759b`. The captured
intake includes nine fork branches, all 346 PR heads and four canonical upstream
branches: **359 observations**, resolved after reconciliation to **345 ancestors
and 14 verified historical replacements**, with zero uncovered observations.
The historical replacements were verified against full trees or exact changed
paths; they are recorded separately from ordinary ancestry.

Raw advertised refs, the bounded inventory and replay result are in `intake/`.
Reproduce the coverage check with:

```sh
python3 docs/validation/word-vba-numeric-20261121/intake/replay_intake.py \
  --repo . \
  --inventory docs/validation/zotero-footnote-separators-20261121/intake/remote-inventory.json \
  --proofs docs/validation/word-vba-numeric-20261121/intake/historical-proofs.json \
  --head HEAD --output /path/to/replay.json
```

The durable branch is `codex/zotero-footnote-separators-20261121`; its review is
[PR #348](https://github.com/CrispStrobe/quds_office_suite/pull/348).
Incremental remote checkpoints preserve the work:

| Commit | Recorded change |
| --- | --- |
| `efabe221abc781c05073b209051e3a1e380b5c05` | Reconcile captured Office branch heads, including Mail planning ancestry. |
| `c70b8b59254d01b27cc7cd1c4ac1ddd3aad96bbc` | Retain intake evidence and the qualification plan. |
| `93089e1bc9585c6d4f2343e3f4b45c3436f29995` | Implement native separator geometry, layout/rendering and bounded file persistence. |
| `fcedf0b4f125485bee9c0c05765ccc11b2ae0399` | Retain LibreOffice fixtures and strengthen geometry precision checks. |
| `20bb0b45bd6d927f02495e9bb6b3f30ba9a8b149` | Preserve converter evidence and harden dormant and ambiguous settings. |
| `434bad5aa95ef18f9afefadccd6fbfe2d1c8bd56` | Merge incoming main documentation commit `cc797dc2e1921be0ee72f90799607af4d787d20b` and retain the separator details. |
| `7a07ca59a0c308b51dfdf825abb9fb8763de4f86` | Correct the stale test assertion, strengthen gate evidence and update the roadmap. |
| `a1b555979b25c5586f27915cf219a95e886febd7` | Close the source-manifest membership edge case before final sequential gates. |

Authenticated GitHub connector updates use expected heads and non-forced ref
updates, followed by local fetch/read-back. Ordinary merge parents retain
incoming ancestry. No remote branch was deleted or rewritten. The later main
documentation reconciliation is distinct from the captured initial inventory.

## Implemented behavior and bounds

- **One document-wide native model** records independent before/after gaps,
  nominal line thickness, relative body width, physical left/center/right
  alignment, RGB color and solid/hidden line style. Lengths must be finite and
  nonnegative; relative width is bounded to zero through one.
- **Layout and rendering** reserve `before + thickness + after` once on each
  page containing footnotes, including continuation pages. Hidden and zero-width
  rules retain their nominal thickness in that reservation. Editor and PDF
  paint the modeled filled rectangle; documents without an explicit model
  retain the existing rendering behavior. Note picture fitting accounts for the
  same reservation, and preference changes invalidate cached note-page layout.
- **Native ODT** reads and emits the supported explicit geometry. Only
  qualified stock LibreOffice metadata enables its convention of omitting
  zero-valued width/before/after attributes; generic producers must supply
  nonnormative dimensions explicitly. Used unsupported or incompatible page
  definitions refuse import. Fully supported uniform dormant preferences
  survive removal of the last footnote and later reinsertion. Unsupported or
  incompatible dormant presets retain the previous validation-only behavior.
- **Bounded native DOCX persistence** uses canonical separator and continuation
  special notes with matching settings references, physical paragraph indents,
  exact spacing and a bottom border. Spacing/indents use twentieths of a point;
  border widths use eighths. The mapper checks emitted page geometry, ID
  collisions, uniform representable body width and numeric limits. Unsupported
  imported special-note content remains opaque. Duplicate expanded attributes
  and namespace declarations are refused by canonical recognition, preserving
  ambiguous source content instead of silently rewriting it.
- **Zotero ownership and review** retain the separator when staging citations
  and reject a stale transaction if its source preference changed. Body and
  footnote citations retain their owners through controlled refresh and native
  file cycles. This increment does not add a live plugin acceptance result.

## Identified converter evidence

The [independent converter report](converter/README.md) describes the exact
commands, fixtures, measurements and visual inspection. Its retained
[archive](converter/converter-probes.tar.gz) contains 397 files: original inputs,
unpatched converter outputs, PDF/PNG renders, XML snapshots, command logs,
validation reports, scripts and `SHA256SUMS`. Archive SHA-256:

```text
ffb7df4ac3d9ba24f6c6f52dbce62eee5024e64d851ec87aa7e41b3423f615f3
```

Converter: **LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. Each conversion used a separate
explicit profile. PDF measurements used PyMuPDF 1.26.6.

| Route | Observed result |
| --- | --- |
| 14 direct ODT geometry cases, each saved twice by LibreOffice | Solid/none, tested integer-percent widths, physical alignments, colors, zero dimensions/gaps and reservation survived. First/second saved attributes and original/final PDF drawings were identical; tested length normalization was at most 0.016 pt. |
| Three active Zotero fixtures: custom, zero-gap and hidden | Each passed two external ODT saves, with controlled refresh and two native DOCX/ODT save/reopen loops after each external save. Both editable citations, footnote ownership, locator and unknown item/citation/document metadata survived. Final native geometry matched each preset. |
| Seven DOCX separator-paragraph probes | **Failed external geometry preservation.** LibreOffice replaced custom border geometry with its own default black rule and normalized saved ODT attributes. Native DOCX persistence is qualified separately. |

The ODT pagination probes exposed the hidden-thickness rule: a 24 pt hidden
separator reduces first-page capacity by the same two 12 pt lines as a visible
one. A separate 24 pt before-gap change also removed two body lines from the
first page. Both results remained stable after two saves.

For the three Zotero fixtures, original/final PDFs stayed one page with
identical separator drawings; only the intended citation-cache strings changed.
Arabic and emoji were visible in the inspected pages. The protocol refresh was
controlled through Quds' citing session. No installed Zotero client or Microsoft
Word was invoked. Release-host LibreOffice, installed Word rendering and live
Word/LibreOffice Zotero plugin workflows remain separate acceptance work.

## Local runtime and resolved development findings

The pinned runtime is **Flutter 3.47.8 / Dart 3.13.7**, Flutter revision
`737ba8f885dc774b53b442759999a312c9461e4e`. Runtime bootstrap, archive verification
and dependency receipts are retained under `runtime/`. The official SDK archive
and 204 hosted dependency archives were verified by SHA-256. Offline dependency
resolution enforced the existing workspace lockfile without changing its hash.
GitHub Actions/check/status queues are not part of the acceptance path and were
not awaited.

The preliminary full-engine reporter reached **2,659 successes and one error**.
Investigation reproduced identical serialized XML and reopened run sequences on
the exact starting source `52e72ca0`, with the regression test unchanged.
Incoming commit `e65ce54c` deliberately preserves explicit empty text packets;
the linked-picture regression still incorrectly expected one `WmlRun`. The
test-only correction selects the
single picture-bearing run, explicitly validates the extra empty, non-atomic,
unlinked run, and retains picture/link/content assertions. Two targeted runs
passed **105 distinct tests**. The earlier failed full run is retained as diagnostic
evidence and is not a passing final engine gate.

The initial editor invocation was interrupted after approximately 4.5 minutes
without new output while two suites were loading and receives **no acceptance
credit**. The same 55-suite selection subsequently completed in five smaller
batches. Final engine, editor, Studio, golden, analysis and formatting results
are listed above. The test-lifecycle audit excludes hooks and hidden loaders
from case totals; preliminary reporter totals do not substitute for the final
unchanged-source and lifecycle receipts.

The [development archive](checks/development-checks.tar.gz) retains 70 files,
including the failed initial engine gate, interrupted editor gate, superseded
narrow-manifest checks, baseline comparison, focused native logs and the
resolved legacy golden mismatch. Its SHA-256 is
`a9a099c2c4fbe7cb883ebc9443b69f50e63217317819cba378b980568929cae3`.
These runs are diagnostic evidence and are not summed into final acceptance.

## Primary format references

- [OASIS OpenDocument 1.4 schema](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part3-schema/OpenDocument-v1.4-os-part3-schema.html): `style:footnote-sep`, physical alignment and geometry attributes.
- [OOXML separator mark](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.separatormark?view=openxml-3.0.1) and [special-footnote references](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.footnotespecialreference?view=openxml-3.0.1).
- [Tested LibreOffice separator importer](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/xmloff/source/style/XMLFootnoteSeparatorImport.cxx) and [exporter](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/xmloff/source/style/XMLFootnoteSeparatorExport.cxx): omitted-zero conventions.
- [Tested LibreOffice footnote layout](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/core/layout/ftnfrm.cxx): reservation includes nominal thickness even when the rule is hidden.
