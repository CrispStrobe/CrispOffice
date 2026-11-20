# Native spaCy grammar v2: four new rule families, 20 November 2026

**Result: three of four families are qualified and on by default inside the
opt-in manual German grammar provider. One family failed and stays
experimental.**

| Family (rule ID) | Panel errors fixed exactly: deterministic / native / combined | Valid + guard findings | GSD test findings (977 sentences) | Linux = macOS | Default |
| --- | ---: | ---: | ---: | :---: | --- |
| `de.spacy.np-agreement` | 4 / **13** / 15 of 24 | 0 / 0 | 2, both genuine errors | yes | **on** |
| `de.spacy.preposition-case` | 12 / **18** / 18 of 24 | 0 / 0 | 0 | yes | **on** |
| `de.spacy.verb-position` | 4 / **9** / 11 of 24 | 0 / 0 | 0 | yes | **on** |
| `de.spacy.subject-person` | 10 / **18** / 18 of 24 | **1** / 0 | 0 | yes | off (experimental) |

The existing W6/W7 rule `de.spacy.noun-verb` is unchanged. With the default
planner, the consumed W6 panel still replays with 0 differences.

The new families are Dart planner logic only. They read the native analysis of
`de_core_news_sm` 3.8.0 from CrispEmbed (tokens, tags, morphology, heads,
dependency labels) and the engine's existing reviewed lexical facts. No native
byte changed. Both qualified digests give identical results: the app-bundled
macOS `ccc96620…` and Linux x86-64 `ea89842e…`. These results come from one
finite authored panel and one clean corpus. They are not a population estimate
of German grammar quality.

## What each family does

Each family abstains whenever the parse or the lexicon is ambiguous. Abstaining
is the default behavior, not an exception.

- **np-agreement**: checks determiner + adjectives + common noun inside one
  parsed noun phrase (`nk` dependents of the noun). It looks at gender and
  number, and at adjective endings that are wrong for every reading of the
  determiner and noun. The noun's licensed lexical readings decide the target.
  The parse only narrows the case (the article's own cases, the parsed role,
  or a governing preposition). The family abstains on a model/lexicon gender
  conflict, coordination, extra prenominal material, a possible relative
  pronoun, compounds and multiword names. It also abstains on a
  nominalized adjective, a quantity head, invariable adjectives, a noun-only
  rewrite and the "Email/E-Mail" variant.
- **preposition-case**: covers a closed list of fixed-case prepositions. The
  parse must make the noun the preposition's `nk` dependent. The family fires
  only when the phrase is internally consistent but in the wrong case. For
  wegen/trotz/während/statt the colloquial dative is accepted. Two-way
  prepositions never establish a case error. "zu der" becomes "zum"/"zur",
  "in das" becomes "ins", and so on.
- **verb-position**: (a) verb-third after one fronted temporal/local adverb or
  prepositional phrase at sentence start, fixed by swapping subject and finite
  verb. (b) verb-second in a dass/ob/wenn/obwohl/nachdem/bevor/falls/damit/
  sobald clause with no other verb, particle, coordination, extraposed PP or
  comparison, fixed by moving the finite verb to the clause end. `weil` with
  verb-second (accepted in speech) is never flagged.
- **subject-person**: a parsed `sb` personal pronoun (ich/du/er/wir/ihr/man)
  or determiner + common noun, and its present finite verb. It uses reviewed
  paradigms only (the engine's 57 plus 110 hand-written ones in
  `grammar_verbs.dart`). Subjects sie/Sie/es, Konjunktiv I homographs and
  infinitives misparsed next to a modal all abstain.

## Protocol and order (all commits are on the feature branch)

| Step | Commit |
| --- | --- |
| Protocol, sealed panel and clean corpus frozen before any candidate output | `4e2c0fb9` |
| Candidate implementation | `d9d0f9cb` |
| Source seal (73 files: planner, provider, engine proofing, evaluators, protocol) | `a26ee9a3` |
| One-shot qualification report and consumed claim, unchanged | `b7f04f12` |

- [protocol.json](protocol.json) sets the gates per family before any output
  was seen. No finding on valid or guard controls. On the clean corpus, either
  no finding or every finding judged a genuine error. At least 25% of the 24
  errors fixed exactly by the native rule. At least 3 added exact corrections
  over the deterministic baseline. No baseline correction lost. At most 2
  non-exact native proposals on error rows. No operational failure. A clean
  recheck. Identical results on both digests.
- [qualification-panel.json](qualification-panel.json) (SHA-256 `80997c7e…`)
  holds 4 × (24 error, 24 valid, 12 guard) plus 4 unsupported locales, so 244
  cases. A separate assistant agent wrote it by hand from a written brief. It
  had no access to the planner or to any model output, and used no corpus
  text. Guards cover coordination, ellipsis, quotations, names, abbreviations,
  numbers, Konjunktiv I, imperatives, homographs, two-way prepositions,
  colloquial "wegen dem" and "weil" + V2. Each family also has one ignored-rule
  guard, and np-agreement has one personal-word guard.
- [clean-corpus-gsd-test.json](clean-corpus-gsd-test.json) holds the 977
  sentence texts of the UD German-GSD r2.15 **test** split (CC BY-SA 4.0,
  attribution in the file). This split was held out. Development used the GSD
  dev split and 9,000 GSD train sentences, plus my own development sentences.
