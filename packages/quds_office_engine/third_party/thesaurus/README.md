# Distributed thesaurus data and provenance

Quds ships two separately licensed, offline thesaurus packs. Independent
implementation code remains MIT; these data licenses are not changed by
indexing, compression or bundling with the application.

| Pack | Exact selected input | License | Retained meaning groups |
| --- | --- | --- | ---: |
| English | Regular OEWN 2025 WN-LMF XML; release tag `dc343f2683279ecbb13fab4e2fd778d7b162d287` | OEWN developments under CC BY 4.0; inherited Princeton WordNet data under its original WordNet terms | 107,519 |
| German | OpenThesaurus SQL export, 17 November 2026 at 23:15:01 UTC | Selected CC BY-SA 4.0 option, including the adapted German pack | 50,264 |

The original compressed lexical inputs are retained in `sources/` so that the
moving OpenThesaurus download URL is not required for reproduction.
`sources.json` records the original URLs, exact SHA-256/size, retrieval time,
release/export identity, notice origins and separately licensed morphology.
The compiler verifies this record before reading a source. Upstream notice
files are preserved verbatim under `notices/`; original COPYING remains intact
even though Quds explicitly selects its CC BY-SA option.

English attribution credits both the Open English WordNet team and Princeton
WordNet. German attribution credits OpenThesaurus, Daniel Naber and contributors
and identifies the Quds transformations. Both packs include their actual
licenses and change notices in the editor asset bundle. These are accessible
through the thesaurus source/attribution view, and are integrity checked just
like lexical records. All distributions of the adapted German pack must retain
its attribution, ShareAlike license and supplied notices without additional
restrictions on covered material.

Additional English word-form lookup uses the selected OEWN's Form records and
an independently implemented, documented WordNet morphology algorithm. German
noun lookup reuses the existing Unicode-3.0 resource, whose license, original
notice and manifest identity are recorded here. The OpenThesaurus fullform
mapping, combined Grundwortschatz databases, frequency lists, generated
synonyms, external models and proper-name expansion are not imported.

The [build and format documentation](../../../../tools/thesaurus/README.md)
records deterministic regeneration, source-field selection and explicit
coverage limits. `qualification.json` records full-file/index verification and
the bounded source-identified lexical panel. `native-benchmark.json` records
actual local-file lookups, notices, memory and latency on the named runtime.
Neither receipt asserts an independent human linguistic review. Host browser
and desktop UI evidence lives in the repository's thesaurus validation record.

## Recorded validation

`reproducibility.json` records an independent repeat build of all 1,037 packaged
files plus generated manifest constants: no byte differences. The full pack
verifier also passed against the final manifest identities.
`provider-tests-summary.json` binds 24 passing provider cases and their JSONL
runner output to the exact provider/test source hashes, including corruption,
cache invalidation, identity, normalized morphology and high-polysemy caching.

The final native benchmark used Linux x64, an Intel Xeon Platinum 8573C with nine
exposed processors, and Dart 3.13.7 JIT. Each language panel had 70 queries that
bypassed the result cache while retaining normalized terms, plus 70 immediate
result-cache repeats. These are a bounded panel, not universal vocabulary or
device guarantees.

| Measurement | English | German |
| --- | ---: | ---: |
| Provider p50, result cache bypassed | 0.815 ms | 0.140 ms |
| Provider p95, result cache bypassed | 2.766 ms | 0.306 ms |
| Immediate result-cache repeat p95 | 0.111 ms | 0.036 ms |

Whole-process baseline RSS was 283,512,832 bytes; final RSS 333,144,064 bytes;
peak RSS 458,772,480 bytes. This includes the Dart JIT, imported engine code,
temporary decoding allocations, morphology and caches; it is not a pack-only
memory measurement. Cold queries are recorded separately and are slower.

The first 32-shard attempt is retained in
`native-benchmark-initial-32-shards.json`. English `run` has 57 meanings across
49 meaning shards and repeatedly evicted its own working set at that bound.
The final 64-shard cache removed the observed thrashing and passed the
provisional 50 ms warm-provider p95 target on this panel. Corpus bytes,
meaning coverage and source licenses were unchanged by this adjustment.

## Upstream sources

- [OEWN downloads](https://en-word.net/downloads)
- [OEWN release license](https://github.com/globalwordnet/english-wordnet/blob/dc343f2683279ecbb13fab4e2fd778d7b162d287/LICENSE.md)
- [Inherited WordNet license](https://github.com/globalwordnet/english-wordnet/blob/dc343f2683279ecbb13fab4e2fd778d7b162d287/WNDB_License.txt)
- [WordNet morphology algorithm](https://wordnet.princeton.edu/documentation/morphy7wn)
- [OpenThesaurus download and license choice](https://www.openthesaurus.de/about/download)
- [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
