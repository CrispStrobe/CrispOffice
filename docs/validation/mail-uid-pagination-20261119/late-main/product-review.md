# Late-main product review — 19 November 2026

Reviewed package delta:
`b655b8a37fddc874bd42a453c371eed6253e82d8` →
`b559f6c764fbfac143f593e89ddc1096ad8b5c4e`.

Integration comparison also used the frozen local source
`162f53c0aff2314d88df912f9a64c0838e2a9da4` and the isolated merge
`45f493cca3574b9f89affe2308406e0aed12e2cf` in `quds_late_main`.
This review did not mutate the primary checkout or shared runtime and did not
query GitHub Actions. No tests were executed by this reviewer while the prior
source qualification was running.

## Scope and retention decision

The incoming work adds the T1 Arabic rule extension, a CrispOffice Studio
rebrand, three-language module chrome, and an account-free saved-message Mail
dialog. It also replaces the Al Tahreer document sample and its 35 image assets
with a small product brief. These are intentional incoming features and sample
changes. They should be retained while fixing integration defects; this review
does not qualify or reject individual linguistic prescriptions.

The removed sample's import, image preload, asset declaration, gallery ID, and
workspace reset name have been updated consistently. A repository search of
the incoming tree, excluding historical documentation, found no remaining
references to `assets/al_tahreer`, `al_tahreer_sample.dart`, `AlTahreerSample`,
`SampleLibrary.images`, or `office-tahreer-word`. Existing probes for a developer's
external `al_tahreer_profile.pdf` are unrelated to those deleted bundled assets.
No missing-asset build dependency was identified from this removal.

The Mail addition is a saved `.eml` reader presented in a dialog. It does not
implement account setup, a synchronized mailbox workspace, composition, or
SMTP; those Mail roadmap boundaries remain.

## Concrete findings and repairs

1. **Mail dialog disposal race.** `_open()` resumed after the asynchronous file
   picker and optional file read, then accessed its controller and called
   `setState()` without checking whether the dialog was still mounted. Closing
   the dialog during either wait could therefore update disposed state. The
   narrow repair checks `mounted` after both waits, before controller access or
   replacement. A deferred-picker widget regression closes the real dialog,
   verifies disposal of its existing controller, resolves the selected bytes,
   and checks for no exception or reopened dialog. The separate file-read wait
   is guarded by inspection; that path is not independently delayed by this
   single widget fixture.

2. **New raw Arabic matches bypassed established token boundaries.** The base
   provider's Unicode continuation rules remained present after merging, but
   new phrase, date, and double-future regexes used only Arabic-letter
   boundaries. For example, the new phrase path matched inside `xعلى حدىy`.
   Numeric-year and future-word suffixes had analogous exposure. The repair
   reuses `_wordContinuation` with Unicode regex mode, including end guards.
   The new raw comparison projection also now uses `_comparisonMark`, retaining
   combining hamza and maddah consistently with the existing provider. The
   extension's vocabulary, categories, optional-rule defaults, and existing
   positive fixtures remain intact. Seventeen new compatibility cases cover
   mixed tokens, Unicode boundaries, retained orthographic marks, and exact
   UTF-16 offsets after decomposed spellings.

3. **Stale Studio test labels.** Existing tests still selected `Word`, `Excel`,
   and `PowerPoint`, or expected the previous application title. The incoming UI
   intentionally changes these labels. `incoming_audit` updated those tests in
   the isolated checkout while preserving their behavior assertions; the
   separate label update is commit
   `f57185f5258040180489f842c6c1fd032a4db031`.

The first two repairs and their tests are the four-file commit
`5293c14162087de1044a2341967d74190a9c9b92`. `incoming_audit` independently reviewed
those changes and reported no blocking finding before that commit. This author
does not represent that independent static review as test execution.

## Local qualification required

- Run the incoming `arabic_extended_rules_test.dart` and the existing
  `arabic_writing_rules_test.dart` on both VM and Node, with the other affected
  proofing suites. Retain all earlier mixed-script, decomposed-spelling,
  protected-text, and offset controls.
- Run all 19 Studio `*_test.dart` suites, including the new
  `studio_mail_lifecycle_test.dart`, the corrected navigation tests, PDF gallery
  smoke/faces/showcase tests, document export, and screenshot suites with their
  required assets and environment configured. The intentional sample deletion
  should not be handled by skipping the replacement sample.
- Refresh the local workspace package configuration offline for the example's
  added Mail package dependencies. Run strict analysis and formatting against
  the integrated changed Dart files before claiming qualification.
- Keep the earlier frozen-source result as historical evidence. It cannot
  qualify this late main delta or these subsequent repairs.

One non-blocking description mismatch remains in incoming gallery metadata:
the replacement product brief still has the old Arabic title and a blurb
promising tables, images, and bilingual content. The replacement sample itself
contains English headings and paragraphs. This does not affect the inspected
asset/import consistency, but the gallery description should eventually match
the replacement content.