- [candidate-seal.json](candidate-seal.json) and its
  [consumed claim](candidate-seal.json.consumed.json) record the seal. The
  evaluator `tool/evaluate_grammar_v2.dart` refuses a changed source, panel,
  corpus or library. It creates the claim exclusively before loading the
  library.
- [qualification-macos.json.gz](qualification-macos.json.gz) is the complete
  report: every annotation, decision, arm and recheck. The SHA-256 of the
  uncompressed file is in `qualification-macos.json.sha256`.
- [linux-replay/](linux-replay/) holds the hosted Linux replay, CrispEmbed
  `heavy-cpu.yml` run
  [44678018577](https://github.com/CrispStrobe/CrispEmbed/actions/runs/44678018577),
  script `tools/ci-heavy/spacy_grammar_v2_linux.py`. It installed the W7
  capsule from the immutable Hub revision (`ea89842e…`) and checked out Quds
  `b7f04f12`. It then compared all 1,221 rows (244 panel + 977 corpus) with the
  macOS report. Compared fields: the analysis digest, decisions,
  deterministic/native/combined arms, merge suppression, operational status
  and corrected rechecks. **0 differences.**

The incoming implementation report records 10/10 passes for the real native
editor gate (`studio_spacy_grammar_native_gate.dart`) with the macOS bundled
library and the new default families. The named `editor-gate-macos.log` was
not present in the captured branch, so that reported result cannot be
independently recounted from this repository. One control changed on
purpose. Ignoring only the noun/verb rule still suppresses its suggestion, but
the other enabled families still analyze. Ignoring every enabled family makes
no native call.

## Findings that need judgement

- **Clean corpus, np-agreement (both are genuine errors in the source;
  [judgement](clean-corpus-judgement.json)):**
  `test-s60` "das Angebot **der** Tages" is corrected to "des Tages".
  `test-s250` "zu einem **fairem** Preis" is corrected to "fairen".
  `de.spacy.preposition-case`, `verb-position` and `subject-person` have no
  findings on the corpus. The deterministic baseline flags 10 of the 977
  sentences.
- **subject-person fails.** `sp-valid-07` is "Meine Kollegin und ich bereiten
  die Präsentation vor." The parser made only "ich" the subject of the
  coordinated verb, so the rule proposed "bereite". The same misparse gives the
  non-exact proposal on `sp-error-14`. The family therefore stays default-off
  and is listed as experimental in Studio. **After** qualification I added a
  guard that abstains when a nominal + "und/oder" directly precedes the
  pronoun (unit-tested). That fix is output-informed, so it is not a new
  qualification. Qualifying this family needs a new sealed panel.
- **Dev/panel overlap.** I checked mechanically: two verb-position panel texts
  match my own development sentences ("Ich weiß, dass er hat keine Zeit." and
  its correct version). This is a coincidence, because the panel author never
  saw the development set. Without `vp-error-03`, verb-position is still 8/23
  native exact (35%), with 6 added over the baseline. It still passes.

Native exact corrections by family: np-agreement 13 (54%), preposition-case 18
(75%), verb-position 9 (38%), subject-person 18 (75%). In total there are 61
native proposals. The merger suppresses 26 that overlap deterministic findings
(deterministic precedence). The combined arm adds 32 exact corrections over the
baseline and loses none. All 62 corrected outputs were rechecked, with 0
further native findings. There were 0 operational failures, and all 4
unsupported locales reported as unsupported.

Misses are retained in the report with their decision reasons. Typical causes
are the lexicon (for example "Mädchen" unknown, "Garten" with a feminine
homograph reading) and model/lexicon gender vetoes ("Mein Schwester", "den
blaue Ordner"). Coordinated noun phrases and genitive prepositions parsed as
conjunctions ("Während die Besprechung") also miss. In verb-position, clause
types outside the formulation miss: indirect questions, "da"/"als" clauses and
modal + infinitive.

## Examples to type in Studio (Check document; never while typing)

| Family | Type | Suggestion |
| --- | --- | --- |
| np-agreement | Diese Buch habe ich meiner Schwester geschenkt. | Dieses |
| np-agreement | Unsere Nachbarn haben einen großes Garten. | einen großen |
| np-agreement | Das Ergebnis des letzten Sitzung war gut. | der letzten |
| preposition-case | Am Sonntag gehe ich mit der Hund spazieren. | dem |
| preposition-case | Wegen die Baustelle ist die Straße gesperrt. | der |
| preposition-case | Trotz die schlechte Wettervorhersage findet das Fest im Freien statt. | der schlechten |
| verb-position | Ich weiß, dass er hat keine Zeit. | keine Zeit hat |
| verb-position | Am Montag die neue Kollegin beginnt ihre Einarbeitung. | beginnt die neue Kollegin |
| subject-person (experimental; tick it first) | Ich kann nicht kommen, weil ich morgen arbeitet. | arbeite |

"zu der Arzt" gives "zum Arzt" from the native rule, but the deterministic
"dem" takes precedence when both fire. Explanations are German in the German
UI and English otherwise. Every new
family is also suppressed by its matching deterministic ignore
(`de.grammar.phrase-agreement`/`adjective-ending`, `preposition-case`,
`pronoun-verb`, `word-order`).

## Scope

This covers manual de-DE only, on the two exact native digests above. The
claims are bounded by a finite authored panel and one clean corpus. Caller
cancellation still does not interrupt native compute. Verb-position
qualification is limited to the two formulations above. A broader treatment of
verb placement (indirect questions, modal clusters, separable verbs,
extraposition) would need an actual clause parser and stays out of scope.
