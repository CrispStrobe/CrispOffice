# Text and inline comment proofing validation

This continuation starts from `97c7ddae9514c6afa9286cd25f7339e92988cee9` on
`codex/document-review-20261118`. It adds text-level language/checking controls
and compact comment suggestions to the existing live review workflow, while
reconciling newer Zotero work. See the [usage and embedding guide](../../document-review.md)
for the user-facing behavior and controller APIs.

**Status: the final frozen gate and its publication are pending.** Development
checks and existing screenshots below do not constitute final acceptance of the
integrated source. This is a local validation record; GitHub Actions results are
not part of its acceptance criteria.

## Final source and acceptance

| Field | Final value |
| --- | --- |
| Tested source commit | **PENDING_SOURCE_COMMIT** |
| Tested source tree | **PENDING_SOURCE_TREE** |
| Comparison base | `97c7ddae9514c6afa9286cd25f7339e92988cee9` |
| Final saved checkpoint | **PENDING_PUBLICATION_COMMIT** |
| Tracked source/fixture/configuration inputs | **PENDING_SOURCE_FILE_COUNT** |
| Source changes during the gate | **Pending** |
| Runtime/dependency changes during the gate | **Pending** |
| Final source binding after evidence assembly | **Pending** |

Populate the source fields and counts from the final `verification.json`, then
verify the saved checkpoint against its source manifest. A later commit containing
only documentation/evidence does not substitute for this source comparison.

| Gate | Requested coverage | Result |
| --- | --- | --- |
| Engine | 4 suites | **PENDING_ENGINE_RESULT** |
| Editor | 34 suites | **PENDING_EDITOR_RESULT** |
| Studio | 5 suites | **PENDING_STUDIO_RESULT** |
| Total regression cases | Counts exclude hidden loader events and visual fixtures | **PENDING_TOTAL_RESULT** |
| Strict Dart analysis | All changed tracked product Dart files since the comparison base | **Pending** |
| Formatting and whitespace | Same changed Dart files; complete Git diff whitespace check | **Pending** |
| Source/runtime/dependency binding | Before and after every complete gate execution | **Pending** |
| Visual fixtures | 2 text-option cases and 1 Studio comment case, counted separately | **PENDING_VISUAL_RESULT** |

The report must record failures and skips as well as passes. A requested suite
with no visible cases, an unfinished test, a reporter error, a failed command,
or a changed bound input prevents a passing gate.

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
  East Asian/bidi language metadata, pending unrelated formatting, unknown run
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
python docs/validation/document-review-inflight-20261118/run_checks.py \
  --head PENDING_SOURCE_COMMIT \
  --base 97c7ddae9514c6afa9286cd25f7339e92988cee9 \
  --runtime /absolute/path/to/restored-runtime \
  --output /absolute/path/to/a-new-empty-output-directory
```

The output directory must be outside the frozen checkout. Preserve previous
attempts by choosing a new empty directory. Dependencies must already be
restored. The six command stages are engine tests, editor tests, Studio tests,
strict analysis, formatting, and whitespace. The exact commands, source commit,
per-suite case counts, errors, runtime identity, and hashes are emitted into
`verification.json` and its companion manifests/logs.

Before declaring acceptance, publish the unmodified accepted output, its
archive/file index, and the final source-binding receipt here. Preserve any
failed frozen attempts separately. **Those final artifacts are pending.**

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

The seven captures were visually inspected after the comment pointer fixture
was corrected. Their development execution logs are preserved below; **final
fixture receipts and binding to the accepted integrated source remain pending**.
Visual fixture cases are excluded from the behavior regression total. Widget layout
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
The later [bounded remote inventory](final-frontier.json), compared against
`a77d67d04dfe4e1d61bc3dae5c96d5d9d3a4f1f4`, found the same reference counts and
identified a newer Zotero head:
`86b9c03c272baec7277d2f8fb548711a73fe9aee`.

**Later integration and post-merge classification: PENDING_INCOMING_RESULT.**
The bounded inventory currently records that head as needing integration;
update this section from the actual merge and final ancestry/equivalence
receipts. A branch name alone is not evidence that its later head was included.

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
final gate total and do not qualify later incoming source without that gate.

The Studio development run named `comment-review-final-studio.log` completed
with **31 passed** before the subsequent comment selection-ownership and
read-only Copy guard changes. It does not validate those later changes. The
additional focused development attempts, including their failures, are retained
for review; the integrated final gate remains pending. The added ownership
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
preserved. The final Studio suite contains 38 cases; the integrated gate is
still pending.

The [development attempt index](attempts/development/index.json) maps each
original source basename to an unchanged compressed log and records both raw
and archive SHA-256 hashes. It preserves text-control attempts 1–3, pane
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

Remote checkpoint publication, exact parent heads, staged-tree equality, and
post-publication verification must be taken from the final publication receipt.
**Publication verification for the final accepted source is pending.**
