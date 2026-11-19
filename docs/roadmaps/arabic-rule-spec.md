# Arabic proofing rules: abstract functional specification (clean-room handoff)

Status: dirty-room output. It describes **what** established Arabic checkers test, in
general linguistic terms. It contains no rule messages, examples, word lists, replacement
pairs, token patterns, regular expressions, tag strings, rule identifiers or file layouts
from the studied sources. Counts are facts. Wherever a closed word class is involved, it is
named by its grammatical definition, with an approximate size. The implementer authors
every member list and every message independently.

Sources studied (read only):

- **LanguageTool Arabic module** at release tag v6.8. This covers the pattern-rule file,
  the plain-text data rules, the Java rule classes and filters, the disambiguation file,
  and the tagger, synthesizer and tokenizer.
- **Fareh**, the rule-authoring database (HEAD as of 2026-11-19).
- **Ghalatawi**, the autocorrect library, and **Aghlat**, the misspelling corpus. Both are
  by the same author as Fareh.
- **Public descriptions** of Sahehly (Sakhr) and Qalam. Only their category level was used.

---

## 1. Summary table

| Framework | Total rules / entries | Licence | Coverage areas (counts) |
|---|---|---|---|
| LanguageTool ar, pattern rules | 450 pattern rules in 40 groups and 14 categories. One category of 9 rules is off by default. | LGPL-2.1+ | Grammar and syntax (see §2): agreement 33, numerals 20, government/case after particles 9, sentence-structure constraints 13, verb transitivity and prepositions 47. Lexical misuse and style: about 290. Redundancy 6. Typography 3. Date semantics 13. |
| LanguageTool ar, Java and list-driven rules | 21 registered rule objects: 5 generic and 16 Arabic-specific. Data lists hold about 1,600 entries. | LGPL-2.1+ | Spelling (Hunspell). Punctuation spacing for 3 Arabic marks. Doubled punctuation. Unpaired brackets (7 pair types). Repeated word. Long sentence (above 50 tokens). Simple-replace list of 663 entries. Vowelling hints, 488. Colloquial and foreign words, 238. Sound-alike and homograph confusions, 170. Redundancy, 18. Wordiness, 11. Spelling-variant consistency, 6. Morphology-aware verb–preposition rule, 6. Inflection-aware word replacement, 2. Context-confusion list, 0 (empty). An n-gram confusion rule exists but is not registered. |
| LanguageTool ar, morphology resources | A full-form lexicon of about 12 MB with a synthesis lexicon of about 15 MB. Hunspell dictionary of about 7 MB. Verbal-noun↔verb maps of about 6.4k and 5.7k entries. | LGPL / GPL (Hunspell part) | Feeds every POS- or lemma-conditioned rule, plus synthesis of corrected forms. |
| Fareh | About 1,020 catalogued common-error entries: about 614 marked done, 8 under review, 14 ignored, the rest untriaged. 38 date-semantics rules, 25 review rules, about 200 converted replace rules. Derivation lexicons: active participle about 6.9k, passive participle about 1.3k, intensive form about 1.9k, adjectives about 520, verbal-noun↔verb about 6.5k. | GPL-3.0 | The upstream of most LanguageTool content. By its own category tags: fixed expressions 157, prepositional transitivity 110, verb usage 108, single-word usage 96, adjectives 45, vowelling 32, construct state (idafa) 29, prepositions 18, other small groups. |
| Ghalatawi (autocorrect) | About 18 regex rewrite rules. A typo table of 2 rules and a punctuation table of about 12 rules. An autocorrect word map of about 1.45 million entries. | GPL-3.0 | Hamzat al-wasl in derived-form verbal nouns. Alif maqsura combined with hamza. Missing space after a word-internal final-only letter. A detached "and" conjunction. Spaces around punctuation. Latin comma and semicolon replaced by Arabic ones. |
| Aghlat | A misspelling corpus of about 23k candidate-word rows plus about 330 confirmed wrong forms. Sample texts of about 85k lines. | AGPL-3.0 | An evaluation corpus, not rules. Useful as a model for building one's own test set; do not reuse its contents. |
| Sahehly / Qalam (commercial) | Not public. | Proprietary | From public category descriptions only: hamza, ta marbuta vs ha, alif maqsura vs ya, misused words, vowelling suggestions, and basic nominal- and verbal-sentence grammar. |

---

## 2. Category catalogue

Each entry gives:

- **(a)** what is detected;
- **(b)** the information required;
- **(c)** the suggestion offered;
- **(d)** the source count;
- **(e)** the severity class;
- **(f)** false-positive risks;
- the feasibility **tier**.

Unless noted, "source" means LanguageTool v6.8.

### 2.1 Spelling / orthography

**S1. General spelling (dictionary lookup).**

- **(a)** A word not found in a large affix-compressed dictionary. Short vowels are
  stripped before lookup, so vowelled and unvowelled text are treated alike.
- **(b)** A full-form or affix dictionary. Words are split on any non-letter character
  that is not a vowel mark.
- **(c)** Nearest dictionary forms by edit distance.
- **(d)** 1 rule. The dictionary is large, and small custom add/ignore lists hold about
  120 entries.
- **(e)** Spelling.
- **(f)** Proper names and transliterated foreign names. Clitic-heavy forms. Words in
  colloquial varieties.
