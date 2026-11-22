# Unified retained-folder navigation — local qualification

## Intake

Baseline: `2eecf9aec2c7d1f979064448b911b516d3f56c73` on 22 November 2026.
All 21 observed fork branch heads and all four upstream heads were ancestors of
this baseline. Both repositories had no open pull requests. Recent PRs and
exact observed heads are retained in [intake.json](intake.json).

Work is checkpointed incrementally to `work/mail-parity-20261122-next`.
The remote was refreshed again during publication. Two branches created during
this work were incorporated with their history, including the latest Word merge
on `main`. Exact heads, ancestry and conflict resolutions are recorded in
[integration.json](integration.json).

GitHub Actions were not awaited. Local qualification is the evidence for this
increment; workflows and branch protections were not changed.

## Delivered increment

The existing Cached mail reader listed saved foreground browsing windows and
omitted folders represented only by durable synchronized memberships. This
increment brings both into one account-scoped folder catalog that observes the
local repository, keeping their different coverage and pagination visible.

- One folder entry per exact account/folder identity, including sync-only folders.
- Explicit browsing-window versus synchronized-header source selection.
- Bounded synchronized pages and safe repair after membership removal.
- Reader identity and stale-callback guards across folder/source/page changes.
- Credential-free, provider-free local reading with honest missing-body states.
- Existing browse-only host compatibility and English/German/Arabic controls.

The implementation and its regression cases were saved at `e6ef3143`; the final
combined Mail run used integrated source `83974fba`, after the Word and Zotero
source merges. The [workflow and ownership contract](../../roadmaps/mail/retained-folder-navigation.md)
describes the UI, source coverage, identity guards and cleanup rules.

This does not add automatic network sync, a cross-account unified inbox, or
durable move/delete dispatch. The latter remains the next ordered milestone:
IMAP `\\Deleted`, Gmail Trash labels, EWS changed identities and Graph immutable
identities require distinct reconciliation behavior. No destination identity may
be guessed and uncertain writes must never replay automatically.

## Accepted local validation

The final integrated run passed **115 substantive cases** across all five Mail
suites, with process exit **0**, a successful terminal event and no failures,
errors, skips or incomplete cases. Source hashes, HEAD and the tracked tree were
unchanged during the run. The five suite-loading pseudo-tests are excluded.
See [integrated-check.json](integrated-check.json) and its archived raw log.

| Suite | Passing cases | Purpose |
| --- | ---: | --- |
| Retained-folder catalog | 22 | Exact identities, source coverage, ordering, bounds and malformed input |
| Existing browse mailbox session | 14 | Existing observation, lifecycle and failure behavior |
| Synchronized mailbox session | 22 | Paging, revision guards, source changes, repair and cancellation ownership |
| Existing cached-mail widget | 37 | Reader, cleanup, local-store and host compatibility |
| Retained-navigation widget | 20 | Sync-only/overlap folders, source/page changes, local refresh and cleanup races |
| **Final integrated total** | **115** | **64 new cases plus 51 existing regressions** |

The same suites were also qualified individually during development. Those
reruns are not additional cases. An earlier, separate host regression gate
passed 124 cases before the last narrow session metadata and cancellation
guards; it is retained as earlier-source evidence, not claimed as an exact-final
host-suite run. [qualification.json](qualification.json) preserves the commands,
case names, outcomes, raw-log hashes and those source bounds.

Strict analysis with `dart analyze --fatal-infos` passed for all seven changed
Mail Dart files. Formatting checked the same seven files with zero changes.
Independent review identified cleanup and cancellation ownership edges; the
final implementation retains failed-cancellation handles, drains pending reads,
revokes the selected observer before cleanup waits, and has regression tests
for those paths. No material review findings remain.

### Reproduction

Use the repository's pinned Flutter **3.47.8** / Dart **3.13.7**, resolve the
unchanged lockfile, and run from `packages/quds_office_editor/example`:

```sh
flutter test --no-pub --machine \
  test/studio_mail_retained_folders_test.dart \
  test/studio_mail_mailbox_session_test.dart \
  test/studio_mail_mailbox_sync_session_test.dart \
  test/studio_mail_cached_mail_test.dart \
  test/studio_mail_retained_navigation_test.dart
```

[runtime.json](runtime.json) records the verified official SDK archive, all 204
verified hosted dependency archives, the unchanged lockfile and the native
SQLite 3.54.1/FTS5 runtime. No dependency, manifest or database migration was
introduced. [source-hashes.json](source-hashes.json) binds the earlier accepted
runs to their inputs; the integrated receipt records its own before/after hashes.

### Concurrent incoming work

- Word VBA cell text controls and bounded `Join`: independently reviewed at
  `d16649e9`, with 552 local native cases, strict analysis, matching Dart/JavaScript
  Join fixtures and a portable cell-text roundtrip. The later `5f6e8686` change
  adds qualification records only. Its merge on `main`, `191ed89b`, is retained.
  See [the incoming Word review](incoming-word/incoming-word-review.json).
- Zotero selected-field source context and temporary rendering: independently
  reviewed at `a83700c6`, with 166 local engine/render cases and strict analysis.
  The subsequent native prompt/controller integration at `e8cc5795` is also
  retained and passed 146 focused host cases plus strict analysis. See
  [the incoming Zotero review](incoming-zotero/review.json) and
  [the host integration review](incoming-zotero/updated-e8cc5795/review.json).
  These runs overlap on nine rendering cases and are not added into one total.
  A two-line indentation correction after testing is recorded as whitespace-only
  in [integration.json](integration.json).

Only changelog entries conflicted during these merges. Both sides' entries were
retained; implementation files merged without conflict. The final Mail run
compiled and exercised the combined source, including the native Zotero prompt
integration. Incoming Office test counts are reported separately from Mail.

## Evidence limits and next work

This qualifies one account's local retained-mail navigation. Search, sorting,
conversation folding and unread counts in this view cover the displayed page.
Refresh reads local storage. Missing bodies stay explicit and are never fetched
implicitly.

No live mail account, OAuth login, provider send/move/delete, installed-platform
acceptance or new CrispCloud host adoption was exercised. These local tests do
not establish full Outlook, Thunderbird or eM Client parity. Durable move/delete
dispatch and provider-specific membership reconciliation remain the next ordered
milestone in the [Mail plan](../../roadmaps/mail/implementation-plan.md).

Unsuccessful bootstrap attempts, superseded runs and corrected test fixtures
remain in [attempts.json](attempts.json). An earlier helper receipt lost the child
exit code during postprocessing; that limitation remains visible. The final
integrated run captured the actual exit code and reran all 22 helper cases.
