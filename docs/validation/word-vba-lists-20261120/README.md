# Word VBA paragraph list formatting — local qualification

## Qualified result

The completed qualification is bound to source commit
`57456c602856a8ec56095352e9c1b9b17476ea69` and tree `ef086f4b2fe1d5a4db86f53e2da7bf210289dba7`.
The working branch is `codex/word-vba-compat-20261120-next`. GitHub Actions,
workflow runs and status checks were neither queried nor awaited.

| Check | Result |
| --- | --- |
| Word/Office regression selection | **2,292 passing cases across 62 original test modules; zero failures, skips or reporter errors** |
| New ListFormat cases, included above | 95 compiler + 61 native + 22 integration = **178** |
| Existing unchanged regression modules | All 59 modules retain their previous per-file counts, totaling 2,114 cases |
| Source binding | Complete set of **1,118** inputs, with exact modes, Git blobs and SHA-256; unchanged during execution |
| Strict analysis | Entire engine, `--fatal-infos`, exit 0, no issues |
| Formatting | All seven changed Dart files, zero changes |
| Actual BAS on VM and compiled JavaScript | All commands exit 0; raw 1,176-byte outputs and canonical results are identical |
| Independent review | Source review and raw-evidence audit accepted; no unresolved concrete finding |

See [qualification.json](qualification.json), [regression.json](regression.json),
[portable.json](portable.json), [analysis.json](analysis.json), and
[format.json](format.json). Counts include each original test case once; focused
reruns, setup smoke tests and interrupted/development attempts are not added.

## Behavior and coverage