- **Tier:** T2.

**S2. Hamza seat and hamzat al-qat' vs al-wasl, list-driven.**

- **(a)** Common words written with the wrong hamza form: missing hamza on alif,
  superfluous hamza on alif, or the wrong seat (alif, waw, ya, or the line).
- **(b)** None; whole-word lookup. Ghalatawi adds a generative variant: verbal nouns and
  derived forms of the measures that begin with a connecting alif (verb forms VII and
  VIII and the like) wrongly written with a cutting hamza. This is done by templates over
  root slots, with optional proclitics and enclitics.
- **(c)** The corrected spelling.
- **(d)** About 100 of the 663 simple-replace entries. About 18 generative rewrite rules
  in Ghalatawi. A very large generated autocorrect map (about 1.45 million), dominated
  by hamza and alif variants.
- **(e)** Spelling.
- **(f)** Some words have two valid readings that differ only by hamza; they change part
  of speech or meaning. Typical cases: a particle versus a noun, or a verbal noun versus
  a verb.
- **Tier:** T1. The generative template variant needs only string morphology.

**S3. Alif maqsura vs final ya.**

- **(a)** A final dotless ya written where a dotted ya is required, or the reverse. Mostly
  in high-frequency function words, prepositions and relative pronouns.
- **(b)** None, for the listed function words.
- **(c)** The corrected letter.
- **(d)** About 12 list entries. One generative rewrite in Ghalatawi.
- **(e)** Spelling.
- **(f)** Regional orthographic conventions (Egyptian practice writes final ya without
  dots). Should be a configurable style.
- **Tier:** T1.

**S4. Ta marbuta vs ha.**

- **(a)** A final ha written for ta marbuta, or the reverse.
- **(b)** Lexical list. A fully general check needs a lexicon.
- **(c)** The corrected spelling.
- **(d)** About 15 list entries.
- **(e)** Spelling.
- **(f)** Ha used as a 3rd-person masculine enclitic pronoun produces a valid word.
- **Tier:** T1 for the list; T2 in general.

**S5. Alif maqsura followed by hamza at word end.**

- **(a)** A dotless ya followed by a free hamza where a hamza on a ya-seat is intended.
- **(b)** A string rule.
- **(c)** The merged letter.
- **(d)** 1 Ghalatawi rule.
- **(e)** Spelling.
- **(f)** Rare.
- **Tier:** T1.

**S6. Run-together words.**

- **(a)** A final-only letter (ta marbuta or alif maqsura) appears in mid-word. This
  signals a missing space.
- **(b)** A string rule.
- **(c)** Insert a space.
- **(d)** 2 Ghalatawi rules. About 14 LT list entries are space or join fixes.
- **(e)** Spelling or typography.
- **(f)** Essentially none for ta marbuta. Rare for alif maqsura (some loanwords).
- **Tier:** T1.

**S7. Particle merging and splitting.**

- **(a)** Prepositions or particles that orthographic convention joins with a following
  "ma" or "la" but that are written apart. Or a conditional particle whose nun
  assimilates before a following "ma".
- **(b)** The next token must be a verb or a clause. The relative/redundant reading of
  "ma" matters, not the interrogative.
- **(c)** The joined, assimilated spelling.
- **(d)** 2 pattern rules, plus a few list entries.
- **(e)** Spelling.
- **(f)** Interrogative "ma" after a preposition is written differently. "Ma" as an
  independent pronoun also does not merge.
- **Tier:** T2 (needs the verb test); T1 for a conservative string version.

**S8. Spelling-variant consistency within a document.**

- **(a)** The same word appears in two accepted spellings in one text, for example two
  accepted hamza seats.
- **(b)** Document-level memory of the first variant seen.
- **(c)** The variant used first.
- **(d)** 1 rule, 6 variant pairs.
- **(e)** Spelling (consistency).
- **(f)** Quotations of other authors.
- **Tier:** T1.

**S9. Malformed lexical forms (non-word or wrong-pattern forms).**

- **(a)** A word built on the wrong morphological pattern. Sub-kinds:
  - a wrong verbal-noun pattern for a given root;
  - a wrong broken plural, or a sound plural where the language uses a broken one;
  - a doubled-root verb written un-assimilated where assimilation is required;
  - a weak-root verbal noun lacking the waw-to-ya assimilation;
  - a verb used in a derived measure (often form IV) that does not exist with the
    intended meaning, so form I is required;
  - a defective noun keeping its final ya in the indefinite;
  - a "hundred" written with an extra alif (both conventions exist).
- **(b)** Mostly whole-word lookup. The rule version inflects through the lemma, using
  any clitics and any number/gender suffix.
- **(c)** The correct form. In the inflection-aware variant, the correct lemma is
  re-synthesized with the original clitics and inflection.
- **(d)** About 320 list entries are single-word lexical substitutions of this or the
  lexical-misuse kind (S/L overlap). Plus 61 single-word pattern rules, of which about 25
  are of this kind. Plus 2 inflection-aware entries.
- **(e)** Spelling or grammar (morphology).
- **(f)**
  - Some forms flagged as "non-existent" are accepted by modern academies or are
    universal in Modern Standard Arabic, so prescriptivism is high.
  - Unvowelled homography: the form-I and form-IV spellings of many verbs coincide in
    the past tense. The sources guard this with antipatterns that check whether the
    correct lemma could also be the reading.
