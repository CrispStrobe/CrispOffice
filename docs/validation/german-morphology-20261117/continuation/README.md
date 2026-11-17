# German morphology continuation — completion

Date: 17 November 2026. Branch: `codex/german-morphology-20261117`.

The recovered morphology implementation, source-bound evidence, latest captured
Office/Zotero work and GECToR qualification tooling are reconciled. The completed
source is [`8432238d`](https://github.com/CrispStrobe/quds_office_suite/commit/8432238d8a694350d6035f1b3314b51ce4254ce4).
This continuation fixes an ODT comment/footnote integration edge, retains the
incoming annotation visibility fix, supplies the missing release notes, and
corrects two historical evidence bookkeeping errors. The German proofing runtime
itself is unchanged from the qualified morphology implementation.

## Delivered proofing behavior

The offline analyzer uses **67,492 noun lemmas, 127,987 readings and 186,607 surface
forms** from pinned Unicode Inflection data. This broadens article, case,
adjective and noun-ending checks beyond the previous 60-noun vocabulary. The
resource loads by lexical bucket in pure Dart on native and web; ambiguous
readings are retained and suggested noun forms must pass the modern spelling
vocabulary. English Harper and English/German hyphenation retain their existing
implementation.

The preserved, audited VM/JavaScript comparison records **68/73 exact targeted
morphology corrections**, up from **1/73**, with **0/175 valid controls flagged**.
The additional review set records **24/24 exact corrections and 0/60 controls
flagged**. Both sets were used diagnostically; these are bounded regression
results, not a population estimate of German grammar accuracy. See the
[original qualification report](../README.md) for the unchanged corpus,
alternative valid corrections, ambiguity safeguards, performance and limits.

## Reconciliation and incremental preservation

The first recovered remote head was `286bdeb7`, including the final evidence
commit that had been left out of the handoff's last visible update. The initial
reference snapshot contained 232 refs. A final fixed refresh observed at
**14:12:12 UTC / 15:12:12 CET** contains **233 references and 157 distinct heads**:
122 fork branches, 103 fork PR heads, four upstream branches and four upstream PR
heads. All are ancestors of the completed source. This is coverage of the
recorded snapshot; independently moving branches after that observation are
outside it.

The integration includes main `3458c897` (ODT comments and the combined Zotero/ODF
landing), office fidelity `685b3413`, office continuation `c21a1549`, GECToR
qualification `9f1ca644`, and annotation visibility `cadb4ae3`. Original branch
and squash-merged PR heads remain in the ancestry. The reference inventory,
coverage proof and independent review are retained in the evidence archive.

| Remote checkpoint | Result |
| --- | --- |
| `96658711` | Current main brought into the recovered morphology branch. |
| `bcf05fd0` | All 232 initially captured refs reconciled. |
| `010d07fc` | Comment/footnote guard, regression and package release notes saved. |
| `c12bd784` | Final 233-ref snapshot integrated while retaining that guard. |
| `8432238d` | Incoming annotation fixture's strict-analysis lint and formatting corrected. |

GitHub's tree/commit API preserved each checkpoint with a lease on the expected
branch head. Remote and local commits differ in metadata; their complete Git
trees match. [source-binding.json](source-binding.json) binds the actual tested
files to the final remote source. No GitHub Actions run was awaited or used as a
gate for this continuation.

## Integration corrections

**ODT comment references preserve body footnotes.** Merging the new comment
writer with bounded note handling exposed an interaction: a reference inside an
annotation could emit the footnote body there, leaving the actual document
reference as a cross-reference to the annotation. A standalone reproducer and
new regression both fail before the fix. The writer now temporarily suppresses
note-body emission while writing comment paragraphs and restores the previous
context in `finally`. Comments before and after the real reference retain their
visible marks; exactly one note body remains at the real document reference.

**Annotation stories stay out of body extraction.** The captured annotation
visibility branch makes streaming extraction, paragraph traversal and fallback
search omit ODF annotations by namespace identity. Comment content remains in
the package and comment model. Its regression set covers ODT/ODS, inline/block
comments, namespace aliases and shadowing, empty/annotation-only documents,
whitespace, CDATA, byte budgets and writer round trips. A string-interpolation
lint in that incoming fixture was corrected before the final strict run; the
failed initial attempt remains in the archive.

The second writer merge contained only relocation of identical comment members
plus an older unguarded comment loop. Resolution preserves the already tested
guarded writer exactly; it does not reintroduce the superseded note API.

## Fresh local validation

Flutter **3.47.8**, Dart **3.13.7** and Node **24.22.1** match the earlier proofing
qualification. The official SDK archive and all 162 pinned Pub archives were
verified; offline workspace resolution preserved the exact historical lockfile.

| Run | Source and result |
| --- | --- |
| Combined-source baseline | `bcf05fd0`: strict engine analysis clean; **503 VM proofing tests**, **156 editor proofing/hyphenation tests**, **105 ODF tests** passed. |
| Comment/footnote correction | Exact source saved at `010d07fc`: strict analysis clean; **66 affected ODT tests** passed. The new regression failed before the fix and passed after it. |
| Final extraction integration | Exact source saved at `8432238d`: strict engine analysis clean; **278 ODF/search/ODS tests across 12 files** passed. |
| GECToR qualification tooling | **18 passed, one skipped, zero failures/errors** among 19 discovered Python tests. The tiny real converter control was skipped because ONNX/ONNX Runtime are not installed; no model inference was run. |

These test sets overlap and must not be summed as distinct tests. The final run
records 1,862 unchanged input hashes: **1,861 tracked files plus the ignored
workspace lockfile**. Every tracked input matches the committed final source;
the lockfile matches its preserved historical copy. No source changed during
any completed test run.

The earlier **503 compiled-Node proofing tests, corpus VM/Node parity, bucket
validation, release web build and packaged license check** remain preserved
historical results on `8649b79e`. They were not rerun on the entire reconciled
application. This continuation verifies identity of 136 proofing/provider/data/
hyphenation/dependency inputs and all seven external `characters` source files.
The later production changes are confined to ODF writing and extraction and are
covered by the focused runs above.

## Evidence recovery and license boundary

The independent [recovery audit](../recovery-audit.json) verifies three historical
archive hashes, all 131 member hashes, nine standalone/archive receipt pairs,
recorded log hashes, source bindings and generated license notices. The old
archives and logs are unchanged. The external final-validation index now lists
its previously omitted internal manifest. The source binding now distinguishes
the ignored root `pubspec.lock` from tracked Git inputs and links its identical
preserved copy.

The implemented morphology resource remains **Unicode-3.0**, with the pinned
upstream license and notices retained in generated data, the package and the
previously verified web notice bundle. No new GPL-family application dependency
or language resource is introduced. The [resource manifest](../../../../packages/quds_office_engine/third_party/proofing/morphology_manifest.json)
retains exact source hashes and the independent spelling guard.

The integrated [GECToR roadmap](../../../roadmaps/german-gector-proofing.md) is
qualification work, not a delivered application provider. Its Apache-2.0 model
baseline still has 9/18 exact expected corrections and one changed clean control
among 12 on the small frozen panel, including a Swiss orthography regression.
Its selected mixed Q4_K native lane is not implemented or qualified here. Native
ORT remains a development control, with its dependency-license boundary still
open under that feature's stricter allowlist. No native runtime is added to the
application by this reconciliation.

Broad clause syntax, unrestricted compounds and noun-subject/verb agreement
remain limitations of the shipped deterministic analyzer. The stronger lexical
resource does not make it a full German dependency parser.

## Reusable evidence

[local-validation.tar.xz](local-validation.tar.xz) contains complete fresh test
logs, before/after source manifests, runners, the negative/positive note probe,
the initial lint failure, reference inventories, source reviews, continuity
checks and toolchain setup receipts. [evidence-index.json](evidence-index.json)
records the archive hash and every member hash, including its internal manifest.
Historical archives remain at their original paths in the parent report.

To repeat the substantive checks on a configured workspace, run strict engine
analysis (`dart analyze --fatal-infos lib test tool`), `dart test test/proofing`,
the 12 ODF/search/ODS files listed in the final receipt, and the 11 editor files
listed in the baseline receipt. The archived runners retain the exact commands,
tool identities and environment paths used here. No remote CI result is needed
to inspect this local evidence.
