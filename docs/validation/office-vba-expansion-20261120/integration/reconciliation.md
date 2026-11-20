# Captured incoming work and reconciliation

This is a point-in-time inclusion and source-preservation audit. It does not
claim that every incoming application feature passed a runtime gate here.
GitHub Actions was neither queried nor awaited.

## Captured scope

The initial fork baseline was `3ffa599ff003a6e678260df1237b01887693e546`
(PR #245). [Initial inventory](initial-inventory.json) records 23 fetched branch
refs, including this run's checkpoint branch and the duplicate
`work/mail-forward-host-tests-20261120` head, and 247 PR heads. Against that
baseline, nine branch refs and three PR heads required reconciliation; these
represented eight unique heads and four minimal integration heads.

The integration checkpoint
`9e0d8173fada4ae3f22ace5c5b896c21ab5191da` accounts for all captured refs:
**14 branches are ancestors and nine have verified historical equivalents;
233 PR heads are ancestors and 14 have verified historical equivalents.**
All four fetched upstream heads are ancestors. The
[captured inclusion receipt](captured-inclusion.json) contains every exact ref,
comparison base, object identity, historical proof and upstream SHA. It is not a
claim about branches or commits created after this capture.

## Exact incoming heads

| Captured branch | Exact head | Disposition |
| --- | --- | --- |
| `work/mail-body-projection-20261120` | `56e1f58c19bbffc00465b8e4e48fa8fbca0c2015` | Included through `f761cfe6`; adds bounded body-only Mail text projection and carries the recent Mail/Downloads integrations. |
| `fix/mail-credential-stores-chrome-20261120` | `a71a7f19e7146a19ecf79122477210fd71afb51b` | Included through `b6d6a26d`; preserves selectable native credential stores, account identity, workspace chrome and reader changes. |
| `perf/incremental-layout-20261120` / PR #247 | `a66657ab4501e2a77852aa55a61d8b75aee60dec` | Included as a parent of `9e0d8173`; local engine differential qualification described below. |
| `integrate/recent-pptx` | `4f5c153774ab7492430c2b68653c54e0c08dc2ad` | Included as a parent of `9e0d8173`; its alternate Downloads/font-row integration is reconciled with the accepted canonical implementation. |

The Mail body head also includes exact heads
`f7bf155337b0ba77dc20c6be548ef38ac06c5c65` (Zotero research-tables branch's
integration checkpoint), `ceb2f5308a9b5edfea200294cbb5d62b728cf7d4` (reply/forward
scope checkpoint and duplicate host-test branch),
`a059c0249a25bef602640c8b8d504bd8da41c619` (Mail accounts, PR #243), and
`84d02025fade09c80f3f58942b466f4522eb4434` (Downloads, PR #242). The captured
research-tables head contains integration work; no new research-table feature is
claimed from that head. Both Mail integration heads leave the baseline engine
tree unchanged. Credential dependencies add `shared_preferences` packages and
raise the lockfile's Flutter minimum to 3.47; existing engine dependency versions
remain unchanged.

## Downloads reconciliation

Five overlapping files use the newer catalog-based font rows, corresponding
localized strings, manager, test fixtures and expanded layout tests. This keeps
Fonts grouping, row icons, licence/status data, review-before-install and removal
while retaining later fixes for host busy/error states, installed-pack Details,
actual installed sizes, package descriptions, and Arabic prerequisite layout.
The alternate manually assembled font rows are superseded by that implementation.
The alternate wrapper's optional `StudioFontPackHost? fontPacks` argument is
retained as an additive follow-up, with the existing global host as its default.
The widget's injected-host API remains available.

The remaining captured incoming changes are preserved through normal merge
ancestry. The credential and Mail UI test results described by their authors are
incoming evidence, not local results from this run. Flutter UI/controller tests,
platform keychains, native signing and live mail providers were not run here.

## Historical equivalents

The prior audit's mappings were independently rechecked with read-only Git:
the accepted commit must be an ancestor of this checkpoint, and every path
changed by the historical head from its recorded comparison base must have the
same Git mode, type and object ID in the accepted ancestor. All 14 proofs pass;
13 also have identical complete trees. The ODT field continuation has exact
changed-path entries without whole-tree identity. This proves historical
inclusion, rather than requiring later evolved source to equal old branches.
Full hashes and path-entry digests are in the JSON receipt.

| Historical PR | Historical head | Accepted ancestor | Changed paths | Whole tree equal |
| --- | --- | --- | ---: | --- |
| #140 | `c34945761e79` | `2c47165d01d0` | 37 | No; changed paths exact |
| #136 | `58fdddfbcf19` | `4eaca83b1928` | 1 | Yes |
| #142 | `69d14f84cabd` | `52c73ae4dbad` | 1 | Yes |
| #135 | `74ce9ffb816c` | `4584d5f319aa` | 7 | Yes |
| #141 | `0a53b8a70128` | `b3f41eb4b4bc` | 8 | Yes |
| #137 | `68a0db23408e` | `d754bf15b07a` | 4 | Yes |
| #145 | `005c708e9f74` | `c84d5e16024c` | 7 | Yes |
| #151 | `7ef09f2408f4` | `34dc6b680686` | 7 | Yes |
| #149 | `3abf8f43b0e7` | `4b2b4e78839d` | 221 | Yes |
| #134 | `128a187d6955` | `d790bca444ee` | 1 | Yes |
| #138 | `b8ddaaeb581e` | `d6010059644b` | 1 | Yes |
| #146 | `a7f144cc983f` | `0ff7d23929e4` | 1 | Yes |
| #147 | `cee6e2632f89` | `bb5556e8cc4c` | 105 | Yes |
| #152 | `da9c956ec5d6` | `23f3b4204fce` | 79 | Yes |

## Independent local Word layout qualification

[Receipt](layout/receipt.json), [raw passing log](layout/passed.log), and
[source manifest](layout/source-manifest.json) record **10 passing tests, zero
failed/skipped tests, and 302 exact comparisons with a fresh full layout**.
The standalone test is
`packages/quds_office_engine/test/word_incremental_layout_differential_test.dart`.
Its public geometry snapshot is independent of the incoming production
`wordLayoutFingerprint` helper.

The cases assert real convergence and bounded block work, then exercise six
seeded 48-edit sequences through mixed Latin/Arabic/emoji text, run and paragraph
formatting, insertions, deletions, reordering, simultaneous paragraph edits,
nested tables, wrapping frames, continuous sections, columns/separators,
first/even/default headers, footer page numbers and line numbers. Separate cases
verify footnote/endnote fallback, discarded state and changed section lists.

Execution used Dart 3.13.7 on the VM with the source compiler and pure Dart
fallback metrics. The engine library tree was
`882cee381d42a4929b0b83a11e796860a337d900`; all 350 recorded inputs remained
unchanged from the manifest captured during test loading through completion.
The initial runner launch could not create its default `/tmp` directory, loaded
no tests, and is excluded from the passing result. A writable scratch `TMPDIR`
resolved that environment issue. No installed Word or Flutter font/controller
comparison is claimed. Future VBA changes need their own final combined gate.
