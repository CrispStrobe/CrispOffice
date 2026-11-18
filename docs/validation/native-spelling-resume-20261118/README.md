# Native spelling resume — final source closeout

Product source is fixed at `04be224b4a7f469476416ee86dc780cb6a1c0990`.
The interrupted final report was not saved, so this continuation rebuilt the
pinned runtime and reran the final source qualification. The original saved
regressions and their bookkeeping correction remain in the archive under
`previous/`; fresh results are separate under `current/`.

**Fresh final-source results:** 1,120 engine and 183 editor proofing tests pass
across 44 suites, with zero failures or skips. The 1,303 registrations represent
1,295 distinct suite/name cases because of eight documented repeated grammar
fixture rows. All 41 new spelling cases are distinct. Two incoming Zotero
stored-details suites separately pass all 21 tests.

The genuine Flutter 3.47.8 / Dart 3.13.7 runtime and all 162 hosted archives
were downloaded and hash-verified again. The locked workspace contains 110
packages and all 11 manifests remain unchanged.

This is an incremental evidence checkpoint. Baseline, portable/static,
full-source asset accounting, final report and remote readback are being
completed. See [status.json](status.json). No new spelling PR has been opened.

The earlier [fixed incoming reconciliation](reconciliation-current.md) covers
376 references at its recorded cutoff. The final source additionally includes
qualified Zotero stored-details work through `8d74db5d`. Later main documentation
and document-review/citation work are recorded separately in the recovery
scope audit; they are outside this fixed product qualification.

[Evidence archive](evidence.tar.xz) · [Member index](evidence-index.json) ·
[Original independent review](review.md)

No GitHub Actions, workflow, check or CI-status endpoint has been queried,
awaited, dispatched or rerun. Checkpoints use non-forced expected-head updates
and `[skip ci]`.
