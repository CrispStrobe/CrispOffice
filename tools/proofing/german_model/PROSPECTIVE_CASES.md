# Prospective synthetic German challenge — 17 November 2026

`prospective_cases_20261117.json` is an authored development challenge for
comparing deterministic grammar, the optional guarded model and their combined
behavior. Its inputs and expected corrections were written before executing or
inspecting any provider outputs for these inputs. No sentences were copied from
a third-party corpus. The existing `cases.json` was read to avoid its exact
inputs; it remains unchanged.

This is a **prospective synthetic development challenge**, not a representative
held-out accuracy sample. It deliberately selects grammatical constructions and
clean near-neighbors. It is not randomly sampled user writing, an independently
annotated corpus, or evidence of absence from model training data. Once its
outputs inform implementation, retain it as a regression panel and identify any
new prospective panel separately.

## Panel and target policy

The panel contains **76 rows**: 32 de-DE errors paired with their 32 corrected
clean counterparts, eight additional de-DE clean adversarial controls, and four
separate locale controls. The 32 pairs cover the following constructions:

| Category | Error/clean pairs | Target |
| --- | ---: | --- |
| `pronoun-verb` | 8 | Finite verb agreement with an explicit personal pronoun |
| `noun-phrase` | 8 | Noun gender, fixed-preposition case and adjective endings |
| `noun-inflection` | 6 | Dative plural, weak nouns and explicit genitives |
| `dass-das` | 4 | Complement conjunction versus subject/object relative pronouns |
| `word-order` | 2 | Main-clause inversion and a finite verb in a `dass` clause |
| `comparison` | 2 | Missing comparative and duplicated comparative inflection |
| `participle` | 2 | Irregular participles of `schreiben` and `finden` |

Targets use contemporary standard written German. They preserve the stated
subject, noun referent, proposition, punctuation and surrounding wording while
repairing the selected defect. Each target is one local grammatical repair;
word-order targets move existing words. Alternative changes to subjects,
lexical choices or sentence structure may also yield grammatical sentences, so
an exact-target miss alone does not prove an invalid suggestion. Review such
outputs separately before interpreting quality.

The comparisons probe inflection, avoiding regional `wie`/`als` usage. The
subordinate-order example uses `dass`, avoiding conversational verb-second
`weil`. Genitives have explicit `des`/`dieses`; they do not require a policy
choice about variable-case prepositions. No stylistic preference is an error
target.

Each clean member is byte-for-byte equal to its error partner's `expected`
text. The eight extra clean cases exercise demonstrative/plural agreement,
singular `Sie`, dative `Ihr`, the distinct readings of `Leiter`, an s-plural in
the dative, and adjacent conjunction/relative/demonstrative/article uses of
`das`. They must remain unchanged.

## Schema and measurement

The file preserves the existing flat-array shape with `id`, `kind`, `input`,
`expected` on errors only, and explicit `locale`. Extra metadata is:

- `category`: the construction or separate control cohort.
- `pair_id`: shared by the error and corrected-clean member; `null` on
  standalone adversarial and locale controls.
- `expected_model_status`: `unsupported` on the four locale controls only.

The two de-AT and two de-CH rows test the model provider's explicit unsupported
status. They are clean regional controls, including Austrian vocabulary and
perfect auxiliary use, and Swiss `ss` spelling. **Do not count unsupported
model checks as successful clean checks or as language-quality errors.**
Deterministic locale support is a separate measurement.

Freeze the reviewed corpus, record its exact SHA-256 and source commit, and
push that checkpoint before the first evaluation. Record each mode's source,
configuration, status, findings and corrected text without changing this file
to match observed outputs. Report exact corrections on 32 de-DE errors and
changed-text/flagged controls on the 40 de-DE clean rows separately. Keep
category and paired-case results available; avoid treating the artificial
error-to-clean ratio as real-world prevalence.

For incremental value, identify errors fixed only by the combined configuration,
deterministic fixes lost or altered, and additional clean-case edits. Preserve
the original frozen panel as an independent regression check. The new challenge
does not qualify broad precision/recall, de-AT/de-CH model support, long-text
coverage, device performance or default model promotion.
