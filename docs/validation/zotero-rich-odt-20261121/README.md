# Native ODT rich import and Zotero continuation

Status: **bounded native ODT import into an editable Word document is implemented
and locally qualified.** Supported native Zotero fields remain active through
DOCX saves. General LibreOffice-file compatibility, native editable ODT output,
and installed Word/LibreOffice/Zotero-plugin acceptance remain open milestones.

Qualified source: `4386cba498f5b4411dc7598bbc94c706005d04db`.
Source tree: `a16dfd32bcf8670f7329e2380da949d030c7cb58`.
Working remote branch: `codex/zotero-parity-2026-11-21`.
The final documentation/evidence commit retains these qualified production and
test inputs. `source-binding.json` records their hashes at publication.

## Delivered behavior

`OdtDocumentReader.readBytes` validates an immutable copy of the source with the
existing bounded ODF/Zotero inventory, then reconstructs a rich `WmlDocument`.
Field identity comes from exact XML endpoints and story/cell ownership. The
reader records rich UTF-16 positions while decoding; it does not search for
matching citation text. Rich source order also distinguishes a note immediately
before or after a field from a note enclosed by that field.

| Area | Qualified scope |
| --- | --- |
| Rich text | Paragraphs, unnumbered headings, supported default/named/automatic styles, rich spans, explicit spaces/tabs/breaks, Arabic and supplementary Unicode, supported absolute external hyperlinks. |
| Zotero ownership | Canonical ReferenceMark citations and ReferenceMark/TextSection bibliographies, including adjacent equal-looking fields, rich caches, empty bibliography paragraphs, body/table/note stories and nested cells. |
| Notes | Supported authored footnotes/endnotes and visible native markers, document-wide decimal numbering, preserved anchor order, and subsequent inline/footnote/endnote citation placement changes. |
| Tables and lists | Bounded rectangular unmerged/nested tables, inherited alignment/row controls/cell fills, explicit width allocation and fixed-width consistency; supported independent decimal/bullet lists, starts/restarts, nesting, continuation paragraphs and source margins. |
| Metadata | Unknown citation/bibliography and XML/JSON preference members are retained. Import-only `ReferenceMark` to `Field` conversion occurs after reconstruction. Original `meta.xml` is archived verbatim in DOCX custom XML; active native preferences have their own Word property owner. |
| Subsequent operations | Citation editing/locator changes, unlinking while retaining rich results, staged citation/bibliography refresh, formatting/preferences, placement changes, and repeated DOCX reopening. |
| Word loader | Byte-based ODT dispatch through asynchronous isolate/current-isolate decoding and layout. Failed or stale imports do not replace an edited, replaced or disposed controller document. Synchronous ODT callers receive explicit asynchronous-API guidance. |
| Studio | Open accepts `.odt`. Successful native import clears the original save path and proposes a new `.docx` destination, protecting the source ODT and retaining active Word fields on first Save. Tests check actual disk bytes. |

The reader refuses ambiguous/malformed fields, unsupported used formatting or
structures, and exhausted budgets before publishing an editable document.
The inventory's archive/XML/text/field bounds remain intact. Additional bounds
cover styles, tables, cells, notes and lists. Large ordinary prose is coalesced
instead of allocating one run per word; repeated equal field codes retain
independent owners without repeated whole-list removal work.

Ordinary ODT export retains its existing cached-result behavior. This increment
does not silently convert that export into an active native-Zotero round trip.
The [native input contract](../../roadmaps/zotero/native-odt-input.md),
[parity roadmap](../../roadmaps/zotero/word-processor-parity.md), and
[support guide](../../zotero-support.md) describe the complete supported envelope.

## Remote intake and conflict reconciliation

The initial baseline was `2f90a0c8f21499d5a1113943971cb7379183885c`.
`initial-intake.json` establishes that all 25 advertised fork branch heads, the
latest 100 PR heads, and the four upstream branch/PR heads were already in that
baseline. Existing commits were not replayed or cherry-picked unnecessarily.

`frontier-intake.json` captures later main
`fcb2128884768553141f41c02bf804e2267f9dbb`, 27 commits ahead of the initial
baseline, including merged PRs #306, #307 and #309. That main advancement was
merged into the working branch without conflict and preserved all Mail work.

