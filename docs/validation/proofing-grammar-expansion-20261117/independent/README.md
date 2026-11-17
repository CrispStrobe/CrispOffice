# Independent German grammar review

**Passed against committed source `3a2ada5a04395fd2fa01c7878f4df9f1b9215558`.**
The [qualification receipt](qualified/receipt.json) binds the exact four current
proofing source files, the restored historical source, the corpus, runtime
binaries, commands and logs. Source hashes were unchanged throughout the run.

## Measured change on the same texts

This is an independently authored, deliberately targeted construction regression
corpus. It is **not** a representative estimate of general German accuracy,
precision or recall. Both comparison arms use the same `de-DE` requests, texts
and runtime; every response has successful provider status.

| Measurement | Previous head `62563c61` | Qualified source `3a2ada5a` |
| --- | ---: | ---: |
| Targeted erroneous sentences | 39 | 39 |
| Detected errors with the exact expected correction | 0 | 39 |
| Valid/adversarial control sentences | 213 | 213 |
| Valid sentences receiving a finding | 4 | 0 |

The 39 errors cover prepositional pronoun/article case, dative plurals,
adjective endings, `das/dass`, missing subordinate commas, comparisons,
third-person and inverted agreement, and newly covered finite verb families.
The complete [positive corpus](qualified/positive-cases.json) gives each
expected rule, source token and replacement. The full
[valid corpus](qualified/negative-text.json) includes subjunctives, imperatives,
finite/infinitive ownership, names, dative and possessive `ihr`, coordination,
adverb modifiers, weak and plural-only nouns, borrowed `-s` plurals, literary
dative singular `-e`, quotes, code and bounded-lookahead cases.

The four inherited false positives were `Kann ich gehen?`,
`Könnte ich gehen?`, `Würde ich gehen?` and `Dürfte ich kommen?`.
The baseline incorrectly conjugated their infinitives. The qualified checker
leaves all four untouched.

The baseline is an exact three-file projection restored with `git show` from
`62563c61f02ee44504776d9e7d26557f9bae490a`, using the same pinned `characters`
dependency. It does not replace any active checkout file. See the
[baseline source receipt](qualified/baseline/baseline-source-receipt.json) and
[restoration program](prepare_baseline.py).

## Source ranges and runtime parity

The candidate also passed the same standalone suite on Dart VM and compiled
JavaScript in Node. Each runtime executed:

- **195 positive variants:** each of the 39 examples as ordinary `de-DE`,
  emoji plus nonzero origin in `de-AT`, authored soft hyphens in `de-CH`, an
  ignored rule, and a protected backtick span.
- **117 correction rechecks:** apply the actual replacement to its exact
  original UTF-16 range and check the resulting text again in the same locale.
- **213 valid controls:** check with an emoji prefix and nonzero source origin.

That is 525 provider requests per runtime. Variants and rechecks are not
additional independent language examples. Swiss replacements are checked for
`ss` rather than `ß`. The complete VM/Node summaries and command hashes are in
the qualification receipt; the generated source is
[grammar_review_suite.dart](grammar_review_suite.dart).

## Review history

The [attempts](attempts/) directory retains the initial findings that led to
the adverb, temporal comparison, infinitive, dative-singular and modal-ownership
safeguards. The reviewers reran the same controls after the fixes.

One initial positive fixture used nonexistent spelling `helfst`. That is
outside the finite grammar's known-form agreement rule. Its original fixture
and failed attempt remain in `attempts`; the final agreement fixture uses the
real wrong-person form `hilfst` in `Ich hilfst gern.`. The correction is
`helfe`. This change is explicit and is not counted as a grammar implementation
fix for an unknown verb form.

## Reproduce

Prepare the pinned SDK and exact workspace lock as described in
[runtime](../runtime/README.md), then run from the repository root with Dart
and Node on `PATH`:

```sh
python3 docs/validation/proofing-grammar-expansion-20261117/independent/qualify_independent_grammar.py \
  --repository . \
  --output ../proofing-independent-replay
```

The program requires the relevant source to be committed, records its current
commit and hashes, reconstructs the baseline separately, checks successful status before counting
an empty result as clean, and records a failed receipt if a comparison or
runtime check fails. Unknown constructions remain outside this finite checker.
