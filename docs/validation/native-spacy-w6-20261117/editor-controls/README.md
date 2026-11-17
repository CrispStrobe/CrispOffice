# Real native grammar/editor integration controls

The explicit `studio_spacy_grammar_native_gate.dart` gate passes **10 controls**
using the restored, authenticated native worker and the actual
`WordEditorController` manual proofing service. The ordinary service is
`GermanWritingRulesProvider`; the optional provider is registered only on the
manual service by this test harness.

The German development segment `Die Katzen im Garten schläft.` follows an
English-language `😀 English. ` run. The request starts at UTF-16 offset 12,
and the actual suggestion selects `schläft` at paragraph offsets **33–40**.
Applying `schlafen` preserves the prefix, language metadata and normal
correction history. Explicit corrected rechecks are clean, and undo/redo
restore the expected text and selection.

The remaining controls exercise both native and existing noun-agreement rule
ignores and restoration, personal vocabulary updates, document and vocabulary
revision invalidation, locked content, paragraph and complex fields, typing
and background omission, and explicit unsupported locales. Native call counts
remain zero for background-only checks and unsupported locale checks. Field
protection prevents applying prior findings and excludes fresh cached text.

Two lifecycle controls delay an **actual** native reply to make stale-result
timing deterministic. They do not change its request, tokens or runtime
identity. No model output is mocked. Each harness awaits owned worker cleanup,
and missing model/native configuration fails instead of skipping.

[The first run](first.json) and [the final run](final.json) both pass all ten
controls. Only the new test changes between them: the final version explicitly
requires successful supported manual reports and successful actual native
responses, ensuring that an operational failure cannot appear as a clean
corrected recheck. Both exact test versions, complete logs and before/after
source manifests are retained. All **422** captured source/manifest paths and
the native library/model manifest remain unchanged during each execution.
[Final static analysis](analysis-final.log) reports zero issues.

[The summary](summary.json) authenticates both attempts. They reuse one authored
development error and its corrected version; repeated runs and lifecycle
variants are not additional independent grammar cases. Neither the separate
grammar qualification panel nor the consumed native acceptance inputs were
read by this gate task. No GitHub Actions endpoint was queried or awaited.
