# Reconciliation of concurrent mail and Word work

This record explains the source choices for the foreground bulk-flag milestone.
It distinguishes retained history, unchanged tests and deliberate behavioral
consolidation. The [acceptance record](README.md) owns final qualification and
publication results; the [source-intake record](intake.md) owns the captured refs
and final ancestry accounting.

## Concurrent bulk implementations

The integration's provider-facing implementation was saved at
`034d73d2d09245c4a151de37bf522664ea5b4a80`. Meanwhile,
`work/mail-bulk-actions-20261120` reached
`b60c0ec26f2a80c984076fb1d480eb2e641b542e` with an overlapping core coordinator,
message-list controls and host work. Keeping two dispatch algorithms would
create competing cancellation, evidence and receipt semantics. The selected
[core implementation](../../../packages/quds_mail_core/lib/src/sync/bulk_flags.dart)
therefore consolidates their functionality into one private `_runBulkFlags`
engine with two public entry points:

- `MailBulkFlagRunner` accepts ordinary `MailResult<MailUnit>` provider replies
  and classifies failure using explicit mutation-boundary evidence.
- `MailBulkFlagCoordinator` accepts certified `MailBulkFlagAttempt` replies and
  preserves the peer's single-use, no-overlap/no-replay contract. Its separate
  cancellation token requests a stop without cancelling the provider lease.

Both entry points share bounded frozen selection, sequential dispatch, immutable
ordered receipts, scope validation, progress, `shouldStop`, uncertainty handling
and the same callback-exception boundary. This is an intentional replacement of
the competing source implementations, not a claim that their source files or
complete behavior were already equivalent. The original peer history is
retained through `9109fcc645d0d95fbe7a7568ddf1e0ebc07bc384`, a parent of local
merge `b658306a99d09f70d1a3a4d8efca8d72082398fd` and published integration
`dee5baf1c5fbf1bf6228434158ef32d49693ff94`. The final intake and publication
receipts account for later captured heads and the eventual main merge.

The peer subsequently advanced to
`9109fcc645d0d95fbe7a7568ddf1e0ebc07bc384`. Its intervening reconnect fix increments
`_mailboxGeneration` on disconnect and checks `mounted` at bulk entry, closing
the reconnect gap identified when reviewing `b60c0ec`. That finding therefore
does not describe the later peer head. The selected implementation retains its
provider/loader identity, revision and frozen-identity guards; the intake record
tracks the later incoming head separately from the original API/test source.

The next peer head, `639ea75a813d558cb5a1a848a6242fbf17bcf0c3`, supplied
`MailBulkFlagAttempt.fromResult`, additional progress/provider-evidence tests
and a cloud mutation-classification refinement. The public factory is retained
and used by the provider runner, leaving one evidence mapping and one execution
engine. Its entire 577-line
[bulk_flags_provider_results_test.dart](../../../packages/quds_mail_core/test/bulk_flags_provider_results_test.dart)
is retained unchanged, with Git blob
`087b6804f5e51ab353140de4a7876e506de81b52`. Neither this import nor the earlier
coordinator suite replaces the integration's stronger compatibility tests.

### Public API choices

| Surface | Retained contract |
| --- | --- |
| Provider scope | `MailBulkFlagPlan.provider` derives from the frozen identities. The optional constructor argument validates it, accepting both the peer's explicit-provider callers and the existing hosts that omit it. Mixed providers and local-provider plans are rejected. |
| Selection bound | A plan contains 1–1000 unique identities from one account/provider. The count is checked before caller-list traversal. IMAP identities must also share the selected mailbox and UIDVALIDITY. |
| Plan IDs | Adopt the peer's nonblank ID requirement and 256-character bound, with control characters rejected and without echoing supplied values in validation errors. This tightens the earlier runner's 1000-character ID allowance. |
| Operations | Public `operationAt(index)` uses `planId:index`, replacing the earlier private runner's `planId-index` format. Receipts retain the exact operation object passed to the callback; `message` derives from that operation. |
| Receipts | `items` and `results` expose the same immutable list. Original problem instances are retained. `stopReason` and `stopProblem` are both available. |
| Progress and stop | Both entry points accept progress and `shouldStop`. The coordinator also retains its independent cancellation token. The current request settles before a requested stop prevents subsequent dispatch. |
| Reuse | A coordinator is consumed by its first run, including a predispatch scope rejection. The stateless provider runner performs no automatic retry or replay; callers remain responsible for starting a new deliberate run. |

