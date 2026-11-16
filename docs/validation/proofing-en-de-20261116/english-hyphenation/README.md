# English hyphenation continuation evidence

Source checkpoint: **d90176bb142e1d26379d228cf924c1a8cae346f8**. Integration base:
`dbf5ff000d66bd6e2833ade990ab84de009e3ad8`.

## Delivered changes

The shared Word layout path now selects separate American and British English
pattern sets as well as the existing German patterns. English uses the
original upstream exception lists and minimum fragments of two letters before
and three after a break. It preserves source UTF-16 offsets and the existing
line breaker's discretionary-hyphen ownership. German implementation and data
are unchanged.

`en` and `en-US` are equivalent American aliases. `en-GB` uses British
patterns. Other English dialects receive no automatic dictionary candidates.
Mixed-dialect words, authored soft hyphens, non-ASCII words, contractions,
identifiers and join-control-adjacent fragments are conservatively skipped.
HTTP(S)/WWW URLs, emails and matching backtick code spans are protected.
The 17 added Dart tests cover those boundaries, upstream exceptions, cache
ownership, mixed English/German dispatch and source-preserving Word layout.

The complete original sources, their license grants, generated data and
SHA-256 provenance are in
[the English provenance directory](../../../../packages/quds_office_engine/third_party/hyphenation/ENGLISH.md).
American patterns use Kuiken's explicit permissive grant; British patterns use
MIT. The restricted underlying OUP word list is not bundled. No package
dependency, GPL/AGPL/LGPL-only corpus or network proofing service was added.

## What executed in this continuation

The attached execution environment was unavailable. The following checks ran
in the available **functions.exec V8 JavaScript isolate**, using the exact
checked-in source data and the actual Dart token/protected-span expressions:

| Check | Result |
| --- | --- |
| American trie versus independent flat-pattern oracle | 442 word comparisons passed |
| British trie versus independent flat-pattern oracle | 741 word comparisons passed |
| Fixed dialect, exception, casing and lexical controls | 21 passed |
| Paragraph offsets, language aliases, protected spans, identifiers and join controls | 32 passed |
| Exact generated pattern/exception equality and original license prefaces | Both languages passed |
| Pattern letter-key uniqueness | Both languages passed |
| Fresh GitHub content readback | All 14 owned source inputs matched |
| Original TeX blobs versus upstream | Both Git blob IDs identical |

These are data and reference-algorithm checks. **They do not execute the
production Dart implementation or establish Dart/Flutter build success.**
The source-derived JavaScript trie and the independent flat oracle agree on
the recorded corpus; the production Dart implementation still requires its
added tests and analyzer to run in a functioning environment.

[reference-receipt.json](reference-receipt.json) records the precise scope.
[source-inputs.json](source-inputs.json) binds the 14 relevant changed inputs
to the checkpoint using SHA-256 hashes and Git blob IDs. This is not a complete
build dependency manifest.

## Reproduction

The evidence checker can run with Node in a functioning checkout:

```sh
node docs/validation/proofing-en-de-20261116/english-hyphenation/reference_check.mjs
```

It first rejects any drift in the recorded inputs, then repeats the same
JavaScript data/reference checks. This Node CLI was not executed here;
the identical pure validation core before its CLI footer was executed in V8.

The existing production validation workflow was extended to include all new
English source/data/provenance files, the generator's `--check` mode, strict
Dart analysis, and `english_hyphenation_test.dart`:

```sh
python3 packages/quds_office_engine/tool/proofing/validate_hyphenation.py \
  --dart /path/to/dart \
  --output /path/to/new-hyphenation-validation
```

Alternatively, the focused data and Dart checks are:

```sh
python3 packages/quds_office_engine/tool/proofing/generate_english_hyphenation.py --check
cd packages/quds_office_engine
dart test test/english_hyphenation_test.dart test/proofing_hyphenation_test.dart
```

**No Dart tests, Dart analysis, Flutter/browser/PDF runtime test, or Python
generator process ran in this continuation.** Prior qualification receipts
remain attached to their original commits. GitHub Actions were not queried
or awaited.
