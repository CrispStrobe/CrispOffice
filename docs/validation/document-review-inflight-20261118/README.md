# Text and inline comment proofing validation

This continuation starts from `97c7ddae9514c6afa9286cd25f7339e92988cee9` on
`codex/document-review-20261118`. It adds text-level language/checking controls
and compact comment suggestions to the existing live review workflow, while
reconciling newer Zotero work. See the [usage and embedding guide](../../document-review.md)
for the user-facing behavior and controller APIs.

**Accepted: 633 regression cases passed, with zero failures or skips, against
the published integrated source below.** Strict analysis, formatting, whitespace,
and source/runtime binding also passed. Three separate visual fixture cases
produced seven inspected screenshots from the same source. This acceptance is
based on local execution; GitHub Actions were neither queried nor awaited.

## Final source and acceptance

| Field | Final value |
| --- | --- |
| Tested source commit | `eedf2aee03964329a2e4c7ee3c771d43b5df4991` |
| Tested source tree | `975389ed58d1851cf72c56b5e1cf594531762ad7` |
| Comparison base | `97c7ddae9514c6afa9286cd25f7339e92988cee9` |
| Saved checkpoints and publication | [Publication receipt](publication.json) |
| Tracked source/fixture/configuration inputs | **3,548** |
| Source changes during the gate | **None**; HEAD/index unchanged, tracked worktree clean before and after |
| Bound runtime and dependency inputs during the gate | **Unchanged**; identical before/after manifests |
| Source binding after evidence assembly | [Final source binding](final-source-binding.json) |

The [accepted gate receipt](accepted/verification.json) records the exact source,
commands, per-suite counts, and before/after manifests. The
[evidence file index](accepted/files.json) supplies the retained artifact hashes.
The source binding and publication receipts distinguish the tested source from
later documentation/evidence commits.

| Gate | Requested coverage | Result |
| --- | --- | --- |
| Engine | 4 suites | **30 passed; 0 failed; 0 skipped** |
| Editor | 34 suites | **544 passed; 0 failed; 0 skipped** |
| Studio | 5 suites, including 38 comment review cases | **59 passed; 0 failed; 0 skipped** |
| Total regression cases | Counts exclude hidden reporter events and visual fixtures | **633 passed; 0 failed; 0 skipped** |
| Strict Dart analysis | All 25 changed tracked product Dart files since the comparison base | **Passed; no issues** |
| Formatting and whitespace | Same 25 Dart files; complete Git diff whitespace check | **Passed** |
| Source/runtime/dependency binding | Before and after the complete gate execution | **Passed; zero mismatches** |
| Visual fixtures | 2 text-option cases and 1 Studio comment case, counted separately | **3 passed; 7 inspected captures** |

All 43 requested suites produced visible cases. There were no missing or empty
suites, unfinished reporter events, reporter errors, failed commands, or changed
bound inputs. The gate ran on 18 November 2026. Source
manifests before and after both hash to
`39fff2337cce65c7c03d13f9d45411ec18e0fc61182e5e5cdae5c9232f3518a0`;
runtime/dependency manifests both hash to
`03ce9ccc6176ae4fcf550044355e4a3f7b40a97a3af9689b43da8d5f85afcda6`.

## Behavior covered

- **Text scope in the editor:** the language/globe status action reveals
  Language and checking at the top of Writing, including when the pane was
  already expanded and scrolled elsewhere. A selection targets selected text;
  a collapsed caret targets its paragraph. Mixed languages and mixed checking
  states are explicit. Narrow/RTL layouts retain usable controls.
- **Undoable text settings:** language and Check this text apply to the exact
  displayed target, preserve text and selection, and create one undo command
  for each actual change. No-op requests do not add history. A multi-paragraph
  operation completes its preflight before any source paragraph changes.
- **Freshness and protection:** stale source, replacement documents, changed
  caret/story ownership, covering modal routes, protected controls, generated
  fields, unsupported ranges, and active IME composition cannot redirect a
  setting change. Grapheme boundaries are preserved.
