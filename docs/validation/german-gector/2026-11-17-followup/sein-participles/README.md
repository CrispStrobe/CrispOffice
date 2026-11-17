# Reviewed sein participle spelling preferences

The spelling provider now prefers nine independently authored, dictionary-verified irregular participles in the existing bounded pronoun/auxiliary frame. Present and past forms of `sein` must agree with the pronoun. The former `haben` preferences keep their existing auxiliary licensing.

For the retained example, `Er ist nach Hause gegangt.` now proposes `gegangen` first in both the spelling and incoming grammar providers. Spelling previously proposed `gebangt`. Accepted words, including the valid finite form `gefallt`, are not reconsidered. The candidate budget, cache separation, protected/literal text, source offsets and grapheme boundaries retain their existing handling. This is a finite suggestion preference, not a general conjugator or sentence parser.

The incoming integration also exposed one message regression: a preposition-case finding lost its preposition-specific wording. Its default message is restored, and incoming verb/copula cases receive their generic message explicitly.

## Local results

- Initial integrated focus: 246 passed, 1 failed (message regression).
- Repaired integrated focus: 247 passed, no failures.
- New tests before implementation: 34 passed, 15 expected failures.
- Final focus: 265 passed, no failures.
- Full `test/proofing` VM suite: 945 passed, no failures or skips.
- Participles compiled to JavaScript and executed in Node: 49 passed, no failures or skips.
- Strict analysis of proofing sources and tests: clean.

Focused and Node runs overlap the full VM count; they are not additional distinct tests. Every captured run, including the failed-before attempts, is preserved in the compressed logs. `summary.json` records commands, identities, counts, failure details and evidence hashes. These tests establish bounded behavior and regressions; representative quality and native performance require separate evaluation.
