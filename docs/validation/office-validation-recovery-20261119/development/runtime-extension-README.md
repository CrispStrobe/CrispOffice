# Verified runtime extension and preparation evidence

This archive preserves the untouched pre-extension receipts and package/native
mappings, the old workspace lock, all 18 newly downloaded locked archive bytes,
the extension receipt and raw offline-resolution/native-smoke logs. It also
contains a snapshot of current runtime metadata, all focused extension-control
evidence, and the original and corrected final formatting preflights.

The extension succeeded with 194 verified archives and 12,272 retained inputs.
Independent reconstruction distinguishes 11,142 original unchanged files,
1,002 new archive-derived package files and 128 separately bound Pub metadata
JSON files. Metadata for 17 inactive package names is explicitly not a new
installed dependency. The initial format preflight found one inherited wrapping
difference; the formatter changed only that line wrap, and all 147 selected
files then passed the repeated check.

The 53 indexed members contain 47 regular files and 11,831,802 original file
bytes. Complete original-byte, size, hash, mode and nanosecond timestamp checks
passed. A second full archive build reproduced identical bytes. Compressed
SHA-256: `d68286c0fdd500a94c0f0d8744affbbaf4d7f85fd11c00c1318f9f77790b93a0`.

SDK copies and extracted copies of the newly downloaded archives are omitted:
they are reproducible from pinned archives and duplicate existing package
bytes. No authored source, receipt or raw log inside the declared sources is
omitted. The full capture command and complete index are adjacent. These are
preparation and development records, not the final aggregate acceptance.