- **Inherited language fidelity:** removing a direct language override restores
  the applicable table, paragraph, and character style language for immediate
  proofing and DOCX save/reload. Document and paragraph defaults remain live.
  East Asian/bidi language metadata, unsaved unrelated formatting, unknown run
  XML, and explicit checking settings are preserved. Preparation leaves the
  original document/package unchanged.
- **Live checking:** affected findings invalidate immediately; ordinary
  configured providers update after the typing pause. Unaffected findings stay
  available, excluded text is reflected in coverage, and late results cannot
  revive obsolete findings. These actions do not start optional manual
  inference; F7 / Check document remains the explicit entry point.
- **Comment suggestions:** primary-clicking marked comment text opens compact
  suggestions when Writing is closed; an existing Writing pane follows the
  finding. Right-click suggestions coexist with editing/thread actions.
  Corrections remain undoable, typing focus stays with the comment, and menus
  are tied to exact document, thread, comment, source, and caret identities.
  Resolved replies offer the thread's Reopen action.
- **Actual compact-canvas input:** regression coverage exercises real pointer
  delivery over marked comment text, including the first line where compact
  content overlaps a layout header band. Compact stories do not dispatch this
  text into nonexistent page-header chrome.
- **Comment selection ownership:** Select mode supports read-only comment
  selection and Copy, including actual drag/right-click input and transitions
  through View. View disables selection while keeping comments visible. Comment
  operations clear stale body/table/frame selection ownership, reject obsolete
  handlers, and avoid materializing empty stored paragraphs in read-only modes.
- **Retained and incoming behavior:** the gate retains the prior keyboard,
  finding, tracked-change, comparison, input/IME, Studio and worksheet suites.
  It also includes every changed/new regression suite from the later Zotero
  head: citation lookup at the caret, document actions, unlinking, composer and
  citing dialogs, and note editing/numbering.

## Reproduce the local gate

[run_checks.py](run_checks.py) requires an explicitly named source commit and a
clean tracked index/worktree. It checks that every requested test and both
visual fixture definitions exist in that tree. It binds all tracked `packages/`
and `apps/` inputs, root configuration, and the runner, including imported test
helpers, fixtures, assets, and fonts. Untracked product inputs are rejected.

```sh
python3 docs/validation/document-review-inflight-20261118/run_checks.py \
  --head eedf2aee03964329a2e4c7ee3c771d43b5df4991 \
  --base 97c7ddae9514c6afa9286cd25f7339e92988cee9 \
  --runtime ../toolchains \
  --output ../review-validation-reproduction
```

The output directory must be outside the frozen checkout. Preserve previous
attempts by choosing a new empty directory. Dependencies must already be
restored. The six command stages are engine tests, editor tests, Studio tests,
strict analysis, formatting, and whitespace. The exact commands, source commit,
per-suite case counts, errors, runtime identity, and hashes are emitted into
`verification.json` and its companion manifests/logs.

Run this from a clean checkout of the tested source commit, with the restored
runtime beside it. The accepted receipt and hashed output are retained under
[accepted/](accepted/verification.json); the source manifest binds the product
inputs even when an evidence-only publication commit has a later HEAD. Earlier
development attempts are preserved separately below and are excluded from the
accepted totals.

### Runtime and dependencies

[Runtime provenance](runtime/provenance.json) and [runtime receipt](runtime/runtime.json)
record the restored official SDK, exact executed bootstrap, compressed SDK
member inventory, verified dependency archives, and setup logs.

| Input | Recorded identity |
| --- | --- |
| Flutter | **3.47.8**, framework `737ba8f885dc774b53b442759999a312c9461e4e` |
| Dart | **3.13.7** |
| Official SDK archive SHA-256 | `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2` |
| Workspace lock SHA-256 | `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130` |
| Verified hosted Pub archives | **162** |
| Resolved workspace packages | **110** |

Both the Dart executable and Flutter tester are verified against their recorded
hashes. Offline `--enforce-lockfile` setup succeeded for the Flutter tools and the
workspace. Setup qualification is separate from application acceptance. Absolute
paths in the receipts describe the recorded environment; restore the runtime
and regenerate its wrappers/package configuration for the destination path.

