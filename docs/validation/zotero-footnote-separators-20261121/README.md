# Zotero active footnote separators — implementation and qualification

This continuation advances the first remaining milestone in the
[Zotero parity roadmap](../../roadmaps/zotero/word-processor-parity.md): modeled
active footnote separators, consistent pagination and rendering, and native
file persistence. This initial branch record retains the implementation scope
and converter boundaries. The integrated local qualification follow-up below
records completed gates; installed-plugin acceptance remains separate.

## Reconciled starting point

The starting remote main was `52e72ca0b5677549f31742faae457f08df05759b`.
The captured inventory covers nine fork branches, all 346 PR heads, and four
canonical upstream branches. After merging the captured Mail keyboard-triage
planning head, the 359 observations resolve to **345 ancestors and 14 verified
historical replacements**, with zero uncovered observations. The replacements
were rechecked against their full trees or exact changed paths using the
existing reproducible intake verifier; they are not treated as ordinary
ancestry. All recent Zotero, Word, editor and Mail implementation heads are
already represented.

The raw advertised fork/upstream refs, bounded inventory and fresh replay are
under `intake/`. The replay is reproducible with:

```sh
python3 docs/validation/word-vba-numeric-20261121/intake/replay_intake.py \
  --repo . \
  --inventory docs/validation/zotero-footnote-separators-20261121/intake/remote-inventory.json \
  --proofs docs/validation/word-vba-numeric-20261121/intake/historical-proofs.json \
  --head HEAD --output /path/to/replay.json
```

The durable work branch is `codex/zotero-footnote-separators-20261121`.
Its first remote reconciliation checkpoint is
`efabe221abc781c05073b209051e3a1e380b5c05`. Local Git has no write credential;
checkpoints use the authenticated GitHub connector with expected-head,
non-forced ref updates, followed by local fetch/read-back. Ordinary merge
parents preserve incoming ancestry. No remote branch is deleted or rewritten.

## Scope and qualification plan

- A document-wide separator model records both gaps, line thickness, relative
  width, physical alignment, RGB color and solid/hidden line style.
- Native layout reserves exactly the modeled height on pages with footnotes,
  including continuation pages. Editor and PDF draw the supplied geometry.
- The bounded ODT reader accepts explicit supported active geometry and rejects
  unsupported or incompatible used page layouts. Native ODT output emits it.
- DOCX has a separate bounded canonical persistence mapping. Arbitrary imported
  special-note contents retain their existing opaque preservation behavior.
- Focused engine/editor checks, repeated Zotero file lifecycles, strict scoped
  analysis and actual local LibreOffice conversions will be recorded with
  source and runtime identity before publication.

The pinned runtime is Flutter 3.47.8 / Dart 3.13.7. Its official archive and
locked hosted dependencies were verified by SHA-256; the existing workspace
lockfile was enforced without modification. GitHub Actions, checks and status
queues are not part of the acceptance path and are not awaited.

## Observed interoperability boundary

Independent initial LibreOfficeDev 26.8 probes normalize custom DOCX separator
paragraph borders and spacing to the converter's own default rule. This failed
route is retained separately from native DOCX persistence and direct editable
ODT round trips. It cannot establish general Word/LibreOffice parity. Installed
Microsoft Word and live Zotero plugin workflows require their own identified
host qualification; no such run is claimed here.

## Primary format references

- [OASIS OpenDocument 1.4 schema](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part3-schema/OpenDocument-v1.4-os-part3-schema.html),
  `style:footnote-sep` and its geometry attributes.
- [OOXML special footnote references](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.footnotespecialreference?view=openxml-3.0.1).
- [LibreOffice DOCX footnote export](https://github.com/LibreOffice/core/blob/master/sw/source/filter/ww8/docxattributeoutput.cxx).

## Integrated local qualification follow-up

The Word VBA comparison/color integration retained implementation head
`a1b555979b25c5586f27915cf219a95e886febd7` and executed the changed native
separator suites, adjacent note/Zotero persistence, package preservation and
macro atomicity in an 18-file engine gate: **465 passed, zero failures/skips**.
Full engine analysis including macro and Zotero tools is clean. The four
affected editor rendering/note suites passed **64 cases** on pinned Flutter
3.47.8 / Dart 3.13.7, with clean scoped analysis.

A new combined two-case regression applies palette and automatic foreground
macros to a document with an active note and modeled separator, preserves
nondefault special-note IDs/settings through repeated native saves, and proves
whole-run rollback after a late invalid target. Those cases also pass within
the pinned Dart **238-case** macro gate. Exact commands, source identities and
logs are in the [integrated qualification record](../word-vba-comparison-colors-20261121/README.md).

These executions use the retained LibreOffice-produced fixtures; they do not
claim a new converter invocation, installed Word rendering, or a live Zotero
plugin UI session. The external DOCX-to-LibreOffice geometry limitation above
remains explicit.
