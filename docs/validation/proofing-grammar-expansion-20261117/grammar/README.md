# German grammar expansion: focused implementation and evidence

The implementation adds seven grammar categories to the existing German writing
provider, expands its reviewed present-tense inventory from 25 to **57 verb
families**, and introduces bounded noun-phrase analysis using **60 independently
authored singular/plural noun pairs**. The provider now exposes 15 rule IDs.
It remains an advisory, finite checker; it does not claim unrestricted German
parsing or complete morphological coverage.

The implementation was saved at
[`3a2ada5a04395fd2fa01c7878f4df9f1b9215558`](https://github.com/CrispStrobe/quds_office_suite/commit/3a2ada5a04395fd2fa01c7878f4df9f1b9215558).
This evidence package changes documentation and retained logs only.

## New phrase and clause checks

| Rule ID | Reviewed example | Result |
| --- | --- | --- |
| `de.grammar.preposition-pronoun` | `Ich komme mit mich.` | `mich` → `mir` |
| `de.grammar.preposition-case` | `Ich rede mit den Mann.` | `den` → `dem` |
| `de.grammar.dative-plural` | `Er kommt mit den Kinder.` | `Kinder` → `Kindern` |
| `de.grammar.adjective-ending` | `Ein gute Buch liegt hier.` | `gute` → `gutes` |
| `de.grammar.das-dass` | `Ich denke, das du kommst.` | `das` → `dass` |
| `de.grammar.subordinate-comma` | `Ich glaube dass du kommst.` | Insert a comma after `glaube` |
| `de.grammar.comparison` | `Die Datei ist wichtiger wie der Bericht.` | `wie` → `als` |

The noun-phrase checker combines reviewed noun readings with definite,
demonstrative, indefinite and possessive determiners. A stable preposition can
resolve case; otherwise the checker requires compatible determiner/noun readings.
It checks at most two adjacent reviewed adjectives. Competing readings cause
abstention instead of an arbitrary correction. This lets it diagnose examples
such as `mit einem gutem Buch` while retaining correctly inflected singular and
plural alternatives.

The complement-clause checks require a reviewed matrix-verb context, an explicit
subordinate subject, and a known finite verb at the end of the bounded clause.
They do not replace every `das` following a comma. Relative clauses, demonstrative
uses, incomplete clauses, and protected context remain outside those matches.

Comparisons use explicit reviewed words. The `so/ebenso/genauso … als` direction
requires a complete, short pronoun or determiner-led nominal comparison. It
abstains on a following pronoun-led clause or bare role noun. The other direction
does not infer a comparative from every word ending in `er`.

## Agreement and Swiss German

The existing `de.grammar.pronoun-verb` identity now also supports distinguishable
`er` and `man` forms and clear verb–pronoun inversion. Examples include `Er haben
Zeit.` → `Er hat Zeit.`, `Man müssen gehen.` → `Man muss gehen.`, and `Hat du
Zeit?` → `Hast du Zeit?`.

The expansion preserves mood and grammatical ownership. Forms such as `er habe`,
`man nehme`, and `Habe du Geduld!` can be subjunctives or imperatives. A finite
governor can precede an infinitive (`Kann ich gehen?`, `Könnte ich gehen?`) or
follow it (`weil ich helfen kann`, `ob er arbeiten wird`). Those infinitives are
not mistaken for independently agreeing finite verbs. Commas stop this local
lookahead, and an incomplete bounded scan cannot prove that a later governor is
absent.

Grammar lookup accepts regional `ß`/`ss` aliases while preserving the source.
All `de-CH` replacement strings use `ss`. Verified examples include `Du weiss` →
`Du weisst`, `Ich heisst` → `Ich heisse`, and `ein grosse Buch` → `ein grosses
Buch`. Correct `weiss`, `heisst`, `grosses`, and `Strassen` forms stay clean.
Orthography remains the spelling provider's responsibility when the inflection
already agrees.

## Safeguards established during review

The regression set explicitly preserves:

- Adverbs modifying adjectives, including `automatisch geänderte Datei`,
  `leicht beschädigte Tür`, and `leise geschlossenes Fenster`.
- Infinitive clauses after `ohne` or `um`, including `zu sein` and `zu tun`,
  parenthetical clauses, and long clauses whose end lies beyond the lookahead.
- Additive `mit`, coordinated subjects, dative/possessive `ihr`, nominal
  pronouns, and capitalized `Man` in prepositional proper-name contexts.
- Optional literary singular dative forms such as `von diesem Tage`,
  `nach dem Jahre`, and `aus dem Texte`.
- Temporal and role constructions such as `früher wie heute`,
  `so klein als er hier ankam`, and `so gut als Lehrer`.
- URL/email/code spans, joined identifiers, Unicode grapheme boundaries,
  authored soft hyphens, emoji prefixes, nonzero source origins, and rule opt-outs.

The checker excludes variable-case and two-way prepositions from the new case
rules, does not guess weak-noun inflection, and does not assign genders to unknown
nouns or gender homographs. Unlisted verbs, stems and clause structures can remain
undetected. These omissions are deliberate precision boundaries, not evidence
that arbitrary German prose has been fully checked.

## Focused validation

The final focused run passed **346 tests** across:

```text
test/proofing/german_writing_rules_test.dart
test/proofing/german_grammar_test.dart
test/proofing/german_agreement_context_test.dart
```

These tests **overlap the full integration gate** and must not be added to its
count. They cover both erroneous and valid/ambiguous sentences, applying a
suggestion and checking the corrected text again, regional behavior, exact source
ranges, and independently ignored rules. The final expanded-reporter output is
[german-agreement-checkpoint.log](logs/german-agreement-checkpoint.log).
The full gate's [receipt](../integration/receipt.json) is the authority for the
broader integration result and its before/after source inventory.

Strict analysis of the two changed source files and two new test files completed
with `No issues found!` in the execution transcript. A separate analyzer log was
not retained during this focused run, so this package does not reconstruct one.

Reproduce the focused tests from `packages/quds_office_engine`, after restoring
the pinned toolchain and locked workspace dependencies:

```sh
dart test test/proofing/german_grammar_test.dart \
  test/proofing/german_writing_rules_test.dart \
  test/proofing/german_agreement_context_test.dart --reporter expanded
dart analyze lib/src/proofing/german_writing_rules.dart \
  lib/src/proofing/german_grammar.dart \
  test/proofing/german_grammar_test.dart \
  test/proofing/german_agreement_context_test.dart
```

## Retained development attempts

| Actual retained log | Reported result | Scope |
| --- | --- | --- |
| [Existing writing regressions](logs/german-existing-initial.log) | 37 passed | Existing tests against the first phrase implementation |
| [Initial phrase attempt](logs/german-new-initial.log) | 146 passed, 1 failed | Exposed an existing agreement ambiguity after `außer` |
| [Phrase checkpoint](logs/german-phrase-checkpoint.log) | 193 passed | Phrase and existing writing tests |
| [Initial agreement attempt](logs/german-agreement-initial.log) | 300 passed, 2 failed | Exposed duplicate finite/infinitive findings after inversion |
| [Second agreement attempt](logs/german-agreement-pass2.log) | 305 passed | Updated agreement tests |
| [Initial Swiss attempt](logs/german-swiss-initial.log) | 309 passed, 1 failed | Exposed title-case inversion after an emoji prefix |
| [Final focused run](logs/german-agreement-checkpoint.log) | 346 passed | Current focused acceptance |

The files are verbatim copies of actual retained local output. They are not a
complete execution history: some intermediate attempts reused an output file.
Earlier logs did not capture individual source inventories and do not establish
current acceptance. [evidence.json](evidence.json) records their commands, sizes
and SHA-256 hashes. It also records source hashes collected during packaging and
checked against the frozen checkpoint; the full integration gate owns the
stronger before/after provenance.

## Source and license scope

Implementation paths:

- `packages/quds_office_engine/lib/src/proofing/german_writing_rules.dart`
- `packages/quds_office_engine/lib/src/proofing/german_grammar.dart`
- `packages/quds_office_engine/test/proofing/german_grammar_test.dart`
- `packages/quds_office_engine/test/proofing/german_agreement_context_test.dart`

No dependency, dictionary, external rule corpus, or statistical model was added.
The phrase rules, bounded lexical tables and regression sentences are first-party
work under the repository's existing terms. Conceptual language references were
used to check grammatical facts and exceptions; no rule files or corpus data
were imported:

- [IDS: Präpositionalphrase](https://grammis.ids-mannheim.de/kontrastive-grammatik/5747)
- [IDS: Flexion der Adjektive](https://grammis.ids-mannheim.de/kontrastive-grammatik/3627)
- [Official spelling rules: Komma bei Nebensätzen](https://grammis.ids-mannheim.de/rechtschreibung/6203)
- [IDS: als/wie comparison](https://grammis.ids-mannheim.de/fragen/134)
- [IDS: Konjunktiv I](https://grammis.ids-mannheim.de/terminologie/400)
- [IDS: Imperativ](https://grammis.ids-mannheim.de/terminologie/104)

No GitHub Actions run was requested or waited on for this focused work.