- **Tier:** T1 for frozen forms; T2 for the inflection-aware version.

**S10. Sound-alike confusions (dad vs za and similar).**

- **(a)** A word containing one emphatic consonant where the near-homophone with the
  other emphatic is the intended word.
- **(b)** In the source, none: every hit is flagged and both options are offered.
  Ideally, collocational context.
- **(c)** Both spellings, with a gloss.
- **(d)** About 52 of the 170 confusion entries.
- **(e)** Spelling (confused words).
- **(f)** High: both members are usually valid words. A context-free implementation
  fires on correct text.
- **Tier:** T1 as a "verify" hint. Context selection is T3, or needs n-grams.

### 2.2 Grammar

**G1. Demonstrative–noun gender agreement.**

- **(a)** A demonstrative pronoun followed by a definite noun with the opposite gender.
  Covers the near and far series and singular and dual forms.
- **(b)** The demonstrative class (closed, about 10 forms including duals), plus the
  gender and number of the next noun from a lexicon. Special lexical subsets: nouns that
  are grammatically feminine without a feminine marker (body parts, natural phenomena,
  about 10 in the source), and the reverse (a handful of masculine nouns ending in a
  feminine-looking letter).
- **(c)** The demonstrative of the other gender.
- **(d)** 16 rules.
- **(e)** Grammar.
- **(f)**
  - The demonstrative may be the subject of a nominal sentence whose predicate is the
    next word; the next word is then not the demonstrated noun. This is the main source
    of false positives. The source guards it only for gender-neutral and some masculine
    cases.
  - Broken plurals of non-human nouns take feminine-singular agreement.
  - Unvowelled ambiguity of gender in the lexicon.
- **Tier:** T2. Becomes reliable only at T3.

**G2. Dual demonstrative case agreement.**

- **(a)** A dual demonstrative whose case ending (the alif form vs the ya form) disagrees
  with the case of the following dual noun in apposition.
- **(b)** Morphological case of the dual noun. A closed set of 4 dual demonstrative
  forms, with optional proclitics.
- **(c)** The demonstrative in the other case form.
- **(d)** 6 rules.
- **(e)** Grammar.
- **(f)** The noun's case is often ambiguous without vowels. Duals of nouns ending in alif.
- **Tier:** T2.

**G3. Relative pronoun agreement.**

- **(a)** A definite masculine/feminine singular noun immediately followed by a relative
  pronoun of the other gender.
- **(b)** The singular relatives (closed, 2), plus the gender of the preceding noun.
- **(c)** The other relative pronoun.
- **(d)** 2 rules.
- **(e)** Grammar.
- **(f)** High. In a construct (idafa) chain the antecedent is often the first member,
  not the adjacent noun. The relative may also refer to a whole clause. Needs at least
  an idafa-aware check.
- **Tier:** T3.

**G4. Adjective agreement with the noun (gender, number, definiteness).**

- **(a)** An attributive adjective that disagrees in gender or number with its noun.
  Restricted in the source to:
  - nouns that are feminine without a marker;
  - adjective patterns whose feminine is not formed with ta marbuta;
  - a dual noun with an elative adjective;
  - an elative carrying the definite article that must agree with its subject.
- **(b)** Gender, number and definiteness of both words. The source uses unification over
  these features.
- **(c)** The inflected adjective, synthesized.
- **(d)** About 9 rules: 3 active, 3 in collocation groups, 2 disabled, 1 pronoun case.
  General adjective agreement is **not** implemented.
- **(e)** Grammar.
- **(f)** Non-human plural takes feminine singular. An adjective may follow the second
  member of a construct. A word may be a predicate rather than an attribute.
- **Tier:** T2 for the lexically restricted version; T3 for general agreement.

**G5. Mood after verbal particles (jussive).**

- **(a)** An imperfect verb not in the jussive after the jussive-governing negators: the
  "not" particle for the past, the "not yet" particle, and the prohibitive "do not".
  Also the prohibitive particle used with a non-second-person verb. The source checks
  the person, separating the negating from the prohibitive "la".
- **(b)** Closed class: jussive-governing particles, about 4 (plus the conditional
  particles if extended). Also the verb's mood, person and number. The source uses a
  disambiguation step that keeps only verb readings after these particles.
- **(c)** The jussive form, synthesized from the lemma. This covers dropping the final
  nun of the five verbs and shortening a weak final radical.
- **(d)** 4 rules.
- **(e)** Grammar.
- **(f)**
  - The unvowelled indicative and jussive of sound verbs are identical in spelling. Only
    defective verbs and the "five verbs" are visibly different.
  - A noun misread as a verb.
  - The negating "la" with a third-person verb is valid and must not be flagged as
    prohibitive.
  - The source uses antipatterns to accept already-jussive readings.
- **Tier:** T2. Morphological synthesis is required for the suggestion.

**G6. Negating a past verb with "la".**

- **(a)** "La" directly before a perfect verb, which classically requires repetition or
  denotes a prayer. The other negator is preferred.
