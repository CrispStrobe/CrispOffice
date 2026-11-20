# Zotero parity continuation — 20 November 2026

## Completed local qualification

This continuation completes the saved embedded-image increment and adds native
nested and multiparagraph research lists to Add Note and Add Annotation. It also
reconciles the captured incoming Office work with original ancestry and repairs
the shared document/rendering defects exposed during review.

The qualified product source is
`708f2821f5563912642d8062ea4db126462a67a1`, tree
`447c9f79b2e0cf400ec2c58d7dba18bafab18206`. Later publication changes contain
only documentation and retained evidence. The retained checkpoint branch is
`codex/zotero-parity-continuation-20261120`; the earlier
`codex/zotero-parity-20261120` branch is also retained.

Publication is recorded in [pull request 238](https://github.com/CrispStrobe/quds_office_suite/pull/238). Its merge
record identifies the final remote-main commit. Branch updates use a non-forced
expected-head check, and final main publication preserves both the observed
main and the qualified continuation as parents. GitHub Actions, workflow runs,
checks and commit-status endpoints are neither queried nor awaited.

## Delivered Zotero behavior

- **Embedded pictures and image/ink annotations:** accept bounded static PNG and
  upright, three-component RGB/YCbCr JPEG from Zotero's existing note payload.
  Preserve accepted image bytes, fractional dimensions, alternative text,
  titles, ordinary hyperlinks, reading order and active citation offsets.
- **Structured research lists:** preserve mixed nested ordered and unordered
  lists through nine native Word levels, independent list starts and counters,
  multiparagraph items and parent-item continuations after a nested list.
  Continuation paragraphs retain indentation without producing a new marker.
- **DOCX ownership:** preserve image-only list paragraphs, continuation
  paragraphs and linked pictures as inline document content through repeated
  save/reopen. Bare legacy picture paragraphs retain their established block
  representation.
- **Atomic edits:** complete the native Zotero transaction and revalidate its
  target before applying the note, pictures, active citations and preferences
  as one undoable edit. Malformed, unsupported, stale or over-depth responses
  refuse the whole result before publication.

The supported image envelope remains explicit: at most 32 images, 4 MiB total
image-file bytes after base64 decoding, 8,192 pixels on either edge, 16 Mi pixels
per image and 32 Mi pixels per note. The decoded note payload is capped at 8 MiB. PNG scanline
expansion has a 32 MiB/image budget and decoded raster data has a 64 MiB/note
budget; compressed PNG metadata has a 1 MiB aggregate budget. These bounds are
implemented and tested, not a promise
to render arbitrary raster content. External image URLs, unsupported formats,
EXIF-oriented or grayscale/CMYK JPEG, tables and custom/reversed list markers
remain refused. See [the usage guide](../../zotero-support.md) for details.

## Intake and preservation of incoming work

Captured main was `5e38de19ab5af8d6811d601c7317cba7f69d516b`. The initial intake
fetched all 235 pull-request heads, 19 fork branches and four upstream branches.
A bounded pre-acceptance refresh added the Mail workspace branch and the later
Android and PPTX heads while main stayed unchanged. All 20 captured incoming
fork branches, all 235 PR heads and all four upstream branches are accounted for
by ancestry or exact historical incorporation proofs in [intake.json](intake.json).
The continuation's own branch is tracked separately.

| Incoming work | Captured head | Preserved integration checkpoint |
| --- | --- | --- |
| Main | `5e38de19` | `d6ec077b` |
| VBA Variants/Word, Arabic lifecycle, fonts and backgrounds | `1fe093a2` | `ef09cc41` |
| CrispOffice application identities | `afc3524e` | `6c6413b3` |
| Android spaCy grammar | `fa8b71b0` | `6adf829a` |
| PPTX normal autofit and metrics | `0e1d6d8c` | `a27df5d1` |
| Later Android replay workflow | `7ac3d3be` | `3eb59a8b` |
| Later radial/PDF opacity work | `20573cab` | `a4ed68f2` |
| Mail workspace and shared Office layout | `6fea99ed` | `708f2821` |

The structured-list feature was separately saved at `3074989e`; image-only
ownership at `aa51b570`; normal-autofit model and spacing repairs at `c30e8bfe`.
Every remote checkpoint tree was compared with its local tree before advancing
the branch. The original newly merged source commits in the table remain in the
published graph.
The archive's `intake/checkpoints.json` retains the full local-to-remote commit
map and independently reverified identical trees for all eleven source checkpoints.

Nine older branch heads and fourteen older PR heads were incorporated by prior
merges rather than preserved as direct ancestors. Their complete changed-path
sets were independently compared by Git mode, type and blob identity against
accepted main ancestors. This includes the five old PR-only heads in the intake
receipt. Old patches were not replayed over later source improvements. No
unresolved or omitted captured head remains. New feature-branch advances after
this bounded snapshot are outside this acceptance; remote main is checked again
at the final compare-and-update step.

## Shared repairs made during integration

- Keep normal-autofit font scale and line-spacing reduction when fresh or
  modified slide models are serialized. Parse percentage and integer forms in
  the owning body-properties element, validate finite unit bounds, handle exact
  zero/full reduction, and preserve unchanged source modes and lexical values.
  Unchanged imported source XML already retained its original autofit.
- Combine the incoming PDF text-layout fixes with the existing numeric/bidi
  layout. Blank, wrapped, numeric and mixed paragraphs use the same measurement
  and painting rules for vertical anchoring, and heading fitting avoids double
  shrinking. Original incoming regression tests remain intact.
- Bind PDF alpha graphics states to page resources and scope picture opacity
  to each image. Source alpha and authored opacity are applied once; subsequent
  images, borders and the caller's graphics state are preserved. Keep the more
  complete existing radial-gradient implementation.
- Retain the incoming Mail workspace feature, including conjunctive loaded-item
  filters, stable keyboard navigation, explicit activation, compact-layout state
  and bounded paging. The final selection includes fresh Mail widget and host
  tests; incoming Office evidence is not treated as Mail qualification.

The incoming CrispOffice rename changes native application identity and Mail
application-support/keychain locations. Its migration documentation now covers
an empty destination, SQLite sidecars and credential re-entry. A native data
migration or release application build was not performed in this environment.
See [the macOS release/migration guide](../../release/macos-signing.md).

## Final local results

All accepted runs below use the same published product source. Test counts
exclude hidden loader events; the 114 root-cohort files and 37 VBA files are
disjoint. Every accepted suite runner exited successfully, produced a successful
completion event and preserved its recorded source/configuration inputs.

| Selection | Files | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Zotero engine and shared Word persistence/numbering | 35 | 733 | 0 | 0 |
| Zotero editor, undo/redo, note numbering and fonts | 48 | 685 | 0 | 0 |
| Studio Zotero transport/shortcuts, Mail and native paths | 7 | 110 | 0 | 0 |
| Mail workspace widget behavior | 1 | 19 | 0 | 0 |
| Arabic lifecycle and unit behavior | 2 | 25 | 0 | 0 |
| Incoming spaCy distribution and grammar planning | 2 | 36 | 0 | 0 |
| Engine presentation and PDF regressions | 10 | 215 | 0 | 0 |
| Editor presentation rendering regressions | 9 | 74 | 0 | 0 |
| VBA Variant/Word, shared macros, operations, CLI/MCP and atomicity | 37 | 1540 | 0 | 0 |
| **Total** | **151** | **3,437** | **0** | **0** |

Additional acceptance:

- Freshly compiled image-note JavaScript and Dart VM replay: **10/10 behaviors
  on each runtime**, with identical JSON receipts and unchanged inputs.
- Real Arabic worker protocol under Node structured-clone transfers: **three
  controls pass**, using a controlled Wasm API. This is not a real model or
  browser/native-host acceptance run.
- VBA portable gate: **seven fresh JavaScript smokes** and **271 canonical cases
  on each of Dart VM and JavaScript**, with exact VM/JS receipt equivalence.
  Existing Excel-corpus receipt identities remain unchanged.
- Strict standalone Dart analysis of all **106 active changed Dart files**:
  no issues, exit 0. Read-only formatting: 106 files, zero changes, exit 0.
  The one archived negative validation fixture is intentionally excluded.
- Independent final intake and shared-rendering reviews found no unresolved
  blocker. Root cohorts guard 5,768 tracked/runtime inputs; static analysis
  guards 2,194 source/configuration files. Portable and VBA receipts record their
  own exact input manifests.

Product/configuration/documentation changes outside archived validation pass
the whitespace check. The broad historical diff also contains 74 required
blank-context prefix spaces in an inherited raw `mail-resolution.diff` evidence
file; that saved patch is unchanged from the earlier image branch.

### Interrupted and superseded evidence

The first combined VBA run was stopped with exit 130 after shared executor disk
exhaustion. It had 442 partial passes and 13 temporary-file/teardown failures;
its input hashes remained unchanged. It is retained as `accepted: false` and is
not counted above. Its generated kernel cache was removed only after the runner
stopped. The replacement uses eight serial cohorts of at most five files,
releasing caches between cohorts, and reruns the entire 37-file selection and
portable gate.

Earlier development runs exposed and then fixed image-only list ownership and
a temporary mid-edit PDF compilation error. A broad earlier autofit run was
explicitly superseded because shared source changed during execution. Those
development results do not contribute to the final totals; the final coherent
source passed the affected tests anew.

## Runtime, receipts and reproduction

The official pinned Flutter **3.47.8** archive (1,581,444,364 bytes) was verified
against SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
It provides Dart **3.13.7**; portable checks use Node **24.22.3**. Only the Linux
Dart/Flutter test-runtime subset was installed. Mobile, browser and native
release-build components are outside this runtime.

All 128 project hosted-package archives and all 101 SDK tool-package archives
were hash-verified. Resolution was offline with lock enforcement. The workspace
lock remained unchanged at SHA-256
`df9ff88b4df699b2420954d0ddc0dd7a1c40dbca8d9e3af3f25bec7e66700e7e`.

- [qualification.json](qualification.json) is the machine-readable accepted
  summary, selections, source identity and scope limits.
- [local-validation.tar.gz](local-validation.tar.gz) retains raw runner events,
  commands, process exits, case results, before/after hashes, runtime receipts,
  portable outputs, static checks, intake review and the interrupted VBA run.
- [local-validation-index.json](local-validation-index.json) lists the archive
  SHA-256 and every member's size and SHA-256. Generated caches and binaries are
  omitted; portable artifact hashes and fresh compiler commands are retained.

The archive includes the runner scripts and `runtime/env.sh` exactly as used.
Adjust their recorded local paths for a new checkout, retain the pinned SDK and
resolve the workspace offline with `--enforce-lockfile`. Then run
`dart run test:test --help` from `packages/quds_office_engine`, where `test` is a
declared development dependency, to warm the generated test executable cache.
Verify the matching workspace-root
`.dart_tool/pub/bin/test/test.dart-3.13.7.snapshot` path before invoking the
snapshot-based drivers. The snapshot is generated tooling, not a checked-in
source dependency.

Root Dart suites
invoke the genuine cached `test` snapshot with the resolved workspace package
configuration; Flutter suites use `flutter test --no-pub --reporter json
--concurrency 2`. The VBA replacement is serial and records every explicit
selection. Reproduction requires the same repository revision, pinned SDK,
locked dependencies and valid local paths corresponding to those recorded in
the command arrays. It does not require a GitHub Actions run.

## Remaining parity work and acceptance boundaries

This is a qualified increment toward Word/LibreOffice parity. It does not claim
complete parity or new live acceptance in Zotero, Microsoft Word, LibreOffice,
Apache OpenOffice, native Mail, native spaCy, or a release application build.
Historical native results remain attributed to their original platform, source
and exact scope.

The ordered next steps remain [in the parity roadmap](../../roadmaps/zotero/word-processor-parity.md):

1. Add native table mapping to research notes with citation ownership and atomic
   refusal for unsupported structures.
2. Broaden Add Note/Add Annotation insertion into authored notes and deliberate
   selections, with explicit story and nested-note rules.
3. Extend image orientation/color fidelity consistently across editor, DOCX and
   PDF before widening the raster envelope.
4. Implement and qualify active ODT fields and Zotero's document-transfer
   export/import handshake with real Word/LibreOffice fixtures.
5. Run current release-host acceptance with native Zotero and installed word
   processors, including cancellation, refresh, bibliography edits, note-style
   conversion, image/ink annotations, save/reopen and return-to-writing focus.

LibreOffice is the current maintained Zotero comparison target. Apache
OpenOffice compatibility requires its own identified application/plugin
versions and acceptance; LibreOffice results do not establish it.
