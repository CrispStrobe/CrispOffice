# Word VBA and integrated Office delivery

The Word VBA extension and captured incoming work are qualified at source
`58cc4283b35b29a4036528f65ee0590230d583f6`, tree `1cba111d27e6b0699ffa65c7df5be2bbb53e8e59`. The Word bridge carries forward through verified
retention, and the final Mail union is accepted. [PR #278](https://github.com/CrispStrobe/quds_office_suite/pull/278) is the
authoritative record for the merge commit, final main tree and post-merge readback.
GitHub Actions were neither awaited nor used as a gate. Full identities and
evidence hashes are in the [structured summary](final-delivery-summary.json).

## Delivered compatibility

Eight methods convert between points and inches, centimetres, millimetres and
picas. Together with `LinesToPoints` and `PointsToLines`, all **ten** accept one
positional argument or the official case-insensitive named argument. Global,
`Application.` and leading-dot `With Application` forms are covered.

Arithmetic uses bounded binary64 `Double`, with 72 points/inch, 2.54 cm/inch,
25.4 mm/inch and 12 points/pica or line. Exact inverse equality permits native
grid normalization; nearby values are not silently snapped. Numeric Variant
contents are evaluated without implicit String, Boolean, Empty, Null or omitted
conversion. Native twip/range guards remain active: `CentimetersToPoints(1)` is
a valid scalar, but an off-grid native write needs explicit author rounding.
Word-specific dispatch and transaction, cancellation, read-only, operation-limit
and rollback checks are retained. Actual eight- and thirteen-operation BAS
examples have matching VM/optimized-JavaScript results; the separate nine-operation
example retains its independent integration coverage. [Feature evidence](https://github.com/CrispStrobe/quds_office_suite/blob/467dcaffe016b9e647f944b59af473b13e3ae7f6/docs/validation/word-vba-unit-conversions-20261120/README.md)

## Incoming work and integration

Initial intake inspected 36 branch heads and 100 updated PRs; 24 non-main heads
already belonged to main. An independent audit verified 13 squash-equivalent
trees and all 37 PR #140 changed-file identities. The later fixed inventory had
38 branches and open PRs #271/#273. Captured measurement, Mail and Zotero branches
were reconciled through #276/#273/#275 and current main `329d0391`, an actual
parent of `4163368b` alongside `e7d9055f`. The earlier `5e7e4d24` reader/session
patch is included; its Mail qualification is included in the accepted union below.

Word intake preserves explicit color/bold-off precedence, distinct authored
header-picture nodes and sparse import baselines. The latest two-file delta
deduplicates repeated references to one visual node within a collection and
updates spacing baselines only when needed. The 31.2-point contained-text fixture
keeps every exact glyph, containment and native-roundtrip assertion. Mail merges
preserve both public API families, mutation-uncertainty evidence, quota/cancellation
stops and stale account/session/UID guards; the latest reader/session patch is
included in the accepted Mail union.

## Accepted results and source boundaries

| Scope | Accepted record | Attribution |
| --- | --- | --- |
| Macro/VBA corpus | **3,598 / 69 suites** | Historical union; compiler unchanged. At c623, 663 fresh + 46 retained match the affected 709 identities exactly. |
| Native/layout ledger | **427 identities / 34 files** | 398 at c623 + 29 disjoint incoming cases. The 71-case bridge replaces existing identities, not adds them. |
| Latest Word bridge | **71 / 3 files; zero failures/skips** | Fresh at 52eace9e: identity 13, styles 17, contained text 41. |
| Editor layout/fonts | **105 passes + 8 exclusions / 5 files** | At c623, 96 fresh + 9 retained font cases, including actual lowercase aliases. |
| Zotero | **470 engine / 14; 257 editor / 9** | At c623: 188 + 282 engine and 143 + 114 editor, with exact source-bound retention. |
| Mail | **1,471 / 70 files; 228 matching Node rechecks** | 606 retained at c623 + 694 unchanged at 416 + 171 corrected at 58. |

These scopes are not a project-wide sum or one-SHA execution. The 427 native
identity union is proved from complete case IDs; it is **not 427 fresh runs at
52eace9e**. Incoming latest Word evidence separately supports 1,055 unique VM
cases and 787 overlapping Node rechecks. Incoming affected Zotero/editor results
keep their own provenance rather than inflating 470/257. [c623 report](https://github.com/CrispStrobe/quds_office_suite/blob/426fbc920b326df6eb746cd56549e3e66b9c31bb/docs/validation/word-final-integration-20261120/README.md)

The 71-case bridge passed whole-engine fatal-info analysis and seven-file
formatting, with 2,859 source inputs and runtime/HEAD seals unchanged. Its evidence
is published at `e7d9055f`. The eight editor exclusions are unchanged
image-only fixtures with the exact reason `no paragraphs to edit`; they remain
excluded, never counted as passes. Font tests do not certify default discovery
on every operating system. [Bridge report](https://github.com/CrispStrobe/quds_office_suite/blob/e7d9055f20462f37c74a38a761d5c092f48ab973/docs/validation/word-late-main-integration-20261120/README.md)

At c623, four strict analyzers/formatting passed; 5,833 source and 6,188 dependency
files were sealed. The interrupted loader remains excluded, with a verified
45-case continuation. Twenty-six English/German/Arabic PNGs had no concrete
bulk-control blocker. [Mail report](https://github.com/CrispStrobe/quds_office_suite/blob/6eea72244c52a157f603f503ca18f5487a2ee877/docs/validation/mail-final-integration-20261120/README.md)

The original 416 attempt remains failed: 847 logical cases passed, 131 matching
Node rechecks passed, and 18 cases failed across six fixture files. Independent
review traced those failures to outdated/lazy ribbon controls, duplicate Close
finders and one fake-async cancellation fixture. Six test-only corrections were
published at 58cc4283; all 171 cases in those files then passed. The accepted union
keeps 694 unaffected 416 cases and 606 source-bound c623 cases, replacing all 171
original corrected-file executions—including 153 earlier passes. Four strict
analyses passed at 416; Studio analysis/formatting passed again at 58. All 17,509 Git
source-blob comparisons passed. The Mail gate includes eight Word-only shared-layout
cases, so the scopes overlap. [Final Mail report](https://github.com/CrispStrobe/quds_office_suite/blob/8206975dd91330914f77d0e3ceab3fadbe9ad519/docs/validation/mail-latest-main-integration-20261120/README.md)

At 58cc4283, [Word retention](word-source-retention.json) matches all 2,302
Word/parser/editor paths, 662 reference fixtures and seven selected hashes.
Of 2,859 sealed inputs, 2,841 are unchanged; all 18 differences belong to Mail.
The shared layout fixture's 17,845-byte pure-Word prefix also remains intact.
The 71-case Word bridge carries forward without a rerun.

Independent [raw recount](mail-latest-independent-review.json) and
[package review](mail-latest-independent-package-review.json) passed without
findings: all 16 checksums, 253 archive members, deterministic rebuild and seven
extracted verifier outputs agree.

## Durable checkpoint ledger

| Remote checkpoint | Purpose |
| --- | --- |
| `30c8401d` | Retained maintenance ancestry |
| `e15d97d0` | Conversion implementation |
| `e08635b3` | Initial Word qualification |
| `1f6df2b5` | Concurrent intake |
| `ba6b170c` | Main #272 reconciliation |
| `cb5909fe` | Combined measurement source |
| `467dcaff` | Measurement evidence |
| `85f4ef96` | Mail branch union |
| `cdd98460` | Word/native and Mail source |
| `cf25a0a3` | Fixture/format corrections |
| `71f1c188` | Initial native/editor evidence |
| `d1c40f41` | Initial Mail evidence |
| `80e240ec` | Main #276 source attempt |
| `039b6e97` | Main #273 Word/instructions |
| `c62338c6` | Qualified Word/Zotero/Mail union |
| `426fbc92` | c623 Word/Zotero evidence |
| `6eea7224` | c623 Mail evidence |
| `52eace9e` | Main #275 Word delta |
| `e7d9055f` | Accepted 71-case bridge evidence |
| `4163368b` | Current-main candidate and preserved failed fixture attempt |
| `58cc4283` | Six test-only corrections and accepted final source |
| `8206975d` | Published final Mail evidence |
| This report’s commit | Final evidence checkpoint; merge metadata on PR #278 |

The c623 Word/Mail and latest bridge archives are remote. The bridge archive is
438,642 bytes, SHA-256 `3fdb5092f6b503d188ea19cd79d8a4865e8190e54f527838b05868e26492c6b0`.
Original failed fixtures, the 80e240ec collector interruption/strict-lint failure,
Mail's interrupted load, corrective receipts and reproducible scripts remain
preserved. No unsuccessful aggregate is rewritten as successful.

## Delivery record and practical limits

This report identifies the qualified source; its evidence checkpoint is the
commit containing the report. Consult [PR #278](https://github.com/CrispStrobe/quds_office_suite/pull/278) for the merge commit,
resulting main tree and exact-tree/compiler/captured-head ancestry readback.
[The verifier](verify_remote_delivery.py) performs those post-merge checks
without querying CI. No self-referential evidence SHA is required.

Runtimes are pinned: engine Dart 3.14.1; Flutter 3.47.8/Dart 3.13.7; package:test 1.31.1;
Node 24.22.3. This work does not claim full VBA/COM, Single emulation, installed
Word/Zotero acceptance or cryptographic DOCM signature preservation. Embedded VBA
stays inert. Edited `w:ind` groups retain existing replacement behavior; unknown
attributes within that edited group are outside the preservation guarantee. Mail actions
remain guarded foreground best effort, without live-provider, durable replay or
multi-account atomicity guarantees.