- **(b)** POS of the next token: perfect verb.
- **(c)** The past-negation particle.
- **(d)** 1 rule, guarded by an antipattern for the repeated construction.
- **(e)** Grammar.
- **(f)** Fixed prayer formulas. A second "la" later in the sentence (repetition).
- **Tier:** T2.

**G7. Case after prepositions (genitive of duals and sound masculine plurals).**

- **(a)** A preposition followed by a dual or sound masculine plural in the nominative
  form, that is, the alif-nun or waw-nun ending instead of the ya ending.
- **(b)** Closed class: true prepositions (about 10 independent ones, plus the
  one-letter proclitic prepositions), and the inflectional case ending of the noun. The
  source keeps only noun readings after a preposition through disambiguation.
- **(c)** The genitive form, via synthesis.
- **(d)** 2 rules.
- **(e)** Grammar.
- **(f)**
  - The nominative noun may head a new clause after a pronominal or construct object.
  - Proper names ending in waw-nun (place and person names).
  - Lexicalized duals.
- **Tier:** T2.

**G8. Case after inna and her sisters.**

- **(a)** A dual or sound masculine plural in the nominative form directly after one of
  the particles that make their subject accusative.
- **(b)** Closed class: inna and her sisters (about 6, plus fused variants with
  pronouns), and the noun's case ending.
- **(c)** The accusative (ya) form.
- **(d)** 2 rules.
- **(e)** Grammar.
- **(f)**
  - The particle may be followed by a fronted prepositional predicate, so the noun
    after it is not the subject.
  - The particle may carry an attached pronoun.
  - Homography: the subordinating "an" (that) versus the conditional "in".
  - The emphatic and the interrogative readings.
- **Tier:** T2. Better at T3.

**G9. Kana and her sisters, and verbs of continuity.**

- **(a)** Misuse of a continuity verb ("still"-type verbs) with a preposition instead of
  a predicate in the accusative.
- **(b)** Closed class: kana-sisters (about 13), plus the next token.
- **(c)** Restructuring advice.
- **(d)** 1 rule. General checking of the accusative predicate is **not** implemented.
- **(e)** Grammar.
- **(f)** The full verb readings of the same lemmas.
- **Tier:** T2. The general case is T3.

**G10. Numerals: gender polarity and agreement.**

- **(a)** The numerals 3–10 must take the gender opposite to the counted singular noun.
  For 1–2 and 11–12, the numeral agrees with the noun. In 13–19 the units part is
  polar and the tens part agrees. For 21–99 the units follow the same pattern before
  "and + tens".
- **(b)** Closed class: cardinal number words (about 30 stems with their gendered
  variants). Also the gender of the counted noun, which for a plural noun is the gender
  of its singular, plus the noun's number.
- **(c)** The numeral in the other gender.
- **(d)** 17 rules.
- **(e)** Grammar.
- **(f)**
  - The counted noun is often plural: in a 3–10 construct the source looks at the
    plural noun's own gender tag, while the rule is defined on the singular's gender.
  - An intervening adjective.
  - Numerals used as ordinals or in dates.
  - Unvowelled forms where gender cannot be read.
- **Tier:** T2. Lemma-level gender is required.

**G11. Numerals: case and the number of the counted noun.**

- **(a)** Several checks:
  - tens in the nominative (waw-nun) form after a preposition;
  - after 11–99, the counted noun must be a singular indefinite accusative, not a plural;
  - a full number-phrase checker that rebuilds the whole numeral phrase in the correct
    case and gender, including units such as currencies and measures.
- **(b)** Closed class: cardinal words and prepositions. The full checker needs a
  number-to-words generator that is aware of gender, case and the counted noun, plus
  disambiguation that tags numeral phrases as a unit.
- **(c)** The corrected numeral phrase, generated.
- **(d)** 3 rules, plus a phrase generator of about 30 KB of support code.
- **(e)** Grammar.
- **(f)**
  - The number may be a subject placed after the preposition's object.
  - Long phrases spanning sentence boundaries.
  - The "thousand" and "million" plural agreement subtleties.
- **Tier:** T2 for case after a preposition and the counted-noun number. Full phrase
  synthesis is T2 plus a generator.

**G12. Indefinite subject at the start of a sentence.**

- **(a)** A sentence beginning with an indefinite noun followed directly by a
  prepositional phrase or adverbial that should be the fronted predicate.
- **(b)** Sentence start, the definiteness of the noun, and the POS of the following
  preposition, adverb or noun (including the one-letter proclitic prepositions).
- **(c)** Reordering advice: put the prepositional predicate first. No automatic
  replacement.
- **(d)** 5 rules.
- **(e)** Grammar (syntax).
- **(f)** High. The rule is wrong whenever the indefinite noun is specified by:
  - an adjective, or a construct (idafa) with a following noun;
  - a preceding negation or interrogative;
  - a verb reading of the noun's homograph;
  - headlines and titles.
- **Tier:** T3.

**G13. Particles restricted to sentence or clause position.**

- **(a)** Sub-cases:
  - a "while/whereas" conjunction used sentence-initially as a temporal opener;
  - the "as long as" particle used sentence-initially, before its main clause;
  - "either… or" without repetition of the second member;
  - the "whenever" particle repeated in both clauses (a calque);
  - the "never" future adverb used with a past verb where the "never" adverb for the
    past is required.
- **(b)** Sentence-start position, the closed set of these particles (about 6), and the
  verb tense for the adverb case.