## Visual evidence

The two committed fixture definitions are [render_text_options.dart](render_text_options.dart)
and [render_comments.dart](render_comments.dart). They use the actual
editor/Studio surfaces, bundled text fonts and MaterialIcons, and controlled
proofing providers. Their definitions are included in the source binding.

| Capture | Fixture size | Demonstrated interaction |
| --- | --- | --- |
| [Mixed text languages](screenshots/text-proofing-mixed-desktop.png) | 1280 × 960 | Selected multilingual text and in-editor language/checking controls. |
| [Selected-text exclusion](screenshots/text-proofing-excluded-desktop.png) | 1280 × 960 | Check this text disabled for one selected span while another finding remains. |
| [Narrow Arabic text options](screenshots/text-proofing-arabic-narrow.png) | 650 × 1000 | Options below the editable document in RTL. |
| [Inline comment suggestions](screenshots/comments-inline-suggestions-desktop.png) | 1760 × 1000 | Primary pointer delivery opens a compact suggestion menu with comment typing focus retained. |
| [Comment context suggestions](screenshots/comments-context-suggestions-desktop.png) | 1760 × 1000 | Correction actions beside normal editing/thread commands. |
| [Comment in Writing](screenshots/comments-writing-desktop.png) | 1760 × 1000 | Open writing pane selects the comment finding. |
| [Narrow Arabic comment suggestions](screenshots/comments-inline-suggestions-arabic-narrow.png) | 900 × 1000 | The compact suggestion menu stays anchored to visible marked comment text in RTL. |

The [accepted visual receipt](accepted/visuals/verification.json) records three
passing fixture cases and seven captures from the exact tested source. All seven
were visually inspected: six regenerated PNGs were byte-identical to previously
inspected captures, and the changed capture was inspected again. Visual fixture
cases are excluded from the 633-case behavior regression total. Widget layout
coverage also exercises 390-pixel windows with 1.6× text scaling; that does not
constitute native phone or operating-system accessibility qualification.

## Incoming reconciliation

The [initial reconciliation](incoming-reconciliation.json) preceded application
edits and inventories **207 fork branches, 168 PR heads, and four upstream
branches: 379 references to 247 unique heads**. It records 349 references already
included in the prior review checkpoint, two incoming Zotero references, and
28 references to 14 historical heads with freshly reverified patch/tree/file
equivalence evidence.

The initial local three-way merge brought in Zotero head
`b2597485b923003f01c1bd69e02d0c62a6943514` / PR #168 without conflicts.
The later [bounded remote inventory](final-frontier.json) and
[final Zotero observation](late-merge-observation.json) closed the observed
frontier at `6c993f7406037ba462c6aea32e7e6afeebd28c03`, a descendant of the
intermediate `86b9c03c272baec7277d2f8fb548711a73fe9aee` head.

The [recorded local merge](late-merge.json) was published as
`68d8c83afad66569e5654023eecbcdc3185cbf20`, preserving its exact tree and parents
`ebd9fce473ee96f4d11785d2edef12c19797b619` and
`6c993f7406037ba462c6aea32e7e6afeebd28c03`. Two test-file conflicts were resolved
deliberately: the Studio comment suite retained the current review fixtures and
pointer coverage instead of incoming formatting of an older fixture; the text
proofing controller suite retained its current regressions and incorporated
stronger incoming assertions for inherited language after save/reload and
changes to the document default. Production controller/workspace changes
merged automatically. The final accepted source contains this merge and the
subsequent reviewed comment-selection fix.

**All 379 observed references are accounted for: 351 are in merged ancestry
and 28 have verified historical equivalence; zero remain outstanding.** These
represent 247 unique heads: 233 ancestral and 14 equivalent. This is closure
of the recorded bounded observation, not a claim about remote heads created
after it. Earlier reconciliation records retain their original execution-time
status; acceptance of the integrated source is established by this gate.

## Development findings and fixes

Development checks identified the following issues before final acceptance:

