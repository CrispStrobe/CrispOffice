# Incoming review after the saved Mail checkpoint

Base: `eafcd80fdfbd7ff678a7a04fb9a9a98b5330ad00`.

The captured origin advertisement found 211 external fork branches and 174
external PR heads; the separate upstream advertisement contains four branches.
All four upstream heads are unchanged. Two external branch/PR pairs advanced:

| Branch / PR | Captured head | New commits |
| --- | --- | --- |
| Offline thesaurus / #174 | `39843ed4874c7b56572c7aa8195716e5892aeca2` | `fa0cd40d6a46767c800546aa2e894eec6567433a`, `39843ed4874c7b56572c7aa8195716e5892aeca2` |
| Zotero word parity / #173 | `17ec8cc8d241c76a753efb69893682c76683db04` | `17ec8cc8d241c76a753efb69893682c76683db04` |

The baseline audit reverified all 14 historical equivalences. Four of the 389
external refs require these two heads; every other captured ref is accounted for.

## Resolution recommendation

Merge the fixed thesaurus head, then the fixed Zotero head. Git merge-tree reports
conflicts only in the editor changelog and Zotero Notes selection helper. It also
would apply the thesaurus branch's alternative document-pane key choice and
semantically equivalent fixture/comment rewrites. Preserve these five complete
files from the saved Mail checkpoint:

- `packages/quds_office_editor/lib/src/embed/office_editors.dart`
- `packages/quds_office_editor/test/word_notes_proofing_controller_test.dart`
- `packages/quds_office_editor/test/word_notes_proofing_pane_test.dart`
- `packages/quds_office_editor/test/word_zotero_notes_pane_test.dart`
- `packages/quds_office_editor/CHANGELOG.md`

The incoming thesaurus evidence explicitly treats the document-pane GlobalKey as
redundant with the stable Flex layout. Retaining the existing key avoids an
unnecessary application change; the omitted key is not asserted to be a proven
regression. Both test variants retain the same focus/selection behavior and the
two stronger tracked-revision assertions. The current changelog already retains
all entries once. Keep coherent current helper variables rather than mixing
conflict fragments.

The resulting incoming integration should change only `docs/` evidence and prose.
The Zotero merge is clean and documentation-only. Confirm these expectations
against the actual integration tree, then rerun `audit_refs.py` against its HEAD.
No new suite is required by these preserved resolutions; the existing 72-suite
Office plan remains selected. Historical thesaurus/Zotero results remain bound
to their original sources and are not new passes for the continued Mail work.

## Reproduction

Run the copied audit with `--repo` set to the restored repository and
`--capture-dir` set to this directory. The audit compares this capture to the saved
`mail-native-20261119` capture, while rechecking the established historical proofs.
`baseline-audit.json` intentionally reports four unaccounted refs before merges.
An actual post-merge audit should report zero.

The audit used read-only Git advertisements and merge-tree object simulation.
It did not alter tracked source, create commits, write remote refs, or query any
GitHub Actions workflow, job, check, or status.
