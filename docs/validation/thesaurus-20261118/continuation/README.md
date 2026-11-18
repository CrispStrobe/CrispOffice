# Offline English/German thesaurus continuation

18 November 2026. **Implementation and targeted local qualification are
complete on the working branch. Installed-desktop, actual offline-browser and
independent human linguistic review remain release gates.**

This is the historical qualification at `315beeb3`. Later review/Zotero
integration, IME/shortcut fixes and refreshed checks are recorded separately in
the [resumed work report](../resume/README.md); the earlier 155 cases do not
automatically qualify the later merged source.

## Recovered checkpoint and completed work

This continuation starts at `decde7792890bf4724c91403fbb6528d8423b01e` on
`codex/offline-thesaurus-20261118`. That remote commit contained the initial
pure-Dart provider and the incoming-work audit, but not the packs, compiler,
editor integration or tests described later in the supplied handoff. The
reconciled Office/proofing/Zotero baseline and
[original audit](../integration.json) were retained. No new broad branch audit,
GitHub Actions wait, main-branch merge or release publication was performed.

The continuation adds the complete real lexical sources and generated packs,
a deterministic compiler, a verified asset loader, source-safe Word targets
and replacement, a meaning-grouped dialog, language override, source notices,
Review/context-menu entry points and Shift+F7. Plain F7 retains writing review.
The engine remains independent of Flutter, filesystem and network APIs.

Lookup uses selected text or the word at the caret without changing the
selection or adding a proofing issue. Source capture happens before dialog or
context-menu focus transfer. Applying a literal returned candidate validates
source text, story, rich metadata, effective language, selection, controller
revision, service/pack revision and lookup generation. It rejects stale,
protected, generated, data-bound, mixed-language, unsupported and active-IME
targets. Rich text, uniform hyperlinks, bookmarks, comments, tracked changes
and story-aware selection are restored by one undo/redo unit.

## Shipped corpora and reproducibility

| Pack | Meaning groups | Terms/senses | Logical bytes, including notices | Shipped bytes, including manifest/notices |
| --- | ---: | ---: | ---: | ---: |
| Regular OEWN 2025 English | 107,519 | 185,129 | 70,552,255 | 14,434,207 |
| OpenThesaurus German, export 2026-11-17 23:15:01 UTC | 50,264 | 203,767 | 48,316,273 | 10,144,956 |
| **Total** | **157,783** | **388,896** | **118,868,528** | **24,579,163 (23.44 MiB)** |

The original input archives are checked in, pinned by SHA-256 and reviewed
alongside their original notices. The English pack retains CC BY 4.0 and
inherited WordNet terms; the adapted German pack uses the explicitly selected
CC BY-SA 4.0 option. Independent implementation code remains MIT. The existing
Unicode noun resource retains its separate Unicode-3.0 notice. See the
[data inventory and receipts](../../../../packages/quds_office_engine/third_party/thesaurus/README.md)
and [redistribution record](../../../roadmaps/thesaurus/licensing-and-notices.md).

An isolated repeat build produced **all 1,037 packaged files and the generated
Dart manifest constants byte-for-byte identically**. The full-pack verifier
checked every compressed/logical file, notice, source identity, shard,
index-to-meaning membership and term reverse index. Its bounded panel retains
specific source IDs for polysemy, phrases, labels, forms and negative controls.
It does not establish universal vocabulary coverage or human linguistic review.

Manifest SHA-256 values:

- English: `13ae58da2a20c0eb74ccf20acc3fade665e12e48daf783351f90b3073fd28e23`
- German: `8788f9af67186b40f963f948aeceed01c012f3e9653ddab68947e16213cb0453`

Regenerate and verify using the
[compiler instructions](../../../../tools/thesaurus/README.md). Builds use only
pinned local source archives and original notices; SQL is parsed as data and
never executed.

## Executed validation

| Check | Result | Evidence |
| --- | --- | --- |
| Python compiler/parser/normalization regressions | 5 passed | [Compiler test command](../../../../tools/thesaurus/README.md) |
| Pure-Dart provider and compressed-pack protocol | 24 passed | [Source-bound summary](../../../../packages/quds_office_engine/third_party/thesaurus/provider-tests-summary.json) |
| Thesaurus dialog and entry points | 18 passed | [Native audit](local/native-test-audit.json) |
| Guarded capture/replacement and undo/redo | 51 passed | [Native audit](local/native-test-audit.json) |
| Existing correction/capture/context regressions | 42 passed | [Native audit](local/native-test-audit.json) |
| Existing review pane | 11 passed | [Native audit](local/native-test-audit.json) |
| Real native bundled-pack panel | 1 passed, containing 15 actual queries and notice checks | [Panel receipt](local/native-pack-report.json) |
| Real native visual fixtures | 3 passed | [English desktop](local/visuals/english-desktop.png), [German desktop](local/visuals/german-desktop.png), [narrow German](local/visuals/german-narrow-large-text.png) |
| Release web compilation | Passed with CSP build option and local web resources | [Build receipt](local/receipt.json) |

