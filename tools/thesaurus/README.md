# Reproducible English/German thesaurus packs

The compiler is an independent MIT implementation using the Python standard
library. It reads only the checked-in, SHA-256-pinned inputs in
`packages/quds_office_engine/third_party/thesaurus/sources/`; it never downloads
data or executes SQL. Data keeps its separate source licenses.

From the repository root:

```sh
python3 tools/thesaurus/build_packs.py
python3 tools/thesaurus/test_build_packs.py
python3 tools/thesaurus/verify_packs.py
```

`build_packs.py` verifies input and notice hashes before building. The defaults
write the editor's real assets and the pinned manifest constants. To rebuild in
an isolated directory, use `--output PATH --constants PATH`. Compare every file,
including manifests, against the shipped asset tree. JSON serialization, entry
order, relation deduplication, compression level and raw-DEFLATE framing are
deterministic. The manifest records the compiler's own SHA-256 and zlib version;
use the same compiler/source bytes and zlib version for byte-for-byte replay.
No timestamps from the build host enter generated outputs.

`test_build_packs.py` covers SQL string escapes, data that resembles executable
SQL, malformed rows, Unicode line separators, lookup normalization and
cross-runtime UTF-8 shard vectors. `verify_packs.py` checks every packaged byte,
all index-to-meaning memberships, every displayed term's reverse index entry,
source identities, shard placement, notice presence and a bounded panel with
identified source records. Its output is a machine-readable qualification
receipt. The panel does not establish universal linguistic quality or substitute
for an independent human linguistic review.

For a reviewable packet, run `export_review_packet.py --report PATH --output NEW_DIR`
with the real native panel report for the build being assessed. It verifies the
observed meanings against current pack hashes and exports readable Markdown plus
full source records and blank decisions in JSON. It does not execute the provider
or approve quality. `test_export_review_packet.py` covers stale/corrupt reports.
The [release acceptance guide](../../docs/roadmaps/thesaurus/release-acceptance.md)
provides actual-browser, installed-desktop/IME and human-review procedures.

## Source choice and conversion

English uses the **regular OEWN 2025 WN-LMF XML**, not the names-expanded 2025+
edition. All 107,519 source synsets and 185,129 lexical senses are retained.
Synsets remain separate meanings, even if they overlap. Original synset,
lexical-entry and sense IDs, POS, definitions, examples and typed relations are
kept. Multiple source definitions are joined with newlines. Explicit source
usage/region relations resolve to human-readable labels while the original
relations remain available. The 4,473 source Form records become lookup aliases,
preserving lemma POS and ambiguity. Independent WordNet morphy suffix logic
only accepts attested, compatible-POS lemmas; it does not generate replacements.

German uses the official **OpenThesaurus SQL export dated 17 November 2026,
23:15:01 UTC**. The text/OXT exports lose structure; the SQL dump provides stable
group/term IDs, per-term levels/tags, categories and relation types. SQL is parsed
as data with a deliberately restricted value grammar. Only visible groups and
German terms are imported: 50,264 meaning groups and 203,767 terms. Group/term
links whose endpoints survive selection are retained; reverse edges use the
reverse names explicitly present in the link-type table. Explicitly disabled
categories and invisible tags are omitted; historic `NULL` visibility flags on
tags remain visible. No POS or definitions are invented for German groups.
Term comments remain notes, including source examples or qualifications.

The source's `normalized_word`/`normalized_word2` columns are **not imported**:
they can fold umlauts and `ß`. Independent lookup-only aliases omit or unwrap
parenthetical text without changing the literal term or equating German words.
For example, `sich freuen` can find `sich freuen (über)`; replacement still
inserts the displayed, reviewed source term. The `word_mapping` fullform table
is not imported. German noun fallback reuses the existing separately qualified
Unicode Inflection resource and preserves its unresolved/ambiguous boundaries.
Verbs/adjectives and Swiss vocabulary expansion are not supplied by that noun
resource. `de-DE`, `de-AT` and `de-CH` select the same labeled German corpus;
there is no global `ß`/`ss` or accent folding.

## Pack format and runtime contract

Each locale contains a plain UTF-8 `manifest.json`, 256 index shards, 256 meaning
shards and plain original licenses/notices. English additionally has a small
compressed morphology-rule file. Logical JSON files are stored as
`<path>.deflate`, using raw RFC 1951 DEFLATE. The manifest records SHA-256 and byte
size for both compressed and logical files. Notices are also hashed. The
editor's generated constants pin the manifest bytes, completing the chain.

Keys use lowercase Unicode with whitespace collapsed and soft hyphens removed
from lookup copies only. The low byte of FNV-1a over UTF-8 selects a shard. The
Dart implementation computes only that byte to avoid JavaScript multiplication
precision differences. Original source spelling and document offsets remain
untouched.

The pure-Dart service's text loader reads manifest/notices. Its optional binary
loader reads compressed shards. It checks compressed hashes before bounded
inflation using the engine's own `RawDeflate` codec, then checks logical size and
hash before decoding JSON. No archive dependency, Flutter, filesystem, model,
FFI or network loader is required by the engine. A host that installs these
compressed packs must supply `loadCompressedAsset`.

Default caches hold at most 64 parsed shards and 64 immutable query results.
`clear()` advances the service revision and prevents old in-flight reads from
repopulating caches. Hosts must call it when replacing an installed pack.
Corrupt/missing shards and malformed indexed entries fail as `failedPack`;
they cannot silently masquerade as `noEntry`. A missing manifest is a
`missingPack`, separate from unsupported language and no lexical entry.

## Validation and performance

Run the synthetic engine suite using the project's qualified Dart/Flutter
environment:

```sh
cd packages/quds_office_engine
flutter test --no-pub test/office_thesaurus_test.dart
```

For real-file native timings, run `benchmark.dart` with the resolved workspace
package configuration, supplying the asset root and receipt path. It exercises
real corpus queries and verifies supported English forms, German
`Häusern -> Haus`, negative controls and bundled notices while measuring first
queries, normalized-equivalent queries that bypass the result cache, immediate
result-cache repeats, bytes loaded and process RSS. See the saved receipt for
the exact runtime, method, sample count and limits; these are measurements of
that environment, not general device performance guarantees. The full-pack
verifier separately asserts source labels and the disjoint `Maße`/`Masse`
meaning sets.

The initial 32-shard cache repeatedly evicted meaning shards for English `run`
(57 meanings across 49 meaning shards). Its result-cache-bypassed p95 exceeded
the provisional 50 ms target. The 64-shard bound retains that query's working set;
the initial and final benchmark receipts preserve the measured change and
memory cost. This is a bounded-cache adjustment; no lexical coverage was cut.

The native driver reads local files only. Actual browser asset/DOM/offline
acceptance belongs to the host validation; compiling this provider to JavaScript
alone is insufficient product evidence.
