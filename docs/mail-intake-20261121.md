# Mail continuation: remote branch intake, 2026-11-21

## Captured baseline and scope

Repository: `CrispStrobe/quds_office_suite`. The captured main commit is
`1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0`, tree
`6167ba3499df3f06ec531e7a8c7143dda58c9143`.

The GitHub branches API returned 51 branches including main. All 50 other
heads were compared against that exact main commit. The dedicated open-PR
endpoint returned an empty list; there were **zero open PRs** at intake.
The most recent 100 updated PRs were also reviewed.

Of the 50 non-main heads, 38 were ancestors of main; 10 were already integrated
through nine squash merges and one exact replay; two contained new changes.
All captured Mail branch heads were already in main.

Upstream `MohammedAsaadAsaad/quds_office_suite` main was
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`. The cross-fork comparison found
zero upstream-only commits and 3,047 fork-only commits. No upstream main
integration was needed.

STATUS: Both intake checkpoints are saved. The benchmark change and reviewed bounded CLI test-runner migration are included; the WIP shared cache and generated working files are explicitly excluded.

## Reviewed integration decisions

### Typing benchmark

Head `8716057f80c4c18b72c5a43a708beefd70bc7588` adds exactly two reporting
fields, `callsFirstKeys` and `coalesce`, in the Studio typing benchmark.
Apply that small change to the captured main file and preserve its head as
an additional parent. Existing benchmark assertions and runtime behavior
are unchanged.

### CLI test runner

The three unique commits on `fix/main-green-20261120` are:

- `5fa01325f00027797dba46d4c61a580ef2386978`: route ten remaining CLI test
  files through the existing bounded helper, use five-minute library test
  timeouts, and compile the per-file kernel in awaited `setUpAll`.
- `f900f7dd0ecf959acdb01192da3fbfa69af2cba0`: merge earlier remote main.
- `0e14940e0e1521c7eb143f83f0abc18b8f65e1c9`: WIP shared kernel cache.

Retain the useful test migration and the per-file setup from the first commit.
Apply its exact context hunks to the captured main files so subsequent
main changes outside those hunks remain intact. Keep the existing bounded
child-process termination and per-file temporary-kernel cleanup.
The existing Word and PowerPoint CLI test files also receive the same
five-minute library timeout: their existing per-test timeouts do not cover
shared setup, and moving compilation into setup must not shorten its deadline.

Do not adopt the WIP shared cache. Its key uses path/size/mtime rather than
content and excludes the SDK and dependency contents; concurrent stale-lock
deletion can race; pruning other kernels can invalidate another test's
selected entry; and teardown still owns the compiler despite the claimed
shared lifetime. These issues require separate qualification before adopting
cross-file caching. The reviewed per-file implementation replaces that WIP
change. Preserve the WIP branch head as an additional parent only once this
resolution is committed, so the retained history and chosen final tree are
both explicit.

Do not add the seven generated working files accidentally included in the
test-runner branch:

- `packages/quds_office_engine/arguments-cli-BW4wg7/helpers.bas`
- `packages/quds_office_engine/arguments-cli-BW4wg7/input.xlsx`
- `packages/quds_office_engine/arguments-cli-BW4wg7/output.xlsx`
- `packages/quds_office_engine/arguments-cli-wnJkho/helpers.bas`
- `packages/quds_office_engine/arguments-cli-wnJkho/input.pptx`
- `packages/quds_office_engine/arguments-cli-wnJkho/output.pptx`
- `packages/quds_office_engine/vba-cli-test-uwCN84/monthly.xlsx`

### Existing squash merges and replay

The exact PR head SHAs were checked using the individual PR API.
These heads are not ancestors because the PRs were squash-merged; their
changes must not be replayed over later source history.

| Branch | Merged PR | Commit already on main |
| --- | --- | --- |
| `codex/odt-field-continuation-20261117` | [#140](https://github.com/CrispStrobe/quds_office_suite/pull/140) | `2c47165d01d01cc883135a434ac9f6591ce6e770` |
| `feat/ods-color-scale` | [#135](https://github.com/CrispStrobe/quds_office_suite/pull/135) | `4584d5f319aab198f1d705f48b4d6647e6cbabea` |
| `docs/ods-color-scale` | [#136](https://github.com/CrispStrobe/quds_office_suite/pull/136) | `4eaca83b192897edad82658107dfeb5bcbed0920` |
| `feat/ods-dynamic-validation-links` | [#137](https://github.com/CrispStrobe/quds_office_suite/pull/137) | `d754bf15b07a24c8a86c8dce339ca749fecd9531` |
| `feat/ods-data-bar` | [#141](https://github.com/CrispStrobe/quds_office_suite/pull/141) | `b3f41eb4b4bca8ca13676b4114891ea6d9185043` |
| `docs/ods-data-bar` | [#142](https://github.com/CrispStrobe/quds_office_suite/pull/142) | `52c73ae4dbadf2ca00a5d619144350ccc353b31a` |
| `feat/ods-icon-sets` | [#145](https://github.com/CrispStrobe/quds_office_suite/pull/145) | `c84d5e16024c502f6c451fd04b9807b1e65f20d3` |
| `feat/ods-time-period-conditions` | [#151](https://github.com/CrispStrobe/quds_office_suite/pull/151) | `34dc6b6806869570e9ec342e4d7ee0d6951c0ba6` |
| `integrate/office-union-148` | [#149](https://github.com/CrispStrobe/quds_office_suite/pull/149) | `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` |
| `integrate/recent-pptx` | Exact replay | `e975cec13b289fe067ef406cd3044701ecc44744` |

For `integrate/recent-pptx`, the three changed files have identical diff
patches and final blob SHAs between
`ec70b9423febefcb9b104629d2ad48b0c96e9082` and
`e975cec13b289fe067ef406cd3044701ecc44744`.
No Word change from that branch is missing.

## Complete captured fork-branch inventory

| Branch | Captured head SHA | Disposition |
| --- | --- | --- |
| `codex/odt-field-continuation-20261117` | `c34945761e7991f5fe49037d79529acdd260b31c` | Already squash-merged in #140 |
| `codex/word-powerpoint-vba-expansion-20261120` | `0f6239396ff3328473a5f57c280b982d57e33a08` | Ancestor of captured main |
| `codex/word-vba-compat-20261120-next` | `650afb7d117337bab943af05d63a250a7e90c058` | Ancestor of captured main |
| `codex/word-vba-compatibility-20261120-continuation` | `8c54d5283804099f9c9023540921f2410b878eb1` | Ancestor of captured main |
| `codex/word-vba-compatibility-20261121` | `38b07e58b7c0e2a5b04a823a7251805cea60fb77` | Ancestor of captured main |
| `codex/word-vba-list-levels-20261120` | `fff4a4afda2beecdd20ae0bd1f3c31622e8c0b37` | Ancestor of captured main |
| `codex/word-vba-measurements-20261120` | `cd306bdea352c6f6400b5d1af7cc33e737004462` | Ancestor of captured main |
| `codex/word-vba-paragraph-controls-20261120` | `90ecd41c8a3ef2a6f35967f1219223022e2b0d32` | Ancestor of captured main |
| `codex/word-vba-paragraph-flow-20261121` | `13fa9ad5b9d140f1d7c085e46b4d0ce395000c49` | Ancestor of captured main |
| `codex/word-vba-paragraph-pagination-20261121` | `1581229f0e5aea24b5242c33a1e92f02d70b4c7e` | Ancestor of captured main |
| `codex/word-vba-paragraph-spacing-20261120` | `d30299dd91634ad7e20c32db5c39a6687fcef4aa` | Ancestor of captured main |
| `codex/word-vba-ranges-20261120` | `22e5960e99915e81a1b5997058cac44dac27ba1a` | Ancestor of captured main |
| `codex/word-vba-sections-20261121` | `49665e51f9eacefc180748c3d0ed7851ef5da5d1` | Ancestor of captured main |
| `codex/word-vba-unit-conversions-20261120` | `bbccae1bdead10951e2d7a23b33cf14c55382e02` | Ancestor of captured main |
| `codex/zotero-multiparagraph-20261121` | `589ccd33243eabe57ce3074c92112e1fdf1325f1` | Ancestor of captured main |
| `codex/zotero-parity-20261120-next` | `0da1b048546f36c658a7ddfb899117b73c5d3e7c` | Ancestor of captured main |
| `codex/zotero-parity-20261121-continuation` | `9942eb76f0ac818e464ad1b3bcec2cc4513d3e3f` | Ancestor of captured main |
| `codex/zotero-parity-20261121-next` | `d4470bab1095593739ddf87fdb9f249bbc948b65` | Ancestor of captured main |
| `codex/zotero-research-tables-20261120` | `34491bca22a2989dd89d9da3c853f5e57de5464f` | Ancestor of captured main |
| `codex/zotero-transfer-20261121` | `a1995c9154357e603b89947654cf95f8bcba6a83` | Ancestor of captured main |
| `codex/zotero-vertical-tables-20261120` | `a7d9f37ecbaaf70544f4866d7d9e572696948184` | Ancestor of captured main |
| `docs/app-store-submission-20261120` | `b08e0a55b629ac22b33c54146b56438862965022` | Ancestor of captured main |
| `docs/ods-color-scale` | `58fdddfbcf198a8c0e38e32f6fcc9d6604e95283` | Already squash-merged in #136 |
| `docs/ods-data-bar` | `69d14f84cabd3931b7640c1654b401c89faba766` | Already squash-merged in #142 |
| `feat/arabic-web-context-20261120` | `be47bed22a88382f016d823e526bae49590bd0eb` | Ancestor of captured main |
| `feat/ods-color-scale` | `74ce9ffb816c70c0d2ae50b91ec52a614f26d688` | Already squash-merged in #135 |
| `feat/ods-data-bar` | `0a53b8a70128870f3e1df6d18cdb177bb64290ee` | Already squash-merged in #141 |
| `feat/ods-dynamic-validation-links` | `68a0db23408e4c95d6d283219504c79aea33a6fe` | Already squash-merged in #137 |
| `feat/ods-icon-sets` | `005c708e9f747cb46cf02e12c869b0a2f85ac824` | Already squash-merged in #145 |
| `feat/ods-time-period-conditions` | `7ef09f2408f467c65427700e65907531ecb26acb` | Already squash-merged in #151 |
| `feat/settings-arweb-20261120` | `e8db6b3f21401f8c6ac4dae4c2934edde8699f4b` | Ancestor of captured main |
| `fix/mail-credential-stores-chrome-20261120` | `a652a205e6daf6b4b8e3baec04db1c1b52fabd0d` | Ancestor of captured main |
| `fix/main-green-20261120` | `0e14940e0e1521c7eb143f83f0abc18b8f65e1c9` | Integrate bounded test runner; reject WIP cache and generated files |
| `integrate/office-union-148` | `3abf8f43b0e79c10271bbd046f391e462b8fe6b9` | Already squash-merged in #149 |
| `integrate/recent-pptx` | `ec70b9423febefcb9b104629d2ad48b0c96e9082` | Already integrated by exact replay |
| `main` | `1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0` | Captured baseline |
| `perf/wrap-chrome-20261121` | `8716057f80c4c18b72c5a43a708beefd70bc7588` | Integrate exact two-line benchmark change |
| `work/mail-accounts-20261120` | `86e44e87f829b0309ea7b84fd5d390f596fe7f26` | Ancestor of captured main |
| `work/mail-bulk-actions-20261120` | `1584a2da8b23128c113d95c3b05b6a12d2d3861e` | Ancestor of captured main |
| `work/mail-bulk-flags-20261120` | `bf0effdcc8f690972d762c5b53079e8847a5e65e` | Ancestor of captured main |
| `work/mail-cached-workspace-20261120` | `c7e721b7703766491fd4459b69de30bf68d9010d` | Ancestor of captured main |
| `work/mail-command-journal-20261121` | `33ce2428ebab825a844895a767e0f9f1a4077d62` | Ancestor of captured main |
| `work/mail-multiple-drafts-20261120` | `b3abdf3b4628a8a703857d69b8f11cd21bc502e1` | Ancestor of captured main |
| `work/mail-offline-accounts-20261120` | `44855ab24c2c7fd34953e879fba571381cce0bc3` | Ancestor of captured main |
| `work/mail-offline-retention-20261121` | `9eb68b9f048d3c08274ece5d7f964f1249004485` | Ancestor of captured main |
| `work/mail-outbox-20261120` | `9443612b024114c424ba2f8146e04050d6e049b0` | Ancestor of captured main |
| `work/mail-outbox-management-20261120` | `79e11935e16ea1d2fa576ead0712c83f22e15c28` | Ancestor of captured main |
| `work/mail-parity-20261120` | `540eb7a41554620e1405807ac1db9dc38bd62148` | Ancestor of captured main |
| `work/mail-parity-20261121` | `fa59496840a36709fe3a6d867bdfe96ab99d72ab` | Ancestor of captured main |
| `work/mail-repository-sessions-20261121` | `0491492d8622ad2ef09fb84e07d3dbba462f9320` | Ancestor of captured main |
| `work/mail-sync-foundation-20261121` | `4a1eaa69e7a068e354bdd851ec9b0323b89ae300` | Ancestor of captured main |

## Recent Mail baseline already retained

- [#298](https://github.com/CrispStrobe/quds_office_suite/pull/298): durable
  offline downloads and retention; merge
  `c10416d39894031164be68313253db5bbb3a5ad2`.
- [#295](https://github.com/CrispStrobe/quds_office_suite/pull/295): localized
  mail dates, reader text and plural-aware counts.
- [#294](https://github.com/CrispStrobe/quds_office_suite/pull/294): saved Mail
  vault unlock and native menu actions.
- [#291](https://github.com/CrispStrobe/quds_office_suite/pull/291): resumable
  folder synchronization and offline browsing.
- [#284](https://github.com/CrispStrobe/quds_office_suite/pull/284):
  repository-backed sessions.
- [#282](https://github.com/CrispStrobe/quds_office_suite/pull/282): uncertain
  mail-action recovery.

## Verification and limits

Root and every touched directory ancestor were checked for agent instruction
files through directory metadata; no `AGENTS.md` was present. The root
`.cursorrules` and `CONTRIBUTING.md` were read.

The changes were reviewed against exact commit-pinned file contents. Each
old unified-diff hunk had to match exactly once before replacement. The
test-runner migration keeps current-main source outside those hunks,
registers cleanup once in each of ten migrated test files, and removes their
raw `Process.run` CLI launchers. The benchmark additions are the exact two
source-branch lines.

The local execution sandbox ran out of disk space during checkout and could
not start another command. **No Dart tests, Flutter tests, analyzer, formatter,
or benchmark execution is claimed for this intake.** Static source and remote
object verification cannot replace those runtime checks.

Remote checkpoints use sequential tree/commit/ref writes with the expected
branch-head SHA and `force=false`. This intake does not update main. No GitHub
Actions workflow, check-run, or CI status was awaited or used as validation.

Read endpoints used for the audit:

- `GET /repos/CrispStrobe/quds_office_suite/branches?per_page=100`
- `GET /repos/CrispStrobe/quds_office_suite/pulls?state=open&per_page=100`
- `GET /repos/CrispStrobe/quds_office_suite/pulls?state=all&sort=updated&direction=desc&per_page=100`
- Commit-pinned comparisons, individual PRs, commits and file contents.


## Final cutoff: concurrent work reconciled

The publication check observed main still at
`1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0`.
The live branch collection had 24 entries after concurrent branch housekeeping.
This continuation did not delete or force-update any branch.

| Newly observed work | Exact head | Disposition |
| --- | --- | --- |
| `fix/main-green-20261120` | `41c363f40cdcdfbcc22a8932ea325ce87872f5a0` | Apply its sole new compile-only package-config URI/path correction to our reviewed per-file helper. Retain all earlier safe runner/test changes and WIP/generated-artifact exclusions. Preserve the new head as a parent. |
| `codex/zotero-native-odt-20261121` / PR #299 | `d9bfa44022781f0dd4493a923ca9f20316dc59f0` | Preserve all four documentation files and their three incremental commits. These specify future native ODT work and retain a 353-reference historical intake; they contain no new application code or tests. Native ODT implementation and qualification remain pending. |
| `codex/word-vba-text-intrinsics-20261121` | `1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0` | Identical to captured main; no additional content at cutoff. |

The initial zero-open-PR count above belongs to the first capture. PR #299 was
the single open draft at this later cutoff. Its documentation is integrated as
documentation, without representing it as a delivered Zotero implementation.
Its original blocker and earlier unmerged-head observations remain a dated
record; this section supplies the subsequent reviewed intake disposition.

The package-config correction changes only the arguments to
`dart compile kernel`: it converts the VM's file URI into a file path. Source
execution retains the existing VM argument behavior. Independent review
confirmed the patch context matched exactly once and that no other new files
were present on that branch. Runtime checks remain unexecuted for the reasons
recorded above.
