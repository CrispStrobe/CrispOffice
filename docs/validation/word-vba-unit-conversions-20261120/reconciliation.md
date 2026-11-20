# Reconciliation of arriving Word and Mail work

This record supplements the [initial incoming review](incoming-review.md).
The fixed incoming heads below arrived after that snapshot and were reconciled
in a separate detached worktree based on
`e08635b3f21c60ad21888821050dc97c2dbf7086`. The active qualification checkout
and remote refs were not changed by this reconciliation.

## Captured heads and local merge order

| Incoming head | Content retained | Local merge commit |
| --- | --- | --- |
| `4d0086aba52fc804424145d8eabe3c4c1c10f201` | Concurrent Word measurements, including PR #271 at `dd8e73a7d6252b336b2e7a437c4931addc42d491` | `681cc62b587e8333f779f19661eeb1d69038c200` |
| `69ab514b57a4d6d4db062d802eb853c2691d80fe` | Foreground Mail bulk flag coordinator, tests and intake evidence | `32ce9ced025d4ec2bc9661e5bac5d1c34178b41e` |
| `0cc6316c61efd8b39a9cb0cfed6b2879f7865d48` | Captured Mail intake ancestry already represented by the preceding merges | `cadb356e57656c929d8608c1f49a4e94ade1a347` |

The third merge changes no files: its tree is identical to its first parent's
tree, `63161c530e33d2ef8b77789c47d85b715b0180e5`. Every captured head is an
ancestor of the reconciled source. All local commits use the explicit
`Codex <codex@openai.com>` identity. No remote pushes, PR comments or CI
operations were performed during these local merges.

The local merge IDs describe preparation in the detached worktree. The durable
GitHub checkpoint publishes the resolved tree with `e08635b3` as its first
parent and the three captured incoming heads as additional parents. It does
not depend on the temporary local merge objects being present on GitHub.

## Word resolutions before the PR #272 main refresh

- Retain the production conversion map, checked official named arguments,
  binary64 numeric implementation and exact native-grid checks from
  `e08635b3`. The incoming alternatives add the same eight physical functions
  and introduce no additional native operation. The production file remains
  byte-identical to the previously qualified implementation.
- At this preceding integration snapshot, retain the thirteen-operation
  `word_measurements.bas`, portable driver, source/integration fixtures,
  named-argument documentation and consolidated changelog. The later main
  refresh below renames this family to `word_named_measurements` and restores
  main's separate eight-operation `word_measurements` family. The original
  incoming examples and implementations remain recoverable through the
  preserved merge parents.
- Preserve the independent `word_unit_conversions.bas` and both
  `office_vba_word_unit_conversions*_test.dart` suites. These add a distinct
  nine-operation example, explicit author-controlled `CLng` twip rounding,
  scalar-only no-op publication and complementary conversion regressions.
- Port thirteen compiler cases from the overlapping measurement fixtures:
  ten explicit `CDbl` conversions, large metric arithmetic, the converted tab
  boundary and conversion-only source-work limits. Port one integration case
  covering existing tab preservation, playback recording, save/reopen and
  replay. The supplied patch was applied before formatting the four affected
  test files with the pinned Dart SDK.
- Retain the current documentation contract, add the explicit
  `CLng(CentimetersToPoints(1) * 20) / 20` example, and remove the obsolete
  TabStops statement that unit conversions are unsupported. No property
  precision guard or native indentation ownership behavior changes.
- Keep both incoming intake JSON files. Rename PR #271's historical README
  to [incoming-pr271-checkpoint.md](incoming-pr271-checkpoint.md), leaving the
  authoritative README for the actual reconciled qualification results.
- At the preceding snapshot, mark the
  [other measurements record](../word-vba-measurements-20261120/README.md)
  as historical at `4d0086ab`. Its referenced `source-review.json` was absent
  from that captured tree and was not available as evidence then. The later
  `6d370884` commit supplies that receipt; it is preserved by the main refresh
  below and remains distinct from executed Dart qualification.

## Independent review of historical intake

