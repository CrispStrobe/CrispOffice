# Current-source suite validation

`validation.json` records the measured source, commands and exact scope. Its
supporting file hashes bind the full logs, dependency resolution and output
inventories. `source-inputs.json` conservatively hashes the tracked package and
validator inputs, plus the generated package configuration and resolved lockfile.

`saved-files.tar.gz` contains 358 engine outputs, 29 editor outputs, the lockfile
and package configuration. `archive-index.json` lists every entry and its exact
SHA-256. Every Office entry was checked against both the committed-inventory
receipt and the independent OpenXML report before the archive was accepted.
All archive entries were read back and checked after creation.

The full editor run includes reviewed visual goldens; its one skip is the
existing optional local-PDF pixel-comparison fixture. The engine result is the
declared fidelity cohort. Neither result claims a newly collected engine
line-coverage percentage or physical-device acceptance.

The separately indexed `../fill/` evidence binds the native fill render results
to an immutable copy of the tested saved bytes. `../controls/` preserves the
unchanged regression tests' original-source failures and fixed-source passes.
