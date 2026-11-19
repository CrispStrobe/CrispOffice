# Language review, downloads and DOCX revisions — 2026-11-19

Base: `caf378f4` on upstream main. No GitHub Actions jobs or status queues were
queried or awaited.

## Cause and behavior

The service already checks `supportsLanguage` before invoking a provider. It
retains an `unsupported` result for diagnostics. The nonmodal review pane was
mistakenly displaying these results as red failures, even alongside a successful
English checker. It now omits those unrelated-language diagnostics; genuine
failures and missing coverage remain visible.

The neutral English demo did not set its document language and could inherit
German. It now declares `en-GB`, including through a real DOCX byte round trip.
The English Harper checker is bundled; downloading German or Arabic resources
is not required to check English text.

## Downloads

CrispOffice exposes **Language downloads** from Settings, the Review ribbon and
the review pane. Changing a selection/paragraph language, document default or
applying detected languages invokes host-owned support review after a valid
edit. Stale edits, no-op edits and Undo never request downloads. Clearing an
explicit language reports the newly inherited language.

The support review explains included checkers, optional analysis and unavailable
language support. In particular, English/French spaCy analysis is not advertised
as a spelling or grammar checker. Nothing downloads on language changes, dialog
opening, refresh or **Not now**. **Review / install** opens the existing explicit
package review with sizes, immutable sources, hashes, licences and cancellation.

The inventory covers Hunspell dictionaries, Arabic morphology, the German spaCy
package, additional English/French models and optional German named entities.
App-owned installed data can be removed independently. NER presence is verified
separately from its enabled preference, so disabled or damaged NER data can also
be removed. Model deletion validates the content-addressed identity and rejects
redirected storage. Shared runtimes are retained when removing a language model.
Bundled files are part of the application and are identified separately; the
manager does not edit signed application resources or delete developer files.

The editor exposes optional host callbacks rather than performing network I/O.
Other embedding applications can provide their own catalogue and consent UI.

## Word DOCX tracked changes

Existing `w:ins` / `w:del` text revision import, display, accept/reject and export
are implemented, including author/date and paragraph ownership in body, tables,
headers, footers and notes. The revision tests exercise repeated DOCX saves,
exact ranges, links and atomic-field boundaries. This qualifies text insertions
and deletions; it does not claim complete Word support for tracked formatting,
tracked moves or table-property changes.

## Verification

The combined local acceptance command passed **128 tests**, with no skips:
DOCX revision import/export and validation, live review/accept/reject surfaces,
text-language controls and routing, the demo DOCX language, real workspace
support-review flow, no eager downloads, package setup/licences/cancellation,
independent removal, disabled NER removal and filesystem deletion guards.
Analysis of the changed production files and new tests passed with no issues.
The real native Harper worker additionally passed 21 tests. An en-GB smoke
check accepted a valid English sentence, found a deliberate article error, and
checked all ten English demo paragraphs; see [native-en-GB.json](native-en-GB.json).
The Harper artifact was reused only after matching every recorded source hash
and every artifact hash to its build receipt. The other native libraries were
built locally. The separate sandboxed arm64 preview passed deep signature verification and
a 20-second startup, including loading the bundled 109-label language detector.
See [acceptance.json](acceptance.json). It has a unique app identity and does
not replace the installed application.

## Incoming bundled macOS runtime follow-up

Integrated main through `9ceb994d` (PRs #213 and #214). The macOS preview now
contains the signed spaCy native library with a sealed digest descriptor and
complete runtime notices. The manager offers data-only installs when that
runtime is bundled. These data downloads still require the existing explicit
review/consent. No Python runtime, daemon or downloaded executable is used.

A further 24 Studio tests, 32 spaCy unit tests and five CrispCloud host tests
passed. The explicit native bundle gate passed against an isolated scratch
installation: real German and English models, lemmas, POS and named entities
through the worker isolate. It asserted no executable package download directory
was created. The separate arm64 Runtime Preview passed deep signature validation
and a 20-second startup. See [bundled-runtime-acceptance.json](bundled-runtime-acceptance.json)
and [native gate output](bundled-runtime-native-gate.txt). Existing open previews
and user documents were not replaced.

## Independent DOCX reader/writer check

The locally installed LibreOffice Writer imported and re-saved the tracked-story
fixture in a separate headless profile. Quds imported that DOCX, preserved all
14 linked body and six header/footer story insertions/deletions with their
author/date, exported and reopened it, and resolved every change with both
accept-all and reject-all. The synthetic fixture's notes and comments have no
body anchors; Writer omits those unreferenced stories. They are not included in
this external-reader claim. Native Quds tests separately qualify those stories.
Three comment tests passed, including range anchors, replies and resolved state.

See [external-reader receipt](docx-writer-acceptance.json) and the
[check script](docx-writer-check.dart). This was **LibreOffice, not Microsoft
Word**; a Microsoft Word application round trip has not been performed.
PR #215's first-analysis saved-setup verification also passed all 15 setup tests.

Final preview source is `088d8090`, incorporating PR #215. It passed the
20-second startup/signature check and the native German/English worker gate
against its own bundled runtime. See [final preview receipt](final-preview-acceptance.json)
and [final native gate](final-native-gate.txt). Model tests use a scratch data
root; no real user download preferences or datasets were changed.
