# Frozen page-text qualification checkpoint

The qualified cache checkpoint is
[`78d1f8db5374a6b2739451834708c8fe9f703ed8`](https://github.com/CrispStrobe/quds_office_suite/commit/78d1f8db5374a6b2739451834708c8fe9f703ed8),
tree `3ccb17f6ec1c0543c7cc93b0b84a5832ddda28f7`. It retains the native Zotero
work and its frozen evidence, incorporates accepted main through
`0de92d6f42b3b2d1f2df43ef56a7af8e0f49d059`, and corrects the new page-text
cache's adaptive-color dependencies. This is the frozen 3,452-case record.
The subsequent [final main reconciliation](../final-main/README.md) incorporates
completed Word positioning and a typed per-page implementation that subsumes
this fix, retains both cache suites, and supplies current-source qualification.

## What the followup adds

After the native-file checkpoint, main accepted the completed Zotero image
qualification via PR #337 and the page-text cache via PR #339. The only new
production path was `render_word_canvas.dart`; the other incoming changes were
documentation and image qualification evidence. Both changelog entries were
retained during reconciliation. Engine library/tool/test, Mail and Studio
sources remain identical to their previously qualified versions.

The incoming renderer cached text whose adaptive color depended on table
selection and the active header/footer background, but did not invalidate that
cache when those values changed. A retained canvas could therefore show a
different text color from a fresh canvas. A noncompact dark-page raster test
reproduced this on the unchanged incoming renderer.

The correction snapshots adaptive-ink inputs at paint time. It observes table
and table-band selection, cross-cell selection extent, edited story membership
and selection color, including mutation of the existing caret without a widget
update. Ordinary collapsed-caret movement and blinking retain the cache. Five
new tests compare retained and fresh canvases when entering and leaving table
band, whole-table, cross-cell, header and footer states.

## Executed qualification

| Final renderer suite | Passed |
| --- | ---: |
| Existing dark-document rendering | 3 |
| New page-text cache regression | 5 |
| Proofing capture cache | 4 |
| Proofing geometry | 13 |
| Selection painting | 10 |
| Selection-path cache | 1 |
| **Completed followup execution** | **36** |

All 36 cases passed with zero failures/skips/errors and empty stderr. All
**2,668 source/dependency hashes** were unchanged during execution. The new
untracked test was explicitly included in the hashes and source copies.
No-write formatting and fatal-info/fatal-warning analysis passed for both
changed Dart files. This is a targeted renderer gate; the full engine,
controller, Studio and Mail populations were not redundantly rerun.

The [case accounting](case-accounting.json) independently unions raw event
identities by repository-relative suite path and test name. **28** of the
followup cases repeat the frozen record; **8** are additional. The final total
is **3,452 distinct accepted cases**:

| Nonoverlapping scope | Distinct cases |
| --- | ---: |
| Engine | 2,698 |
| Editor and rendering | 508 |
| Studio Zotero | 41 |
| Mail core/store/Studio | 205 |
| **Total** | **3,452** |

The expected red raster failure is retained separately. A subsequent compiler
attempt used the wrong caret method in a new return-transition assertion;
its 31 partial passes and two loader/compiler errors are excluded entirely.
The corrected final test uses `CaretEngine.collapseSelection()`. The archive
retains exact source copies for each phase and explains that return-transition
assertions were added after the red baseline.

## Source and remote continuity

| Remote checkpoint | Purpose |
| --- | --- |
| `c179c61a198df9b2cd1af3899d6f805159481ce2` | Frozen 3,444-case native-file record and evidence |
| `8afb6f9135bb18f59532e1a6f1ad37b5c6da7ad8` | Accepted main/image evidence and page-text renderer |
| `78d1f8db5374a6b2739451834708c8fe9f703ed8` | Qualified adaptive-ink correction and five new tests |

The accepted test run used local integration HEAD `4c4f476c...` plus the two
explicitly hashed working files. Those exact files were committed locally as
`e78cdf408bbd76bb0c60ba26cad3ad22b303ec81`; the resulting entire tree matches
the published `78d1f8db...` checkpoint. The
[source continuity record](source-continuity.json) binds those objects and
preserves the applicable earlier source comparisons.

The original 383-ref and bounded 386-ref intake snapshots remain unchanged.
The separately recorded accepted main additions do not convert the deferred
PR #336 aliases into an acceptance claim at this checkpoint. Their later
completion and ancestry are recorded in the final-main followup. Accepted incoming commits retain their
merge ancestry, and the checkpoint branch is preserved. No GitHub Actions,
checks or status queues were queried or awaited;
no force update or protection change was used.

The [archive](evidence.tar.gz), [member index](index.json) and
[verifier](verify_evidence.py) preserve exact commands, raw events, source
manifests, accepted/rejected receipts and independent count derivation. Run the
verifier from this directory or the repository root. The parent native-file
record still owns the four actual LibreOffice fixture routes and their stated
development-build and installed-plugin limitations.
