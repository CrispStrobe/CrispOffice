# Mail outbox: initial branch reconciliation

Repository: `CrispStrobe/quds_office_suite`. Captured main:
`c3df77d01ea9df4846e18131e69160d858f174ac` (merged PR #248).
Audit date: 20 November 2026. This is the initial snapshot, not a claim about
later branch heads. Refresh before final publication.

Local Git ancestry, tree identities, changed-path comparisons and unique commit
lists account for all 26 captured heads: 12 non-main heads are main ancestors,
nine historical heads are incorporated by exact content equivalence, four
contain continuation commits, and one is main. No Actions were used or awaited.
Ahead counts describe commit ancestry; they do not establish missing content.

## Branch dispositions

| Branch | Captured head | Ahead of main | Disposition |
| --- | --- | ---: | --- |
| `codex/odt-field-continuation-20261117` | `c34945761e7991f5fe49037d79529acdd260b31c` | 2 | Historical changed-path equivalence; retain current source |
| `codex/word-powerpoint-vba-continuation-20261120` | `d46d4ef394ed7cafd40bc266c793f8c0df6ec57f` | 0 | Main ancestor |
| `codex/word-powerpoint-vba-expansion-20261120` | `c9cbeb1248d6b5f088d1084a8c113a743aa7a77f` | 2 | Reviewed four-file cache correction; selected for integration and local qualification |
| `codex/zotero-note-targets-20261120` | `6c23d94472f741aceff6aef0de0e6ef847195afe` | 0 | Main ancestor |
| `codex/zotero-parity-continuation-20261120` | `40a8f8eb76bd9bf51205fa0cb9f576ba497ad76b` | 0 | Main ancestor |
| `codex/zotero-research-tables-20261120` | `40442e5e3b188386bc7a410efb92cab46bf68b82` | 17 | Active draft PR #249; retain owner, consume a finished main publication on refresh |
| `docs/ods-color-scale` | `58fdddfbcf198a8c0e38e32f6fcc9d6604e95283` | 1 | Historical whole-tree equivalence |
| `docs/ods-data-bar` | `69d14f84cabd3931b7640c1654b401c89faba766` | 1 | Historical whole-tree equivalence |
| `feat/downloads-manager-redesign-20261120` | `e6737bc6bccd521660dff0425ca620525dc04a58` | 0 | Main ancestor, including isolated license-loader fix |
| `feat/ods-color-scale` | `74ce9ffb816c70c0d2ae50b91ec52a614f26d688` | 1 | Historical whole-tree equivalence |
| `feat/ods-data-bar` | `0a53b8a70128870f3e1df6d18cdb177bb64290ee` | 2 | Historical whole-tree equivalence |
| `feat/ods-dynamic-validation-links` | `68a0db23408e4c95d6d283219504c79aea33a6fe` | 1 | Historical whole-tree equivalence |
| `feat/ods-icon-sets` | `005c708e9f747cb46cf02e12c869b0a2f85ac824` | 1 | Historical whole-tree equivalence |
| `feat/ods-time-period-conditions` | `7ef09f2408f467c65427700e65907531ecb26acb` | 1 | Historical whole-tree equivalence |
| `fix/mail-credential-stores-chrome-20261120` | `a652a205e6daf6b4b8e3baec04db1c1b52fabd0d` | 0 | Main ancestor |
| `integrate/office-union-148` | `3abf8f43b0e79c10271bbd046f391e462b8fe6b9` | 1 | Historical whole-tree equivalence |
| `integrate/recent-pptx` | `4f5c153774ab7492430c2b68653c54e0c08dc2ad` | 0 | Main ancestor |
| `main` | `c3df77d01ea9df4846e18131e69160d858f174ac` | 0 | Preserve current combined source |
| `perf/incremental-layout-20261120` | `baf6d1bc53b611e9fb37082ca69c409e5f8d6381` | 3 | Draft PR #247; unique content is performance documentation, selected for integration |
| `work/mail-accounts-20261120` | `c30d8fc7fb83efc89feff6cec2dc48e5cabbdd60` | 5 | Separate account owner; consume a finished main publication on refresh |
| `work/mail-body-projection-20261120` | `d5680c7066b971d67c335fe7cd9c4ab5c52b69a9` | 0 | Main ancestor |
| `work/mail-forward-host-tests-20261120` | `feffbfa437ee466a74801276fbeb178b548845e0` | 0 | Main ancestor |
| `work/mail-main-reconcile-20261120` | `4df7a148f156d9a697028994f14b171877d1d47c` | 0 | Main ancestor |
| `work/mail-reply-forward-20261120` | `56d5fdf15a20ced764561a1ac2429c2c37a6e780` | 0 | Main ancestor through PR #248 |
| `work/mail-validation-20261120` | `d6de5ef4707004d000fcf00935197e88fb0a4c1d` | 0 | Main ancestor |
| `work/mail-validation-final-20261120` | `bc9dbe395f38cebef3d1b33b77b66699f2086eb5` | 0 | Main ancestor |

## Independently verified historical equivalence

These eight heads have exactly the same Git tree as the following main
ancestors. Reapplying them over modern files is unnecessary and could undo later
changes.

| Historical branch | Equivalent main ancestor |
| --- | --- |
| `docs/ods-color-scale` | `4eaca83b192897edad82658107dfeb5bcbed0920` |
| `docs/ods-data-bar` | `52c73ae4dbadf2ca00a5d619144350ccc353b31a` |
| `feat/ods-color-scale` | `4584d5f319aab198f1d705f48b4d6647e6cbabea` |
| `feat/ods-data-bar` | `b3f41eb4b4bca8ca13676b4114891ea6d9185043` |
| `feat/ods-dynamic-validation-links` | `d754bf15b07a24c8a86c8dce339ca749fecd9531` |
| `feat/ods-icon-sets` | `c84d5e16024c502f6c451fd04b9807b1e65f20d3` |
| `feat/ods-time-period-conditions` | `34dc6b6806869570e9ec342e4d7ee0d6951c0ba6` |
| `integrate/office-union-148` | `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` |

For `codex/odt-field-continuation-20261117`, all 37 branch-changed paths exactly
match main ancestor `b5b1fa99228f6f1862af0bc4efba6e527c2bec43`. The original
publication had a different combined base, so the claim is changed-path
equivalence, not whole-tree equality.

## Selected incoming work and review

### Performance evidence

`baf6d1bc` contains the unique documentation commits `9b581e8a` and `9b5de9cb`.
Only `docs/performance/incremental-layout-20261120.md` changes relative to the
shared source: 46 added lines and one removed line. Product implementation is
already in main. Preserve the measurements with their original source/runtime
scope; they do not qualify the new outbox.

### Word paragraph break-cache correction

`c9cbeb12` contains `4a260716`, affecting only:

- `packages/quds_office_engine/lib/src/word/layout/word_layout.dart`
- `packages/quds_office_engine/lib/src/word/layout/word_incremental_layout.dart`
- `packages/quds_office_engine/test/word_incremental_layout_differential_test.dart`
- `packages/quds_office_engine/CHANGELOG.md`

The source change clears a prior paragraph break-cache entry before dirty/full
layout processing. This reaches early-return paths, including an empty paragraph,
that may not produce a replacement entry. Proven-clean incremental paragraphs
keep their existing reuse eligibility. The existing wrapping-path invalidation
in main remains in place; the new early guard is conservative and compatible.
The cache is an `Expando`, and assigning null removes its stale value.

Source review found no blocking issue in this four-file delta. The two added
tests exercise text and font edits around frame wrapping/removal. Their assertions
overlap the wrapping correction already in main; they should not be described
as unique evidence for every early-return case. Run the incremental differential
and related layout suites after integration, then Compose against the combined
Word source. This review itself is not an executed-test claim.

## Active owner continuations

The account tip `c30d8fc7` adds explicit credential JSON/platform typing after
earlier integration commits. The user assigned multiaccounts to another agent;
this task preserves that lane. The latest commit changes seven credential and
test paths (22 additions, 16 deletions). Its older combined tree must not replace
current Mail or license source.

Draft Zotero PR #249 at `40442e5e` includes Word layout-engine provenance, trailing
chrome refresh, queued credential-store fencing, Zotero table fixtures and
qualification evidence. It has multiple merge bases with main; a three-dot diff
can overstate unique work. Retain its owner and refresh for its finished main
publication. If that publication arrives, requalify affected layout/Compose,
chrome-settle and credential-selection integrations as applicable.

Normal merges of selected work must preserve main's later Mail evidence and
`studio_licenses.dart` correction. Whole-tree replacement from an older branch
is inappropriate. Record actual integration commits and local test receipts in
the final outbox validation record. Refresh main/branches/PRs before final merge;
use incremental non-forced remote checkpoints without waiting for Actions.