The peer's original core test file is retained byte-for-byte as
[bulk_flags_coordinator_test.dart](../../../packages/quds_mail_core/test/bulk_flags_coordinator_test.dart).
Its Git blob remains `fbbb20b4ee8d7cb6fe03dfe4606394154749132b`; all 31 tests and
their assertions are unchanged. In the integration's original
[runner suite](../../../packages/quds_mail_core/test/bulk_flags_test.dart), only
the three literal operation-ID expectations changed to the adopted colon
format. The additional
[compatibility suite](../../../packages/quds_mail_core/test/bulk_flags_compatibility_test.dart)
exercises both public entry points, receipt identity and the safety refinements
below.

### Failure evidence and stop precedence

[MailProblem](../../../packages/quds_mail_core/lib/src/model/result.dart) now
carries optional `mutationMayHaveOccurred` evidence. For ordinary provider
replies, only `false` certifies a definite failure with no remote effect. `true`
and absent evidence both produce an uncertain result. A generic conflict,
permission, cancellation or stale-operation code does not by itself prove that
a write was never accepted.

The native IMAP, native EWS and cloud adapters attach this evidence at their
existing mutation boundaries, preserving their problem codes. The cloud
boundary uses `mutationPossible`; native and EWS paths track whether the write
has started. Unsupported adapters can certify that no write was attempted.
Exceptions escaping an invoked callback remain uncertain because that callback
may already have dispatched its request. Raw exception text is not copied into
the receipt.

The coordinator's explicit `MailBulkFlagAttempt.failed` is itself an adapter
certificate of no effect, preserving the peer's definite-rejection behavior
even when its problem lacks the new metadata. Two deliberate refinements make
the combined contract more conservative:

- A failed certificate accompanied by `mutationMayHaveOccurred: true` is
  contradictory evidence and becomes uncertain.
- Certified `cancelled` or `staleOperation` failures stop additional dispatch
  even when the host has not yet retired its lease or scope predicate.

An uncertain reply takes precedence over a simultaneous cancellation or scope
change. Otherwise a certified provider cancellation/stale result wins, followed
by foreign-account lease, cancellation token, stale lease, scope-predicate and
requested-stop checks. A failed scope predicate is distinguished from an
exception thrown while checking it. Lease/cancellation is checked again after
caller guards, closing a reentrant retirement gap. An acknowledged in-flight
success remains confirmed in its receipt; each host separately rejects applying
that acknowledgement to a newer view. Exceptions in a progress observer cannot
erase an outcome or cause a replay.

## Message list and host consolidation

The selected [message list](../../../packages/quds_mail_ui/lib/src/workspace/message_list.dart)
retains selection and action generations, separate opening/navigation behavior,
explicit desired-state commands and loaded-visible-row selection. It freezes
the selected IDs and generation in each popup value when the menu opens. This
matters because an already-open `PopupMenuButton` route can later invoke an
updated callback after a host rebuild. The retained generation must therefore
travel with the menu value, rather than be read only when that callback runs.
The actual-open-popup refresh regression in
[message_list_bulk_test.dart](../../../packages/quds_mail_ui/test/message_list_bulk_test.dart)
exercises that route, in addition to captured-callback tests.

The peer's distinct
[bulk_message_list_test.dart](../../../packages/quds_mail_ui/test/bulk_message_list_test.dart)
is retained with explicit API adaptations: `selectionScopeId` maps to
`selectionRevision`, `bulkActionsEnabled` to `bulkEnabled`, the cancellation
fixture uses the opaque `bulkStatus` slot, and widget keys use the selected
implementation's names. Its frozen-menu helper captures the private menu value
through `itemBuilder`; it does not widen the production type to bypass the
guard. Intentional behavioral updates require selection to clear immediately
when an action is accepted, explicitly reselect rows before a new action, and
disable Clear after a refresh-required transition has already cleared checks.
These are adapted scenarios, not byte-for-byte or whole-source equivalence.
The peer's Escape scenario is preserved, and Escape now clears checked rows
without opening a body or mutating mail.

