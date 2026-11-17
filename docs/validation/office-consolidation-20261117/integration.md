# Integration decisions

## Captured main — `388bd7451067794b58276d174fe05470aa9994ed`

Merged the captured main, including PR #115 table borders/row heights, PR #118
paragraph tabs, and the newer bounded German noun-agreement source, evaluator
tools and source-bound syntax evidence. The merge retained the recovered PAGE,
paragraph-color validation and structured-frame code automatically.

## Parallel Office qualification — `7a9702c3b74e0e905c76fcf467d608bbb852d004`

The paragraph-style conflict was resolved using the already integrated writer:
its strict six-digit color validation, PAGE fixes and newer tab/table support
remain. The incoming color-key implementation is weaker and is superseded by
the recovered normalized identity; it adds no distinct supported behavior.

Both original paragraph-decoration regression suites remain executable. The
20-case recovered suite keeps its path. The incoming two-case suite is retained
byte-for-byte as `test/odt_paragraph_decoration_resume_test.dart` within the
engine package to resolve an add/add path collision.

The section-test conflict differed only in explanatory wording; the recovered
wording and equivalent empty-body assertion remain. The `const` correction is
already present. The incoming qualification documentation, archives and
changelog entries remain, with their original source and runtime attribution.
Historical passes do not qualify this new combined source.

## AOT integration — `8b19ead89800f81ed9743ffbaf3279ac88fdd06d`

Retained the complete optional AOT package, Studio analysis UI, manual-provider
labels, workspace/dependency entries, and historical evidence. The proofing
guide retains both the new noun-agreement section and the AOT section.

The AOT branch carries an earlier reconciliation of the same frame histories.
The recovered `odf_text.dart`, both current extraction test suites, and current
section tests retain the later synthetic-anchor distinction and existing
regressions. An ODP hyperlink assertion differed only by its location in the
same test; its recovered location remains. The changelog retains the recovered
description of structured frame behavior and paragraph-color repairs.

The AOT package source is preserved without adding its historical unrelated
Android URL-launcher lockfile bump to the pinned validation workspace.

## Completed morphology and GECToR evidence

Merged `e67c8090e0bc93eac6b4eb0195461d52e27b7d8e` and
`c98c75eae50ddabfa8eb9aa918ed1af9754b7923`. These remaining deltas complete
historical reports, raw evidence and roadmaps. The proofing guide retains the
new combined-quality section alongside AOT and noun agreement. The only source
test conflict again concerns equivalent empty-document explanatory wording.

## Original and vendor table/tab histories

The original feature, vendor mirror and squash-on-main patches have identical
stable Git patch IDs for each feature; see
[vendor-patch-equivalence.json](vendor-patch-equivalence.json). Both features
and their tests had already arrived through captured main. An explicit
tree-preserving ancestry merge retains the four remaining original/mirror
heads without reapplying duplicate changes. This is not an assertion that all
branch trees are equal: it records equality of these exact feature patches.

All 268 captured external references (179 distinct heads) are included by
ancestry after this checkpoint, before subsequent product repairs.
