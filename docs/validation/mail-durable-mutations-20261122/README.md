# Durable Mail Move/Delete — local acceptance and integration

Local acceptance is complete for the durable foreground organization increment.
The integrated source is `918e7dd12e66b79e75082a41c250887a92db0d4e`; subsequent
acceptance-record commits change documentation/evidence only. This record makes
no complete desktop-client parity, live-account or installed-platform claim.

## What changed

Single-message Move/Delete now shares the existing read/flag command runner and
journal: freeze intent and exact identities, save intent, save an applying
marker, invoke the provider, then retain the typed receipt. Production dispatch
fails closed if either pre-dispatch save fails. Restart never repeats uncertain
operations. A retired view can still save its original late acknowledgement
without publishing into a newer account/folder view.

Schema 13 adds a validated, quota-accounted move destination to the existing
journal and preserves prior flag receipts. The activity view displays the
original action, subject and exact destination. Flag-only recovery is rejected
for membership commands before any observer call; unresolved receipts remain
protected from completed-history cleanup.

Native IMAP exposes capability-checked Move and an explicitly confirmed **Mark
deleted** action. That action sets `\Deleted` without EXPUNGE. Exchange EWS and
Microsoft 365 use their existing Move/Deleted Items semantics; Gmail supports
Trash and continues to refuse folder-style Move. Confirmed moves and cloud/EWS
deletes retire the original foreground row. IMAP marked-deleted rows remain
visible. Explicit refresh is required afterward, and no destination identity or
cached membership is fabricated. Generic checked-message menus remain the four
read/flag actions.

See [durable-mutations.md](../../roadmaps/mail/durable-mutations.md) for the user
workflow, guarantees, provider boundaries and ordered next steps.

## Remote intake and incremental preservation

The initial 22 November 2026 intake began at
`a5b4eb7d329b0700768b1fc72bb63cf58a9f5cd6` on
`CrispStrobe/quds_office_suite/main`. A new checkout was acquired without
replacing existing local work.

- All 24 initial fork branches were inspected; the other 23 tips were already
  ancestors of main. All four upstream branch tips were also contained.
- Neither repository initially had an open PR. All 30 recently updated closed
  fork PRs inspected were merged, including #359 (Word VBA), #360 (retained Mail
  folders) and #361 (Zotero selected-field context).
- Two branches appeared during implementation. The integration preserves Word
  VBA `45a1c0846f3fb78a203f2967e5b80a79fdca2ca9` and Zotero recovery
  `6ba219a03a9933eded77980f9d7cdbd118183ee1` through actual merge parents.
- At the final recorded intake, all 27 fork and four upstream branch tips were
  ancestors of the integrated branch. The newly opened Word PR #362 points to
  the included Word tip; upstream had no open PRs.
- The source and checkpoints remain on
  `codex/mail-durable-mutations-20261122`. Commits use `[skip ci]`; no GitHub
  Actions status was queried or awaited.

| Remote checkpoint | Content |
| --- | --- |
| `ecfc7ae65cbd0904d6d38b9c8d76158d031a457a` | Initial intake and ordered scope |
| `cd6aa8044a7c6fb0738758a4038cdbd626b5721d` | Core/store/provider extension and first connected controls |
| `f14974a435ec0348d6618906ab21b5c784b04fd1` | Native metadata hardening, host regressions, localized history and roadmap |
| `262a13c2b0971f22d1442ac88cab48bddf2c6bce` | Merge of the current Word VBA history |
| `918e7dd12e66b79e75082a41c250887a92db0d4e` | Merge of the current Zotero history, including its captured Mail/Word ancestry |

Word later added documentation and its own qualification evidence at
`934c33a57f3bed934df59a4e925ffc35fe406ee2`; that history is also retained. It
changes no production or test source. Zotero subsequently advanced to the
already qualified integrated head `918e7dd1`.

The exact recorded inventory and ancestor checks are in [remote-intake.json](remote-intake.json).
The final publication uses a normal PR merge to main with the expected branch
head, retaining these parents. The branch remains available after publication.

## Accepted local checks

The toolchain is pinned to Flutter **3.47.8** and Dart **3.13.7**. The official
SDK archive and 204 resolved package archives were SHA-256 verified. Offline
locked dependency restoration succeeded, and `pubspec.lock` remained unchanged.
The Node runner used **v24.22.3**.

| Accepted scope | Passed cases |
| --- | ---: |
| Complete Mail core, native runtime | 521 |
| Complete store coverage, combining ordinary and native process fixtures | 1,010 |
| IMAP, EWS and cloud provider-adapter suites | 250 |
| Native message loader | 131 |
| SQLite journal adapter and history/dialog | 47 |
| Complete shared Mail UI suite | 273 |
| Existing provider, localized visual and native workspace host suites | 116 |
| Connected journal host, EWS and cloud suites | 190 |
| **Unique Mail cases covered in the native runs above** | **2,538** |
| Core under genuine Node execution | 521 |
| Portable store under genuine Node execution | 52 |
| **Node test executions** | **573** |
| Mail organization controls rerun after Word/Zotero integration | 11 |
| Incoming Word/Zotero engine regressions | 561 |
| Incoming editor recovery and adjacent regressions | 84 |

