# Zotero note formatting: LibreOffice converter cohort, before direction IO fix

This cohort uses the actual installed `LibreOfficeDev 26.8.0.0.alpha0 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5` headless converter. It does not exercise an installed Zotero or Word integration plugin, and this development LibreOffice build is not a stable-release qualification.

## Fixtures and input attribution

`fixture.dart` drives the real Quds Zotero citing session, including temporary field insertion/deletion, rich note insertion, conversion of two placeholders in reverse requested order, complete, and apply. The same authored rich note is inserted into the main body, an existing authored footnote, and a supported table cell. It includes an LTR heading, RTL and LTR paragraphs, matching exported padding and 30/60/90 pt indentation, left/right/center/justify alignment, an empty explicitly LTR paragraph, two active citation payloads, and document preferences. Foreground RGB and nonstandard opaque RGB highlights appear in separate LTR/RTL runs. Expected snapshots are captured from the native documents before exporting either format.

`inputs-before.json` and `inputs-after.json` hash 22,035 source, manifest, package-configuration, dependency, generator, and Dart runtime files. They are identical. `summary.json` records their equality and the cohort counts. Converted files, expected snapshots, raw native results, and XML findings are retained without rewriting them to pass.

## Results

All 12 actual save operations succeeded: three fixtures, two formats, and two LibreOffice save cycles per format. All six original files passed the native reopen checker. Independent XML checks passed all nine ODT files and found physical RTL indentation differences in all nine DOCX files, including the three original exports. Native reopening of the six LibreOffice DOCX outputs found two additional differences: the empty LTR paragraph's `jc=end` becomes left alignment, and both citation result packets become guarded against native editing. The six LibreOffice ODT outputs were refused by the existing outline-style guards.

The DOCX RTL indentation issue is real despite the original native roundtrip passing: the writer and reader use the same physical/logical mapping error. `direction-evidence.json` records primary specification references and converter geometry. The centered RTL TAIL run has center x=312.581 pt in the original DOCX and x=282.599 pt in the corresponding ODT; the approximately 30 pt displacement corresponds to applying the 30 pt indent on the opposite side. The second LibreOffice DOCX cycle retains the original DOCX geometry. All rendered PDFs are retained in `pdf-probe`.

The citation editability difference is independent of the new highlight serialization. `field-diagnosis.json` shows valid, unlocked, nonnested, single-paragraph fields with `opaqueMetadata=true`. LibreOffice adds run properties to instruction/separate/end field boundaries. The existing `_OpenField.addBoundary` guard considers any such properties opaque. These particular boundary properties contain font, style, color, size, and direction data, with no highlight/shading element.

The ODT cycle-one guard reports `Numbered or positioned ODT outlines are not supported.` Cycle two reports `Unsupported ODT outline-level-style attribute: loext:num-list-format`. Independent XML inspection still verifies the preserved content markers, physical paragraph formatting, colors, two balanced reference-mark ranges with exact citation data, story ownership, and raw document preferences (`ReferenceMark` field type). This does not establish native reopen or plugin refresh acceptance.

`xml-initial-results.json` and `xml-initial-check.log` retain an early verifier development run. The final `check_xml.py` corrects ODT spaces, nested note ownership, inherited text styles, and direction-relative margins; `xml-results.json` is the authoritative independent inspection. No original or converted fixture was changed during verifier development.

## Reproduction

Source `/workspace/scratch/eba1aedcc131/toolchains/env.sh`. Use the repository's existing `.dart_tool/package_config.json`, not a modified dependency graph. From this directory, run:

```sh
python capture_inputs.py inputs-before.json
dart --packages=/workspace/scratch/eba1aedcc131/quds_office_suite/.dart_tool/package_config.json fixture.dart generate original
python convert.py
python check_native.py
python check_xml.py
python capture_inputs.py inputs-after.json
/opt/codex/runtimes/codex-primary-runtime/dependencies/python/bin/python3 geometry_probe.py
```

`convert.py` captures the exact conversion commands and logs, including isolated profiles. `check_native.py` compiles the unchanged generator/checker with the real Dart runtime before checking all 18 documents. `geometry_probe.py` records its exact PDF conversion commands. Transient LibreOffice profiles and the compiled kernel are omitted from the compact evidence archive. This before-fix cohort is preserved separately from the later verification of corrected IO.
