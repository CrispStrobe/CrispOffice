# Zotero research materials: continuation and publication

This continuation finishes [PR #223](https://github.com/CrispStrobe/quds_office_suite/pull/223), which was still open when the attached handoff ended. It restores and independently checks the saved qualification, reconciles the ready incoming work, and validates the combined source locally.

**Freshly tested source:** `f3f98987824e021ed22a4d909e38d6307495267b`.
**Dart lint correction:** `3cba1810b41a2fff5b2cd1eb355137a46b09f225`.
**Final main follow-up source:** `6b917be36d5d54aa8a55ef3c8b9ce649aa8bab82`.
The lint correction only adds braces to an existing `if` statement in the standalone grammar evaluation tool. At that step, application libraries, selected tests, fixtures, manifests and locks remain byte-identical to the fresh test source; [the publication audit](publication-audit.json) records that boundary. A subsequent main update changes the macOS build script and two documentation paths, including Dart documentation comments. Its separate [final follow-up audit](publication-followup/final-audit.json), one repeated pin test, ten controlled shell checks and fresh static analysis qualify that later delta without rewriting the earlier results.

## Delivered Zotero workflow

**Library → Reference details → Notes and attachments…** browses a connected reference's direct child notes and attachment metadata. Users can read and copy inert plain-text note previews, inspect and copy attachment details, and page, retry or reload without losing selected references or unfinished search/tag input. Connection and library-version guards discard stale responses. Document contents and undo history are preserved, including in read-only documents.

The previously implemented scope is unchanged during this continuation. The [usage guide](../../../zotero-support.md#read-research-notes-and-inspect-attachments) explains the exact connection/version requirements and limits. Attachment file downloading, launching and Zotero writes are outside this increment.

## Original evidence recovered and verified

The retained branch at `e79c32e77f1990e303527e477e4909df993c1b9b` already contained the complete original evidence. Its old PR description was out of date; no product work or raw qualification results needed reconstruction.

An independent replay of the eleven saved event streams verifies **2,886 distinct passing cases in 135 files**, no failures/skips/errors/layout diagnostics, complete requested suite coverage, all recorded artifact hashes, and source bindings. It rehashes 3,833 unique source blobs and checks all 55 original static-target hashes. The original source attribution remains 2,884 cases at `f0122cb5`, followed by two Word macro guard cases at `d1b8f9be`. This is an evidence re-audit, not a new execution of those 2,886 tests. See [restored-branch.json](evidence-audit/restored-branch.json) and the [audit explanation](evidence-audit/README.md).

The new main integration changes the proofing/spaCy/Studio dependency graph, so the report does not claim every old aggregate input remains unchanged. The exact delta is [listed and reviewed](evidence-audit/publication-delta.json). Zotero, Mail, rendering and VBA implementations and their previously selected tests are retained; the engine facts change is additive. The new affected behavior is covered by the fresh gates below.

## Fresh local qualification

| Cohort | Distinct passing cases | Files |
| --- | ---: | ---: |
| [Zotero engine](accepted-engine-zotero/receipt.json) | 642 | 29 |
| [Zotero editor](accepted-editor-zotero/receipt.json) | 632 | 43 |
| [Engine proofing](accepted-engine-proofing/receipt.json) | 1,705 (1,713 executions) | 37 |
| [spaCy package](accepted-spacy/receipt.json) | 114 | 11 |
| [Studio integration](accepted-studio-integration/receipt.json) | 108 | 9 |
| **Distinct total** | **3,201** | **129** |

The five fresh selections contain **3,201 distinct passing cases across 129 files**. They contain no failing application cases, skipped cases, errors, incomplete test events or layout/tap diagnostics in the final evidence. Every cohort has exact requested suite coverage and unchanged before/after source, dependency, package-resolution and recorded runtime inputs. The fresh counts are **not added to the original 2,886**: the full Zotero selections deliberately repeat 1,274 earlier cases.

The proofing suite makes 1,713 successful executions but contains eight pre-existing duplicate fixture pairs in two table-driven files. Its unchanged primary runner correctly rejects the name-uniqueness acceptance guard. That original receipt remains unchanged. The [independent accounting audit](proofing-accounting.json) verifies each pair against the exact original `(source, expected)` tuples and counts the eight repeats once: **1,705 distinct passing proofing cases**. No fixture names, application assertions or primary runner guards were changed to make that count pass. This explicit accounting exception is separate from application test outcomes.

The first spaCy invocation has 113 passes and one explicit opt-in skip because the qualified macOS library file was not yet present. That attempt is retained separately. The final run supplies the exact pinned, hash-verified library as a data fixture and exercises all 114 cases, including its recorded code digest. The file is read as bytes on Linux; it is not loaded or executed as a native library. Its before/after identity is captured separately from the SDK inventory.

The Studio selection covers Zotero shortcuts and citing transport, spaCy setup and pinning, downloads, linguistic analysis, settings, language detection and the repaired comment-draft language flow. It exercises the actual merged Studio wiring. Engine proofing and the complete spaCy package cover the new additive facts, grammar rules and signature-independent identity behavior.

**Strict analysis and formatting pass all 83 changed Dart targets**, measured from the original milestone base `a452efda`. The first continuation analysis found one existing incoming `curly_braces_in_flow_control_structures` diagnostic in `tool/evaluate_grammar_v2.dart`. That failed analysis and its successful formatting result are preserved under [diagnostics](diagnostics/static-before-lint-fix/receipt.json). After all test runs finished, the two braces were added and the full static selection rerun. This tool is outside the selected tests' execution paths; the publication audit records the exact source exception instead of claiming byte identity for that file.

The exact official Flutter **3.47.8** / Dart **3.13.7** archive was restored and hash-checked. All 194 hosted package archives match the existing lockfile hashes, enforced offline resolution succeeds, and all 33 captured manifest/lock paths remain unchanged. [Runtime setup](runtime/runtime-ready.json) records the archive, executable identities and resolution checks. Its 31-case smoke test is setup evidence only and is not counted again.

## Incoming-work reconciliation

Three additional merge checkpoints preserve the original incoming ancestry:

| Remote checkpoint | Preserved incoming work |
| --- | --- |
| `36fb7fd9c1422d1c8d60c8194e25f8ef4ed07170` | Main `6b2f392c`: macOS signing and native spaCy grammar v2 from merged PRs #224/#225 |
| `c50a787c70219d3a3e6c9458ca09d6c4639f4122` | `bf606aa0`: portable macOS paths and same-tool stripped-library comparison |
| `f3f98987824e021ed22a4d909e38d6307495267b` | `a56397df`: assert and dismiss the language-download modal in the comment-draft regression |

During publication, main advanced to `b0b79d90b0f4ca0036483d73095b4821efddcc8e` by merging that same already-tested comment fix as PR #226. Checkpoint `b1c8c8e534c41914b934defd6023839b851b28a2` preserves the new merge history. Its complete tree is `f7d9d4a3f77483e3bfdcdc11e30227ac725bd21c`, exactly equal to the lint-corrected `3cba1810` tree; this synchronization changes no qualified source or evidence bytes. PR #226 is recorded as a publication supplement to the bounded intake below.

The [bounded intake](intake.json) and [fresh ref audit](ref-audit.json) account for **16 fork branch heads and 225 historical/refreshed PR heads**. The 20 most recently updated PRs were refreshed in this continuation; older immutable head observations retain their original attribution. All 14 historical equivalence proofs were recomputed over 480 complete changed-path mode/type/blob identities. The [upstream refresh](upstream-refresh.json) confirms the same four upstream branches and four PR heads, all already included, and no open upstream PRs.

Three newer captured branch heads remain separate because they are unfinished or not yet qualified:

| Head | Recorded readiness and disposition |
| --- | --- |
| Mail `e1291020` | Its commit explicitly says a save/reopen background regression remains and this is not an acceptance checkpoint; PR #221 is draft. Earlier qualified attachment work is included. |
| VBA `03477679` | The new Variant-conversion validation README explicitly says work and independent reconciliation are ongoing; its development runs are not the final combined-source gate. Earlier qualified VBA work is included. |
| PPTX `e7ba3544` | New picture-background, shape-preset and theme changes expand the source beyond the accepted rendering head and overlap the documented background regression. Earlier qualified rendering work is included. |

This is an explicit cutoff and readiness record, not a claim that those branches were deleted, abandoned or merged. Their original remote work remains available.

The [incoming review](incoming-review.json) checks 50 path observations across 46 unique paths at the tested source `f3f98987`, applying the later selected source where commits overlap. Two combined files preserve the exact reviewed changes from both sides. Local `bash -n`, YAML parsing and all 14 workflow shell-fragment syntax checks pass. These checks do not execute a GitHub workflow or a macOS build.

### Publication follow-up: PR #228

Main subsequently advanced to `3e5f44ae14926b8054b2e5c0558ce71477891a33` with the published macOS portability branch. Its new commit `aeb1f09dfb4b61ca30f8b6f086f0c60cf0607cf9` preserves the pinned spaCy bytes during ad hoc builds, verifies their existing signature, and retains the hard code-digest gate for release signing. The unsigned-file cross-check applies where the local signing tool reproduces its reference normalization. Source checkpoint `6b917be36d5d54aa8a55ef3c8b9ce649aa8bab82` preserves that main history and the earlier complete evidence checkpoint `f4b7f7af`.

The exact three-path delta consists of the build script, release documentation and documentation comments in `distribution.dart`; every executable Dart token and every selected test remain unchanged. All script pins are unchanged. The [macOS build review](publication-followup/macos-build-review.json) passes exact-script Bash syntax and ten controlled cases for the changed signing and qualification branches, including signature failure, mismatched code, mismatched normalized bytes, rebuilds and explicit spaCy omission. Apple signing commands are stubbed in those checks; no native signing or macOS build is claimed.

The one selected test that reads the build script, `studio_spacy_pin_test.dart`, passes again on the final source with all original runner guards. It is already included in the 3,201-case total and is not counted twice. [Final static checks](publication-followup/static/receipt.json) again pass all 83 changed Dart targets. The [follow-up audit](publication-followup/final-audit.json) binds this new source and its inputs separately; the earlier 3,209-execution evidence and accounting exception remain immutable. PR #228 is a further publication supplement to the bounded intake.

## Reproduction and publication

Use the recorded source commit, official pinned runtime and unchanged locked dependencies. Set `FLUTTER_ROOT` and `PUB_CACHE`; use new output directories. The original runner is unchanged and the adapter records its pinned identity and its additive cohort selections.

```bash
python3 docs/validation/zotero-research-materials-20261120/run_validation.py editor-zotero --repo . --output /path/to/fresh/editor-zotero --expected-head f3f98987824e021ed22a4d909e38d6307495267b
python3 docs/validation/zotero-research-materials-20261120/continuation/run_continuation.py engine-proofing --repo . --output /path/to/fresh/engine-proofing --expected-head f3f98987824e021ed22a4d909e38d6307495267b
```

Repeat the original runner for `engine-zotero` and the adapter for `studio-integration`. For the complete spaCy run, obtain the exact byte fixture identified by the pinned URL, size and SHA-256 in [spacy-qualified-bytes.json](spacy-qualified-bytes.json), then use the wrapper that verifies and fingerprints it before and after the run:

```bash
python3 docs/validation/zotero-research-materials-20261120/continuation/run_spacy_with_qualified_bytes.py --repo . --fixture /path/to/libcrispembed-spacy.dylib --output /path/to/fresh/spacy --expected-head f3f98987824e021ed22a4d909e38d6307495267b
```

The shared local lock preserves serial Flutter/compiler-cache access. Application timeouts are unchanged. No runner resolves packages, modifies source or contacts GitHub.

At the final main follow-up source, reproduce the repeated one-file pin gate separately:

```bash
python3 docs/validation/zotero-research-materials-20261120/continuation/publication-followup/run_studio_pin.py studio-pin --repo . --output /path/to/fresh/studio-pin --expected-head 6b917be36d5d54aa8a55ef3c8b9ce649aa8bab82
```

Source and evidence checkpoints use non-forced remote updates with the expected previous head. Publication verifies the remote branch tree against the local candidate, refreshes main before merging, and verifies the resulting main tree and ancestry afterward. The PR description records the final merge identity.

**GitHub Actions, workflow-run, check and commit-status endpoints were neither queried nor awaited.** Acceptance is local Dart/Flutter, serializer, CLI and controlled-transport behavior. Incoming macOS author qualification stays separately attributed. This continuation makes no new live Zotero/Mail-account, installed-application or actual Word/LibreOffice interoperability acceptance claim.
