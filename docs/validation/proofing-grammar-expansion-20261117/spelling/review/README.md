# Independent read-only German grammar review

The review inspected the new phrase analysis, determiner/adjective ambiguity,
dative plurals, inverted agreement, Swiss replacement normalization, protected
context checks, and soft-hyphen source projection. It used
[`grammar-review.dart`](grammar-review.dart) to confirm specific suspected
defects. The reviewer changed no production or test source and performed no Git
writes. The grammar implementation owner supplied fixes and regression tests.

## Confirmed defects and fixes

### Subordinate infinitives before a modal or future verb

The initial implementation incorrectly conjugated the infinitive in ordinary
subordinate clauses:

| Valid input | Incorrect initial suggestion |
| --- | --- |
| `Ich weiß, dass er gehen kann.` | `gehen` → `geht` |
| `Wenn ich helfen kann, komme ich.` | `helfen` → `helfe` |
| `Du sagst, dass du kommen willst.` | `kommen` → `kommst` |
| `Wie schön es ist, wenn ich lesen darf.` | `lesen` → `lese` |
| `Ich weiß, dass er gehen wird.` | `gehen` → `geht` |

The implementation owner added a bounded lookahead for a governing finite
verb. An intermediate rerun still flagged `Wenn ich helfen kann, komme ich.`:
the lookahead crossed the comma and interpreted `ich` in the next main clause
as competing evidence. The owner changed this particular lookahead to use a
comma-aware boundary, preserving the older, separate `ihr` handling. All five
inputs are clean in the final focused rerun.

### A role is not necessarily an equality comparison

`Er ist so gut als Lehrer.` and `Er ist so gut als Arzt.` initially received
`als` → `wie`. Here the bare noun can name a role. The reverse comparison rule
now requires a bounded single pronoun or determiner-led noun phrase and
abstains on those bare roles. Both inputs are clean in the final rerun.

The positive control `Er ist besser wie erwartet.` still produces the intended
`wie` → `als` suggestion. The probe also contains a deliberately ambiguous
`Es geht mir besser wie jedes Jahr im Frühling.` example; its unchanged
comparison finding is retained in the raw output and is not claimed as a clean
negative control or evidence of general sentence interpretation.

## Evidence and boundaries

- [`grammar-review.jsonl`](grammar-review.jsonl): original findings.
- [`grammar-review-fixed.jsonl`](grammar-review-fixed.jsonl): intermediate fix,
  retaining the comma-boundary failure.
- [`grammar-review-final.jsonl`](grammar-review-final.jsonl): final focused
  behavior after both fixes.

The remaining inspected phrase/source handling revealed no further concrete
range, protected-context, or replacement-normalization defect. New issues pass
through the existing soft-hyphen projection and grapheme checks; phrase rules
verify their governing context against protected spans, and Swiss replacement
normalization occurs centrally.

This is a focused review of specific risks, not an exhaustive German grammar
evaluation. It neither establishes broad linguistic accuracy nor removes the
documented limits of finite noun/verb/adjective resources and bounded context.

Reproduce against the selected checkout from the repository root:

```sh
dart --packages=.dart_tool/package_config.json \
  docs/validation/proofing-grammar-expansion-20261117/spelling/review/grammar-review.dart
```
