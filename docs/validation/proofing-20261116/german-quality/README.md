# German proofing quality checkpoint

Source: `3ebe347f8d3c9577d44ac51b1f1fc92a544f1bf4`. The implementation and regressions are saved in
`codex/proofing-german-quality-20261116` after the reconciled `dbf5ff0` base.

## Changes

- German spelling and writing checks protect closed code spans with matching
  one-or-more-backtick delimiter lengths, including multiline spans. Unmatched
  delimiters leave subsequent prose eligible for checking.
- Finite indicative agreement covers `sein`, `haben`, `werden`, `können`,
  `müssen`, `dürfen`, `sollen`, `wollen` and `mögen` for adjacent `ich`, `du`
  and `wir`. Existing narrow `ihr`/`sein` checks exclude common dative and
  impersonal constructions. Ambiguous `sie`/`es` are not inferred.
- Comparison, coordinated-subject, relative-clause coordination and nominal
  pronoun contexts remain outside those narrow corrections. Subjunctive and
  imperative forms are not inferred. Tabs, NBSP, narrow NBSP, source offsets,
  uppercase replacements, protected context and grapheme boundaries are covered.
- Spelling suggestions can repair one unknown component of an explicit hyphen
  compound while keeping other components' case. The existing search budget
  remains in force. ASCII/U+2010/U+2011 separators retain their source style,
  including for distinct occurrences sharing a normalized lookup result.

These are independently authored, bounded checks, not a full grammar or
morphology parser. New external language data and dependencies were not added.

## Verification and limits

**No Dart/Flutter execution was available.** Ten Dart regression-test
definitions were added and reviewed; they were not run. The two modified
test files now contain 26 spelling and 24 writing test definitions.

The saved JavaScript evidence contains **209 checks**:

- 182 checks reading the actual grammar regexes and finite paradigms, then
  executing an independent translation of the relevant control flow.
- 27 spelling-model and protected-token checks using the real shipped
  dictionary: 444,123 standard forms, 9,451 Swiss additions, 113 decoded chunks.

The previous 10 isolated code-delimiter probes are included in the 27 and
must not be counted twice. None of these results establishes compiled Dart,
Flutter, browser, or native integration correctness.

[receipt.json](receipt.json) binds the exact four Dart-file blobs and 17 data
blobs. [cases.json](cases.json) retains positive and valid-control grammar
examples. [probe.mjs](probe.mjs) reproduces the independent checks with Node
built-ins and refuses changed source blobs:

```sh
node docs/validation/proofing-20261116/german-quality/probe.mjs .
cd packages/quds_office_engine
dart test test/proofing/german_spelling_test.dart test/proofing/german_writing_rules_test.dart
```

During this session, a pinned pako 2.1.0 inflater (MIT AND Zlib) was used only
in the transient JavaScript isolate to decode the shipped dictionary.
It is not shipped, installed or added as a package dependency. The reusable
probe uses Node's built-in `zlib` instead.

GitHub Actions were neither queried nor awaited. Source and tests were pushed
incrementally with `[skip ci]`; this evidence does not reclassify earlier
test receipts as results for the new implementation.
