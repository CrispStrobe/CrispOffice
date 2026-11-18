# Thesaurus release acceptance

**Status: open.** Headless tests, source verification and web compilation do not
complete any of the three gates below. Record actual results against an exact
build and preserve failed attempts. Leave a case unassessed when its required
device, input method or reviewer is unavailable.

## Actual offline browser

Use the [fixture replay instructions](../../validation/thesaurus-20261118/continuation/local/README.md)
on a host that can launch Chromium. Retain the successful compile receipt,
source inventory, compiled-file inventory and compile logs with the browser
receipt. The current runner requires `--compile-receipt`; older compilation
receipts do not qualify a changed fixture. Compile with the pinned SDK and
`--pwa-strategy=none` so Flutter's own worker cannot replace the test worker.

The runner must complete installation and verify every cached asset, disable
network access, stop the HTTP origin, reload into a fresh fixture session, and
exercise English/German replacement, undo/redo and source notices. Its final
panel runs in a fresh offline tab. Retain browser/version, CSP violations,
console/page errors, request records, cache verification, screenshots and
timings. An unsuccessful browser launch is a blocked result, not a pass.

This worker qualifies the bundled fixture only. Production distribution needs
its own installer/update, cache storage, eviction and upgrade acceptance against
the actual shipped origin and cache policy. Do not promote the test worker to
an application deployment merely to close this gate.

## Installed native desktop

The Studio example has checked-in Linux and Windows runners under
`packages/quds_office_editor/example`. On the matching fully provisioned host,
resolve the committed workspace lock using Flutter from `.fvmrc`, then build
the release target from that example directory (`flutter build linux --release`
or `flutter build windows --release`). Build and install the intended release
artifact; a headless test or debug session is insufficient.

Record the commit, SDK, OS/version, architecture, packaging command, package and
executable SHA-256, install path, window/display scale and keyboard/input-method
versions. Launch the installed copy outside the source checkout, with the
checkout unavailable and network disabled. Preserve the whole asset bundle,
including both language packs and their notices.

Verify the installed pack bytes with the existing verifier. For a Linux Flutter
bundle, the pack root is normally
`data/flutter_assets/packages/quds_office_editor/assets/thesaurus` beneath the
installed bundle; inspect and record the actual path before using it.

```sh
python3 tools/thesaurus/verify_packs.py \
  --packs /absolute/installed/bundle/data/flutter_assets/packages/quds_office_editor/assets/thesaurus \
  --output /absolute/new-evidence/installed-pack-verification.json
```

The verifier checks source integrity. It does not establish application
execution, OS input behavior or human assessment of lexical usefulness.

| Case | Action in the installed application | Required observation |
| --- | --- | --- |
| Cold launch | Launch offline after closing every application process. | Editor and both language packs work without the repository or downloads. |
| Entry points | Look up a selection and a word at the caret through Review, the context menu and Shift+F7; repeat with the Review pane focused. | Same intended source is captured; lookup creates no edit or undo entry. |
| English meanings | Query `bank`, `run` and `ice cream`. | Separate source meanings, examples and available labels are readable; related concepts remain distinct from alternatives. |
| German forms | Query `Bank`, `Häusern`, `Maße`, `Masse` and `sich freuen`. | Ambiguous meanings remain separate; umlauts and ß remain meaningful; parentheticals remain literal. |
| Lookup override | Change **Look up in**, close and reopen the dialog, and inspect document language. | Lookup language does not silently change document language. |
| Replace and history | Select a returned alternative, press Replace, undo once and redo once. | Only the captured target changes; each operation restores text, selection and formatting. |
| Rich text | Repeat in a supported formatted target with hyperlink, bookmark/comment anchors and tracked changes. | Supported metadata and anchors survive replacement and history; rejected targets remain unchanged. |
| Stale target | Keep a lookup open while changing its target through another permitted editor surface; attempt replacement. | Stale results cannot replace changed text or selection/language. Record whether the host permits the scenario. |
| Protection | Repeat on read-only/protected or generated content. | Inspection remains available where supported; forbidden replacement changes neither content nor history. |
| Real OS composition | Start actual IME composition, invoke Shift+F7, finish composition and try again. | Refusal leaves composing text/range, focus and undo state intact; completed text can then be looked up. Record the actual IME, not a simulated value. |
| Shortcut separation | Exercise plain F7, Alt+F7 and Alt+Shift+F7, with/without a modal. | Writing review retains its own behavior and cannot act behind a covered modal. |
| Narrow/RTL layout | Use a narrow window and increased text/display scale, including Arabic chrome; open the dialog and source notices. | Controls remain reachable, labels readable and attributions complete. Record dimensions and scale. |
| Missing or damaged pack | In a disposable installed copy, remove or corrupt a pack asset and restart; restore the original asset and retry. | Missing/failed verification is distinct from no entry; failed data cannot replace text; repaired data can be retried. |
| Relaunch and notices | Restart offline, query both languages and read Sources and licenses. | Verified notices remain available and no source-checkout dependency reappears. |

For every row, record `pass`, `issue` or `not assessed`, an observation and an
evidence path. Copy the table for each OS/input-method combination. A pass on
one platform does not establish another. Keep known failures open until the
fixed build is exercised again.

## Independent linguistic review

Export a new packet from the native report belonging to the build under review:

```sh
python3 tools/thesaurus/export_review_packet.py \
  --report /absolute/new-evidence/native-pack-report.json \
  --output /absolute/new-evidence/linguistic-review
```

The exporter checks observed sense fields against current hashed pack records
and preserves complete source records, examples, term labels and notes. Every
reviewer decision stays blank; existing review directories cannot be overwritten.
The paired Markdown is readable without special tooling; JSON retains complete
identities and evidence hashes. Export success is not a fresh provider run.

An independent reviewer with the relevant English/German expertise must assess
the packet and application, cite sense/term IDs, add regional/domain/unknown-word
cases, and state a bounded recommendation. Review `Jänner`, `Oheim` and `colour`
in the application as extra label cases. Mark untested languages/domains. The
shared German corpus, finite morphology, literal replacements and lack of
automatic agreement remain boundaries even when this review passes.

| Gate | Reviewer/operator | Exact build/evidence | Result |
| --- | --- | --- | --- |
| Actual offline browser | Unassigned | Not recorded | Open |
| Installed native desktop and real OS/IME | Unassigned | Not recorded | Open |
| Independent linguistic review | Unassigned | Not recorded | Open |