The [Word contract](../../VBA_WORD_MACROS.md#paragraph-list-formatting) defines
typed `Paragraph.Range.ListFormat` selectors, aliases, required `ByVal` helpers,
nested `With`, named optional arguments and statement/`Call` forms for
`ApplyBulletDefault`, `ApplyNumberDefault` and `RemoveNumbers`.

Native operations inspect the input document at execution time for matching-kind
toggles. They allocate collision-safe default definitions, preserve imported
numbering, write persistent suppression when clearing, retain indentation on
removal, and preserve unrelated content. Source guards reject ambiguous numbering and requests
that cannot preserve field semantics before mutation or detached publication.

The actual [word_lists.bas](../../../packages/quds_office_engine/example/macros/word_lists.bas)
executes eight native steps as one revision and survives two additional reopens.
The portable driver also checks changing list kinds, late rollback, policy
refusal, selected LISTNUM refusal, four opaque-boundary cases, and eight rejected
source forms. The opaque cases separately assert two paragraph-mode refusals
with original bytes intact and two fully opaque field-preservation results with
every native field token retained. The canonical result SHA-256 is
`3ad9648c52a2495ffa433f629e97302edd94501b7393424036f6f81986e01def`; see [portable-result.json](portable-result.json).

Independent review exposed two concrete field-span problems during development:
all-number removal overlooked boundaries hidden in opaque containers, and an
existing serializer rule could discard a modeled closing boundary whose opening
was opaque. The first is guarded by opaque field scanning. All new list methods
also use the serializer's own unbalanced-boundary predicate before mutation,
across body, header/footer, note and comment stories. The serializer itself is
unchanged. Full marker-sequence checks replace the earlier instruction-only
preservation assertion. See [source-review.json](source-review.json).

## Execution and evidence limits

The gate imports the 62 original test modules as separate Dart libraries into
one generated suite, grouping each under its filename. It preserves the original
module source, private library globals, setup/teardown scopes, nested groups,
per-test timeouts, fixture cwd and actual CLI subprocesses. All 44 `office_vba_*`
modules are selected together with 18 native/style/fidelity/preservation/ODT
modules. No selected file has library-level test metadata or a `dart_test.yaml`.

**The modules share one VM isolate and process-wide caches. This does not claim
the original separate-file isolate boundary.** The raw collector checks complete
start/done pairs, unique identities, every declared filename group, matching
per-file and root totals, final success, zero skips/errors, and unchanged source
and runtime input manifests. The independent reviewer recomputes these checks.

Dart 3.14.1 and 56 hosted dependency versions exactly matching the repository
lockfile were used. Only copied dependency manifests had workspace declarations
removed; package roots point to original checkout source. No tracked manifest
or dependency lock was modified for setup. [environment.json](environment.json)
records SDK and package identities. The reproduction helper is reconstructed
from executed setup steps and syntax-checked, not rerun as an additional gate.

The first two full-gate attempts were interrupted after 162 and 600 partial cases
when later checks found source changes were needed. Both exited 130. The first
final portable attempt failed the field-token assertion described above. These
attempts and earlier development checks remain in the development archive and
are explicitly **excluded** from the qualified totals.

## Remote source reconciliation

The initial intake preserved main `5c48058bedc42dd8cbf3fb9d6f1fb492b2ac1eb8` and
the subsequent Zotero test-label continuation at
`79e11935e16ea1d2fa576ead0712c83f22e15c28`.
The initial capture had 19 fork heads, 257 existing PR heads and four upstream
heads. The final capture at `2026-11-20T15:56:28.761986+00:00` accounts for
**21 fork heads, 258 existing PR heads and
4 upstream heads, with zero uncovered heads**.

Fourteen historical equivalence proofs were recomputed: thirteen full-tree
identities and one exact 37-changed-path ODT continuation equivalence, each with
an accepted ancestor. New Mail account intake at `9c4fbb2b` and implementation at
`63ff7f238c6c2871082cc4dc557552a04aecde68` were merged with their histories.
At integration checkpoint `57456c60`, all 17 incoming implementation paths
matched source `63ff7f23` exactly and overlapped none of the Word qualification
inputs. The later Mail continuation at
`fee58398c80ec811f4adfbbaef7ae08598abdda0` also preserves the Word checkpoint
and all 1,118 qualified inputs. Its 21
changed paths are recorded separately. These checks prove inclusion; the Word
gate does not qualify Mail store/provider/Flutter runtimes.

See [final-capture.json](final-capture.json), [final-intake.json](final-intake.json),
[incoming-mail-review.json](incoming-mail-review.json),
[incoming-mail-continuation-review.json](incoming-mail-continuation-review.json)
and the initial records.
[qualified-inputs.json](qualified-inputs.json) records the complete qualified
path/mode/blob comparison. It is repeated against the final publication and
remote main so later evidence or disjoint reconciliation changes cannot silently
replace tested engine inputs.

## Evidence files

| Archive | Contents |
| --- | --- |
| [regression-evidence.tar.xz](regression-evidence.tar.xz) | Completed reporter stream, case identities, source/runtime before/after manifests, generated harness, collector, analysis/format logs, exact setup/build records and reproduction helper |
| [portable-evidence.tar.xz](portable-evidence.tar.xz) | Used portable runner, retrospective wrapper-invocation receipt, exact child/BAS payload commands, input binding, VM/compiler/JavaScript logs, generated JavaScript, and canonical result |
| [development-evidence.tar.xz](development-evidence.tar.xz) | Explicitly superseded attempts, failing probes, focused development logs and independent review probes |
| [reconciliation-evidence.tar.xz](reconciliation-evidence.tar.xz) | Initial/final remote captures, inclusion/equivalence audits and exact audit scripts |

[archive-members.json](archive-members.json) gives byte counts and SHA-256 for
every archived file; [evidence-files.json](evidence-files.json) hashes the delivered
evidence files. The SDK, package cache and runner binary are omitted; their
versions/hashes and the exact kernel build command are recorded. Archives retain
original workspace-relative paths and commands. The gate helper expects a root
containing `quds_office_suite/` and `runtime/`; the setup helper supports creating
that layout in a fresh environment. Extraction alone does not install runtimes.

## Compatibility boundary

This remains a bounded VBA source adapter. New defaults use Quds geometry
(18-point left, 9-point hanging); clearing retains indentation. Only omitted/
Word8 default behavior is supported. Live collection/property reads, arbitrary
Word ranges, customized galleries/templates, outline application, indent/outdent,
COM and embedded VBA execution remain outside this increment. Existing supported
table-style inheritance layers are reused. Ambiguous or lossy field/numbering
sources may be refused conservatively across the document.
