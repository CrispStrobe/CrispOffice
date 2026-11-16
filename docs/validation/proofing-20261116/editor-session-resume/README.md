# Resumed Word proofing session verification

This record covers the resumed controller/session implementation and the fix for
inherited comment proofing properties. All commands passed on the same captured
source files. It does not claim browser execution, mobile spelling availability,
or a complete application acceptance run.

- **28 session/controller tests passed.** These cover modeled stories, nested
  blocks, language/noProof segmentation, Unicode offsets, stale asynchronous
  results, cache reuse, availability states, protected content, complex
  fields and generated page-number caches, active IME, undo/redo, shortened-correction caret safety, tracked
  replacements, vocabulary ownership, and reference-counted view lifecycle.
- **24 existing engine style/comment regressions passed.** These cover style
  inheritance, native comment threads, style introduction, and styleless import
  fidelity following the change to load comments before applying the style
  cascade.
- **Strict scoped analysis passed with no issues.** The exact file list and
  commands are in `receipt.json`.

`source-sha256.json.gz` records hashes of the editor and engine Dart libraries,
the relevant tests, workspace manifests, and lockfile before validation. The
runner compared them again after all commands and observed no changes. The
receipt includes individual implementation hashes, the parent commit visible at
start, runtime command paths, relevant environment settings, durations, exit
codes, and log hashes. A clean parent commit is not claimed: these hashes bind
the evidence to the tested worktree while the integration checkpoint was being
prepared.

The authored DOCX regression verifies inherited `de-CH` and `noProof`, a
character-style `noProof=false` override, a direct `de-AT` override, exact issue
positions, and the same results after serialization and reopening. Imported
body/table/frame/note/header/footer properties use the existing style cascade;
comments now participate in it as well. The document language remains a live
fallback for untagged runs.

## Intentional boundaries

Opaque blocks, opaque inlines, and preserved unmodeled header/footer stories
are counted as unchecked and prevent a complete-clean claim. Generated field
caches, TOC text, explicit noProof spans, and pending tracked deletions are
excluded from proofreading with a separate count. Protected text can still be
reviewed, but a correction cannot bypass document restrictions, native content
locks, active IME composition, generated fields, or overlapping pending tracked
changes.

A result can be corrected in any modeled story. Canvas navigation currently
reveals body and comment paragraphs; note and header/footer result navigation
is disabled explicitly. Hosts persisting user vocabulary own its storage and
must match the snapshot owner. Hosts that mutate the model directly must call
`proofing.invalidate()` to update display eligibility; correction, ignore, and
selection actions still perform fresh full-source validation. Normal controller
commands invalidate automatically.