- **(c)** Restructuring or substitution.
- **(d)** 6 rules.
- **(e)** Grammar or style.
- **(f)** The sentence-initial use of some of these is widespread in modern prose
  (prescriptive). Repetition detection across long sentences.
- **Tier:** T1/T2.

**G14. Interrogative particle "hal" incompatibilities.**

- **(a)** The yes/no particle "hal" followed by:
  - a negated clause;
  - an emphatic particle (inna);
  - a conditional particle;
  - plus its restriction of the imperfect to future meaning.
- **(b)** Closed class: negators and emphatic/conditional particles (about 10), plus the
  next token's POS.
- **(c)** Use the hamza interrogative instead.
- **(d)** About 4 rules.
- **(e)** Grammar.
- **(f)** Low.
- **Tier:** T1.

**G15. Verb government: prepositional transitivity.**

- **(a)** A verb (or its verbal noun or participle) followed by the wrong governed
  preposition, or by a preposition although it is directly transitive, or used
  directly although it requires a preposition. Also verbs that are doubly transitive
  (two direct objects) wrongly used with a preposition.
- **(b)** A lexicon of verbs with their governed preposition(s), matched by lemma. The
  preposition token may carry an attached pronoun, so the full set of the preposition
  plus each pronoun suffix must be recognized. Skip gaps of 1–2 tokens between the verb
  and the preposition allow for an intervening subject. The Java variant detects a verb
  with an attached object pronoun followed by a wrong or missing preposition. It then
  re-synthesizes the verb without the pronoun and the preposition with the pronoun.
- **(c)** The correct preposition. In the Java variant, a regenerated verb+preposition
  pair.
- **(d)** 27 verb-government rules, 20 rules on prepositions after nouns and
  participles, and 1 Java rule with 6 lexical entries. Fareh catalogues about 110
  prepositional-transitivity and 7 double-transitivity errors.
- **(e)** Grammar.
- **(f)**
  - The preposition may belong to a following adverbial phrase, not to the verb.
  - Verbs that legitimately take several prepositions with different meanings.
  - Skip gaps that cross clause boundaries.
- **Tier:** T2. The data list is the main effort.

### 2.3 Style / usage (lexical)

**L1. Verb–object collocation misuse (wrong verb for the object).**

- **(a)** A specific verb lemma with a specific object-noun lemma that classical usage
  considers wrong, for one of three reasons:
  - the verb's attested meaning differs;
  - the verb is intransitive;
  - the measure is wrong.
  The prototypical cases are calques of European idioms.
- **(b)** A lemma for the verb in any tense/person with clitics, a lemma plus the "no
  article/no clitic" condition for the object, and skip gaps of 1–2 tokens. Tense
  conditions apply in some cases. Antipatterns accept the correct verb when its
  unvowelled spelling collides with the wrong one.
- **(c)** A replacement verb, or advice only (many rules carry no replacement), plus a
  dictionary-style gloss.
- **(d)** 99 rules (the largest group).
- **(e)** Style. The source classes these as "wrong use".
- **(f)**
  - Strongly prescriptive: many targets are standard modern usage.
  - Skip gaps produce matches in which the noun is not the verb's object.
  - Unvowelled homographs of verbs.
- **Tier:** T2.

**L2. Fixed-expression and collocation errors.**

- **(a)** Multi-word expressions considered ungrammatical, calqued, or malformed. Kinds
  include:
  - an exceptive particle used with the wrong preposition;
  - an elative with the article followed by the comparison preposition;
  - "as + noun" in the sense of "in the capacity of" (a calque);
  - a superfluous "for" before a duration adverbial;
  - a repeated "between" with a pronoun;
  - "choose between" instead of "choose one of";
  - "a matter of" and "in the frame of" fillers;
  - wrong formulas for oaths, concession and exception;
  - wrong morphology in fixed idioms.
- **(b)** Mostly fixed token sequences, sometimes with a lemma, a POS slot or a short skip.
- **(c)** A replacement expression, often several alternatives.
- **(d)** About 50 collocation rules, 26 miscellaneous rules, 14 calque/structure rules,
  3 verbal-noun rules and 2 cognate-accusative rules (about 95 in total). A further
  about 280 multi-word entries sit in the simple-replace list.
- **(e)** Style or grammar.
- **(f)** Prescriptive. Fixed strings can occur across phrase boundaries.
- **Tier:** T1 for fixed strings; T2 where lemma/POS slots are used.

**L3. Single-word usage, semantic misuse and neologisms.**

- **(a)** Individual words whose modern meaning is considered a misuse of the classical
  sense, or neologisms, or adverbs formed irregularly. The suggestion is the preferred
  synonym.
- **(b)** Whole-word or lemma lookup with optional proclitics. A few rules carry
  context conditions (the following noun or preposition).
- **(c)** Preferred synonym(s), often 2–4, plus an explanation.
- **(d)** About 61 pattern rules and about 46 adjective rules (noun + adjective pairs in
  which the adjective is the wrong derivation or meaning). A large part of the about
  320 single-word replace entries.
- **(e)** Style.
- **(f)** Very prescriptive. Flags every occurrence regardless of sense.
- **Tier:** T1 for listed words; T2 with lemma conditions.