`publication-frontier.json` fixes the next cutoff at **2026-11-21 12:27:32 UTC**:
27 branches, the latest 100 PRs and 210 comparisons covering 105 distinct heads.
Every captured incoming head except the moving VBA branch was already in
qualified `77c4ef27`; the remaining head,
`05c14895c44054ca92a3f3c6671749ea2c7aa69c`, is a second parent of final qualified
source `4386cba4`. PR #308 was still marked draft at that cutoff; this record
states the independent checks executed here, without adopting unfinished
author-reported qualification as our own result.

The VBA branch shared Word deserializer/property/style code with the new ODT
route. Its language/font operations and native persistence received targeted
tests, successful ODT-citation cross-feature cases, and a VM/JavaScript smoke.
Later overlapping table changes were reconciled deliberately:

- Preserve the newer reader's whitespace/note ownership, bounds, inherited
  properties, and allocation of declared table width to unspecified columns.
- Add the missing duplicate used-property-container refusal to the existing
  style validator. Keep accepted inert `style:class` and
  `style:auto-update="false"` metadata.
- Retain all 23 incoming table regressions, including explicit/implicit widths,
  conflicting fixed widths, inheritance, transparent fills, nested unsupported
  content, duplicate containers and used foreign metadata.
- Retain the incoming validation history and update the changelog additively.
  Do not reintroduce a redundant competing structural-style validator.

All production bytes in `4386cba4` match `77c4ef27`. The last reconciliation
changes documentation/evidence and the table test file. Source binding checks
also connect the earlier broad editor gate to final code: three production
files differ only by pinned formatting with identical parsed Dart output; the
one executable difference is the duplicate-property guard qualified by the
final engine and focused loader runs.

## Closing main reconciliation

After the fixed publication cutoff, PR #308 merged to main at
`d572de0bcfb9d1a033fd16f073db439e869057e6`. Its delta from the already
preserved `05c14895` is seven VBA validation documentation/evidence files;
the complete `packages` tree is identical. The final main was merged normally
into evidence checkpoint `7ab5a0c7f21182925254f5d8a2f39acba6f1276c`. All
1,296 qualified inputs remain byte-identical after that reconciliation.
`closing-main-reconciliation.json` records the exact parents, paths and check.
The final PR retains both this completed main history and the independently
qualified ODT source, with no additional test execution claimed for unchanged
inputs.

### Incremental remote checkpoints

| Commit | Preserved work |
| --- | --- |
| `3040a06ed3c5902d4ed731d410d4e23e961bb70b` | Initial intake and native-reader continuation plan. |
| `3b1625e58a50438d10652032ab8dc5cecc098e34` | First bounded reader/style implementation and focused tests. |
| `5f98dc561f6ac214c8c2004380a948230de6185f` | Refined reader, resource/ownership guards, asynchronous loader/controller/Studio integration. |
| `2c6d66ef19df4d62c2bdfe51e1157d376d38727e` | Latest main and all 27 concurrent main commits. |
| `5647e457b9419fa90f302e196ddbeeac8585ccfb` | Captured VBA/native persistence branch for combined qualification. |
| `ec656412511369446804d9fb287d4e11890ad871` | Support/roadmap/changelog contract, broad editor results and cross-feature tests. |
| `77c4ef27008a1a2468b94c3b67423c43ac28438d` | Incoming table history, central duplicate guard and pinned formatting. |
| `4386cba498f5b4411dc7598bbc94c706005d04db` | Publication-frontier ancestry and all 23 incoming table cases, retaining qualified production bytes. |

Remote writes use expected-head leases and preserve parent ancestry. GitHub
Actions were neither queried nor awaited. Local execution is the acceptance
path for this increment.

## Executed local qualification

Runtime: repository-pinned **Flutter 3.47.8 / Dart 3.13.7**, exact locked
dependencies, offline resolution with `--enforce-lockfile`. The official SDK
archive and hosted package archives were checksum verified. All 18 tracked
manifest/lock inputs remained unchanged during setup; `runtime-setup.json`
retains the runtime identities and setup receipt.

