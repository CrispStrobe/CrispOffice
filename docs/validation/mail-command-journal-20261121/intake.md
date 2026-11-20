# Incoming source reconciliation for the mail command journal

**PASS** for remote checkpoint `f92250cd32e2afe9e7c8a17991abeda3c356b491`,
complete tree `bb7491759f9cbca39960260f31f3d6c908ec67f3`.
This report establishes source inclusion before the new mail-journal changes.
It does not treat incoming validation reports as newly executed acceptance.

## Frozen inventory

The complete GitHub API recapture finished at **2026-11-20T22:38:59Z**.
[remote-refs.json](remote-refs.json) preserves the exact repository names, API
URLs, pagination and all observed heads. The original attachment reported
`f67c18574176d34f48ddab14918aee5a787c3843`; the starting live main had already
advanced to `5e7e4d24284954603a0a5951699bea870ad1955f`.

| Source category | Captured heads | Direct ancestors | Proven equivalents |
| --- | ---: | ---: | ---: |
| Fork branches | 40 | 30 | 10 |
| Fork PR heads | 277 | 263 | 14 |
| Upstream branches | 4 | 4 | 0 |
| Upstream PR heads | 4 | 4 | 0 |
| **Total** | **325** | **301** | **24** |

Fork branch pagination ended with 40 entries. Fork PR pages contained
100, 100 and 77 entries. Each upstream collection ended with four entries.
The newly created `work/mail-command-journal-20261121` branch is included in
the 40 fork branches; it pointed to the starting main at this capture.
There are **zero uncovered heads and zero unavailable objects** at the bound
target. The eight upstream references exactly match the preceding milestone's
frozen inventory.

The first API pass observed the Word branch at `c62338c6` and maintenance at
`71f0454e`. The complete recapture includes their newer heads below. It also
caught PR #277 advancing during this intake; that new head was fetched and
reconciled before the final audit. This is an explicit fixed cutoff, not a
claim that concurrently active remote branches can never advance again.

## Recent heads and disposition

| Incoming head | Work and integration |
| --- | --- |
| `5e7e4d24284954603a0a5951699bea870ad1955f` | Main's reader HTML spacing, opt-in remote images, native saved-account autoconnect and ribbon changes. Included from the initial branch base. |
| `520d0ca8870c6a169e23603660f2cde96366f9b2` | PR #277's bounded vertical research-table merges, pagination, row geometry, hit testing, and complementary Mail/Word source reconciliation. Merged at `e219e25772a109f7e1edc9af3608dcd6b92de5a6`. |
| `426fbc920b326df6eb746cd56549e3e66b9c31bb` | Final Word qualification and the preceding `039b6e97` / `c62338c6` reconciliation. Merged at `8041940a38ebf573e2ec9398547dd400ae0aeff0`, preserving the newer product implementation and complementary placement tests. |
| `15271321a9f4550c1ab796a2cf9eaed910824574` | Latest maintenance branch, including 27 refreshed editor golden PNGs and retirement of its temporary regeneration workflow. Merged at `4ea3751beb18a51f736542c975be636e63a0b809`. Its delta against the starting main contains only those 27 PNGs. |
| `37148e37736a4134bba1d3c07b0ad847c2e1447d` | PR #277's concurrent merge of `520d0ca8` and the new main. Its complete tree is identical to our earlier integration. Its history is also joined at `f92250cd32e2afe9e7c8a17991abeda3c356b491`, without a source-tree change. |
| `3883f23cb850fb728e4e480dccedad99032b74b7` | Updated bookmark/incremental-layout documentation; already an ancestor through PR #277. |
| `ec70b9423febefcb9b104629d2ad48b0c96e9082` | Duplicate Word/font patch on `integrate/recent-pptx`; independently proven equivalent at every changed path to already included main commit `e975cec13b289fe067ef406cd3044701ecc44744`. No duplicate patch replay. |

PR #273's final head `1584a2da`, PR #275's `bf0effdc` and PR #276's
`0da1b048` are also direct ancestors. PR #277 was the only open fork PR in
the captured API pages. Its captured draft state is historical metadata,
not a claim about a later publication state.

