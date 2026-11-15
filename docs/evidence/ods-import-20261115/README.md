# Canonical ODS import qualification

Source: `79aaf82eb82ea5a4019c8e3536789b34dabede5c` in
`CrispStrobe/quds_office_suite`, local branch
`integration/storage-odf-qualification-20261115`.
Tree: `0d53cc4632d2d53fbeb4308380863c2f4b253408`.
Parent: `793c64ac4fc2e896706aa65c13eaa70bd27f7267` (canonical main).

## Saved-source result

- ODS import: **19/19 passed**.
- Existing BIFF/legacy spreadsheet import: **6/6 passed**.
- Existing spreadsheet wrap fidelity: **7/7 passed**.
- **32/32 total**, three exact requested suites, zero failures, errors or skips.
- Strict Dart analysis of the changed reader and test: **no issues**.
- Both gates recorded unchanged source, dependency-resolution inputs and tools
  before and after the command on the clean saved commit.

The recorder captured raw machine events in `canonical-ods/stdout.log`.
`canonical-ods/summary.json` separately parses those unchanged events with the
existing strict app qualification parser. Suite paths are relative to the
recorded engine working directory, stated as `reported_suite_base`; this
avoids treating package-relative reporter paths as root-relative paths.
The parser identity and all resulting artifact digests are retained.

## Regression evidence

`ods-baseline-exact.jsonl.gz` runs only the two new coordinate regressions on
the unchanged reader from the parent commit. They fail because the value after
a horizontal merge is missing at `C1`, and data after two empty repeated rows
is missing at `A4`. Expansion tests were not run on the unsafe baseline.
The baseline receipt distinguishes the original production-reader hash from
the newly authored regression-test hash.

The initial fixed-source test log is also preserved. Its sole failure was a
new test expecting an explicit wrap override on an XLSX-deserialized cell;
the parser correctly stores imported wrap in the cell's style instead. The
regression now checks that effective style after saving, while still checking
the imported cell's explicit wrap before saving. `ods-fixed-2.jsonl.gz` is the
subsequent 19-test pass. Final acceptance is the saved-source gate above,
which also includes the final UTF-8 expansion accounting and profile notes.

The canonical workspace has no tracked root lockfile. `flutter pub get`
resolved its unchanged dependency declarations; the resulting lockfile and
source/lock/package-config hashes are retained. No native hooks, test checks,
production dependencies or golden references were disabled or changed.

The engine CHANGELOG documents supported coordinate/style improvements and
explicit import boundaries, including stored data in covered cells, repeated
formulas and limits on cells, dimensions, XML, merge work and expanded text.
This evidence qualifies the recorded ODS reader changes and adjacent existing
spreadsheet tests; the combined CrispCloud app has its own qualification.

## Remote source identity

The tested source was saved remotely as `fe500e2bf50aae3098040ee0308221db2ae0d9f6` on the same named
branch. `remote-save-receipt.json` verifies identical complete tree identity,
all three changed blobs and their modes against the tested local commit.
The local tested HEAD remains unchanged.