**L4. Colloquial and foreign loanwords.**

- **(a)** Dialect words and unassimilated loanwords (mostly Maghrebi and Levantine
  colloquial, plus European loans).
- **(b)** None; whole-word list.
- **(c)** The Standard Arabic equivalent.
- **(d)** 238 list entries.
- **(e)** Style (register).
- **(f)** Some colloquial forms are homographs of Standard Arabic words. Loanwords in
  technical contexts. Regionally variable.
- **Tier:** T1.

**L5. Light-verb and periphrastic constructions.**

- **(a)** Several patterns, each better expressed by a single verb or adverb:
  - "do/carry out + preposition + verbal noun" instead of the verb itself;
  - "in a + adjective manner" instead of an adverb or cognate accusative;
  - a "constitute/represent" verb used as a copula.
- **(b)** POS: an auxiliary verb lemma followed by a verbal noun with a proclitic
  preposition. A verbal-noun-to-verb lexicon (about 6k pairs). Synthesis of the main
  verb inflected like the auxiliary (same person, number, tense). A verb-to-cognate-
  accusative mapping.
- **(c)** A synthesized inflected verb, or a cognate verbal noun.
- **(d)** About 4 rules, plus 2 filters.
- **(e)** Style.
- **(f)**
  - The verbal noun may have several verbs.
  - The construction is required when the action noun is modified.
  - Synthesis may produce forms in the wrong voice.
- **Tier:** T2 (needs synthesis).

**L6. Redundancy and wordiness.**

- **(a)** Pleonasms: double future marking, a restriction particle combined with an
  "only" adverb, superfluous head nouns, double prepositions, "last but not least"-type
  calques. Wordy openers that can be compressed.
- **(b)** Fixed strings, a few lemma or POS slots, and a closed set of future markers
  and restriction particles.
- **(c)** The shorter form, or deletion.
- **(d)** 6 pattern rules, 18 redundancy list entries and 11 wordiness entries.
- **(e)** Style.
- **(f)** Emphatic repetition used deliberately.
- **Tier:** T1.

**L7. Vowelling hints (commonly mis-pronounced words and homographs).**

