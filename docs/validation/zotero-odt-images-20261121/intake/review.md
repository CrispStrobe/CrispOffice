# Initial ref intake audit

Baseline main: `4970f71f983535d045ce263e86835b499db4fda9`.

Freshly checked 378 refs: 364 ancestors, 10 patch-equivalent PR heads, 4 squash-merged PR heads. No unintegrated work in this captured frontier.

| PR | Accounting | Evidence |
|---|---|---|
| 134 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 135 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 136 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 137 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 138 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 140 | squash-merged | Fresh GitHub merged metadata; squash `2c47165d01d01cc883135a434ac9f6591ce6e770` is an ancestor; exact old/new blob delta across 37 files. |
| 141 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 142 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 145 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 146 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 147 | squash-merged | Fresh GitHub merged metadata; squash `bb5556e8cc4cb73e2c668b5319a2844a20c6c50c` is an ancestor; exact tree match. |
| 149 | squash-merged | Fresh GitHub merged metadata; squash `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` is an ancestor; exact tree match. |
| 151 | patch-equivalent | All unique nonmerge patches match main via fresh git cherry; stable patch IDs retained. |
| 152 | squash-merged | Fresh GitHub merged metadata; squash `23f3b4204fce45d38a103e3159bdc7f1e8d37c4e` is an ancestor; exact tree match. |

PRs 147 and 149 were formerly labeled only as having no unmatched nonmerge patches. This audit strengthens their disposition: each was squash-merged and its full resulting tree exactly matches the corresponding squash commit in main.

No source edits, commits, ref updates, remote writes, or CI calls were made. This is a historical frontier audit, not a promise about later remote changes.
