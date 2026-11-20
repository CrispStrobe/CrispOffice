# Mail multiple-draft continuation — 20 November 2026

This record accompanies [multiple-drafts.md](../../roadmaps/mail/multiple-drafts.md).
The work branch is `work/mail-multiple-drafts-20261120`. Source is saved to
GitHub incrementally; local qualification does not wait for GitHub Actions.

## Intake and source checkpoints

The [initial audit](intake.json) captures 16 fork heads, the open Zotero PR,
upstream branches and independent equivalence checks for historical branches.
The integrated source retains normal ancestry from:

- `192ea2aedbf0b1494627953c79a7042037a63301`: Office/Word/VBA union, including
  recent remembered-account work and the earlier Outbox/Zotero changes.
- `ce9ff1c8b155c03a0e2707d6fc8b41b52e611a93`: latest captured Outbox provider/
  foreground qualification and fixture corrections.
- `231bd0403a3d2855dc23bf8dacefaedba01f2aab`: latest captured Zotero/layout
  reconciliation and regression evidence.

Initial remote integration checkpoint:
`d4787143856f83ca80a1928f86ce010a64822268`.
Remote draft-storage checkpoint:
`7f98f5fbad00e34abafabf1e901a27102c30acd7`.

Direct command-line pushes lack authentication in this workspace, so source
checkpoints use the connected GitHub Git-data API. Every generated remote tree
is compared against the local Git tree before the branch is advanced using an
expected-head lease. Local and remote histories are then aligned only after
their committed trees compare equal. No force update or workflow/ruleset change
is used.

## Completed local gates at the UI checkpoint

| Scope | Result |
| --- | --- |
| Exact integrated intake: full core, MIME and transport, plus three affected document-layout suites | 579 passed |
| Full native store, including new catalog and actual process-kill recovery | 596 passed |
| Existing Node codec/platform/browser-error cohort | 46 passed |
| Store strict analysis; browser entry and worker compilation | Passed |
| Focused new catalog plus legacy Studio draft/Outbox storage | 48 passed |
| Draft-list widget actions, stale deletion and three language layouts | 7 passed |
| Connected IMAP/EWS multiple-draft and existing Outbox host workflows | 7 passed |
| Remembered-account suite, including exact manual/iCloud offline identity | 22 passed |
| Offline workspace and existing composer autosave | 22 passed |
| Both-host catalog ownership, failed recovery, stale callback, reply and complete forwarding | 12 passed |

These cohorts overlap and must not be added as a unique-test total. The final
source acceptance receipt and broader host results are added after the final
incoming-head reconciliation. Intermediate qualification is not a statement
that all Office functionality, installed apps or live mail providers were tested.

The runtime is the repository-pinned Flutter 3.47.8 / Dart 3.13.7 with enforced
locked dependencies. Official SDK/package archive hashes were verified. Native
storage uses the unchanged sqlite3 package build hook and its genuine SQLite
3.54.1 artifact, with FTS5 enabled.

## Development findings addressed

- A missing native-assets manifest caused the first isolated transport run's
  SQLite setup failures. Preparing the unchanged locked native hook resolved
  them; a full 402-test transport rerun passed without source changes.
- The new corruption test initially changed blob length and hit SQLite's CHECK
  before the intended hash check. Its fixture now changes equal-length bytes.
- Localized page-navigation controls overflowed narrow windows. They now wrap;
  the English, German and Arabic layout tests pass.
- If the selected-draft read failed after closing the chooser, an old host
  snapshot could otherwise be saved into a different selected ID. Hosts now
  consume a chosen snapshot directly or retire an unreadable owner before
  allowing another edit. Both-host regression tests cover this path.
- Catalog ownership is verified independently of the optional Outbox interface.
  Offline URI construction is guarded and controls follow changed account
  settings. Read-only provider sessions can retain local drafts without sending.

## Limits

Offline entry is limited to remembered IMAP explicit-server/preset records whose
exact draft identity is reproducible. EWS/cloud and incomplete historical
autodiscovery records still require connection. Browser checks cover portable
code and compilation, not new catalog execution in IndexedDB/OPFS. No real mail
was sent, no production account credentials were used, and no installed-platform
or external-provider delivery certification is claimed.
