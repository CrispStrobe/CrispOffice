# Comments IO on the final joined canonical source

Saved source: [`4e8c8f80f206e93be8530a94da478e06c0f87608`](https://github.com/CrispStrobe/quds_office_suite/commit/4e8c8f80f206e93be8530a94da478e06c0f87608). This includes the additional ODS regressions and canonical legacy-parser mirror before qualification.

## Results

- **144 tests passed across all eight requested suites**, with no failures, errors, skips, missing or unexpected suites. This includes 24 comments cases and 70 ODS cases, with schema/import, builder, formula and native spreadsheet controls.
- **Strict analysis of three files found no issues**, with fatal infos and warnings enabled.
- Three fresh XLSX save/reopen cycles passed **339 independent ZIP/XML checks**. openpyxl 3.1.5 recovered each of six comment texts and authors exactly in every cycle, including edge whitespace, multiline text and tabs, empty text, escaped XML and Unicode, and repeated authors.
- All four commands used the same saved source, with unchanged before/after source, HEAD/tree, package-resolution inputs and tool hashes. The independent checker also confirmed unchanged workbook bytes.

## Cleared comments remain cleared

Ordinary clearing removes the owned comments link and unshared part. When doing so would activate an unrelated unowned fixed-name legacy comments part, saving retains an explicit empty comments part and relationship. The unrelated decoy stays byte-identical. Shared parts use copy-on-write so another owner's text and relationship remain valid.

The two targeted decoy tests first failed on saved `9d1f6755`; their failure records remain in `../decoy-baseline/`. They passed separately on saved `fd14d8a6` and again inside the complete joined cohort above. Each case exercises three serialized save/reopen cycles, including the empty part's namespace/containers and the shared owner's unchanged text, author and target.

An independent reviewer approved the comments correction and reran the original isolated reproduction against an immutable `fd14d8a6` library snapshot. The original reproduction now observes no comments after clearing while retaining the decoy bytes. The three reviewed comment source/test/fixture blobs are identical at the joined source; those exact Git blob identities are archived. The reviewer also independently counted the focused raw events and verified stable source inputs.

Official ECMA-376 Transitional SpreadsheetML XSD validation confirms that an empty `comments` root must contain `authors` then `commentList`, each permitting zero children. The archived primary proof covers that XML shape, not the entire workbook.

## Evidence

`artifacts.tar.xz` contains commands, raw events, per-suite results, before/after snapshots, tool hashes, the actual XLSX files, independent checker and report, source-review reproduction, schema proof and runner. Every member and the complete inventory were verified against `artifacts-manifest.json`. The original dependency setup is retained in `../baseline/`; historical failures and earlier narrower successes remain intact.

This qualifies the recorded plain-comment and listed unit scope. It does not certify rich-comment formatting, VML geometry, native Excel execution or the complete Open XML schema. No GitHub Actions result was awaited.
