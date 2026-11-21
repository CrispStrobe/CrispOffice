# Mail intake review at captured head 4d435f81

Reviewed immutable `4d435f81493c88e8fd4fb90a62558a1cc8a7ec22`, compared with its merge base `2cd11ced136a30354169fd0043e002079bcabfa3`. This is a source and retained-evidence review, not a new test result.

## Dependencies and overlap

The head adds three commits. Word branch `81b762008dfca9a8ab8d32cd9159a8d93ec3c6f2` already contains the first, `c375becb51939dcca5c145bf1bcdb14a4febe041`. Neither complete head contains the other. Their mailbox-view stream source/test and controller/layout-equivalence source/test files are byte-identical. Merging Word first therefore brings the stream and controller recovery work; merging the exact Mail head afterward adds its two session/host commits while preserving ancestry.

The controller recovery change restores the replaced-document marker if layout throws. It introduces two tests for explicit and lazy replacement retries. The earlier local 68-pass layout cohort does not contain these two cases. The integrated controller should run these cases, preferably with the complete equivalence suite because proofing also modifies the controller.

## Product review

The repository exposes bounded catalog and selected-folder streams after committed domain changes. Reads retain typed failure results, coalesce redundant reads, respect pause/resume, and drain cancellation. Session selection uses generation checks and serial cancellation to reject stale callbacks. Snapshot validation checks account/provider identity, duplicate IDs/remotes, bounded size, revision high-water mark and IMAP mailbox/UIDVALIDITY consistency. A missing saved view remains distinct from an empty saved view.

Projection binds cached flag metadata to the original current provider header identities from a successful save. It refuses partial/different membership, changed remote identities, invalid/stale revisions and invalidated windows. Connected IMAP/EWS hosts drain subscriptions before releasing storage ownership and preserve selected readers across compatible metadata changes. EWS retires the cached-window observer before move/delete so it cannot restore a removed row. Cached browsing displays unknown read state separately and retains errors rather than reporting an empty cache.

No concrete correctness blocker emerged from this read-only review. Deterministic tests still need to validate the newly connected hosts on the final integrated source.

## Retained evidence applicability

`receipt-applicability.json` records independent SHA-256 comparisons with captured Git blobs. Every recorded hash matches this head.

| Receipt | Recorded result | What independently matches | Limits |
| --- | --- | --- | --- |
| store-validation.json | 117 passed, zero failed/skipped | 8 named paths, complete 16-file Mail core library tree, complete 36-file store library tree | Retained summary; no raw test log in this receipt |
| session-validation.json | 14 passed, zero failed/skipped | Exact session source and test | Does not bind all dependencies or cover new native/cached integration; no raw log |
| incoming-word-validation.json | 70 passed, 8 excluded, zero failed/errors | Exact controller, layout engine and equivalence test; archive hash; raw test JSON re-counted; before/after inputs equal | Eight pre-existing image-only fixtures have no editable paragraphs; not passes; does not qualify new proofing merge or profile performance |

`layout-retained-log-audit.json` independently records the raw archive analysis. The archive is 26,996 bytes with SHA-256 `18800633895384f91bff014386db86e4152a23652c012b448c435c80d8fdb3a9`.

The tip `4d435f81` connects native/cached hosts after these retained receipts. Its new and changed integration tests therefore require a current local run before the tip is treated as accepted.

## Recommended integrated local gates

From `packages/quds_office_editor/example`, run these four suites using the exact locked runtime and authentic SQLite hook asset:

- `test/studio_mail_mailbox_session_test.dart`
- `test/studio_mail_capture_projection_test.dart`
- `test/studio_mail_cached_host_test.dart`
- `test/studio_mail_cached_mail_test.dart`

Analyze the six changed Studio source files and four tests with fatal infos. If Mail store sources or dependencies differ after integration, rerun `mailbox_view_streams_test.dart`, `mailbox_views_test.dart`, `flag_journal_test.dart` and `flag_reconciliation_test.dart`; the retained source hashes can establish whether that repeat is necessary.

Run the merged `word_incremental_layout_equivalence_test.dart` separately, retaining its explicit no-paragraph exclusions. This does not assert a profile-mode performance result.

No GitHub Actions/status APIs were queried or awaited. No source files were changed during this review.