The selected hosts continue to use the provider-facing runner. Native IMAP
requires the optional `StudioMailBulkMessageActions` port, including stable
remote identity and mutation evidence; the older single-message action port
alone does not enable bulk commands. The shared EWS/Gmail/Microsoft 365 host
uses the provider's `apply` method. Both freeze selection before dispatch,
preserve unrelated nullable flags and retain the open reader.

Peer scenarios were adapted into
[studio_mail_workspace_test.dart](../../../packages/quds_office_editor/example/test/studio_mail_workspace_test.dart)
and
[studio_mail_bulk_provider_test.dart](../../../packages/quds_office_editor/example/test/studio_mail_bulk_provider_test.dart).
They cover reverse-order subsets, caller-list mutation, all four actions,
reader preservation, unknown flags, unrelated answered/draft/deleted flags,
folder A-to-B-to-A transitions, malformed selections and reconnects with
overlapping row IDs. Generic provider failure codes without explicit evidence
remain uncertain. A legacy native fake without the safe bulk port is expected
to expose no bulk callback.

The retained lifecycle guards bind callbacks to provider/loader, account
session, folder and observation revision. Native IMAP additionally checks
UIDVALIDITY and all frozen selected UIDs before dispatch and projection. The
shared provider host defensively checks the current header-ID-to-remote-ID map
against every frozen selected row. If that check fails while the same run and
scope still own the foreground operation, it retains the settled receipt,
releases busy state and requires refresh without projecting stale results.
It does not release a later run's busy state.

Independent review found that captured native Stop/Dismiss callbacks could
otherwise affect a later batch or call `setState` after disposal. The selected
[native host](../../../packages/quds_office_editor/example/lib/studio_mail_native.dart)
now guards them with `mounted` plus the captured session/report identity. The
`old status callbacks cannot stop or hide a later batch` regression also invokes
them after disposal. The shared provider host uses analogous run/report guards.

A later retained peer disposed-action test also caught a missing `mounted`
check at native `_changeBulkFlags` entry. The entry now rejects a disposed
callback before constructing a plan or changing status, independently of the
Stop/Dismiss guards. Hosts also require refresh for a certified stale-scope
result even when its failed item proves no mutation. This host recovery gate
does not change the core `requiresRefresh` property's uncertainty-only meaning.

The shared
[StudioMailBulkStatus](../../../packages/quds_office_editor/example/lib/studio_mail_bulk_status.dart)
labels the unfinished bucket **Pending** while running, because it includes
the current in-flight message. Final receipts label remaining entries
**Not attempted**. Details are disabled until the run settles, so they cannot
claim that an in-flight request was never sent. Progress is labelled
**Messages completed**, and the outcome counts are configured as a live region.
English, German and Arabic wording and compact layout are represented in the
host/UI tests; this is not a claim of live assistive-technology certification.

## Foreground and cache boundary

This milestone executes foreground read/unread/flag/unflag changes against a
frozen selection from the currently loaded mailbox. Selection and bulk actions
do not fetch message bodies or additional pages. Confirmed results update the
current live view; failed, uncertain and unattempted results do not manufacture
new observed flags. Unknown unrelated flags remain unknown.

The bulk path does not persist a remote-command journal or a durable bulk
receipt, and it does not call the mailbox cache's `saveView` after each result.
Native cached header observations can therefore remain the earlier browse
snapshot. Confirmed live-view flags are not guaranteed to survive offline
reopening or reconnect until a fresh provider observation updates the cache.
Cached-only hosts expose no mutation selection. An uncertain result requires
an explicit fresh observation before another mutation; dismissing a receipt
cannot clear that requirement. Durable sessions, journaling, reconnect replay
and crash recovery remain separate milestones.

## Word work incorporated during the mail increment

Remote main advanced through merge
`b01cb23dc1b7bc94b691d68a2507b61dc6d48d7a` with the reconciled Word measurement
and official named-argument work. The incoming continuation then reached
`c12ad8bc9c17f1849acdf92b2245e9198f1005b8`. The local integration incorporated
these at `fcc7bd27f` and
`e583e2dd26d4c58cb56172a8ac016c6fed24e41d`, respectively.

