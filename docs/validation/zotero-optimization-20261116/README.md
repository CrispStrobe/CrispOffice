# Zotero refresh and native-session optimization

## Qualified source

The final implementation is commit
`0dd09811b1c02514c32c33bd13744dadb202e7af` on
`codex/zotero-optimization-20261116`. Later commits in this delivery add
documentation and evidence. CrispCloud consumes these exact shared engine and
editor bytes through its guarded Office manifest.

This work preserves the existing native picker, first-use document preferences,
CSL formatting, saved searches, small capitals, bibliography paragraphs and
DOCX roundtrip support. It improves two existing paths: basic citation metadata
refresh and native field/note processing.

## Changes and behavior

`ZoteroClient.metadataItems()` retrieves 1–50 selected sources with
`format=json`, `include=data,csljson`, the exact `itemKey` selection and an
explicit limit. The response must contain the exact requested set, with unique
keys and matching durable source URIs. Results are immutable and retain request
order. Missing, duplicate, additional or substituted records refuse the entire
result. Existing export/bibliography validation reuses the same verified parser.

The shared editor groups basic-refresh sources by durable library scope. Fifty
sources from one library now need **one metadata request instead of fifty**.
Repeated citations share the request; identical keys in personal/group libraries
remain distinct. The existing 50-distinct-source operation bound remains.
All batches are staged until every source has CSL data and the original edit
target still matches. Missing data in a later library leaves earlier results
unapplied. The operation remains one undo step, retaining citation IDs, original
URI aliases, locators, affixes and unknown native JSON members.

Native citing sessions index field IDs, body paragraph identities, separate
footnote/endnote ID buckets and original field counts per note. A field-list
response calculates note order once. Every later response rebuilds it from the
current staged state, so insertions, deletions and conversions cannot reuse
stale note positions. Deep validation matches original fields through identity
and content counts, consuming each occurrence once while retaining editability,
document-preference and current-document checks.

The batch request contract is documented by Zotero's
[Web API basics](https://www.zotero.org/support/dev/web_api/v3/basics) and
[local API](https://www.zotero.org/support/dev/web_api/v3/local_api).
Metadata identity is proved in the same response, so the operation does not
depend on the newer database/version headers required for a separate raw export.
An available desktop database pin continues to be enforced.

## Final local qualification

| Executed cohort | Passed |
| --- | ---: |
| Native citing, bibliography layout, preferences and rich-field editing | 119 |
| Catalog, identity, saved searches and batch metadata | 81 |
| All nine shared editor Zotero controller, format and dialog suites | 164 |
| **Unique canonical tests** | **364** |
| Strict analysis of all six changed Dart targets | Clean |
| Declared Dart 3.12 formatting | Six files, zero changes |
| Whitespace check | Clean |

The final [receipt](final/receipt.json) records the exact source, commands,
disjoint test lists and logs. All **1,575** canonical source/dependency hashes,
HEAD and both genuine harness input sets remained unchanged. The aggregate
source SHA-256 is
`742b06bc08b5e7a27324d7e4b5824f6b10c0a99879004e91ebab36ac8c36d95e`.
The before/after source maps are preserved losslessly as gzip JSON; the receipt
refers to their uncompressed content. Earlier overlapping runs do not contribute
to the final total. The initial formatting-gate attempt remains in
`final/pre-format/` with its original result.

New regressions exercise a 720-field body/table/footnote/endnote document;
reading order with ordinary explanatory notes; duplicate note identities;
insert/delete/convert sequences; unknown and deleted field IDs; equal-looking
fields in different paragraphs; 50 sources plus a repeated citation; zero
requests for 51 distinct sources; cross-library key reuse; wrong local profiles;
missing records/CSL in a later batch; and a changed edit target between batches.

The official local runtime was Flutter **3.47.8**, Dart **3.13.7**, framework
`737ba8f885dc774b53b442759999a312c9461e4e` and engine
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`. Genuine dependency graphs were
resolved with their original enforced locks. Production manifests and
constraints were not changed. The [setup receipt](setup/receipt.json) records
the runtime and reconstruction inputs.

Reconstruct the harnesses using the existing
[setup scripts](../zotero-continuation-20261116/setup/), then use
[run-final-editor-checks.py](final/run-final-editor-checks.py). Its command-line
arguments select the checkout, engine/editor harnesses, runtime and output
directory; run `--help` before choosing paths. Keep temporary analysis package
configuration outside source control. The runner restores any original config.

## Native benchmark

The [benchmark report](benchmark/README.md) preserves the exact fixture,
original raw measurements, source/dependency manifests and reproduction runner.
It isolates the native session file: the baseline uses the same engine tree
with only that file restored from `428679a3`.

For **2,400 fields and 1,600 notes**, median field enumeration decreased from
**228.704 ms to 1.773 ms** and five complete selection passes decreased from
**115.496 ms to 1.639 ms**. Full protocol snapshot hashes were identical at
300, 1,200 and 2,400 fields. Full validation and construction remain dominated
by other work: validation was 83.643 → 79.806 ms; construction was
165.762 → 179.471 ms. These are local synthetic JIT measurements, with five
samples after warmup; they do not claim overall application or live Zotero
speedups. No timing threshold is used as a test gate.

The measured source was `91c725f`; `0dd0981` changes only formatter wrapping in
the native source/test. Both exact target hashes are retained in the report.

## Incoming work and checkpoints

The [ref inventory](incoming-refs.json) records all 35 incoming Quds branch
heads and 55 advertised PR heads, plus this new branch. The integration starts
from retained Office/Zotero source `be2c3a91`, preserving Zotero PR #50, and
merges main `6c2e3d17` through PR #55. PRs #51–55 are patch-equivalent squash
heads; `git cherry` evidence records their equivalence. The older ODS vendor
draft is superseded by the audited successor with bounded range expansion and
quoted-sheet-name handling. Upstream main `15c5d29b` is already an ancestor.

CrispCloud's companion branch includes all 44 incoming branch heads and 156
advertised PR heads at its recorded cutoff. A refresh additionally preserved
terminal optimization `50107514` and recovery evidence `3fb3eed4` with both
parents. Original shared branches were not rewritten. The companion audit
records its exact integration source and cutoff.

Implementation and consolidation checkpoints were saved remotely throughout
the work, with `[skip ci]`. GitHub Actions were not queried, awaited or rerun.

## Scope

This pass qualifies focused engine/editor and companion host behavior locally.
It does not claim a new full application build, a new live Zotero acceptance
run, private-account/keychain acceptance, or Microsoft Word/LibreOffice
interoperability run. Earlier live desktop and compiled Studio results remain
available under their separately identified
[fidelity evidence](../zotero-fidelity-20261116/README.md). Native unsupported
stories, unsafe note conversions and active ODT transfer retain their existing
boundaries. The basic-refresh 50-source bound is unchanged.