- **(a)** Unvowelled words that are commonly mispronounced, and homographs whose meanings
  differ by vowels. The checker suggests adding short vowels. Includes about 67
  multi-word proper names (Qur'anic and historical).
- **(b)** None; list lookup.
- **(c)** The fully or partly vowelled form; for homographs, all readings with glosses.
- **(d)** 488 vowelling entries and about 110 homograph entries.
- **(e)** Style (hint).
- **(f)** Very noisy: fires on every occurrence in correct text. Should be opt-in or
  info-level.
- **Tier:** T1.

**L8. Word repetition.**

- **(a)** The same word twice in a row.
- **(b)** Tokens, plus a small exception set of reduplicated adverbials ("step by step"
  type, about 2 in the source).
- **(c)** Delete one.
- **(d)** 1 rule.
- **(e)** Style or grammar.
- **(f)** Intensifying reduplication. Poetry.
- **Tier:** T1.

**L9. Sentence length.**

- **(a)** A sentence over a token threshold (50 in the source).
- **(b)** Sentence segmentation.
- **(c)** None.
- **(d)** 1 rule.
- **(e)** Style.
- **(f)** Arabic prose is traditionally long and comma-chained; the threshold should be
  higher or configurable.
- **Tier:** T1.

### 2.4 Typography

**T1-a. Placement of the accusative nunation (tanwin fath).**

- **(a)** The double-fatha mark placed on the seat alif instead of the preceding letter,
  or the reverse convention.
- **(b)** A character pattern at word end.
- **(c)** Move the mark.
- **(d)** 1 rule. A related rule suggests adding the nunation to distinguish indefinite
  accusatives.
- **(e)** Typography. Two conventions exist, so this should be configurable.
- **(f)** Both conventions occur in reputable print.
- **Tier:** T1.

**T1-b. Compound theophoric names.**

- **(a)** The servant-of prefix written fused to the following divine name.
- **(b)** A string pattern with a closed set of divine names (about 99 in the
  traditional list) and optional proclitics.
- **(c)** Insert a space.
- **(d)** 1 rule.
- **(e)** Typography.
- **(f)** Rare legitimate fused forms (some country-specific registrations).
- **Tier:** T1.

**T1-c. Kashida (tatweel).**

- **(a)** Elongation characters inside words.
- **(b)** Character test.
- **(c)** Remove them.
- **(d)** Not a rule in LT; it is stripped during normalization. Ghalatawi has a disabled
  rule for it.
- **(e)** Typography.
- **(f)** Intentional justification in display typography.
- **Tier:** T1.

**T1-d. Detached conjunction "wa".**

- **(a)** The one-letter conjunction written as a separate token.
- **(b)** Character test.
- **(c)** Attach it to the next word.
- **(d)** 2 Ghalatawi rules; none in LT.
- **(e)** Typography or spelling.
- **(f)** Enumerations in lists. Quotations of the bare letter.
- **Tier:** T1.

### 2.5 Punctuation

**P1. Spacing before Arabic punctuation.**

- **(a)** A space before the Arabic comma, the Arabic question mark or the Arabic
  semicolon. Also missing space after them.
- **(b)** Characters.
- **(c)** Remove or insert the space.
- **(d)** 3 dedicated rules, plus the generic comma/bracket whitespace rule.
- **(e)** Punctuation.
- **(f)** Number formats that use the Arabic comma. Ellipsis.
- **Tier:** T1.

**P2. Latin punctuation in Arabic text.**

- **(a)** The Latin question mark, comma or semicolon (and combined marks) used next to
  Arabic letters.
- **(b)** The script of the adjacent word.
- **(c)** The Arabic mark.
- **(d)** 4 list entries in LT and 2 Ghalatawi rules.
- **(e)** Punctuation.
- **(f)** Mixed-script segments. Code. URLs. Latin-digit decimal commas.
- **Tier:** T1.

**P3. Doubled punctuation.**

- **(a)** Two consecutive commas or periods, using the Arabic comma as the comma character.
- **(b)** Characters.
- **(c)** A single mark.
- **(d)** 1 rule.
- **(e)** Punctuation.
- **(f)** Ellipsis written as two dots.
- **Tier:** T1.

**P4. Unpaired brackets and quotes.**

- **(a)** An opening mark with no closing one, or the reverse. Covers round, square and
  curly brackets, guillemets, ornate Qur'anic parentheses, and straight double and single
  quotes.
- **(b)** Sentence or paragraph scope.
- **(c)** None, or the missing partner.
- **(d)** 1 rule over 7 pair types.
- **(e)** Punctuation.
- **(f)** Enumerations with a single closing parenthesis. Multi-paragraph quotations.
  The right-to-left mirror-glyph confusion: the ornate parentheses are encoded in
  visual order.
- **Tier:** T1.

**P5. Whitespace hygiene.**

- **(a)** Multiple spaces and missing space between sentences.
- **(b)** Characters.
- **(c)** Normalize.
- **(d)** 2 generic rules.
- **(e)** Typography.
- **Tier:** T1.

### 2.6 Semantic / consistency

**M1. Weekday vs calendar date.**

- **(a)** A weekday name followed by a day–month–year date on which that weekday does
  not fall. Supports Gregorian month names in their Levantine, Egyptian/Gulf and
  Maghrebi naming series.
- **(b)** Closed classes: weekday names (7, with and without the article) and three
  series of month names (about 12 each). A calendar computation.
- **(c)** The correct weekday.
- **(d)** 12 rules, plus filters (DMY and month-first variants). Fareh holds 38 drafts.
- **(e)** Grammar (semantics); consistency.
- **(f)** Hijri dates written with Gregorian-looking numbers. Partial dates. Ranges.
- **Tier:** T1.

**M2. Implausible year.**

- **(a)** A five-digit number after a season, month or "year" word.
- **(b)** A closed class of time words (about 40 including month series) and a digit
  pattern.
- **(c)** Ask whether a 4-digit year was meant.
- **(d)** 1 rule.
- **(e)** Typography or semantics.
- **(f)** Amounts following a month name in financial text.
- **Tier:** T1.

### 2.7 Tier roll-up

| Tier | Categories | Approximate share of source rules and entries |
|---|---|---|
| T1 | S2, S3, S4 (list), S5, S6, S8, S9 (frozen), S10 (hint), G13, G14, L2 (fixed), L3 (list), L4, L6, L7, L8, L9, all of §2.4, §2.5 and §2.6 | About 1,500 list entries and about 120 pattern rules |
| T2 | S1, S7, S9 (inflected), G2, G5, G6, G7, G8, G9, G10, G11, G15, L1, L2 and L3 (lemma variants), L5 | About 280 pattern rules |
| T3 | G1 and G4 when made reliable, G3, G12, general adjective and kana/inna agreement | About 30 pattern rules; most of the uncovered grammar lives here |

---

## 3. Engine-feature overview (what the rules need)

1. **Tokenization.**
   - Split words on whitespace and punctuation, with the Arabic comma, semicolon and
     question mark treated as punctuation.
   - Short vowels and tatweel are stripped for matching but kept for display.
   - Sentence segmentation must know the Arabic marks.
2. **Clitic-aware tagging.**
   - Each token gets every reading produced by stripping proclitics (conjunction,
     prepositions, article, future prefix) and enclitic object or possessive pronouns.
   - Each stem is looked up in a full-form lexicon.
   - Readings carry these features:
     - part of speech (noun/verb/particle with subclasses such as verbal noun,
       adjective, participle, proper noun, elative, frozen noun);
     - gender and number, separating sound and broken plurals;
     - case or mood, and the visible case-ending type;
     - verb tense, person and voice;
     - flags for conjunction, preposition, definite article and enclitic presence.
   - Rules depend on all of these features.
3. **Token patterns.**
   - Match by exact word, a word alternative set, the lemma (any inflection), a regular
     expression over the surface form, or a feature condition over readings.
   - Negated tokens and exception sub-conditions on a token are both used.
4. **Skips / gaps.** Up to 2 tokens between anchors (in L1, L2, G15), and optionally
   unlimited until a condition holds.
5. **Antipatterns.** Whole-sequence vetoes. Used for these purposes:
   - accept correct forms that share an unvowelled spelling with the error (verb
     measures; jussive already present);
   - list gender-neutral nouns;
   - legitimate repetition constructions.
6. **Unification.** Require gender, number or definiteness to be equal or unequal across
   two tokens (G1, G4, adjective rules). Used in about 45 rules.
7. **Synthesis of corrected forms.** Generate a word from the lemma plus target features.
   Main uses:
   - jussive mood;
   - genitive or accusative of duals and plurals;
   - the opposite-gender demonstrative or adjective;
   - re-inflect a replacement lemma like the original token (clitics, number, gender);
   - inflect a verb like an auxiliary verb;
   - move an enclitic pronoun from a verb onto a preposition.
8. **Filters (post-match code).**
   - Calendar check.
   - Number-phrase rebuild (number words in gender and case, plus counted-noun units).
   - Verbal noun to verb.
   - Verb to cognate accusative.
   - Adjective to exclamatory form (present but barely used).
9. **Disambiguation.** A few rules:
   - keep only verb readings after verbal particles;
   - keep only noun readings after prepositions;
   - mark numeral sequences as a numeric phrase;
   - a multiword chunker (its list is empty in the source).
   No statistical tagger is used. Hence T3 rules rely on adjacency heuristics and have
   high false-positive rates.
10. **List-driven replace rules.**
    - Word or phrase lookup to suggestions, with an optional explanation per entry.
    - Matching is case- and diacritic-insensitive.
    - Multi-word keys are matched as token sequences.
    - A document-level coherency variant remembers the first variant seen.
11. **Optional statistical layer.** An n-gram confusion-pair rule exists but is
    unregistered, since there is no Arabic language model. A context-word confusion rule
    exists with an empty list. Both would be the right home for S10.
12. **Rule metadata.** Category, severity type (grammar / style / typographical /
    numbers / semantics), default-off flag, and per-rule examples used as unit tests.
    Every source rule ships correct/incorrect examples that are verified in CI. The
    implementer should do the same with their own sentences.

---

## 4. What the existing Quds ruleset already covers, and the gaps

The Quds ruleset has 11 rule IDs, covering:

1. Hamza on alif for listed words. This corresponds to S2, list form, at T1. **Gap:** the
   generative template rules for connecting-alif measures (forms VII, VIII and X verbal
   nouns), and hamza-seat errors on waw and ya.
2. Definite ta marbuta for listed stems. This corresponds to S4 at T1. **Gap:** the
   indefinite forms, and the reverse error (ta marbuta written for the ha pronoun).
3. Alif maqsura vs ya. This corresponds to S3.
4. Final ya written as alif maqsura (style). This corresponds to S3, regional-convention
   variant.
5. Arabic punctuation marks and spacing before and after them. This corresponds to P1
   and P2.
6. Tatweel. This corresponds to T1-c.
7. Repetition of closed-class words. This is a subset of L8. **Gap:** repetition of
   content words; an exception set for reduplicated adverbials.
8. Detached conjunction waw. This corresponds to T1-d.
9. Mixed digit systems (Arabic-Indic vs Western within one text). There is no direct
   source equivalent; it is a consistency check similar to S8.

**Not covered: T1 gaps, cheapest first.**

- P3 doubled punctuation.
- P4 unpaired brackets and quotes, including the ornate parentheses and guillemets.
- P5 whitespace hygiene.
- S5 alif maqsura combined with hamza.
- S6 run-together words after a final-only letter.
- S8 spelling-variant consistency in a document.
- T1-a nunation placement (configurable).
- T1-b fused theophoric names.
- M1 weekday/date consistency (needs calendar code only).
- M2 implausible year.
- G14 "hal" incompatibilities.
- G13 position-restricted particles.
- L6 redundancy and wordiness.
- L4 colloquial and loanwords (needs an authored list).
- L2 fixed expressions (needs an authored list).
- L3 single-word misuse (needs an authored list; keep it opt-in because it is
  prescriptive).
- L7 vowelling hints (opt-in only).
- L9 long sentences, with a higher threshold.
- S10 dad/za confusions as an info-level "verify" hint.

**Not covered: T2 gaps, which need a lexicon with gender, number, case and lemma.**

- G10 and G11 numeral agreement. This is the highest-value grammar area and is mostly a
  closed class: number words plus the gender of the counted noun's singular.
- G5 jussive after negators. The visible cases only: defective verbs and the five verbs.
- G7 and G8 case endings of duals and sound masculine plurals after prepositions and
  after inna-sisters.
- G2 dual demonstrative case.
- G6 "la" with a past verb.
- G15 prepositional transitivity (lexicon-driven).
- L1 verb–object collocations.
- L5 light-verb constructions (needs a verbal-noun↔verb map and synthesis).
- S7 particle merging.
- S9 malformed patterns (inflection-aware).
- S1 general spelling (needs an MIT-compatible dictionary; the Hunspell dictionary in the
  sources is GPL).

**Not covered: T3 gaps.** Demonstrative, relative and adjective agreement made reliable
(G1, G3, G4), the indefinite-subject rule (G12), and general kana/inna predicate case.
All the studied open checkers implement these only as adjacency heuristics with many
false positives. They should not be attempted without a POS disambiguator.

---

### Self-check

This spec contains no copied rule messages, explanations, comments, example sentences,
word or replacement lists, pattern token sequences, regexes, POS-tag strings, rule IDs or
file structures from the sources. Closed classes are described by grammatical definition
and approximate size only.
