# Qualified Mail reconciliation

The exact captured Mail head `177f29d3f9450a58f41189b462b0814aad37e45c` is
preserved as an original parent of published source
`a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1`. Its tree exactly matches the
[reviewed proposal](proposal.json); [publication.json](publication.json) records
the identity and subsequent focused rendering evidence.

The reconciliation adds authored/inherited background state, correct media
ownership and copy/save behavior in three slide implementation files, plus
assertions in two engine test files. Current Word/font, Zotero, theme, geometry,
web, controller and renderer code is preserved as recorded. The existing six
geometry enum values, parser/writer mappings and regression remain exact.

The ordinary recursive merge encountered a missing synthetic virtual-base
object. The proposal instead records a genuine common base, all conflict
resolutions and a deterministic isolated-index tree. No source-side conflict
is silently replaced by an older whole file. The complete implementation diff
is [resolved-product.patch](resolved-product.patch).

On the published combined source, **228 engine/PDF/font cases in 14 files**
and **109 editor-rendering cases in 10 files** pass every original guard.
These repeated populations are not added to earlier qualification totals.
The imported Mail author's 2,049-case report remains separately attributed;
this continuation does not claim to have rerun or recounted all of it.

The known pentagon silhouette limitation and incomplete native Word fidelity
remain disclosed in the [continuation report](../README.md). The captured
newer unfinished VBA branch is outside this completed reconciliation.
