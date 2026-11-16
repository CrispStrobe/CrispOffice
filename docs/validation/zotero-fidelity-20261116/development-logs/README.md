# Development and review logs

These logs preserve incremental checks and the failures that informed the final
implementation. They are not an additional test total. The non-overlapping final
combined execution is recorded in `../final/receipt.json`.

- Unicode expansion tests exposed Dart simple-uppercase limitations; the licensed
  default Unicode full-uppercase expansion table fixes these cases.
- Shaping tests exposed combining-mark object replacement; display offsets now
  follow source indices, including narrow-cell wrapping.
- Older simplification tests now use unsupported `all-small-caps`, because native
  small capitals are supported.
- Earlier catalog harness launches lacked canonical analyzer configuration or
  raced the Flutter shell wrapper. Genuine locked harnesses and direct SDK/tool
  entrypoints were used for final qualification.
- Bibliography development corrected a typed inline-list insertion error, test
  fixture property/whitespace expectations, and the identical-plain-text legacy
  layout edge. The final engine and controller regression cohorts passed.

Archive hashes are recorded in `inventory.json`. No earlier overlapping run is
counted as an additional executed final test.
