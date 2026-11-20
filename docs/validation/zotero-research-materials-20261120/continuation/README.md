# Zotero research materials: continuation and publication

This continuation finishes [PR #223](https://github.com/CrispStrobe/quds_office_suite/pull/223), which was still open when the attached handoff ended. It restores and independently checks the saved qualification, reconciles the ready incoming work, and validates the combined source locally.

**Freshly tested source:** `f3f98987824e021ed22a4d909e38d6307495267b`.
**Dart lint correction:** `3cba1810b41a2fff5b2cd1eb355137a46b09f225`.
**macOS-only follow-up source:** `6b917be36d5d54aa8a55ef3c8b9ce649aa8bab82`.
**Broad core qualification source:** `214c4ed80bef0cb871f74e90c506d508679d3d6e`.
**Mail/web combined source:** `a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1`.
**Arabic follow-up source:** `f69e774fbb32a103260541e4a28fb17600bfc17e`.
**Mobile-main integration source:** `65ea4c3095ff5d821c57d4dced0ba50bdd9387e7`.
**Final formatter source:** `2b74f1091c8fb968f1cb53c803bdd2a0b395159d`.
The [final mobile-main supplement](mobile-main-followup/README.md) preserves
PR #232 without changing the Zotero implementation. Its incoming native
mobile evidence retains its author/source attribution; the Arabic mobile
receipt predates the currently required ABI 3 / adapter 2 and does not qualify
that combined native source. Earlier test populations remain bound to their
recorded source revisions.
The final supplement's fixed-configuration host runs pass **51 cases in five
files** at `65ea4c30`; the later source formats one incoming test call and
retains the original failed formatting receipt separately. Its two affected
cases pass again, and all **18 final changed Dart targets** pass strict
analysis and formatting at `2b74f109`; repeated cases are not added twice.
The later Word/slide/host integration has its own fresh core qualification below; earlier results retain their exact original source attribution.
The lint correction only adds braces to an existing `if` statement in the standalone grammar evaluation tool. At that step, application libraries, selected tests, fixtures, manifests and locks remain byte-identical to the fresh test source; [the publication audit](publication-audit.json) records that boundary. A subsequent main update changes the macOS build script and two documentation paths, including Dart documentation comments. Its separate [final follow-up audit](publication-followup/final-audit.json), one repeated pin test, ten controlled shell checks and fresh static analysis qualify that later delta without rewriting the earlier results.

## Delivered Zotero workflow

**Library → Reference details → Notes and attachments…** browses a connected reference's direct child notes and attachment metadata. Users can read and copy inert plain-text note previews, inspect and copy attachment details, and page, retry or reload without losing selected references or unfinished search/tag input. Connection and library-version guards discard stale responses. Document contents and undo history are preserved, including in read-only documents.

The previously implemented scope is unchanged during this continuation. The [usage guide](../../../zotero-support.md#read-research-notes-and-inspect-attachments) explains the exact connection/version requirements and limits. Attachment file downloading, launching and Zotero writes are outside this increment.

## Original evidence recovered and verified

The retained branch at `e79c32e77f1990e303527e477e4909df993c1b9b` already contained the complete original evidence. Its old PR description was out of date; no product work or raw qualification results needed reconstruction.

An independent replay of the eleven saved event streams verifies **2,886 distinct passing cases in 135 files**, no failures/skips/errors/layout diagnostics, complete requested suite coverage, all recorded artifact hashes, and source bindings. It rehashes 3,833 unique source blobs and checks all 55 original static-target hashes. The original source attribution remains 2,884 cases at `f0122cb5`, followed by two Word macro guard cases at `d1b8f9be`. This is an evidence re-audit, not a new execution of those 2,886 tests. See [restored-branch.json](evidence-audit/restored-branch.json) and the [audit explanation](evidence-audit/README.md).

The new main integration changes the proofing/spaCy/Studio dependency graph, so the report does not claim every old aggregate input remains unchanged. The exact delta is [listed and reviewed](evidence-audit/publication-delta.json). Zotero, Mail, rendering and VBA implementations and their previously selected tests are retained; the engine facts change is additive. The new affected behavior is covered by the fresh gates below.

## First continuation qualification

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

At the first bounded intake, these three heads were deferred. The later Word/slide/host supplement below supersedes the PPTX inclusion and Mail readiness observations:

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

### Publication follow-up: Word, slides and host integration

Source **`214c4ed80bef0cb871f74e90c506d508679d3d6e`** preserves main
`64f977ab003031d560c6564cf8895b1250d120d9`, including the newer Word font metrics,
paragraph-mark layout and host changes, and PPTX head `e7ba3544`. This is a
substantive source change: the earlier first-continuation receipts are retained
with their original attribution, and the affected core selections run afresh.
The [incoming review](host-main-followup/incoming-review.json) covers all 119
changed paths, including 30 Dart paths, and the
[gate review](host-main-followup/gate-review.json) explains the selected scope.

| Cohort | Distinct passing cases | Files |
| --- | ---: | ---: |
| [Zotero engine](host-main-followup/accepted-engine-zotero/receipt.json) | 642 | 29 |
| [Zotero editor](host-main-followup/accepted-editor-zotero/receipt.json) | 632 | 43 |
| [Slide/PDF rendering and fonts](host-main-followup/accepted-engine-rendering/receipt.json) | 214 | 14 |
| [Slide/editor rendering](host-main-followup/accepted-editor-rendering/receipt.json) | 109 | 10 |
| [Word layout engine](host-main-followup/accepted-engine-word-layout/receipt.json) | 232 | 22 |
| [Word layout editor](host-main-followup/accepted-editor-word-layout/receipt.json) | 87 | 14 |
| [Mail host](host-main-followup/accepted-mail-host/receipt.json) | 319 | 11 |
| [Studio integration](host-main-followup/accepted-studio-integration/receipt.json) | 151 | 14 |
| **Current core qualification** | **2,386** | **157** |

All eight cohorts pass the original acceptance guards, with exact requested
suite coverage, zero failed or skipped cases, no duplicate case identities,
and unchanged recorded source, runtime, dependency and package-configuration
inputs during each run. The original runner is used directly for editor
Zotero; the seven other selections use a hash-pinned adapter. The
[independent audit](host-main-followup/audit.json) recounts the raw JSON streams
and rehashes their artifacts and inputs. The [summary](host-main-followup/summary.json)
keeps these **2,386** cases separate from the overlapping earlier 3,201 and
original 2,886 results. The earlier proofing accounting exception does not
apply to this current core gate.

All **102 changed Dart targets** pass strict analysis and formatting at this
source. The root lockfile changes only the existing `image` dependency from
direct to transitive; no package version, archive hash, resolved package
configuration or runtime byte changes. The
[dependency delta](host-main-followup/dependency-delta.json) records 4,502
dependency-file rechecks, 12 runtime records and both package configurations.
No package resolution or dependency-cache mutation was performed for this delta.

The [eight Python comparator controls](host-main-followup/comparator-controls/receipt.json)
also pass, separately from the Dart totals. Their source and Python/Pillow
runtime inputs are recorded before and after execution. They test synthetic
scoring and corpus-validation rules; they do not execute Microsoft Word or
rerun a real native corpus.

The incoming native Word evidence is verified as author evidence: all 12
recorded artifact hashes match, but only **20 of 24 macOS pages** exceed its
strict 95% layout threshold. The author report has `targetMet: false`; four
Arial/Times exact-spacing cases remain below the threshold. This continuation
does not turn that result into a native parity pass. The review also records
an existing geometry limitation: Flutter and PDF currently use the same
six-vertex notched path for `pentagon` and `chevron`. Passing selected local
regressions does not establish complete shape or Office interoperability fidelity.

The later bounded snapshot supersedes two initial readiness observations:
PPTX `e7ba3544` is included in this source, and Mail `177f29d3` now has an
author-qualified checkpoint whose core attachment/composition source is
already identical here. Its remaining shared slide-background repairs require
separate reconciliation. VBA `2f55e535` still explicitly marks combined-source
qualification as work in progress. Their exact dispositions, scope and
author-attribution limits are recorded in the incoming review.

Main's subsequent PR #229 is reviewed separately in
[web-persistence-review.json](host-main-followup/web-persistence-review.json).
It adds a narrow web data-store and host integration; it is not included in
the `214c4ed8` execution source above. Its completed reconciliation, passing VM qualification and blocked Chrome
launch are recorded in the final combined-source supplement below.

### Combined source: web persistence and qualified Mail reconciliation

The Mail/web combined source is **`a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1`**,
tree `abb783deb0dcf32f5cd4a985818f040da6ac6229`. It preserves published main
`43db439e1e605d6329a6eabe6817b04ca44ba1aa` (web persistence in PR #229 and
the documentation-only GlotLID feasibility note in PR #230), plus the captured
qualified Mail head `177f29d3f9450a58f41189b462b0814aad37e45c` as original
merge ancestry. The source and every preceding completed evidence checkpoint
were saved remotely with non-forced expected-head updates.

The [Mail reconciliation](mail-qualification-followup/proposal.json) changes
exactly three slide implementation files and two engine test files. It preserves
authored and inherited slide backgrounds through copying and save/reopen,
including picture relationship ownership, while retaining every current
geometry enum/parser/writer addition and its regression. All current Word/font,
Zotero, theme, renderer, PDF exporter, controller, workspace and web source
remain exact. The 236-path merge also retains the incoming Mail documentation
and historical evidence, separately attributed to its author. An explicit
genuine common base and isolated index were used to resolve the recorded
recursive virtual-base limitation; the resulting tree and every resolution are
reviewable. This supplement supersedes the earlier deferred-Mail disposition.

| Final focused cohort | Distinct passing cases | Files |
| --- | ---: | ---: |
| [Slide/PDF rendering and fonts](publication-final/accepted-engine-rendering/receipt.json) | 228 | 14 |
| [Slide/editor rendering](publication-final/accepted-editor-rendering/receipt.json) | 109 | 10 |
| [Web host/cancellation/downloads on VM](web-persistence-followup/accepted-web-vm/receipt.json) | 19 | 3 |
| **Successful final focused total** | **356** | **27** |

These three fresh selections run on the exact combined source above and pass
their input, coverage, completion, no-skips and unique-case guards. They are
not added to the overlapping **2,386-case core gate at `214c4ed8`**, the earlier
3,201-case proofing integration gate, or the original 2,886-case milestone.
The new engine rendering run contains the added background and picture-border
assertions and supersedes the earlier rendering applicability. The final
source and accounting audit is retained under [publication-final](publication-final/).

**The fresh Chrome check is blocked by the execution environment.** The
[preserved launch receipt](web-persistence-followup/accepted-web-chrome/receipt.json)
correctly remains `failed`: Chromium cannot create its Unix process-singleton
socket (`Operation not permitted`), and the SDK aborts after launch retries. **Zero browser application cases execute.** The real JSON loader
error, complete process logs, launch arguments and before/after inventories
remain intact; every recorded immutable input stays unchanged. The directory
name is historical and does not override its failed receipt. No browser pass
or successful Cache Storage execution is inferred from that attempt.

PR #229's author reports three Chrome cases on the exact web source preserved
here. Those remain separately attributed metadata, not independently recounted
or freshly executed browser results. The three selected tests cover synthetic
verified-byte restoration, removal and corruption handling; they do not prove
live downloads, real morphology-model activation or an explicit partial-file
case. The unchanged pinned runner can be repeated on a host that permits the
required browser IPC. The browser receipt remains rejected, and its test source and acceptance
guards remain unchanged.

**All 108 active changed Dart application, test and tool targets pass strict
analysis and formatting.** The
[active-source static receipt](publication-final/static-product/receipt.json)
preserves every source fingerprint and uses the unchanged strict flags. The
initial [110-path diagnostic attempt](publication-final/static/receipt.json)
remains failed: two newly imported historical Mail harnesses under `docs/`
have 14 informational diagnostics in the current root package context, and
one would be reformatted. Those exact two archived files are excluded only
from the active-source selection, with pinned blobs, SHA-256 values, author
artifact-index entries and original execution receipts. Their original bytes
remain intact. No active code, test or tool receives an exception, and the
report does not claim all 110 paths pass.

The [dependency reuse proof](publication-final/dependency-reuse.json) verifies
the actual new Studio manifest. Its direct `web: ^1.1.2` declaration uses the
already locked and resolved `web` 1.1.2. All 152 effective package dependency
closures, all 192 recorded web files, the lockfile and both saved configuration
files are unchanged. The saved graph predates the new direct edge and is
explicitly reused rather than claimed to have been regenerated. No package
resolution, dependency replacement or configuration rewrite was required.

The conservative VM import analysis preserves the original core receipts
without pretending their broad source inventories are identical to this later
source. The unchanged `dart.library.io` factories exclude the changed web
hosts from all 157 earlier core roots. Direct web-host imports receive their
own fresh VM run. Slide/background libraries remain reachable through engine
exports; their changed behavior is confined to slide/PPTX operations and is
covered by the fresh rendering gates. Word and Zotero implementations and
selected tests remain exact. The review distinguishes compilation reachability
from changed behavior and records the actual callsites and source delta.

The captured newer VBA head remains explicitly unfinished at the bounded
snapshot and is not imported as a completed increment. The known pentagon
silhouette limitation and the incoming native Word result of **20/24 pages
above the strict threshold** remain disclosed. No new live Zotero/Mail account,
native macOS bundle, actual Word export or LibreOffice acceptance is claimed.

### Latest main follow-up: Arabic morphology and grammar

The latest combined source is **`f69e774fbb32a103260541e4a28fb17600bfc17e`**,
tree `1a45545ffa7f4c8548853a30c95bdb38309e3da9`. It preserves published main
`098412152fa1d64796eb3fb9c06699ced0f0c44d` (PR #231) and the complete earlier
source/evidence checkpoint `a3373021`. The ordinary merge is conflict-free;
all 38 incoming paths, including 23 Dart paths, match main exactly. The
[incoming review](arabic-main-followup/incoming-review.json) covers the Arabic
context-morphology API, host setup, transport, grammar rules, pins and notices.

| Fresh Arabic follow-up gate | Distinct passing cases | Files |
| --- | ---: | ---: |
| [Morphology unit](arabic-main-followup/accepted-arabic-unit/receipt.json) | 17 | 1 |
| [Engine Arabic rules](arabic-main-followup/accepted-engine-arabic/receipt.json) | 526 | 4 |
| [Studio integration](arabic-main-followup/accepted-studio-integration/receipt.json) | 90 | 7 |
| **Latest focused total** | **633** | **12** |

Every selected case passes with all original source, runtime, dependency,
configuration, coverage and event-accounting guards; there are no failures or
skips in these three cohorts. The Studio selection includes new Arabic setup,
downloads, settings, linguistic analysis, comment drafts, Zotero shortcuts and
citing transport. The author's unspecified Studio baseline exception is not
used to excuse any failure here. The [independent summary](arabic-main-followup/summary.json)
and [source applicability](arabic-main-followup/applicability.json) preserve
all earlier raw receipts and their original source attribution. These 633
cases overlap earlier proofing/Studio selections and are not added to earlier
totals. Word, Zotero, slide and Mail implementations remain exact; changed
Arabic and Studio paths receive this separate qualification.

**All 129 active changed Dart targets pass strict analysis and formatting.**
The [static receipt](arabic-main-followup/static/receipt.json) captures all 131
changed-file fingerprints, including the same two byte-preserved historical
Mail harnesses excluded from the active selection. The earlier 110-path
archive-inclusive diagnostic remains unchanged; it is not relabeled or rerun
as this source's acceptance.

The [dependency proof](arabic-main-followup/dependency-reuse.json) explicitly
records the local morphology manifest's version change from 0.2.0 to 0.3.0.
Dependency edges, unversioned local path consumers, hosted versions/hashes and
resolved paths are unchanged. The saved graph retains its prior 0.2.0 label
and the earlier indirect Studio-to-web edge; neither is claimed to have been
regenerated. All 126 hosted versions/hashes, 4,502 dependency files, 12 runtime
records and both configurations match their prior inputs. The effective 152
package dependency closures remain equal. No package resolution or runtime
replacement was required for these tests.

Arabic's updated native ABI 3 / adapter 2 requirement is distinct from the
unchanged spaCy library. The macOS build script builds and installs the Arabic
library separately, and its updated builder pins the compatible revision.
Existing ABI 2 Arabic libraries require rebuilding. This is a source-level
compatibility review; the native build, real model execution and WebAssembly
runtime are not freshly qualified in this environment.

**Browser qualification remains unavailable.** The earlier blocked Chrome
attempt belongs to `a45ee3bf`; no fresh browser application cases execute at
this later source. In particular, the earlier PR #229 nine-path equivalence
is superseded where the Arabic README and web host changed. The
[web model-removal limitation](arabic-main-followup/web-model-removal-limitation.json)
records an additional source-identified concern: the web host retains a
verified database object whose buffers are transferred to its worker, then
reuses that object when removing the optional model. On the JavaScript path,
those retained buffers can already be detached, so restoring the base analyzer
is at risk. This is a source finding, not a reproduced browser result, and it
is retained as an incoming Arabic limitation outside the Zotero workflow.

Reproduce the three selections using `arabic-main-followup/run_arabic_followup.py`
with `--expected-head f69e774fbb32a103260541e4a28fb17600bfc17e` and fresh output
directories. Use `arabic-main-followup/run_product_static.py` for its exact
active-source static selection. The summary retains native/browser scope and
all source boundaries explicitly.

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

At the earlier macOS-only follow-up source, reproduce the repeated one-file pin gate separately:

```bash
python3 docs/validation/zotero-research-materials-20261120/continuation/publication-followup/run_studio_pin.py studio-pin --repo . --output /path/to/fresh/studio-pin --expected-head 6b917be36d5d54aa8a55ef3c8b9ce649aa8bab82
```

For the later core source, run all eight named selections in
`host-main-followup/run_host_followup.py` using fresh output directories and
`--expected-head 214c4ed80bef0cb871f74e90c506d508679d3d6e`. The comparator
controls have a separate `run_comparator_checks.py` runner. The independent
auditor is `host-main-followup/audit_host_followup.py`.

At the earlier Mail/web combined source, repeat the two rendering selections with the
same host adapter and `--expected-head a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1`.
Use the [web adapters](web-persistence-followup/README.md) for the separate VM
and Chrome cases, and `publication-final/run_product_static.py` for the exact
active-source static selection. All output directories must be fresh.

Source and evidence checkpoints use non-forced remote updates with the expected previous head. Publication verifies the remote branch tree against the local candidate, refreshes main before merging, and verifies the resulting main tree and ancestry afterward. The PR description records the final merge identity.

**GitHub Actions, workflow-run, check and commit-status endpoints were neither queried nor awaited.** Acceptance is local Dart/Flutter, serializer, CLI and controlled-transport behavior. Incoming macOS author qualification stays separately attributed. This continuation makes no new live Zotero/Mail-account, installed-application or actual Word/LibreOffice interoperability acceptance claim.
