# English/German grammar expansion — 17 November 2026

This continuation starts from `62563c61f02ee44504776d9e7d26557f9bae490a`.
Implementation is saved on `codex/proofing-en-de-20261117` and proposed in
[draft PR #91](https://github.com/CrispStrobe/quds_office_suite/pull/91).
The source selected for the full local gate is
**`3a2ada5a04395fd2fa01c7878f4df9f1b9215558`**. Later documentation/evidence
commits preserve the qualified source and are verified separately. After the
evidence save `ee030afd`, the [saved-source verification](post-qualification-source-equivalence.json)
confirmed all 2,102 source inputs, nine runtime files and captured incoming
heads still match. The subsequent receipt checkpoint changes documentation
and the evidence index only.

**The complete local integration gate passed**, finishing at 07:41 CET on
17 November 2026. All **2,102 recorded source inputs** and **nine runtime files**
stayed unchanged. The independent German comparison, actual English dialect
checks and license continuity audit also passed.
No GitHub Actions runs, workflow checks or queue were queried or awaited.

## What changed

### German grammar: phrase morphology and clause context

`GermanWritingRulesProvider` now has **15 writing/grammar rule categories,
up from eight**. Seven independently authored categories add local phrase and
clause checks. A finite morphology table contains **60 reviewed singular/plural
noun pairs** and reviewed adjective stems. It lets the checker reason about
article gender/case, adjective endings and dative plurals without adding an
external rule resource or dictionary.

| New rule | Example | Offered correction |
| --- | --- | --- |
| Pronoun case after a fixed-case preposition | `mit mich`, `für ihm` | `mit mir`, `für ihn` |
| Article case/gender after a fixed-case preposition | `mit den Mann`, `für dem Kind` | `mit dem Mann`, `für das Kind` |
| Dative plural | `mit den Kinder` | `mit den Kindern` |
| Adjective agreement | `ein gute Buch`, `mit einem gutem Buch` | `ein gutes Buch`, `mit einem guten Buch` |
| Selected `das`/`dass` complement clauses | `Ich denke, das du kommst.` | `Ich denke, dass du kommst.` |
| Missing comma in selected complement clauses | `Ich glaube dass du kommst.` | `Ich glaube, dass du kommst.` |
| Reviewed `als`/`wie` comparisons | `größer wie ich`, `ebenso wichtig als der Bericht` | `größer als ich`, `ebenso wichtig wie der Bericht` |

Agreement expands from **25 to 57 present-tense verb families**. It includes
adjacent `er`/`man` when indicative and subjunctive readings can be distinguished,
and bounded verb-before-pronoun constructions. Examples include `Er haben Zeit`
→ `Er hat Zeit`, `Man müssen gehen` → `Man muss gehen`, and `Hat du Zeit?`
→ `Hast du Zeit?`. The narrow `ihr`/`sein` handling retains its ambiguity guards.

Swiss spellings participate in the same analysis. `Du weiss das` receives
`Du weisst das`, and `Ein grosse Buch` receives `Ein grosses Buch` in `de-CH`.
Grammar accepts the relevant `ß`/`ss` forms for inflection analysis and emits
only `ss` replacements in that locale; the spelling provider owns orthography.

### Avoiding changes to valid German

The implementation does not treat every matching word pair as an error.
Competing analyses cause abstention. Independent review found concrete false
positives during development, and the final source includes regression guards
for them:

- Adverbs before adjectives, including `automatisch geänderte Datei`,
  `leicht beschädigte Tür` and `leise geschlossenes Fenster`.
- `ohne`/`um` infinitive clauses, optional literary dative forms such as
  `von diesem Tage`, and ambiguous noun readings.
- Konjunktiv I and imperatives, including `er habe`, `man nehme`,
  `Habe du Geduld` and `Habe er gesagt`.
- Coordinated subjects, nominal pronouns and ambiguous dative/possessive `ihr`.
- Finite verbs governing infinitives on either side: `Kann ich gehen?`,
  `Könnte ich gehen?`, `Würde ich gehen?`, and `Wenn ich helfen kann, komme ich.`
- Temporal and role readings, including `so klein als er hier ankam` and
  `so gut als Lehrer`.
- Incomplete bounded lookahead, which cannot establish a complete clause.

The `Kann ich gehen?` control also fixes an inherited false positive in the
previous implementation. The first-party independent corpus and original failed
review outputs are retained separately from the final successful qualification.
See [grammar implementation notes](grammar/README.md),
[independent qualification](independent/README.md) and
[the additional focused review](spelling/review/README.md).

This remains a finite checker. Two-way and variable-case prepositions,
unlisted noun/adjective forms, unrestricted compounds, general tense/mood
analysis and broad sentence parsing are outside its scope. The selected
`das`/`dass` and comma rules require a reviewed matrix/clause pattern; they are
not a complete German punctuation or homophone checker.

### German spelling: better candidates with bounded work

The shipped word list and accepted word forms are unchanged. Suggestion search
adds an indexed distance-two fallback that includes first-letter mistakes and
transpositions. Length and anchor buckets interleave candidates within the
existing shared **6,000-candidate / five-suggestion limits**. Each searched lexical candidate or compound component must be an exact
dictionary form or declared personal term. Explicit hyphenated suggestions
can reconstruct a compound from those validated components.

| Input | Verified suggestion |
| --- | --- |
| `interresant` | `interessant` |
| `Komunikazion` | `Kommunikation` |
| `Rechschreibugn` | `Rechtschreibung` |
| `Wissenscahflt` | `Wissenschaft` |
| `Scmetterlng` | `Schmetterling` |
| `Strasenbahnn` | `Straßenbahn` |
| `xnternehemen` | `unternehmen` |
| `QudsClodu`, with personal term `QudsCloud` | `QudsCloud`, preserving exact declared case |

Personal candidates stay within the active locale. Ignored words, phrases,
control-containing values and oversized entries do not become word suggestions.
The index is a bounded shortlist, not an exhaustive edit-distance search; an
unlisted modern word still requires personal vocabulary.

Each uncached suggestion operation yields to the event loop. Cached and known
words keep the inexpensive batch path. Deterministic tests cover progress,
disposal and vocabulary changes during a check. A 49-token diagnostic found
shorter heartbeat gaps after this change, at the cost of scheduling overhead;
it is not a latency guarantee or population-quality benchmark. The cold German
dictionary initialization still benefits from the existing warm-up path.
Exact diagnostic inputs, measurements and limitations are in
[the spelling evidence](spelling/README.md).

### English and hyphenation: consistent locale selection

The shared language normalizer now recognizes equivalent modern Latin-script
tags, German `1996` orthography, and valid Unicode locale preferences. Proofing
and English/German hyphenators select the same reviewed regional resources.
Historical German orthography, other scripts, unknown variants and unsupported
regions remain unsupported rather than silently choosing a different language.

Harper retains US, UK, Canadian, Australian and Indian English. Additional real
Linux-native and shipped-Wasm probes each passed 20 successful requests and
four explicit unsupported-language rejections, exercising all five dialects
and extended locale aliases, regional spelling, source offsets, protected
URLs/email/code, and sequential/concurrent backend reuse. One Wasm worker was
reused and disposed at completion. All 337 recorded source inputs stayed
unchanged in this separate dialect qualification.
The Harper engine and dependency graph are unchanged in this continuation.

Automatic English hyphenation remains US/UK only; it does not imply that
Canadian/Australian/Indian pattern corpora were added. German and English
hyphenation keep existing exceptions, protected-text behavior and original
source mapping. Locale tests and compiled-JavaScript checks cover the new
selection behavior.

### Review UI and source fidelity

The review dialog centers a bounded context passage on the actual finding.
It highlights the precise source span or a semantic insertion marker instead
of showing only the beginning of a long paragraph. Context cuts use whole
graphemes, including joined emoji. Long findings have bounded previews, and
the text remains visible at narrow widths and larger text scale.

All seven new rules have readable ignore/restore labels. Editor tests use the
real German provider to apply corrections, recheck, undo and redo. One test
spans German locale aliases and differently formatted runs containing an
authored soft hyphen, preceded by English no-proof text and emoji. Original
UTF-16 offsets, restored source text and formatting are asserted. Stale findings
are rejected. See [editor evidence](editor/README.md).

## Before/after qualification

The exact baseline and candidate ran the same **39 targeted error sentences**
and **213 valid/adversarial sentences**, with successful provider status for
every request.

| Measure on the identical de-DE corpus | Previous `62563c61` | Qualified `3a2ada5a` |
| --- | ---: | ---: |
| Exact intended corrections for the 39 new-construction errors | 0 / 39 | **39 / 39** |
| Valid controls receiving an incorrect finding | 4 / 213 | **0 / 213** |

The four inherited false positives were `Kann ich gehen?`, `Könnte ich gehen?`,
`Würde ich gehen?` and `Dürfte ich kommen?`. Each incorrectly conjugated its
infinitive in the baseline and remains unchanged in the candidate.

On each of Dart VM and Node, the candidate additionally passed **195 positive
variants, 117 correction/rechecks and 213 valid controls** (525 requests per
runtime). These repeat the same language examples under different contexts;
they are not 525 independent German sentences. Exact input/output, successful
status gates and unchanged source hashes are recorded in the
[independent receipt](independent/qualified/receipt.json).

This deliberately targeted first-party regression corpus measures the specific
new constructions and adversarial controls. It is not an estimate of general
German precision or recall. Both versions must report a successful provider
status; an unavailable/failed checker cannot count as a clean result. Exact
correction matching checks the rule, original source and sole replacement.
Locale, offset, soft-hyphen, correction/recheck, ignore and protected-text
variants are separate candidate checks on Dart VM and compiled JavaScript.

## Local integration and real backend results

| Validation | Final result |
| --- | --- |
| Strict engine, editor, example and Harper analysis | All four passed |
| Hyphenation, layout, serialization and PDF/export VM group | 258 passed |
| English/German hyphenation compiled to JavaScript | 23 passed |
| Shared/German proofing | 424 VM + 424 Node passed |
| Standalone compiled German smoke checks | 10 passed |
| Exact dictionary and pattern regeneration | Passed; shipped data unchanged |
| Incoming ODF/PDF/sheet/Zotero engine regressions | 515 passed |
| Selected editor/widget suites | 335 passed |
| Separate IME reattachment regression | 1 passed |
| Release web build, installed Harper assets and notices | Passed; 123 bundle files hashed |

Fresh Harper qualification passed **five Rust tests**, **33 VM tests with the
native backend enabled and zero skips**, **29 JavaScript contracts**, **five
actual Wasm-worker checks** and **11 compiled-Dart transport checks**, plus
license and host-packaging verification. The integration gate verified the
matching source/artifacts and all nine command logs before retaining that
same-turn receipt.

The release compiler completed successfully with the existing CupertinoIcons
font-asset warning retained in its log. Packaging and Node/Wasm execution do
not establish interactive-browser acceptance.

Groups overlap and are not added into one inflated total. Full commands,
return codes, logs and source/runtime manifests are retained in
[integration/receipt.json](integration/receipt.json). The matching-source
Harper qualification is copied into `integration/harper/`; the separate dialect
probes are in [dialects/](dialects/).

The runtime uses Flutter 3.47.8, Dart 3.13.7, Rust 1.100.0 and wasm-bindgen
0.2.130. The 162 locked pub archives were SHA-checked and resolved offline
against the restored prior lock. Runtime preparation and provenance receipts
are in [runtime/](runtime/).

## Incoming commits, PRs and branches

The first inventory was reconciled before proofing changes. It covers 196 fork
branch/PR references with 132 distinct fork heads; the eight upstream references
were already ancestors. Incoming ODT/ODP, rendering and Zotero histories were
preserved, including original heads equivalent to main's merged implementations.
An old ODT PNG test fixture conflict retained main's corrected fixture.

A second inventory captured work arriving during implementation at **07:33:14
CET on 17 November 2026** (06:33:14 UTC). It covers **206 named references and
138 distinct heads**: 104 fork branches, 94 fork PR heads, four upstream
branches and four upstream PR heads. Every captured head is an ancestor of
the selected source `3a2ada5a`. This includes later ODF whitespace, PDF text
decoding, spreadsheet conditional styling/PDF rendering and Zotero work. The
final two merges were conflict-free; their regressions join the local gate.

The [initial reconciliation](reconciliation.json),
[API inventory](incoming-api-inventory.json) and
[final reconciliation](final-reconciliation.json) retain the precise scope.
This is an explicit snapshot cutoff; other remote work may advance afterwards.

### Incremental remote checkpoints

Every update used an expected current branch SHA with `force: false`.

| Commit | Saved work |
| --- | --- |
| `1fbcabcaf43157c23a7b5a81457676535292be5b` | Initial incoming history reconciliation |
| `09cdacb956ea93e827058b1cd2cf0d73a9da37c1` | Unicode-safe review context and initial evidence |
| `93a8950aee4aa013b34e4e20a43d6a694168148d` | Stronger spelling candidates and shared locale selection |
| `aadae32de7f32901f7f92bc6ef1962d077ad41b8` | Seven grammar categories and real-provider editor integration |
| `466298ff97d98342ae7e5f5e97e60967bd7664b9` | Cooperative suggestion scheduling and lexical personal terms |
| `6bb618e160bbb871fbc1abc80389d83718a14902` | 57-family agreement, Swiss handling and clause safeguards |
| `3a2ada5a04395fd2fa01c7878f4df9f1b9215558` | Final incoming reconciliation and broader local gate |
| `ee030afda1bcffd64db4af74842d330996506571` | Completed local qualification, independent comparisons and full evidence |
| Receipt checkpoint following `ee030afd` | Saved-source equivalence receipt and final report/index |

Later commits save completed documentation and evidence. No GitHub Actions
execution is needed to interpret or reproduce this qualification.

## License continuity

The independent [license continuity receipt](license/receipt.json) passed
against the exact qualified source. All **107 protected existing inputs** and
**14 dependency/toolchain manifests** are unchanged from `62563c61`. The audit
also verifies Harper's existing **226-package graph** and the three required
MPL source archives. The new grammar part is first-party code; there is no new
GPL/AGPL/LGPL-only component or imported rule/data resource.

No dependency, dictionary, pattern corpus, external grammar rules, model or
license selection was added. The German morphology tables and regression
sentences are first-party work. The existing reviewed MIT dictionary/pattern
inputs, original English pattern notices, Harper notices and MPL obligations
are preserved. This is a continuity audit of the existing policy, not a new
legal opinion or a claim that every existing dependency has only one license.

Conceptual references consulted for independently authored rules include IDS
descriptions of [prepositional case](https://grammis.ids-mannheim.de/kontrastive-grammatik/5747),
[adjective inflection](https://grammis.ids-mannheim.de/kontrastive-grammatik/3627),
[subordinate-clause commas](https://grammis.ids-mannheim.de/rechtschreibung/6203),
[als/wie comparisons](https://grammis.ids-mannheim.de/fragen/134),
[Konjunktiv I](https://grammis.ids-mannheim.de/terminologie/400) and
[imperatives](https://grammis.ids-mannheim.de/terminologie/104).
No external rule files or example corpus were copied.

## Reproduction

Use the repository's pinned Flutter/Dart toolchain and prepared locked
dependencies. Run the source gate from the repository root on committed source:

```sh
python3 tools/proofing/verify_integration.py \
  --flutter /path/to/flutter/bin/flutter \
  --dart /path/to/flutter/bin/cache/dart-sdk/bin/dart \
  --node /path/to/node \
  --output /path/to/new-integration-evidence \
  --german-wordlist /path/to/pinned/wortliste \
  --harper-build /path/to/qualified-harper-build \
  --harper-receipt /path/to/matching-harper-receipt.json \
  --build-web
```

The runner rejects dirty relevant source, verifies exact data regeneration,
and compares source/runtime hashes before and after execution. It verifies
the reused Harper receipt's source, artifacts and log hashes; an arbitrary
receipt cannot substitute for actual backend qualification. Omit
`--harper-receipt` to run fresh Harper checks against the supplied build.
The separate grammar qualifier restores the exact prior source into an
isolated package and checks it against the same corpus; see its README.

The [evidence inventory](EVIDENCE.json) hashes every retained file except itself.
After checkout, `python3 docs/validation/proofing-grammar-expansion-20261117/verify_saved_evidence.py`
checks those hashes, the qualified source manifest and every captured incoming
head. Add `--runtime` on the original host to verify its nine runtime files.
Restore the exact ignored workspace lock before checking source equivalence.

## Remaining acceptance limits

- **Real browser acceptance is still unverified.** The HTTP/CSP Chromium
  harness aborts at `process_singleton_posix` with socket `EPERM` before loading
  a page. No HTTP requests or worker checks completed. The failed receipt and
  log are retained in [browser/](browser/). The sandbox was not disabled.
- Native Harper runtime acceptance covers Linux x86_64. Other desktop/mobile
  platforms and Android/iOS device spelling acceptance remain outstanding.
- The German checker has finite, explicitly bounded grammar and morphology.
  An unflagged sentence is not a guarantee of correctness. The existing German
  spelling dictionary is a pinned 2016 word-form snapshot, with personal
  vocabulary for unlisted terms; regional Austrian vocabulary is not exhaustive.
- The experimental German model remains disabled. This continuation adds no
  model download, online proofing service or external grammar corpus.
- Failed development probes remain evidence of the development process; only
  successful source-bound final receipts support the final result.