The retained [PR #271 intake](intake.json) is an earlier snapshot at
`2026-11-20T20:20:11.317Z`, not a replacement for the later incoming review.
Local Git-object checks independently confirmed its initial-main tree and
2,786-commit graph; all declared ancestor classifications (23 fork branch
heads, 256 fork PR heads, four upstream branch heads and four upstream PR
heads); all thirteen complete-tree squash proofs; and all 37 changed-file
blob identities and modes for PR #140.

That historical snapshot excluded the temporary-workflow-only commit
`332d7b26`. Its ancestry is now preserved through `30c8401d`, while the
temporary workflow remains deleted. The older record's exclusion is not a
claim about the current ancestry.

## File identity checks

The Word production file remains unchanged from `e08635b3`:

| File | SHA-256 |
| --- | --- |
| `packages/quds_office_engine/lib/src/automation/office_vba_language.dart` | `41de865411b884d18c1097e9a80d68cd6bf1fb245e1844a46f72af05636f5ecd` |

The four Mail files below are byte-identical to captured head `69ab514b`:

| File | SHA-256 |
| --- | --- |
| `packages/quds_mail_core/CHANGELOG.md` | `0bb90ae30df78fb174ad30a5a2d605d6fce4eadaca5ccff5c2756caba159fb32` |
| `packages/quds_mail_core/lib/quds_mail_core.dart` | `cd206870c62bdce16c3f495e98c88e04c19d58ea8492ac9c0ba2af6a6dc81b19` |
| `packages/quds_mail_core/lib/src/sync/bulk_flags.dart` | `ce2b319a35727917eda7926139d0fc5f301ecf30e02f9b3172fd2a7c5b77296b` |
| `packages/quds_mail_core/test/bulk_flags_test.dart` | `9b189f4a5458172bb3463581da19832a21de7f988420f27a3bf29cfd0fef1e7f` |

These checks establish the content retained by the local merge. Execution of
the added suites, reconciled analysis and portable driver is a separate gate;
this receipt does not claim those subsequent runs have passed. The final
qualification record must report their observed results.

## Later main refresh: preserve all three example families

Remote main subsequently advanced through PR #272 to
`b01cb23dc1b7bc94b691d68a2507b61dc6d48d7a`. It already contains both Word
continuations, the named-argument production implementation and new
source-review/arithmetic-model evidence. This fixed main head was merged into
the published integration checkpoint
`1f6df2b5d5947056792ff9f880dd4a38fb07c03b` in the separate worktree.

The reconciled naming follows current main:

| Example and fixture family | Source example | Operations | Portable define |
| --- | --- | ---: | --- |
| Original physical measurements | `word_measurements.bas` | 8 | `WORD_MEASUREMENTS_BAS_BASE64` |
| Independent physical-unit conversions | `word_unit_conversions.bas` | 9 | Covered by its source/integration suites |
| Named measurements and line conversions | `word_named_measurements.bas` | 13 | `WORD_NAMED_MEASUREMENTS_BAS_BASE64` |

All three BAS files are byte-identical to captured main. The original
measurement example, its two suites and portable driver are retained from
main. The independent unit-conversion example and two suites are likewise
retained. Formatting was applied with the worktree's resolved package language
configuration; no behavior changes were made to these incoming fixtures.

The previously qualified measurement source/integration suites, including the
thirteen compiler additions and one integration addition above, are preserved
under `office_vba_word_named_measurements*_test.dart`. Their content is
byte-identical to the prior integration checkpoint except for the integration
suite's portable-helper import and BAS filename. The named portable driver is
the prior thirteen-operation driver with only its required environment define
renamed. The production file remains byte-identical to both captured main and
the prior qualified source, with the SHA-256 recorded above.

The detailed named-argument, precision, native-ownership and explicit `CLng`
rounding contract is retained; its example links now match the three-family
layout. Main's `source-review.json`, `arithmetic-model.js` and updated
measurement intake JSON are retained byte-for-byte. The README in that
measurement evidence directory is labeled historical at `b01cb23d` and
distinguishes its source-review claims from later executed local tests.
The source-review receipt was absent at `4d0086ab` and was subsequently added
by `6d370884`; both facts remain explicit. PR #271's historical README remains
under `incoming-pr271-checkpoint.md`, leaving the current README for final
qualification.

All four Mail files remain byte-identical to `69ab514b`, and both Mail intake
records are preserved. The latest-main merge does not restore an older Mail
or Word implementation. Six focused suites and both portable drivers require
qualification against the final named layout; this merge record does not
claim those new runs have passed.