| Gate | Scope | Result |
| --- | --- | --- |
| Final engine | 122 files: all Zotero, ODF/ODT, relevant notes/isolate open/save, incoming language-control suites and shared native-persistence regressions. | **2,576 passed**, zero failures/errors/skips. Process exit 0; 1,296 captured inputs unchanged. |
| Broad editor | 60 files, including all 50 `word_zotero_*` suites, native ODT loading and affected Word editing/save regressions. | **1,043 passed**, zero failures/errors/skips. |
| Broad Studio | ODT opening, File menu, Zotero transport and shortcuts, four files. | **40 passed**, zero failures/errors/skips. |
| Final loader replay | Native ODT controller plus Studio ODT/File-menu paths after the duplicate guard. | **8 editor + 7 Studio passed**; these overlap the broad totals and are not added again. |
| Static checks | All 29 changed Dart paths, with final changed-test revalidation and unchanged-path binding. | Strict analyzer clean; pinned formatter clean. |
| Portable VBA | VM, optimized JavaScript compilation and Node execution of the incoming language/font smoke. | Exit 0 throughout; identical JSON and native-part hashes, seven operations/recorded steps and retained opaque DOCM VBA bytes. |

The broad editor/Studio run captures 1,123 inputs and four runtime identities;
the focused replay captures 1,062 inputs and the same runtime identities.
All were unchanged during their respective executions. Exact source heads,
commands, selected files, every case result, raw JSON events, stderr and hashes
are retained in the archives below. The cross-feature cases exercise a rich
native ODT citation, independent normal/complex font/language slots, public VBA
execution and repeated DOCX reopening with metadata/formatting preserved.

Five incoming Dart files required formatter normalization. Raw scanner tokens
differ only in optional trailing commas; complete successful analyzer
`CompilationUnit.toSource()` output is identical before/after for every file.
The formatter proof retains original/final bytes, hashes and parsed output.

An initial engine run completed all 2,574 then-selected cases successfully, but
its report writer failed when saving a deliberate isolated UTF-16 surrogate in
a test name using unescaped UTF-8 JSON. The raw successful event stream and
unchanged-input recovery remain in `engine-receipt-diagnostic`. The writer now
escapes JSON strings and persists the child process exit code before parsing
results. The final engine cohort was rerun after the last incoming tests; only
that final cohort supplies the engine total above. Earlier scoped/development
runs and the focused loader replay are not added to final totals.

## Actual LibreOffice converter boundary

Installed **LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, converted a synthetic Quds DOCX to
native ODT using a separate headless profile. The file contains two rich prose
paragraphs with bold/italic, Arabic and supplementary Unicode; it has no Zotero
fields and is not an installed-plugin fixture.

The untouched ODT has SHA-256
`9fd4e0d23bf9cd2be0248bd5e9cfb496dfe512ec1226c456f324f2171705e1bd`.
Import is **explicitly refused at active `fo:hyphenation-ladder-count`**. Other
native script-specific defaults also exceed the represented style model.
The recorded probe checks unchanged source/input bytes. Original DOCX/ODT,
extracted XML, converter version/command and refusal output are retained.

This is a concrete compatibility gap, not successful general LibreOffice
acceptance. Empty inactive `office:scripts` is accepted; active scripts and
unrepresented formatting remain refused. The original file was not simplified
to manufacture an acceptance result.

## Evidence inventory and practical limits

- `results.json`: compact gate results, qualified heads, counting rules and
  archive hashes.
- `local-validation.zip`: final engine events/commands/full input manifests,
  static checks, formatting equivalence, portable VBA results, converter probe,
  reproducible runners and the report-writer diagnostic.
- `editor-validation.zip`: broad editor/Studio raw evidence and source binding.
- `loader-final-validation.zip`: final overlapping open/save replay evidence.
- `loader-development.zip`: earlier scoped loader checks and actual native
  converter fixture/probe, including the corrected async test-helper attempt.
- `initial-intake.json`, `frontier-intake.json`, `publication-frontier.json`:
  immutable remote audit cutoffs.
- `source-binding.json` and `evidence-sha256.json`: publication input bindings
  and independently verified archive/member hashes.

Archive members were reopened, CRC-checked and hash-verified. Exact execution
commands include their original checkout/runtime paths; reproduction in another
checkout must substitute those paths while retaining the pinned runtime and
locked dependency graph.

Remaining work is explicit: expand real native LibreOffice formatting and
structures from retained fixtures; implement native editable ODT output as its
own contract; execute current installed Zotero/Word and Zotero/LibreOffice
bidirectional acceptance; and specify exact legacy versions before claiming
Apache OpenOffice compatibility. Synthetic tests and a converter-only probe
cannot establish those host/plugin claims.
