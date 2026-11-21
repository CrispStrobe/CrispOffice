# Editable ODT note-numbering supplement — 2026-11-21

Independent reconciliation of the editable Zotero exporter found two note-label
changes in an actual LibreOfficeDev 26.8.0.0.alpha0 save. This supplements the
[original exporter record](../zotero-editable-odt-20261121/README.md); it does not
replace that record or claim installed Zotero-plugin acceptance.

The original `table-notes` acceptance fixture exported decimal footnote/endnote
labels `[1, 1]`, but Writer saved `[1, i]`. Automatic endnotes lacked an explicit
ODF numbering configuration. The editable path now declares decimal numbering
for each emitted note class. A second fixture with an uncited Roman endnote and
a subsequent cited decimal endnote changed `[i, 2]` to `[i, 1]`: fixed ODF labels
do not advance the automatic counter. The exporter now counts only automatic
ODF notes and refuses a cited note when its required label cannot be retained.
The source document remains unchanged; ordinary cached-result ODT export keeps
its existing behavior.

The lifecycle regression verifies the declared decimal formats and unchanged
refusal of the mixed sequence. The converter acceptance tool now includes note
classes and labels in its exact comparison, so the original fixture fails the
expanded check before the correction and passes afterwards. Actual Writer saves
now retain `[1, 1]`, all seven field records, their owners, and preferences across
the two acceptance files.

## Executed checks

- Before this correction: 132 engine tests passed across the new writer and
  lifecycle suites plus existing ODT reader, writer, and merged-table suites.
- After the correction: 48 tests passed across the editable writer, lifecycle,
  and ordinary writer suites; no failures or skips. These overlap the first gate.
- Studio export: 5 tests passed. Editor merged-table loading: 3 tests passed.
  These ran before the engine-only numbering correction. The initial parallel
  Studio compiler terminated; a direct Flutter-tools retry passed all assertions.
- Both initial engine/Studio analysis gates and the final three-file analysis
  passed with `--fatal-infos`. Scoped formatting completed successfully.
- The actual converter comparison passed both generated documents after the
  correction. Flutter 3.47.8 / Dart 3.13.7 and locked offline dependencies were used.

The [receipt](receipt.json) records exact commands, file hashes, test counts and
consumer version. [Execution evidence](execution.tar.gz) contains the original
failing regression, passing logs, synthetic before/after ODTs, expected
inventories, and the mixed-numbering reproduction. GitHub Actions were not used.