The test total is **155 cases**: 5 Python + 24 provider + 126 Flutter. Queries
within a single panel case are not counted again. Native test events have no
skipped or unclosed cases, overflow warnings or missed-tap diagnostics.
Targeted source analysis also passed. The final native run and web compilation
bind exact source/asset inventories before and after execution; both stayed
unchanged. The official Flutter 3.47.8 / Dart 3.13.7 runtime and 162 dependency
archives were hash verified without relaxing project manifests.

The source/pack error cases include corrupt manifests, malformed indices,
compressed and logical digest mismatch, bounded decompression, missing packs,
unsupported languages, invalidated asynchronous reads and source-notice errors.
Explicit Retry invalidates failed manifest/shard caches before reloading a
repaired pack. The editor tests also cover forged candidates, language and
selection changes, text changes followed by undo, source metadata changes,
composed/surrogate characters, soft hyphens and the IME guard.

See [local execution details and replay](local/README.md) for exact commands,
raw logs, runtime metadata, visual fixtures, earlier attempts and limitations.
Original upstream license whitespace is preserved verbatim rather than changed
to satisfy a generic diff whitespace check.

## Measured performance and cache correction

The initial 32-shard cache repeatedly evicted data for English `run` (57
meanings spread across 49 meaning shards). Its warm provider p95 was about
1,291 ms in the targeted benchmark. The default is now **64 parsed shards and
64 result entries**. A 50-meaning regression verifies that an equivalent query
which bypasses the result cache needs no extra shard reads after warm-up.

Final native provider benchmark: Linux x64, Intel Xeon Platinum 8573C, nine
exposed logical processors, Dart 3.13.7 JIT. Each language has 70 normalized
variants that bypass result caching, plus 70 immediate cached repeats.

| Measurement | English | German |
| --- | ---: | ---: |
| Warm provider p50, result cache bypassed | 0.815 ms | 0.140 ms |
| Warm provider p95, result cache bypassed | 2.766 ms | 0.306 ms |
| Immediate result-cache repeat p95 | 0.111 ms | 0.036 ms |

This bounded native panel passes the provisional 50 ms warm-p95 target.
First lookups remain slower: in this provider run English `bank` took 912 ms
and `run` 1,364 ms; the first German `Bank` query later in the same process took
67 ms. These are shared development/JIT observations, not installed release or
browser guarantees. Whole-process RSS was 283,512,832 bytes before,
333,144,064 after and 458,772,480 at peak, including JIT and all other process
allocations. The
[final benchmark](../../../../packages/quds_office_engine/third_party/thesaurus/native-benchmark.json)
and [initial 32-shard attempt](../../../../packages/quds_office_engine/third_party/thesaurus/native-benchmark-initial-32-shards.json)
retain exact source hashes and measurement methods.

## Remaining release gates and product boundaries

1. **Actual offline-browser acceptance.** Chromium could not start because the
   execution sandbox rejected Unix sockets. The supported cloud browser could
   not reach the local fixture origin. Web compilation passed, but browser
   rendering, CSP behavior, network-disabled execution and browser performance
   are unqualified. The replayable fixture and offline service worker are test
   infrastructure for a browser-capable host, not production deployment changes.
2. **Installed native desktop packaging.** Native headless Flutter tests and
   real rendered dialogs passed. This environment lacks the compiler/GTK setup
   for an installed Linux application; no installed Windows/macOS/Linux or
   mobile acceptance is claimed.
3. **Independent human linguistic review.** Real, source-identified query
   panels pass, but that is not independent human assessment of lexical quality.

English morphology is bounded to source forms and documented suffix rules;
German reuses finite noun readings and preserves ambiguity/unresolved cases.
German regional locales share one labeled corpus without ß/ss folding. Source
parentheticals remain literal reviewed replacement text. There is no automatic
agreement, generalized reinflection, sentence rewriting or contextual sense
selection. Cross-paragraph and unmodeled source ranges remain outside the
editable target contract.
