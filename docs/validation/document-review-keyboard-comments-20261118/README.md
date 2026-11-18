# Keyboard and inline comment review validation

This continuation builds on `ec28480130786cb923d0447ee92a1d3de19f35c0` on
`codex/document-review-20261118`. It adds keyboard review and inline comment
replies while preserving the existing progressive checks, Writing / Changes
panes, filtered batch decisions, and paragraph previews.

The accepted source is `6c88efed8de24951ef640f79af64b8df6097b248`, tree
`d1425163a0560ec60ad7481d5c0efb51d2103b85`. **All 391 targeted tests passed, with zero failures and zero skips.**
The following commits only assemble documentation and evidence; the source hashes
remain bound to this tested revision.

## Behavior covered

- **Keyboard finding navigation:** Alt+F7 / Alt+Shift+F7 select the next or
  previous current finding, wrap, and open Writing. Navigation from pane controls
  respects their category filter and keeps focus in the pane. Document navigation
  uses all current findings and does not start manual inference.
- **Caret context menu:** Shift+F10 / Menu opens suggestions and editing commands
  at the document caret. Arrow keys, Home/End, Enter, Escape, and Tab work without
  moving the source selection or creating an undo step just by opening the menu.
  The menu owns keyboard focus and returns it to the document when dismissed.
- **Exact review identity:** overlapping findings and adjacent tracked changes
  retain the explicitly selected item. Stale source changes close obsolete menus.
  Covered modal routes and active IME composition cannot trigger these commands.
  Geometry checks cover wrapped/RTL text, headers/footers, nested tables, links,
  offscreen carets, and unavailable layout.
- **Explicit checks during background work:** Check document remains available
  while ordinary providers are running. An explicit request includes configured
  manual providers; repeated identical requests share that run. Old background
  results cannot overwrite its current result.
- **Inline Studio replies:** ribbon, card, and comment-menu Reply actions select
  the thread and focus its composer. Drafts stay separate by exact thread and
  document identity. Post reply or Ctrl/Command+Enter posts explicitly with Undo
  support; Enter inserts a line break and active IME composition is not submitted.
  Switching/hiding/resizing preserves session drafts, while removed threads and
  replaced documents discard their drafts.
- **Comment proofing and layout:** the active existing comment body shows current
  document proofing marks; a marked-text click selects its finding in Writing.
  Comments sit beside wide documents and below narrower windows, with a visible
  composer. Unposted reply text enters document proofing after posting.

See the [usage and embedding guide](../../document-review.md) for shortcuts,
configuration, retained review workflows, and limitations.

## Accepted local gate

The committed [runner](run_checks.py) requires the supplied source commit, a clean
tracked index/worktree, and the verified runtime. It binds source, selected tests,
manifests, fonts, the runner, dependency configuration, and runtime executables
before and after the checks. Outputs are written outside the frozen checkout.

| Gate | Result |
| --- | ---: |
| Editor: 24 suites | 360 passed, 0 failed, 0 skipped |
| Studio: 5 suites | 31 passed, 0 failed, 0 skipped |
| Total regression cases | **391 passed, 0 failed, 0 skipped** |
| Strict analysis of 15 changed Dart files | No issues |
| Formatting and whitespace | Clean |
| Source binding | 629 files; no mismatches |
| Runtime and dependency binding | Unchanged |
| Frozen HEAD/index/tracked worktree | Unchanged and clean |

The new suites contribute **41 regression cases**: 16 keyboard interactions,
11 caret-context geometry cases, four identity/modal regressions, and ten Studio
comment cases. The accepted gate also covers existing live/incremental proofing,
manual providers, finding selection, tracked-change review, comparison, input
ownership, IME/focus, report designer, Studio startup, and worksheet navigation.
Visual fixtures and runtime setup smoke tests are excluded from these counts.

The complete unmodified accepted runner output is saved in
[accepted/evidence.tar.xz](accepted/evidence.tar.xz). The browsable
[verification report](accepted/verification.json),
[source manifest](accepted/source-after.json),
[environment manifest](accepted/environment-after.json), and
[archive/file index](accepted/index.json) identify the exact inputs, commands,
per-suite results, individual cases, errors, logs, and SHA-256 hashes. Extract the
archive to obtain both raw JSON reporter logs and their compressed copies.
[Final source binding](final-source-binding.json) checks those inputs again after
documentation/evidence assembly, including the source hashes behind the visuals.

Reproduce with the recorded runtime and locked dependencies:

```sh
python docs/validation/document-review-keyboard-comments-20261118/run_checks.py \
  --head 6c88efed8de24951ef640f79af64b8df6097b248 \
  --runtime /absolute/path/to/runtime-setup \
  --output /absolute/path/to/a-new-empty-output-directory
```

Run from a clean checkout at the stated source commit. The runner does not install
dependencies or contact GitHub. [Runtime provenance](runtime/provenance.json)
records Flutter **3.47.8** / Dart **3.13.7**, the official archive hash, verified
executables, the pinned workspace lock, 162 verified hosted dependency archives,
and the exact compressed bootstrap script. Absolute paths in receipts describe
this execution environment; supply the restored runtime's path when reproducing.

### Preserved failed attempt and fixture repair

