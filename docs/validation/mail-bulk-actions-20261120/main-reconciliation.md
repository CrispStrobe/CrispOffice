# Main rendering/font reconciliation at e975cec1

This record qualifies main commit
`e975cec13b289fe067ef406cd3044701ecc44744` and the corrective source published
at `3f9d3647a20b06c73f5bfd0ade2846e7859e4502`. It supplements the immutable
original mail acceptance archive. A subsequent main advance is a separate
publication reconciliation; this record does not silently extend to later code.

## Preserved history and changes

The original mail acceptance was published at `511990e9`. Main's three-file
rendering/font change was incorporated without conflicts at `75da007c`.
Review and reproducible regression cases then identified defects in the incoming
Word source. Corrections were saved at `d9b86f63` and `3f9d3647`.

- Keep inline header/footer pictures. Deduplicate only the identical model node
  represented in both inline and floating collections, preserving distinct
  images with equal dimensions or shared underlying assets.
- Carry the recorded body-frame prefix across continuous sections, rebuilding
  header/footer decoration separately. Body-bottom calculation uses that same
  provenance, preserving body images and full/incremental layout agreement.
- Include inline header pictures in existing body-clearance calculation. Keep
  main's 4.25-point table padding and correct its obsolete unit comment.
- Use the existing sparse style cascade for first-row run formatting. Remove
  the later repaint that overwrote direct colors, explicit not-bold values,
  child-style overrides and nested-table boundaries.
- Preserve an explicitly declared direct border width when table-style color
  fills an automatic/omitted color. An omitted width still inherits the style.
- Keep compact table spacing in the imported property snapshot so an untouched
  export stays sparse and later style changes still apply. The suspected
  inherited-spacing value override was disproved by tests and was not changed.
- Retain all eight lowercase Arial/Times New Roman filename aliases and
  metadata validation, with canonical-name priority and deduplication tests.

The incoming empty-paragraph border behavior is preserved. No Mail Dart file
changed during this reconciliation.

## Fresh local qualification

| Gate | Actual result |
| --- | ---: |
| Word, 26 VM suites | 961 passed, no failures/skips |
| Word, seven compiled JavaScript/Node suites | 758 passed, no failures/skips |
| Three committed BAS examples | VM and Node passed; parsed JSON identical |
| Six complete mail host suites, fresh single run | 352 passed, no failures/skips |
| Eight host strict analyzer targets | Clean |
| Localized visual tests | 8 passed, 21 PNGs |
| Font loader and canonical/lowercase candidates | 9 passed, strict analysis/format clean |
| Focused header-picture gate | 11 passed, strict analysis/format clean |
| Focused table-style gate and four existing suites | 85 passed, strict analysis/format clean |

The focused Word results are included in the broad Word runs and are not added
to them. VM, Node, host and visual cohorts also overlap. The
[Word summary](final-main-word-summary.md) and
[portable replacement record](final-main-portable-compiler-applicability.json)
describe the fresh executions that replace the previous assembled Word cohorts.

All 492 inputs stayed unchanged through the broad Word run; host and visual
runs respectively bind 1,002 and 1,006 unchanged inputs. The nine font cases
bind their exact loader/metadata/parser/fixture/font-asset scope. The earlier
85-case deserializer gate predates the later layout edit, so its full source map
is preserved as historical qualification; the fresh Word run covers every one
of its suites on the corrected combined source.

Every newly rendered PNG has the same SHA-256 and size as its directly inspected
original. The separate visual comparison record applies the same inspection
findings and limitations by exact byte identity, without claiming a second
direct viewing.

## Honest diagnostics and applicability

The incoming header-picture implementation passed two of eleven new cases and
failed nine. The incoming deserializer passed twelve of twenty-one cases and
failed nine; a separate sparse-spacing export case also failed. Those raw
diagnostics remain separate from the subsequent passing results.

[final-source-applicability.json](final-source-applicability.json) proves that
all 211 Mail Dart paths are unchanged from `511990e9`. Every one of the 268
core/transport and 59 shared-UI input hashes still matches, so their earlier
accepted results remain applicable. The only production differences were the
three explicitly requalified Office files; two also belong to the Word scope.

[acceptance-published-source-binding.json](acceptance-published-source-binding.json)
independently verifies all 1,104 tracked original acceptance inputs directly
from published Git blobs. Three runtime-only configuration/library inputs have
separate hashes and native-assets provenance. The accepted 320-ref frozen intake
target remains an ancestor, so its independently verified historical equivalents
remain accounted for without a new branch/PR scan.

The supplement archive and its manifest preserve raw commands, terminal test
events, source hashes, diagnostics, runners and captures. The original
`evidence.tar.gz` and `evidence-manifest.json` remain byte-for-byte unchanged.
GitHub Actions, workflow runs, checks and status endpoints were never queried
or awaited. No live-account, installed-release or native-browser/WASM gate is
claimed by these local results.