The production helper and [Word VBA contract](../../VBA_WORD_MACROS.md) were
resolved to the coherent named-argument version already on main. The production
[office_vba_language.dart](../../../packages/quds_office_engine/lib/src/automation/office_vba_language.dart)
blob remains `07dc3c5737661abaf3b17db24439c71482de22ed`; the contract blob remains
`e1ba38ca57f2c997cb3d978a4f3e24b3946fb4d9`. Both are identical between the captured
main merge and `e583e2dd2`.

That implementation supports the eight physical conversions and official
named arguments across all ten Word measurement helpers, including the existing
line conversions. It already converts numeric inputs with `.toDouble()` before
multiplication, so the continuation's integer-intermediate overflow fix was
present without restoring its older positional-only dispatcher. The bounded
native-grid canonicalization and existing numeric/work limits are retained.
The continuation's unique `large scalar conversions do not overflow grid
intermediates` regression in
[office_vba_word_unit_conversions_test.dart](../../../packages/quds_office_engine/test/office_vba_word_unit_conversions_test.dart)
and its review/intake documents are retained. Earlier physical-conversion,
named-measurement and integration suites remain separate fixtures. Historical
Word records explicitly describe their own execution limits; they are not
promoted into current runtime passes by this merge.

## Core and provider qualification

Evidence paths here are relative to the evidence archive root described in the
[acceptance record](README.md). Each receipt records exact commands, working
directories, source/configuration hashes, log hashes and before/after stability.

The earlier [compatibility receipt](core-compatibility/receipt.json), SHA-256
`ade511b7fd090c319cdffbf9a55e56626fa6cb8190628e70ca4fde90ca704b6e`, records 172
core VM passes, 78 bulk Node passes and 191 provider-boundary passes for core
source SHA-256
`5bf9dd9025cd59b88875e23cd22744c82af004f1d60a76c73d02bca713fe5eb0`.
Those results qualify that earlier source, before the `fromResult` import.

### Incoming cloud change: failed run and bounded correction

The peer's new cloud rejection whitelist initially applied to the shared HTTP
request path, including submissions. Its first qualification produced **205
core VM passes and a failed transport run with 191 passes and four failures**.
For both Gmail and Microsoft 365, existing tests exposed HTTP 429 send outcomes
changing from retryable failure to uncertain, and HTTP 410 send outcomes
changing from rejected to uncertain. The
[initial receipt](core-provider-results/receipt.json), SHA-256
`dd3f42a4ceb16dd25d137a9bda7e08414f35f7068cb19159dc0f8a406c539825`, and its
failed raw log remain preserved. They are not reported as a passing transport
cohort.

The correction confines the narrower whitelist to `MailCloudOperation.apply`.
Foreground message mutations certify no effect only for the explicit HTTP
400/401/403/404/409/412 rejection set; dispatched HTTP 429 and unfamiliar HTTP
499 outcomes remain uncertain and stop the batch. The four new peer cases
cover that behavior across both cloud providers. Submission retains its
existing explicit client-rejection and Retry-After contract. **No existing
send assertions were changed**, and no additional mirrored tests were added.
The final cloud source SHA-256 is
`48358fc8f6b36fc24e88f4c139f050d44c0bdb569b170e8a5ad89ce370f7858d`.

### Accepted combined source

The [accepted receipt](core-provider-results/accepted/receipt.json), SHA-256
`78ed863dd723b9d78a2ca85473b73d03cd6adb4246f7eee053048c69f058a33d`, records:

| Cohort qualified after the correction | Recorded result |
| --- | --- |
| Entire mail core on Dart VM | 205 passed |
| Four bulk suites compiled to JavaScript and run on Node | 111 passed |
| Native, EWS and cloud provider boundary suites | 195 passed |
| Entire core and transport analysis | Clean |

These cohorts overlap and must not be added into a unique-test total. Formatting
and whitespace checks also passed. All five recorded command cohorts have
`source_hashes_unchanged: true`. The combined core source SHA-256 is
`eb7b9a2fc78067c814b121ecf8851c7076ab03576186723483c497c09ac6b537`.
This evidence qualifies the portable foreground contract and deterministic
provider boundaries. Final UI, host, Word and publication qualification belongs
in the acceptance record; live accounts, real mailbox writes and durable
post-restart receipts are not established by these local suites.
