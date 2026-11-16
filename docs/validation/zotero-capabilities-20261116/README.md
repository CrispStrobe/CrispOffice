# Zotero capabilities continuation — 16 November 2026

The combined Quds implementation at
[`8e017e8c148517fea61f8d55eaafc7f070b82bba`](https://github.com/CrispStrobe/quds_office_suite/commit/8e017e8c148517fea61f8d55eaafc7f070b82bba)
passed **825 distinct local tests, with zero skips**, after the latest observed
ODS and proofing work was reconciled. Its exact source tree is
`17eecf8b8c8558c78dbbefe9ffc9b1249e2455cf`. Subsequent delivery commits add
documentation and evidence; CrispCloud pins this qualified implementation.

Work is saved incrementally on `codex/zotero-capabilities-20261116` in both
repositories. The previous continuation PRs #56 and #167 were already merged
when this pass started. New checkpoint messages include `[skip ci]`.
**No GitHub Actions jobs, workflow runs or CI status checks were queried,
awaited or rerun.**

## What changed for Zotero

### One embedded source across linked URI aliases

`WordZotero.distinctEmbeddedItems` now provides the shared source selection
used by embedded CSL collection and the basic bibliography formatter. It
joins complete URI alias sets before selecting snapshots, including late and
transitive bridges. For example, citations carrying `[A]`, `[B]` and `[A, B]`
now contribute one bibliography source. A bridge without embedded CSL still
establishes identity, while the first available snapshot is retained exactly.

Canonical library URIs, opaque URIs and offline IDs retain distinct identity
namespaces. Equal bare item keys or CSL IDs across unrelated personal, group
or local-profile sources do not collapse. Malformed or escaped URI paths are
not silently normalized into valid linked identities. Selection does not
rewrite citation fields, locators, URI order or unknown citation metadata.
Regressions include a DOCX roundtrip.

The [isolated behavioral controls](behavioral-controls/README.md) compile the
same fixture against the old and new source. The late-alias example produced
two sources before this fix and one afterward; the before run is an expected
behavioral failure, not a compile failure.

### One field scan for the document tab

The Zotero document tab derives its action availability from the field list
it already read. Opening the real widget on a 1,000-citation document now
performs **one full field scan instead of four**. Bibliography-only documents
still disable citation-dependent actions. This removes repeated traversal
within a build without introducing a persistent document cache.

The same counting-controller fixture was executed against both source pins;
see the [controls and exact request counts](behavioral-controls/README.md).
This is a traversal-count measurement, not an end-to-end latency benchmark.

### Online server pauses survive client replacement

An online `ZoteroSession` now owns a shared `ZoteroBackoffState`. Reconnecting,
replacing a key, selecting another public library, forgetting credentials or
reopening the dialog in the same session preserves the current server pause.
Late responses from an older client cannot shorten a longer deadline. The
state contains only the deadline; it adds no persisted credentials, document
data, timers or automatic retries. Local desktop clients keep independent
state and remain available during an online pause.

This preserves the existing handling of successful `Backoff` responses,
HTTP 429 and applicable `Retry-After` responses across replacement clients,
consistent with the [Zotero API rate-limiting documentation](https://www.zotero.org/support/dev/web_api/v3/basics#rate_limiting).
Custom hosts that construct online clients directly can supply a shared
`backoffState`. The [isolated reconnect control](backoff-controls/README.md)
compiled on both revisions: the old dialog made an unwanted second request,
while the revised dialog retained one request until the deadline expired.

The incoming continuation's verified refresh of up to 1,000 distinct linked
sources, in batches of at most 50 per library, remains in place. The current
cohorts also retain native citing, saved searches, rich fields, bibliography
formatting, local profiles, one-step undo and stale-document guards.

## Concurrent work and source integrity

The [complete incoming audit](incoming-work.md) accounts for **113 observed
Quds/upstream refs**: 111 are ancestors and two have explicit dispositions.
The exact observed refs, fetch evidence, timestamps and preserved initial
inventory are in [incoming-refs.json](incoming-refs.json).

- Main `14b13980`, including ODS hyperlinks through PR #59, and the primary
  proofing continuation `52d6ae43` are integrated. The original hyperlink
  feature/PR head also has retained ancestry.
- The older ODS vendor head `95debbc` is behaviorally superseded by the merged
  feature. Main additionally preserves shared/blank-cell validation and
  correct relationship namespace ordering. The [source comparison](ods-vendor-disposition.md)
  records exact blobs and methods; it does not claim whole-branch patch
  equivalence.
- The alternate proofing resume head `4d395da` contains a competing session
  architecture. Its remote branch is retained. Two demonstrated caret fixes
  were adapted to the integrated model: directional authored soft-hyphen hit
  testing and the generated-hyphen caret endpoint. The [disposition](resume-disposition.md)
  documents nine merge conflicts, the duplicate session produced by a
  diagnostic auto-merge, and the optional transport/packaging changes left on
  that branch. It does not claim every alternate change was merged.

The four new caret regressions use actual `WordLayoutEngine` documents and
fitted painter geometry. Before the fixes, three failed on source offsets or
the visible caret endpoint; afterward all four and seven existing hyphenation
cases pass. Raw controls are retained in `hyphenation-controls/` and are not
added to the final cohort count again.

CrispCloud also retains its current main `f7353bf5`, including the concurrent
keychain-settings and direct-favorites work. Its vendor guard checks **2,468
managed Office files** against the exact Quds pin above. The independent
legacy parser remains at `4895712158127b2fc930d796e17035c3ca0dac62`.
Proofing dictionary/hyphenation sources and notices are included by the
guarded sync, and the host registers the bundled notices. The optional Harper
backend is not added to CrispCloud's runtime dependencies in this increment.

## Final local qualification

| Disjoint canonical cohort | Passed |
| --- | ---: |
| All engine Zotero suites | 390 |
| All editor Zotero suites | 186 |
| Engine proofing and hyphenation | 59 |
| ODS reader integration | 99 |
| Word layout and styles | 31 |
| Editor proofing and platform spelling | 49 |
| Hyphenation painting and caret behavior | 11 |
| **Total** | **825** |

Strict analysis with `--fatal-infos` passes for **12 canonical targets**.
Dart 3.12 formatting passes with zero changes. All **1,505 canonical
source/manifest inputs** match the published source and remain unchanged;
all **3,857 external dependency/runtime inputs** and the locked harness inputs
also remain unchanged. The temporary analyzer configuration was restored.
Runtime: genuine Flutter 3.47.8 / Dart 3.13.7, with unchanged production
dependency constraints.

The [canonical qualification report](final-canonical/README.md),
[execution receipt](final-canonical/receipt.json) and
[artifact inventory](final-canonical/artifact-inventory.json) contain exact
commands, selections, hashes, exit codes and reproduction instructions. The
four large maps are archived losslessly as `.json.gz`; `gzip -dk *.json.gz`
restores the exact JSON filenames and bytes referenced in the receipt.
The runner belongs in `zotero-toolchain/expanded-canonical-qualification` for
reproduction, as described in its README.

The actual host qualification is recorded separately in the
[CrispCloud companion report](https://github.com/CrispStrobe/CrispCloud/blob/codex/zotero-capabilities-20261116/docs/validation/zotero-capabilities-20261116/README.md).
Earlier qualification at `039c1e29`, development runs, setup smokes and
expected-failure controls are preserved separately and excluded from the
final totals. See [pre-concurrent evidence](pre-concurrent-qualification.md).

## Practical limits

These results qualify the listed local engine, widget, integration and host
behaviors. This increment does not establish a fresh full application build,
live account/private-key acceptance, or Microsoft Word/LibreOffice acceptance.
The historical live desktop and terminal/keychain evidence retains its own
source and platform scope; it is not counted as a fresh result here.
