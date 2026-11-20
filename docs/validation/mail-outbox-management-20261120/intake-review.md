# Incoming-head and multiple-draft review — 20 November 2026

Read-only review for the Mail Outbox management continuation. No working-source,
index, checkout, remote ref, PR state, workflow or Actions mutation was performed
by this review. No AGENTS.md was found in the cloned repository. This is source
review and ancestry/equivalence evidence, not an executed-test claim.

## Captured intake

Main: `13be50464d1b43e9f2100fb9ccc12f8fe22eb55e`.
17 live fork heads were inspected. The latest 50 PRs ordered by updated time
include 46 merged heads already in main, closed unmerged PR #202 whose head is
also already in main, and these three open PRs:

| PR | Head | State | Finding |
| --- | --- | --- | --- |
| 249 | `93dc987cf993787bd613018b3028e7ad60d5472a` | Draft | Only two evidence files remain beyond the multiple-drafts integration |
| 251 | `c20b41d9c7eed574c02e49f1fd96789843aec2e6` | Draft | Exact ancestor of the multiple-drafts head; final Outbox/account requalification still described as pending |
| 252 | `0f6239396ff3328473a5f57c280b982d57e33a08` | Ready | Exact ancestor of the multiple-drafts head; source-bound scoped qualification published |

`work/mail-multiple-drafts-20261120` at
`e7ed2efd4e661ef244a21dd2836525c8e1531b7e` has 42 commits ahead of main, none
behind, and preserves the current accounts and VBA heads plus Zotero through
`7f363b99`. Its four unique commits add a draft catalog, offline composition,
host recovery and integration. Its README explicitly defers a final-source
acceptance receipt and broader host results. Listed intermediate cohorts overlap
and must not be totalled or relabelled as final-source qualification.

Recommended integration: preserve `e7ed2efd` by ordinary ancestry, then merge
`93dc987c` (two additional Zotero qualification artifacts only). Preserve owner
branches. Run the affected Mail/store and shared host boundaries on the actual
candidate before publication.

The following refs are already main ancestors: `fix/mail-credential-stores-chrome-20261120`,
`integrate/recent-pptx`, `work/mail-outbox-20261120`.

Eight historical whole-tree equivalences were independently recomputed; every
equivalent commit remains a main ancestor:

| Ref | Equivalent main ancestor |
| --- | --- |
| docs/ods-color-scale | `4eaca83b192897edad82658107dfeb5bcbed0920` |
| docs/ods-data-bar | `52c73ae4dbadf2ca00a5d619144350ccc353b31a` |
| feat/ods-color-scale | `4584d5f319aab198f1d705f48b4d6647e6cbabea` |
| feat/ods-data-bar | `b3f41eb4b4bca8ca13676b4114891ea6d9185043` |
| feat/ods-dynamic-validation-links | `d754bf15b07a24c8a86c8dce339ca749fecd9531` |
| feat/ods-icon-sets | `c84d5e16024c502f6c451fd04b9807b1e65f20d3` |
| feat/ods-time-period-conditions | `34dc6b6806869570e9ec342e4d7ee0d6951c0ba6` |
| integrate/office-union-148 | `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` |

ODT continuation `c3494576` independently matches all 37 changed paths at main
ancestor `b5b1fa99228f6f1862af0bc4efba6e527c2bec43`. It is a changed-path proof,
not a whole-tree proof. Reapplying historical branches would be inappropriate.

## Bounded multiple-draft source review

Reviewed the new repository catalog/capacity transaction, draft adapter catalog,
selected-draft epoch fencing, IMAP/EWS host selection/recovery, offline draft
workspace and chooser, and the associated focused test assertions. No concrete
blocking defect was found in these existing changes within that scope.

- Admission cap and revision comparison share the SQLite transaction with the
  write. Existing records remain editable at capacity. Canonical tombstones are
  excluded in SQL; other records are decoded and validated before being skipped.
- Selecting and deleting use account/ID/listed revision, with per-selection epoch
  fences for queued saves. Clear and Outbox transfer retain revision tombstones.
- Both hosts consume a selected chooser snapshot directly. If a post-chooser
  reload fails, the old store and host snapshot are retired, so a previous message
  cannot overwrite the newly selected ID.
- Offline identity is restricted to exact saved explicit-server/preset IMAP
  routes. Settings, credential revision, account ID and host generation are
  captured. The chooser/composer is local-only and submission is disabled in
  both UI and finish handler. Ordinary close waits for the profile lease release.

## Constraints for the new Outbox edit-copy operation

These are implementation requirements, not defects in the incoming draft work:

1. `StudioMailDraftCatalog.createDraft` intentionally creates a new selected
   draft with uncertainty false. Do not reuse it blindly for a previously
   uncertain Outbox record. Either restrict copying to definitely unsent entries
   or explicitly preserve the earlier-attempt uncertainty in the durable copy.
2. A cancel-then-create sequence must not lose the frozen message if draft
   creation fails. A create-then-cancel sequence must not leave two sendable
   copies after failure. Add a repository transaction for editable handoff, or
   clearly expose duplication as an explicit copy with duplicate-delivery guard.
3. The queued draft's original ID is now a revision tombstone. Create a new ID;
   do not resurrect that cleared row or erase the Outbox's immutable wire data.
4. Capture current account and selection epoch for the host callback. Keep the
   existing editable draft durable before changing selection. Consume the
   returned new snapshot directly after a successful handoff.
5. Recover Bcc from the saved transport envelope; it is deliberately absent from
   MIME headers. Validate MIME address/header projections against that envelope.
   Do not reconstruct export bytes from a preview or from mutable draft state.
6. Preserve attachment bytes, reply headers and body without fetching external
   resources. A new send should receive a fresh Date/Message-ID when queued;
   retries of an existing frozen entry must continue using its original bytes.

## Targeted incoming-source qualification paths

Run these from their package roots, in addition to the new Outbox suites. These
are concrete affected boundaries; they are not a demand to replay every incoming
unrelated package or relabel scoped historical evidence as a new combined run.

### packages/quds_mail_store

- `test/draft_catalog_test.dart`
- `test/outbox_draft_transfer_test.dart`

### packages/quds_office_editor/example

- `test/studio_mail_draft_catalog_test.dart`
- `test/studio_mail_draft_host_recovery_test.dart`
- `test/studio_mail_local_drafts_test.dart`
- `test/studio_mail_outbox_host_test.dart`
- `test/studio_mail_outbox_cloud_test.dart`
- `test/studio_credential_selection_test.dart`
- `test/studio_credential_selection_race_test.dart`
- `test/studio_mail_credential_backend_switch_test.dart`
- `test/studio_mail_selected_store_integration_test.dart`
- `test/studio_word_chrome_settle_test.dart`

### packages/quds_mail_ui

- `test/body_presentation_contract_test.dart`
- `test/reader_theme_scroll_test.dart`

### packages/quds_office_engine

- `test/word_incremental_layout_test.dart`
- `test/word_incremental_layout_differential_test.dart`
- `test/word_incremental_layout_prefix_test.dart`
- `test/word_paragraph_mark_layout_test.dart`
- `test/slide_text_insets_preservation_test.dart`
- `test/office_vba_powerpoint_margins_integration_test.dart`
- `test/word_zotero_note_tables_integration_test.dart`

### packages/quds_office_editor

- `test/word_zotero_add_note_controller_test.dart`
- `test/word_zotero_note_image_controller_test.dart`

Before publication, refresh the live heads/PR inventory. Source compatibility
and read-only intake do not establish provider delivery, installed-platform
behavior or final-source qualification on their own.
