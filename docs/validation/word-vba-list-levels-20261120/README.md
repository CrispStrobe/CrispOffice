# Word VBA outline numbering and list levels

This record qualifies the Word/Office engine source at
`3c87debcd4d50cac88981ec39255c3c6890fe8fa`, tree
`9bd6e399e689cc12d6ff51090c038c72f4901d05`.
The implementation was saved incrementally on
`codex/word-vba-list-levels-20261120` and published through
[PR #261](https://github.com/CrispStrobe/quds_office_suite/pull/261).
Later changes to this directory record evidence; the complete qualified source
inventory is checked again against the published branch and merged main. All
heads present at initial intake and the completed updates to main are included.
A separate Mail feature created after that intake remains explicitly deferred
on its preserved branch and draft PR #262; this record does not claim that all
heads in the later inventory have been incorporated.

GitHub Actions, workflow runs and status endpoints were neither queried nor
awaited. The qualification below comes from local execution and independent
source/evidence review. Incoming Mail, provider and Flutter changes retain their
separate runtime qualification.

## Implemented behavior

| Word VBA source | Native operation | Supported behavior |
| --- | --- | --- |
| `ListFormat.ApplyOutlineNumberDefault` | `docx.listOutlineDefault` | Toggle a validated numeric outline off, or apply the Quds nine-level decimal scheme at source level 1 |
| `ListFormat.ListLevelNumber = n` | `docx.listLevel`, `level: n - 1` | Select an existing supported level using an exact numeric integer from 1 through 9 |
| `ListFormat.ListIndent` | `docx.listLevel`, `delta: 1` | Increase the current level by one |
| `ListFormat.ListOutdent` | `docx.listLevel`, `delta: -1` | Decrease the current level by one |

These operations use an explicitly selected existing body paragraph. Typed
`ListFormat` aliases, required `ByVal` helpers, nested `With`, `Call`, and the
supported named/omitted optional-argument forms retain their existing behavior.
Methods capture the receiver before arguments. The setter retains the bounded
adapter's existing right-hand-value-before-selector order, each evaluated once;
this is not a claim about a Word COM host's evaluation order.

The executable
[word_list_levels.bas](../../../packages/quds_office_engine/example/macros/word_list_levels.bas)
requires three existing body paragraphs. It emits 13 operations and finishes
at source levels 2, 3 and 9. Every default application first clears paragraph
numbering so the example can run again on its own prior output. The independent
portable driver checks this repeatability, actual source bytes, dry-run behavior,
single-transaction publication, and repeated save/reopen.

The generated scheme uses 18 points of left indentation per source level,
9 points of hanging indentation, and decimal labels such as `%1.`, `%1.%2.` and
`%1.%2.%3.`. Level edits preserve the existing numbering instance and definitions.
They use actual native definitions rather than display labels or assumed IDs.
New definition IDs avoid existing definitions and references in stored Word parts.

## Preservation and explicit boundaries

New geometry retains the paragraph's right indentation and its direct or
inherited ownership. A later style edit can still change inherited right
indentation, while an explicit earlier write remains direct. The narrow native
indentation projection in the style cascade resolves namespace identity rather
than prefix spelling; original paragraph/style XML and extension metadata remain
intact. Foreign `ind` lookalikes remain opaque. Independent probes cover direct,
inherited and rebound native prefixes, ordinary import/export, later style edits,
and repeated save/reopen.

Supported native levels have complete definitions, valid referenced ancestor
counters, supported point/twip indentation and left-aligned labels. Native bullets
and decimal, decimalZero, upper/lower Roman and upper/lower letter formats are
supported. Absolute/relative level edits refuse a missing list, undefined level,
boundary overflow, unresolved restart, partial or ambiguous definitions, linked
or picture numbering, unsupported level properties, and unsafe field boundaries
before publication. They do not clamp levels or invent a missing list.

Positive first-line indentation is written without a competing hanging
attribute. Potentially inherited hanging, logical or character-unit indentation
is conservatively refused where it could override the requested native geometry.
This includes stored style/default/table regions beyond the selected paragraph.
Existing numbering-alternative, namespace and serializer-sensitive field guards
remain in force.

Outline classification requires explicit supported multilevel metadata and at
least two complete numeric levels. Mixed bullet/number schemes and ambiguous
metadata are refused for outline toggling. Explicit level editing instead checks
the actually defined level. Default-list behavior accepts omitted arguments or
`wdWord8ListBehavior`; Word9/Word10 behavior remains unsupported. Live list reads,
arbitrary ranges, list galleries/templates, COM and embedded VBA execution are
outside this bounded source adapter.

Level edits do not rewrite imported numbering definitions. Ordinary serialization
can still normalize XML and introduce its existing fallback definitions, so
arbitrary whole-part byte identity is not promised. Raw imported definition and
instance nodes have preservation checks; complete numbering-byte comparisons use
fixtures normalized by an ordinary save. Opaque DOCM VBA project/signature bytes,
content types and relationships are covered without executing embedded VBA.

See the complete [Word contract](../../VBA_WORD_MACROS.md#outline-numbering-and-list-levels)
and [independent source review](source-review.json) for the supported subset and
resolved findings.

## Executed qualification

| Check | Result |
| --- | --- |
| Word/Office regression | **2,569 passing cases across 70 modules**, zero failures and zero skips |
| New increment coverage included above | **233 cases**: 88 compiler, 101 native, 44 integration |
| Previous unchanged modules | 60 modules retain their previous counts, totaling 2,136 cases |
| Whole-engine strict analysis | `dart analyze --fatal-infos packages/quds_office_engine`: no issues found |
| Formatting | All 9 changed Dart files checked; zero formatting changes |
| Exact BAS on VM and compiled JavaScript | Byte-identical 1,553-byte JSON output and equal canonical results |
| Complete source binding | All **1,123 inputs** match the frozen HEAD before/after every final phase; full path sets, modes, Git objects and SHA-256 identities retained |
| Recorded runtime binding | 11 regression inputs; 20 analysis/format inputs; 20 portable inputs, unchanged within their respective phases |
| Independent supplemental probes | 18 passing probes, separately recorded and excluded from the regression total |
| Independent evidence review | Accepted after recomputing raw case identities/counts, source/runtime bindings and VM/JavaScript outputs |

The 70-module selection includes all 46 `office_vba_*` modules, the complete
previous 62-module gate, the three new modules, and five additional modules
covering numbering snapshots, collisions, style introduction, namespace capture
and ODT paragraph properties. These additions address the actual list and style
cascade changes. New compiler fixtures replace two former unsupported-operation
fixtures in the existing list test module without changing its 95-case count.
The incoming continuation adds six existing-module regression cases.

The original modules run as separate Dart libraries inside **one serial VM
suite**. Module source, private library globals, setup/teardown, nested groups,
timeouts, fixture paths and real CLI subprocesses are retained. Modules share
one isolate and process-wide caches; separate-file isolate boundaries are not
claimed. The collector checks start/done pairing, every declared module count,
unique file/name/occurrence identities, reporter errors/skips, the successful
final event and unchanged source/runtime inputs. The independent evidence audit
also verifies the before/after HEAD and tree identities and the complete path set.

The portable run checks all nine levels, relative changes, toggling, imported
IDs/definitions, repeated save/reopen, example replay, policy/allowlist/step-limit
refusals, no-list/undefined-level/boundary/restart errors, late-failure rollback,
macro recording/replay and twelve rejected source forms. Its canonical SHA-256
is `7a9ec647658d5ee448107d9f358e15a75b16aa6bdd46f9465407043149d8a27c`. The exact BAS SHA-256 is
`c9f4cb3e07d65a103cc75a4bb308be51ac5aaebf1f9cf5b468c09d74301398a6`.

## Incoming history and remote checkpoints

The supplied baseline `acca1cbcba2a322ad1ae2d7d9fb415110ce22554` is retained.
Before implementation, the continuation through
`46e98c8c7ec65e67e8f71dc386804693e8ef1163` was integrated. Its native namespace,
numbering-suppression and style-projection fixes and six regression cases are
included in this engine gate. During implementation, completed PR #260 advanced
main to `bb5320a50f288d95844a6d60cfd72eab13a9befc`; its eight additional evidence
files were merged with both parents retained, without changing engine inputs.

The requested initial intake includes 21 fork heads, 260 PR heads and four
upstream heads. Every one remains incorporated by ancestry or its recorded
historical equivalence proof. Completed main updates through
`bb5320a50f288d95844a6d60cfd72eab13a9befc` are also included.

| Captured source at final inventory | Captured | Incorporated | Explicitly deferred |
| --- | ---: | ---: | ---: |
| Fork branch heads | 23 | 22 | 1 |
| PR heads, including this PR | 262 | 261 | 1 |
| Upstream branch heads | 4 | 4 | 0 |

The two deferred references identify the same newer Mail draft head,
`0730e7f61293b8e2dbe1f25150bc8754a563b101`: `work/mail-cached-workspace-20261120` and PR #262.
That feature started after initial intake and remains outside this Word merge.
Earlier captured heads `2d3799af` and `47d3fc0d` had two independently
demonstrated findings: cached content could consume quota needed by draft saving
without an exposed cleanup action, and cached-body metadata crossed the storage
boundary before type/size preflight. The final captured head `0730e7f6` adds
bounded cleanup and metadata preflight changes with new source tests. Its
committed validation record still contains the earlier runs and withholds final
acceptance of these corrections. This newly corrected Mail feature needs its
own source-bound qualification; the completed Word gate cannot supply that.

The raw [final intake](final-intake.json) deliberately retains both uncovered
reference entries and the inclusion audit exit code 1. The independent
[publication scope review](publication-scope-review.json) proves every initial
head and completed main update is included, binds the exact later draft
references to their review evidence, and requires zero unclassified references.
This is an explicit boundary for the completed Word publication, not an
ancestry/equivalence proof for the deferred Mail implementation. The draft
branch and its original commits remain remote; no incoming changes are discarded
or marked as merged. Mail source/runtime qualification remains separate.

Historical inclusion uses 13 recomputed full-tree identities and one exact
37-path continuation equivalence. Each accepted replacement is an ancestor;
path sets, modes, types and object identities are checked. The initial and final
receipts contain every captured head, inclusion proof and explicit deferral. Intake qualification is about
source/history inclusion, not incoming Mail/platform runtime execution.

Six remote checkpoints precede final qualification: `e60b1d8e`, `72881290`,
`974dffe8`, `fd77d074`, `2a474670`, and `3c87debc`. Checkpoint `273d78f5` then
preserves the accepted raw Word gates while the later Mail findings are reviewed.
That standalone checkpoint remains in Git history. Its `word-gates-checkpoint.*`
files are an explicitly limited intermediate record; the final archives below
supersede that packet. Publication creates Git objects
through the connected GitHub API, verifies each tree against the local index,
and updates the branch with the expected prior SHA and without force. The final
evidence checkpoint is identified by the PR's head and commit history. Before
merge, the complete qualified source selection is compared with that checkpoint;
after merge it is compared with freshly fetched remote main, along with whole
tree equality and required ancestry. The PR records the final merge verification.

## Evidence files

| Record | Contents |
| --- | --- |
| [qualification.json](qualification.json) | Combined final qualification and precise scope |
| [regression.json](regression.json) | Executed case/module totals and unchanged-module comparisons |
| [analysis-format.json](analysis-format.json) | Exact strict-analysis and formatting commands/results |
| [portable.json](portable.json), [portable-result.json](portable-result.json) | Exact-source VM/JavaScript command receipts, output equality and canonical result |
| [source-review.json](source-review.json), [evidence-review.json](evidence-review.json) | Independent source findings, 18 probes and recomputed final evidence |
| [initial-intake.json](initial-intake.json), [pre-gate-intake.json](pre-gate-intake.json), [final-intake.json](final-intake.json) | Captured branch/PR/upstream heads and explicit inclusion proofs |
| [checkpoints.json](checkpoints.json) | Incremental remote object/ref publication receipts |
| [publication-scope-review.json](publication-scope-review.json) | Exact initial-scope inclusion and transparent deferral of the later unfinished Mail draft |
| [source-consistency.json.gz](source-consistency.json.gz) | Complete qualified input comparison for the accepted remote gate checkpoint before final evidence publication |
| [environment.json](environment.json), [runtime-verification.json](runtime-verification.json) | SDK hash, exact dependency pins and observed runtime identities |
| [archive-members.json](archive-members.json), [evidence-files.json](evidence-files.json) | Member/file byte sizes and SHA-256 digests |

`regression-evidence.tar.xz` contains raw final regression events, full input and
case manifests, the generated suite, commands, strict-analysis/format logs,
independent final probes/audit and runtime reproduction records.
`portable-evidence.tar.xz` contains the exact BAS, generated JavaScript, raw VM,
compiler and Node output, commands and complete before/after manifests.
`reconciliation-evidence.tar.xz` contains fetched-head audits, publication
receipts, the captured Mail findings and the intake/publication verification helpers.
`development-evidence.tar.xz` retains superseded or failing development logs,
prepared plans and earlier probes. None contributes to the final passing total.

Development failures include stale expectations about legacy fallback IDs,
the inherited-right and alternate-prefix preservation bugs fixed in this
increment, an unsupported example variable name, a recording helper assumption,
and a Node launcher that exited before asynchronous Dart main. The corrected
launcher supplies `globalThis.self = globalThis`. An accidental nonexistent
test selector is disclosed in its command-correction receipt; that discarded
stdout was not preserved and is not claimed as evidence. The successful portable
development attempt remains unqualified because it began with uncommitted
inputs. Only the final committed-source run is qualification.

## Reproduction

The final run used Dart 3.14.1, Node v24.22.3 and 56 hosted dependency versions
matching the repository lockfile. The SDK archive is pinned by SHA-256
`759bed01e0aeb50e1a0b0a19474ba5c80c6087ce1d37b3214e475c81a44430e8`.
The bootstrap creates isolated manifests and maps package roots back to the
original source; no tracked package manifest or lockfile was changed for setup.
The runtime binaries and package cache are omitted from the archives; hashes,
pins and the reproduction helper are included.

Use a fresh working directory, a Linux x64 host with Python, Git, curl and the
recorded Node version, and network access to the recorded SDK/package sources.
Obtain the evidence archives from this PR, then run:

```sh
git clone https://github.com/CrispStrobe/quds_office_suite.git quds_office_suite
git -C quds_office_suite checkout 3c87debcd4d50cac88981ec39255c3c6890fe8fa
mkdir archived
tar -xJf regression-evidence.tar.xz -C archived
tar -xJf portable-evidence.tar.xz -C archived
python archived/runtime/reproduce_runtime.py \
  --repo quds_office_suite --runtime runtime \
  --record archived/runtime/environment.json
cp archived/runtime/word_office_gate.py runtime/
cp archived/runtime/run_word_list_levels_checks.py runtime/
cp archived/runtime/run_word_list_levels_portable.py runtime/
python runtime/word_office_gate.py run --out runtime/reproduced-regression
python runtime/run_word_list_levels_checks.py run --out runtime/reproduced-checks
python runtime/run_word_list_levels_portable.py --out runtime/reproduced-portable
```

The collectors emit fresh commands/manifests/receipts and fail unless the
declared source and output conditions hold. Absolute runtime paths and generated
environment files are recorded for each run and naturally differ after relocation.
The archived `verify_list_level_publication.py` independently compares a target
Git tree's complete source path set, modes, blob identities and SHA-256 content
with the qualified manifest, checks whole-tree equality with a published
checkpoint, and verifies required ancestry. It reads Git objects only; fetch the
remote ref before using it to make a statement about remote main.