1. Clearing a direct language on imported styled text produced live `de-DE`
   while save/reload restored inherited `de-CH`. A standalone engine diagnostic
   reproduced it. The new detached inheritance helper now maintains the
   effective language and sparse direct metadata together.
2. Newly authored run-property fragments and extracted `tblLook` elements lost
   their inherited Word namespace when parsed in isolation. This initially
   broke language reset after an earlier save and conditional table-language
   inheritance. The helper now supplies a Word namespace context for generated
   run fragments and reads table-look attributes directly from their XML nodes.
3. The language dropdown's mixed value required a nullable helper parameter.
   No-op choices needed feedback that does not promise a new Undo entry, and
   repeated status actions needed to reveal already-expanded controls.
4. Source review found unnecessary concatenation of every preceding paragraph's
   text during status inspection. Traversal now stops at the target and scans
   preceding field boundaries without constructing their text. Mutation
   operations still perform fresh source/protection preflight.
5. Real pointer dispatch exposed compact comment text being mistaken for page
   header chrome. Compact canvases now use body-text hit testing for these
   interactions; geometry and Studio fixtures exercise the rendered surface.

The focused engine development run completed with **21 passed, zero failed and
zero skipped**: 13 new inheritance cases, four existing comment-style cases, and
four style-introduction cases. Strict analysis of the changed engine files and
new engine suite was clean. These development results are **not added to** the
final gate total; the later integrated source passed the separate canonical
gate recorded above.

The Studio development run named `comment-review-final-studio.log` completed
with **31 passed** before the subsequent comment selection-ownership and
read-only Copy guard changes. It does not validate those later changes. The
additional focused development attempts, including their failures, are retained
for review. The added ownership
fixture initially chose View rather than Select: Studio Select permits
read-only selection and Copy, while View disables selection but keeps comments
visible. The behavioral assertions were retained, the fixture mode was
corrected, and coverage now also rejects stale View-mode handlers. The later
selection-ownership clearing and read-only empty-placeholder changes passed
their six focused cases. A subsequent real-pointer case exposed that Select
mode did not render an interactive comment canvas and that the parent pane
could see the previous controller mode during a rebuild. The pane now uses
the build-safe configuration sync before rendering the effective selection
mode. The actual drag/right-click/Copy and Select → View → Select case passed,
with editing and IME input disabled. Its initial failure and passing rerun are
preserved. All 38 cases in the final Studio comment suite passed in the
integrated gate.

The [development attempt index](attempts/development/index.json) maps each
original source basename to an unchanged compressed log and records both raw
and archive SHA-256 hashes for **33 retained logs**. It preserves text-control attempts 1–3, pane
attempts 1–2, engine inheritance attempts, text/comment visual runs, and comment
menu, clipboard, actual-pointer, geometry, ownership, and analysis attempts.
File names containing `final` are the original development names. These logs
came from evolving working-tree source and have no frozen per-attempt source
manifest; they are **not** accepted final-gate records. Failed logs remain
alongside later successful development runs.

## Scope and limitations

The acceptance target is the selected local engine, controller, widget,
rendering, and DOCX round-trip workflows. It does not claim a complete repository
suite, full native application builds, native operating-system shortcut dispatch,
live optional-model inference, or live connected Zotero/network-service coverage.
Configured providers retain their existing installation/language requirements.

Text options cover supported editable body/table/frame text, default
headers/footers, and active existing comment text. Empty/unsupported selections,
generated fields, protected controls, note marks, and active composition have
explicit boundaries. The setting UI does not add full native formatting-change
tracking. Existing revision tracking remains supported text insertions/deletions,
and two-document comparison remains a read-only report.

Reply drafts remain session-local until explicitly posted; this work does not
add live proofing of unposted drafts. Comment suggestion menus are Studio host
UI; the shared editor retains its own Writing/Changes panes and document caret
menu. Screenshot sizes document the exercised layouts, not every device size.

The [publication receipt](publication.json) records remote checkpoints and their
parent/tree identities. The [final source binding](final-source-binding.json)
ties the evidence publication to the 3,548 tested inputs, while the accepted
gate records the source and environment used for local execution.
