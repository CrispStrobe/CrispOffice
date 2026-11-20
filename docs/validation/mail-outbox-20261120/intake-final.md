# Mail outbox: final premerge intake

Repository: `CrispStrobe/quds_office_suite`. Captured **2026-11-20T13:20:42.055009+00:00**.
This is a bounded snapshot before publication; active owners can continue advancing their branches.

Remote main is `b42eca1db058f0def247b86c2f15dea90c11b4e8`; the remote Outbox checkpoint is `ce9ff1c8b155c03a0e2707d6fc8b41b52e611a93`.
Main is an ancestor of that checkpoint. The complete exact refs, PR metadata, ancestry and equivalence checks are in [intake-final.json](intake-final.json).

## Changes since the initial intake

- The live inventory changed from **26 to 16 branches**: 11 old refs were deleted independently and this task added its Outbox branch. Every deleted ref’s initially captured commit remains an ancestor of current main. This task issued no branch deletion.
- **PR #247 is now merged**, at `b42eca1db058f0def247b86c2f15dea90c11b4e8`. Its only final tree delta from initial main is `docs/performance/incremental-layout-20261120.md`, already incorporated before Outbox implementation.
- The initial performance head `baf6d1bc53b611e9fb37082ca69c409e5f8d6381` and reviewed Word frame-cache head `c9cbeb1248d6b5f088d1084a8c113a743aa7a77f` were preserved in `c824caafce175ee37cff67fe778396779ce76b6a`; both remain ancestors of the candidate.
- The separate account, Zotero and VBA continuations advanced. They remain with their owners; the outbox audit did not merge or modify those active branches.
- The latest **50 PRs ordered by update time** contain 48 merged PR heads already in main, closed PR #202 already incorporated by ancestry, and active draft PR #249. No completed, unincorporated PR appears in this captured window.

## All live branch dispositions

Ahead counts are recorded in JSON as ancestry information; they do not by themselves imply missing content. The eight historical whole-tree equivalents and the 37-path ODT equivalent were rechecked against main ancestors.

| Branch | Captured SHA | Disposition |
| --- | --- | --- |
| `codex/odt-field-continuation-20261117` | `c34945761e7991f5fe49037d79529acdd260b31c` | 37-path historical equivalent |
| `codex/word-powerpoint-vba-expansion-20261120` | `192ea2aedbf0b1494627953c79a7042037a63301` | Active owner continuation; retained |
| `codex/zotero-research-tables-20261120` | `06defcfef83e1b33215441c92531c9467d3f89f4` | Active owner continuation; retained |
| `docs/ods-color-scale` | `58fdddfbcf198a8c0e38e32f6fcc9d6604e95283` | Exact historical tree equivalent |
| `docs/ods-data-bar` | `69d14f84cabd3931b7640c1654b401c89faba766` | Exact historical tree equivalent |
| `feat/ods-color-scale` | `74ce9ffb816c70c0d2ae50b91ec52a614f26d688` | Exact historical tree equivalent |
| `feat/ods-data-bar` | `0a53b8a70128870f3e1df6d18cdb177bb64290ee` | Exact historical tree equivalent |
| `feat/ods-dynamic-validation-links` | `68a0db23408e4c95d6d283219504c79aea33a6fe` | Exact historical tree equivalent |
| `feat/ods-icon-sets` | `005c708e9f747cb46cf02e12c869b0a2f85ac824` | Exact historical tree equivalent |
| `feat/ods-time-period-conditions` | `7ef09f2408f467c65427700e65907531ecb26acb` | Exact historical tree equivalent |
| `fix/mail-credential-stores-chrome-20261120` | `a652a205e6daf6b4b8e3baec04db1c1b52fabd0d` | Already in main by ancestry |
| `integrate/office-union-148` | `3abf8f43b0e79c10271bbd046f391e462b8fe6b9` | Exact historical tree equivalent |
| `integrate/recent-pptx` | `4f5c153774ab7492430c2b68653c54e0c08dc2ad` | Already in main by ancestry |
| `main` | `b42eca1db058f0def247b86c2f15dea90c11b4e8` | Current main; ancestor of candidate |
| `work/mail-accounts-20261120` | `625f4d76d10ddf2144220f25ae8d867452eeed61` | Active owner continuation; retained |
| `work/mail-outbox-20261120` | `ce9ff1c8b155c03a0e2707d6fc8b41b52e611a93` | This task; incrementally saved Outbox |

