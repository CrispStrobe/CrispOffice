# English and German proofing continuation

**Implementation source:** [`03523a205f3cd5fa162aaed8b15307b7fada9fa1`](https://github.com/CrispStrobe/quds_office_suite/commit/03523a205f3cd5fa162aaed8b15307b7fada9fa1)  
**Branch:** [`codex/proofing-en-de-20261116`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/proofing-en-de-20261116)

The continuation is implemented and saved incrementally to GitHub. It adds
automatic American/British English hyphenation, expands conservative German
agreement and spelling corrections, and improves English Harper source mapping
and shared vocabulary. The recent fork/upstream histories were reconciled
before implementation, refreshed against the recorded snapshot, and updated
again when a later main/PR #86 commit became visible during PR creation.

**Dart/Flutter/runtime qualification is pending.** The attached execution
environment reported that no usable execution environment was available.
JavaScript reference/data checks, source review and exact remote integrity
checks ran; they do not establish a passing Dart build or production runtime.
Earlier retained validation receipts keep their original source attribution.
No GitHub Actions endpoints were queried, waited on or rerun.

The original proofing reference integration was frozen at
[`1199750e3a0a6118336f6c3daf0e4467ff3eeb59`](https://github.com/CrispStrobe/quds_office_suite/commit/1199750e3a0a6118336f6c3daf0e4467ff3eeb59).
After the first report, main advanced with PR #86. The final combined source
above includes its four spreadsheet implementation files, two test files and
the corresponding local-verifier update. All 39 recorded proofing source/data
bindings are unchanged; the incoming spreadsheet changes have not been executed.

## Remote reconciliation and durability

The final bounded external snapshot at **2026-11-16 20:10:47 UTC / 21:10:47 CET**
contains **185 named refs and 126 unique heads**: 92 fork branches, 85 fork PRs,
four upstream branches and four upstream PRs. The frozen source includes all
126 heads, including the subsequently integrated German implementation.

The integrated base includes main through `fb62dbf` (spreadsheet PR #86), text-rendering PR #72
through `f23675a`, the proofing recovery `738f0b6`, Zotero recovery
`c6b9856`, and PR #85 `b87f9d6`. Equivalent/squashed histories were checked
against their actual changes before their ancestry was retained. Unique source
and evidence changes were imported; no unique changes were discarded by
attaching empty merge parents.

| Implementation track | Final component head | Source/evidence |
| --- | --- | --- |
| English automatic hyphenation | `ffc672fec2df9919233b4ee5b0ba783ef1758f99` | [English report](english-hyphenation/README.md) |
| German spelling and agreement | `a916bbf09169f6906a89bd2ca3e3c42120ead466` | [German report](../proofing-20261116/german-quality/README.md) |
| Harper source projection and shared vocabulary | `65d5815e4866549fe7f03b145b626f2c4aaba8e0` | [Reference receipt](harper-projection-reference.json) |

[final-integrity.json](final-integrity.json) binds the final source and records:

- All **5,498 expected repository blob entries** match the remote frozen tree,
  with no missing, unexpected or changed entries.
- All **39 component source/data bindings** match their recorded reference
  checkpoints after integration.
- All **66 protected existing inputs** checked are unchanged: package manifests
  and locks, existing notices, German dictionary data and hyphenation implementation,
  and Harper native
  source/license inputs.
- All **346 proofing-evidence files** already present in the initial observed
  main snapshot remain unchanged.
- Ancestry comparisons prove the final source descends from the prior proofing
  freeze, which already contains all 126 pinned snapshot heads. The later
  main `fb62dbf` and original PR #86 head `001367e` are also ancestors.

The full starting inventory and integration decisions are preserved in
[reconciliation.json](reconciliation.json),
[reconciliation-refresh.json](reconciliation-refresh.json), and
[reconciliation-verification.json](reconciliation-verification.json).
The last external refresh is recorded in
[final-external-refresh.json](final-external-refresh.json),
[its explanation](final-external-refresh.md), and
[its verification](final-external-refresh-verification.json).
The subsequently observed main/PR #86 import is recorded separately in
[late-main-refresh.json](late-main-refresh.json). All six incoming paths matched
the merge-base on our branch, so their exact incoming blobs were imported. The
original PR head and its squash commit have identical complete trees; both
histories were retained. This import is not included in the earlier 185-ref
snapshot count. The earlier final receipt remains available at
[`6cc6c07`](https://github.com/CrispStrobe/quds_office_suite/blob/6cc6c07369ca1c7f33bf1715d88222ab685530be/docs/validation/proofing-en-de-20261116/final-integrity.json).
These are bounded snapshots, not a claim about future remote commits.

## English automatic hyphenation

`EnglishHyphenator` supplies separate American and British patterns.
`OfficeHyphenator` routes those and the unchanged German implementation
through existing shared Word layout used by the editor and PDF export.

| Language | Automatic patterns | Boundary |
| --- | --- | --- |
| `en`, `en-US` | American: 4,938 patterns, 14 exceptions | Equivalent aliases, including within one word across runs |
| `en-GB` | British: 8,527 patterns, eight exceptions | Distinct British break choices |
| `de`, `de-DE`, `de-AT`, `de-CH` | Existing modern German patterns | Existing implementation and data unchanged |
| Other English dialects/languages | No automatic pattern fallback | Authored soft hyphens remain available |

English preserves the upstream exceptions, including words with no allowed
break, and leaves at least two letters before and three after a break.
Original source text and UTF-16 ownership are preserved. The existing layout
engine chooses fitting candidates and measures/paints the discretionary hyphen.

Contractions, unsupported accented words, identifiers, oversized words,
words with authored soft hyphens, genuinely mixed-language words and unsafe
join-control-adjacent fragments are conservatively excluded. URLs, email
addresses and closed matching-backtick spans are protected. Ordinary
punctuation-wrapped words and U+200B source breaks remain usable.

The English implementation has 17 new Dart regression definitions, including
mixed-language Word layout, explicit exceptions, language aliases, source
offsets, code/URL guards and paragraph suppression. These tests are unrun here.

## German grammar and spelling

The existing agreement rule now covers finite present-indicative forms of
**sein, haben, werden, können, müssen, dürfen, sollen, wollen and mögen** for
adjacent **ich, du and wir**. Examples include:

| Input | Offered replacement |
| --- | --- |
| `ich hast` | `ich habe` |
| `du wird` | `du wirst` |
| `wir kann` | `wir können` |
| `Huas-Tür` | `Haus-Tür` |
| `HUAS-TÜR` | `HAUS-TÜR` |
| Swiss `Straße-Tür` | `Strasse-Tür` |

The finite agreement rule preserves uppercase replacements and accepts spaces,
tabs, NBSP and narrow NBSP. It avoids false corrections in comparisons,
nominalized pronouns, coordinated subjects and relative-clause coordination.
Examples that remain accepted include `Ihr ist kalt`, `Ihr bin ich dankbar`,
`Du und ich sind hier`, and
`Mein Bruder, den du kennst, und ich haben Zeit`.

Existing narrow `ihr`/`sein` checks now have additional dative/impersonal
guards. Ambiguous `sie`/`es`, unlisted verbs, subjunctives, imperative
inference and full sentence parsing are not added.

Spelling repairs one unknown constituent of an explicit hyphen compound,
retaining the other constituents' case and each occurrence's ASCII/U+2010/U+2011
separator style. This runs one ordinary bounded suggestion search; there is
no unrestricted compound or morphology expansion. Spelling and writing both
protect closed code spans whose backtick-run lengths match. Unmatched
delimiters do not hide the remaining prose.

Ten Dart regression definitions were added. No German dictionary, generated
data, source manifest or original license notice was changed.

## English Harper source mapping and vocabulary

Harper receives complete words after U+00AD discretionary soft hyphens are
removed from checker input only. A per-request scalar index maps findings back
to the exact original UTF-16 source, including emoji, nonzero segment origins
and soft hyphens inside a correction. Both source and projected grapheme
boundaries are enforced. This avoids repeatedly rescanning the paragraph for
every finding; no measured runtime speedup is claimed.

`HarperProofingProvider` accepts the host's
`OfficeProofingVocabulary`. Matching-dialect personal/ignored words suppress
spelling findings only; grammar and style still run. Vocabulary changes
invalidate cached configuration and stale in-flight results. The example host
shares the same vocabulary with German and English providers.

The review language selector now exposes Harper's Canadian, Australian and
Indian English choices alongside US/UK English and German regions. Automatic
hyphenation remains scoped to the table above. Harper still requires installed
local native/Wasm assets; missing assets report unavailable, not a clean check.
No backend ABI, Rust implementation or dependency graph changed.

Fifteen Dart source/provider regression definitions were added. Existing real
native and Wasm smoke paths also now include a soft-hyphen article case.

## Licensing

No GPL, AGPL or LGPL-only code, dictionary, model or rule corpus was added.

| New material | Terms and provenance |
| --- | --- |
| American patterns | Kuiken's explicit royalty-free copying/distribution grant, with or without modification, preserving copyright/permission notices; recorded as `LicenseRef-Kuiken-permissive`, not relabeled MIT |
| British patterns | MIT, with complete original copyright and permission text |
| New grammar/algorithm code | Independently authored within the fork's existing MIT code |
| New runtime dependencies | None |

Both English originals are pinned to tex-hyphen
`5684c0f51c0b81133db2efbe60a408b4155a3ff5`; checked-in Git blob identities match
upstream. Source prefaces/notices survive generation. The restricted underlying
OUP word list is not shipped. [English provenance](../../../packages/quds_office_engine/third_party/hyphenation/ENGLISH.md)
records hashes, minima, exceptions, license distinctions and reproduction.
Existing German and Harper dependency/license boundaries remain in force.

## What actually ran

All algorithm probes below ran in the available **V8 JavaScript isolate**.

| Check | Observed result | Scope |
| --- | --- | --- |
| US/GB hyphenation | 442 US + 741 GB trie-versus-flat-oracle comparisons; 21 fixed word controls; 33 paragraph controls | Exact data and source-derived/reference algorithms |
| German proofing | 182 grammar + 27 spelling/protection checks | Actual regex/paradigm literals and translated control flow; actual shipped dictionary |
| German data decoding | All 113 chunks decoded; 444,123 standard forms and 9,451 Swiss additions | Existing data integrity, not a new corpus |
| Harper projection | 28 semantic checks, including 2,000 source ranges | Independent range-mapping reference |
| Remote integrity | 5,498 matching entries; all 126 snapshot heads plus late main/PR #86 retained; 39 source bindings match | Git tree/blob/ancestry checks |
| Independent source review | Completed; identified issues corrected before final source freeze | Static review, not compilation |

The earlier isolated German delimiter probes overlap the 27 spelling/protection
checks and are not added again. These groups are not a repository-wide test
total. **The 42 new Dart regression definitions were written and reviewed but
not executed.** No new Dart analysis, Python generator process, Flutter test,
release build, actual native/Wasm check, browser/CSP or mobile dictionary
acceptance is claimed.

## Reproduce and complete local qualification

In a functioning, dependency-resolved checkout, the reference probes can be
repeated with Node:

```sh
node docs/validation/proofing-en-de-20261116/english-hyphenation/reference_check.mjs
node docs/validation/proofing-20261116/german-quality/probe.mjs .
node packages/quds_proofing_harper/tool/source_projection_probe.mjs
```

The actual local qualification gate remains the existing source-bound tool:

```sh
python3 tools/proofing/verify_integration.py \
  --flutter flutter \
  --dart dart \
  --node node \
  --output docs/validation/proofing-en-de-20261116/local-qualification \
  --build-web
```

Use Dart from the prepared Flutter SDK. The tool requires committed source and
already resolved dependencies, preserves source/runtime/log hashes, and refuses
to overwrite an existing receipt. Supply `--german-wordlist` with the exact
pinned source file to avoid its normal pinned download. A matching built Harper
distribution supplied through `--harper-build` additionally exercises the real
native/Wasm and packaging gates.

The existing hyphenation verifier now includes English sources/data/provenance,
the English generator's `--check`, strict analysis and the new Dart suite.
Integration validation now analyzes Harper and runs its source/provider
contracts even without optional native assets. The Harper runtime verifier
also includes the new tests on the compiled-JavaScript path. The integration
suite now additionally runs `ods_sheet_writer` and `sheet_save_cache_and_freeze`
for the late incoming spreadsheet changes. No GitHub Actions queue is needed
for any of these commands.