The first frozen run at `785f4694` finished with 389 passed and two failures. Its
complete unmodified output is preserved under
[attempts/pre-integration](attempts/pre-integration/README.md). One test still
expected Check document to be disabled during background work; its expectation
was updated to the intended enabled state while retaining stale-result checks.

The worksheet failure also reproduced on the original `ec284801` baseline.
Its synthetic invalid draft was discarded by the existing editor focus guard.
The fixture now focuses the actual sheet editor, asserts focus, and verifies the
invalid draft before testing a worksheet switch. All original toast, draft,
selection, corrected-value, and history assertions remain. No worksheet product
code changed. The [diagnosis](worksheet-fixture-verification.json), diagnostic
fixture, and original/fixed logs preserve this evidence; failed expanded logs are
compressed without changing their bytes.

## Visual verification

**Three visual fixture cases passed and six PNGs were inspected.** The fixtures
use the actual editor/panes, bundled text fonts and MaterialIcons, and controlled
proofing providers. Their counts are separate from regression tests.

| Capture | Size | What it demonstrates |
| --- | --- | --- |
| [Keyboard suggestions](screenshots/keyboard-suggestions-desktop.png) | 1280 × 1000 | Actual Alt+F7, Shift+F10, and ArrowDown delivery; selected suggestion and menu focus. |
| [In-flight Writing](screenshots/keyboard-inflight-writing-desktop.png) | 1280 × 1000 | A held later paragraph while earlier findings, corrections, and Check document remain usable. |
| [Comment drafts](screenshots/comments-drafts-desktop.png) | 1760 × 1000 | Separate inline drafts beside the editable document. |
| [Comment proofing](screenshots/comments-writing-desktop.png) | 1760 × 1000 | A current comment finding selected in Writing. |
| [Narrow English comments](screenshots/comments-drafts-english-narrow.png) | 900 × 1000 | Comments below the document with the composer available. |
| [Narrow Arabic comments](screenshots/comments-drafts-arabic-narrow.png) | 900 × 1000 | The corresponding RTL layout. |

[Keyboard visual verification](keyboard-visual-verification.json) records source,
fixture, event, and image hashes; [comment verification](comments-verification.json)
records its source, test, fixture, and image hashes. The reproducible fixtures are
`render_keyboard.dart` and `render_comments.dart`. The narrow captures establish
900-pixel window coverage, not phone-size coverage.

## Incoming work preserved

Before application edits, the initial audit covered **205 fork branches, 166 PR
heads, and four upstream branches**. It included Zotero through `8002b674`, with
current review assertions preserved. [Initial audit](incoming-audit.json) and
[ancestry/equivalence classification](local-ancestry.json) record all 375 refs.

A bounded recheck at **2026-11-18 17:09:59 UTC** observed **207 fork branches,
167 PR heads, and four upstream branches**. All **378 refs** are accounted for:
350 by ancestry after integration and 28 references to 14 unchanged historical
heads by their recorded patch/tree/changed-file equivalence. Those old equivalence
records were retained and their heads checked unchanged; this pass does not claim
to recompute every historical equivalence proof.

| Incoming work | Integrated head | Scope |
| --- | --- | --- |
| Fork main | `556c55c0ef312eda2cca11600021d293a81ab44b` | Already included; unchanged at the bounded final check. |
| Native spelling | `1cdedeebcae9c4fd1a50a7bfea6f487af5bb688c` | Latest documentation and validation evidence. |
| Zotero / PR #167 | `a40a26663f7a2c6b7fb8de91540fd04b9875ed9c` | Latest qualification records and evidence. |
| Offline thesaurus | `decde7792890bf4724c91403fbb6528d8423b01e` | Engine service and export, plus its integration audit. |

The Word-like Zotero branch at `7638c5ee` was already included by ancestry.
All four upstream heads were unchanged and included, including upstream main
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`.

The three new incoming heads were combined with actual isolated three-way merges.
The single conflict retained the current selection test and its three richer
caret assertions. A narrow lint-only follow-up aligned the two incoming engine
files with strict analysis. Remote `6c88efed` preserves the resulting tree and
has the previous review checkpoint plus all three incoming heads as parents.
See [final frontier](final-frontier.json), [local merge record](late-merge.json),
[thesaurus lint checks](thesaurus-lint-checks.json), and
[remote publication record](publication.json).

## Scope and remote preservation

All checkpoints use expected previous heads, never force-push, and have matching
local staged and remote tree hashes. Commit messages include `[skip ci]`.
**No GitHub Actions status was queried or awaited.** PR #162 remains the review
branch's integration PR; this work does not merge it into main.

This gate qualifies the targeted local controller/widget/rendering workflows.
It does not claim a complete repository suite, a full native application build,
native OS shortcut dispatch, live optional-model inference, or a complete new
thesaurus qualification. The incoming thesaurus is an engine service/export;
this continuation does not add a thesaurus UI or language packs.

Comment drafts are session-local and are neither serialized nor included in
document proofing until posted. Keyboard caret context menus apply to the focused
document canvas; existing comments use marked-text clicks to reach Writing.
Native revision tracking remains supported text insertions/deletions, and
two-document comparison remains a read-only report.