## Owner continuation boundaries

- **Multiaccounts:** `625f4d76d10ddf2144220f25ae8d867452eeed61`. The new non-merge owner commit since initial capture, excluding already incorporated main history, isolates host-preference fixtures and resolves integrated lints in 13 credential/reader/test paths. The user explicitly reserved this lane for another agent; older published account work stays preserved.
- **Zotero:** `06defcfef83e1b33215441c92531c9467d3f89f4`, still draft PR #249. The five later commits since initial capture refine native-store fixtures, callback-safe expectations, sequential complete replay and acceptance evidence. The full active continuation remains outside this task’s publication.
- **Word/PowerPoint/VBA:** `192ea2aedbf0b1494627953c79a7042037a63301`. The initially reviewed cache fix is included. The later `dfa8407b` correction preserves imported PowerPoint margin baselines. The owner then merged main, accounts, Zotero and the older Outbox checkpoint `bda00b32`; this active combined continuation is recorded and remains with its owner.

## Refs deleted independently since initial capture

The live remote no longer lists these 11 names. Deleting actor/time was not queried. Each captured SHA is still reachable from main; no work recovery or ref recreation is required.

| Deleted remote ref | Initial SHA retained in main |
| --- | --- |
| `codex/word-powerpoint-vba-continuation-20261120` | `d46d4ef394ed7cafd40bc266c793f8c0df6ec57f` |
| `codex/zotero-note-targets-20261120` | `6c23d94472f741aceff6aef0de0e6ef847195afe` |
| `codex/zotero-parity-continuation-20261120` | `40a8f8eb76bd9bf51205fa0cb9f576ba497ad76b` |
| `feat/downloads-manager-redesign-20261120` | `e6737bc6bccd521660dff0425ca620525dc04a58` |
| `perf/incremental-layout-20261120` | `baf6d1bc53b611e9fb37082ca69c409e5f8d6381` |
| `work/mail-body-projection-20261120` | `d5680c7066b971d67c335fe7cd9c4ab5c52b69a9` |
| `work/mail-forward-host-tests-20261120` | `feffbfa437ee466a74801276fbeb178b548845e0` |
| `work/mail-main-reconcile-20261120` | `4df7a148f156d9a697028994f14b171877d1d47c` |
| `work/mail-reply-forward-20261120` | `56d5fdf15a20ced764561a1ac2429c2c37a6e780` |
| `work/mail-validation-20261120` | `d6de5ef4707004d000fcf00935197e88fb0a4c1d` |
| `work/mail-validation-final-20261120` | `bc9dbe395f38cebef3d1b33b77b66699f2086eb5` |

## Read-only capture and publication boundary

The audit used the complete branch API, `git ls-remote --heads`, non-pruning fetches, Git ancestry/tree/path comparisons, an explicit `sort:updated-desc` PR search, and individual metadata reads for all 50 selected PRs. The explicit search was used because the connector’s empty-query listing did not honor updated ordering.
The old/new PR-window boundary swaps #203 for #201 at the same update timestamp; this does not indicate a newly unincorporated change. Initial PR #203 remains in main.
No checkout, index, working-source, HEAD or remote mutation was performed by this audit. Only these two intake documents were written in the repository. No GitHub Actions, checks or queues were queried or awaited.
Remote main remained `b42eca1db058f0def247b86c2f15dea90c11b4e8` throughout the capture. A VBA-owner update observed during capture was fetched and recorded without merging it. Final publication still requires the root agent’s source qualification and expected-head main reconciliation.