The 11 final Mail cases are repeat acceptance against the combined tree and are
not added to the 2,538 unique native total. Node is a second execution platform,
not additional unique core behavior. The store total comprises 975 ordinary
Flutter cases, 28 native journal process-kill/reopen cases and seven other
native archive/ownership process cases. A focused 180-case store cohort is
also retained but is not counted again.

Accepted machine runs have no failures, skips or runner errors. Strict analysis
passed for core/store, transport, journal UI/adapter, connected hosts and their
changed tests, shared menu tests, and incoming Word/Zotero targets. Formatting
checked all 67 changed Dart files with zero changes. The store browser entry
and worker compile to JavaScript; that is compilation evidence only.

The final source comparison verifies unchanged qualification inputs: 141
core/store files, 146 Node inputs, 72 journal inputs, both connected host source
files, and seven incoming Word/Zotero production files. The changed Dart source
and lock/configuration hashes are captured separately. Incoming histories
merged without conflicts; two documentation EOF whitespace issues were cleaned
without modifying their runtime code.

## Review findings and meaningful failure coverage

Independent review identified and the implementation corrected three native
issues: organization-only adapters unnecessarily required legacy flag setters;
retiring the cached observer cleared other rows' read/flag metadata; and setting
Deleted on a header without raw flags could turn unknown independent flags into
false. Dedicated connected regressions now cover all three, including confirmed
and definite-failure Move outcomes.

The tests also cover pre-dispatch SQLite failures, complete frozen identities,
stable-account rebinding, substituted move destinations, uncertain outcomes,
reopen without replay, closing while applying and saving a late receipt,
unsupported capabilities, cancelled delete confirmation, Gmail's unsupported
Move, and the absence of membership commands from generic flag menus. Receipt
migration, quotas, corruption, ownership and interrupted transaction boundaries
are exercised in the core/store cohorts.

English, German and Arabic compact history/details were rendered with enlarged
text. The retained visual samples were inspected for readable wrapped text and
accessible controls; their original PNGs and hashes are included in the evidence.

## Unaccepted attempts and environment limits

All attempts are retained rather than replacing unsuccessful output with a
success summary:

- The complete store run under Flutter stopped 35 subprocess fixtures before
  their barriers because that isolate does not implement
  `Isolate.resolvePackageUri`. Every one of those cases subsequently passed
  under native Dart; the original failed log is retained.
- Chromium failed before test execution because this environment denies the
  Unix-domain socket used during its startup. No browser runtime or persistence
  acceptance is claimed.
- Initial connected fixtures tapped a popup before its opening animation had
  completed and assumed explicit account setup while saved-account restoration
  was enabled. Those fixture assumptions were corrected; the 190-case final
  run passed with the real SQLite owner.
- An initial menu assertion used an exact private generic widget type. A typed
  widget predicate now verifies the actual popup contents. All 273 UI cases
  passed afterward.
- An earlier host run passed its assertions but reported a compiler-process
  exit. The accepted 116-case rerun was serial and exited successfully.

The checks use synthetic mail, identities and credentials. They do not qualify
live-provider interoperability, installed macOS/Windows/mobile behavior,
hardware power loss, or browser persistence. Local cache encryption is not
added by this increment. Full membership reconciliation, broader durable bulk
organization and complete desktop-client parity remain subsequent work.

## Reproducible evidence

- [qualification.json](qualification.json): exact commands, test names/counts,
  source comparisons, environment limits and artifact digest.
- [qualified-source-sha256.json](qualified-source-sha256.json): changed Dart
  source and dependency/configuration hashes.
- [core-store-receipt.json](core-store-receipt.json): full store coverage and
  native process-fixture accounting.
- [node-receipt.json](node-receipt.json): actual Node execution and browser
  compilation evidence.
- [incoming-office-receipt.json](incoming-office-receipt.json): focused incoming
  branch qualification and reviewed source identities.
- [local-evidence.tar.gz](local-evidence.tar.gz): raw accepted and unsuccessful
  logs, detailed receipts, source manifests, toolchain/dependency provenance and
  the three inspected original screenshot samples. The other 18 generated
  screenshot references in the detailed receipt are explicitly digest-only,
  listed in `qualification.json`; they are not included in this archive.
  The environment setup script is included. Paths within the archive
  correspond to the logged workspace-relative paths; generated executables and
  SDK/package archives are excluded.