## Decisions between overlapping implementations

The unit-conversion continuation carries an older alternative integration of
Mail and Word. Its history and source-bound qualification supplement are
retained. It does not replace the later combined implementation:

- The current Word layout keeps vertical merges on every physical page, the
  physical-row metadata needed by table handles, and identity-based suppression
  of repeated references to one authored visual node. The older alternative
  would discard these improvements. Both versions carry only body frames into
  continuous sections; the existing shared helper is retained.
- The current deserializer retains direct border-width precedence and updates
  imported spacing provenance only when its fallback changes a paragraph with
  an existing imported baseline. The older unconditional baseline reset is not
  adopted.
- Two additional header/footer tests now explicitly distinguish separate model
  nodes that reuse one `OfficeVisual` at identical coordinates. The existing
  shared-model-node and repeated-reference tests remain intact.
- Mail retains one dispatch algorithm, both public compatibility APIs, reentrant
  lease checks, contradictory-evidence handling, quota stops and the stronger
  alias-consistency checks. The cloud provider retains its established send
  rejection policy separately from foreground flag classification.
- Native reader/ribbon changes from the new main are retained. Complementary
  incoming IMAP tests were identified for account substitution and account
  retirement during an acknowledged batch. Those additional cases belong to
  the subsequent mail implementation/acceptance work, not this ancestry gate.

Two apparent incoming test-file additions are exact renames of retained tests:

| Incoming test at `c62338c6` | Retained test | Exact Git blob |
| --- | --- | --- |
| `packages/quds_mail_core/test/bulk_flag_runner_test.dart` | `packages/quds_mail_core/test/bulk_flags_test.dart` | `4a600a0f34b4b1c462398897542aa6b120f17d62` |
| `packages/quds_mail_core/test/bulk_flags_test.dart` | `packages/quds_mail_core/test/bulk_flags_coordinator_test.dart` | `fbbb20b4ee8d7cb6fe03dfe4606394154749132b` |

The maintenance branch's refreshed goldens are preserved as incoming assets.
Their inclusion does not, by itself, establish that the current implementation
passes those golden comparisons. Runtime acceptance is reported separately.
The retired `.github/workflows/tmp-regenerate-editor-goldens.yml` remains absent.

## Independently replayed replacements

All 14 historical replacement proofs from
`docs/validation/word-vba-list-levels-20261120/final-intake.json` were recomputed
from local immutable Git objects. Thirteen pairs have identical complete trees.
The ODT continuation has the same mode/type/object at all 37 changed paths as
its accepted ancestor. The checker rederives the paths, object entries and tree
IDs and verifies that every replacement is an ancestor of the target.

The additional `ec70b942` proof verifies all three changed paths, their original
and resulting mode/type/object entries, and byte-for-byte equality of the full
Git diff against each commit's respective parent. The accepted `e975cec1` is an
ancestor of the target. This accounts for the additional equivalent branch
without restoring an older Word implementation over later corrections.

A separate complete-tree check also proves that concurrent PR #277 merge
`37148e37` and remote checkpoint `e219e257` both have tree
`6c29a093730b12cfaf9e98822183d35dd842956c`. Both histories are ancestors of the
final intake checkpoint, so this extra check is not used to excuse a missing
head. In total the report independently checks **16 proof records**: 14 prior
replacements, the three-path Word/font duplicate, and this concurrent merge.

## Replay

[verify_intake.py](verify_intake.py) uses only Python's standard library and
local Git objects. From the repository root, choose a new output directory:

```sh
python3 docs/validation/mail-command-journal-20261121/verify_intake.py \
  --repo . \
  --snapshot docs/validation/mail-command-journal-20261121/remote-refs.json \
  --target f92250cd32e2afe9e7c8a17991abeda3c356b491 \
  --output-dir /absolute/path/to/intake-replay
```

The command writes only `remote-refs.json` and `intake.json` to that output
directory. It changes no Git refs, disables Git lazy fetching and does not use
network services. The report binds its snapshot and historical proof input with
SHA-256 hashes. An unavailable or uncovered captured head fails the audit.

**GitHub Actions, workflow runs, status and check endpoints were neither queried
nor awaited.**
