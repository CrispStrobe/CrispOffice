# Tasks implementation and recovery plan

Date: 2026-11-25. This is the engineering companion to the
[roadmap](README.md). Implementation status is in [progress](progress.md).

## Boundaries and package sequence

| Boundary | Initial package / location | Responsibilities |
| --- | --- | --- |
| Portable domain | `packages/quds_tasks_core` | Immutable field values, identities, capabilities, typed failures, sparse patches, pure reconciliation |
| Microsoft tasks | `packages/quds_tasks_graph` | Graph JSON mapping, account-scoped HTTP/token ports, list/task deltas, bounded task CRUD |
| DAV tasks | `packages/quds_tasks_caldav` | iCalendar VTODO codec, server profiles, collection discovery, conditional resource operations |
| Durable repository | `packages/quds_tasks_store` | SQLite inbound snapshots, cursors and restart recovery. Local working copies and pending operations are planned. |
| Coordinator | Pull worker in `quds_tasks_store`, with host scheduling planned | Resumable pulls and account-generation fencing. Merge, push and retry scheduling are planned. |
| Studio | Task UI package and native Studio host | Tasks workspace, account setup, consent, conflict controls, notification choices and credential vault |
| Later providers | EWS / OX HTTP / Vikunja / Planner modules | Implement the shared task boundary with explicit capability and fidelity differences |

Protocol packages use public, injectable transport/authentication boundaries.
They do not own account passwords, UI dialogs, durable task state or conflict
decisions. A native transport can be a separate conditional entry point.
Neither task models nor protocol codecs depend on mail message IDs.

## Core data model

The initial API should stay small enough to implement and test in one increment.
Exact class names may evolve before integration; these invariants must remain.

- Account identity includes provider and a stable host-owned account key, not
  merely the displayed email address.
- Remote identity includes account, list/collection and item ID. CalDAV also
  retains the resource href and iCalendar UID. Graph item IDs may change on
  moves, so a local identity must never be the raw provider ID.
- A task field snapshot includes title, body plus body format, status, priority,
  dates, and provider data needed for faithful updates. Retain unknown values
  instead of replacing them with a convenient known default on write.
- Dates distinguish civil dates, floating wall times, named-zone wall times,
  and UTC instants. No implicit use of the machine's timezone.
- Patches represent unchanged, set and clear independently. Notes are not
  rewritten when only completion or title changes.
- Capabilities describe supported fields/operations, write safety, and
  restrictions. The UI must use them; an unsupported operation fails explicitly.
- Immutable snapshots defensively copy collections and cannot be mutated after
  validation. Provider payloads and credentials are excluded from diagnostics.

## Repository state

Persist, scoped by account/list:

1. Local task IDs, local revisions and selected-list configuration.
2. Remote bindings and the last successfully synchronized remote base.
3. Server version/ETag and the entire opaque continuation/delta token.
4. Pending operations with unique operation IDs, exact local revision, intended
   patch, attempted flag and acknowledgment/unknown-outcome state.
5. Tombstones, conflicts, retry deadlines and account sync generation.

A transaction applies a remote page and advances its associated checkpoint.
The last committed completed-round cursor remains recoverable until a new
round is safely committed. Empty intermediate pages still advance the round.
Repeated pages and repeated acknowledgments must be idempotent.

## Reconciliation policy

Use a three-way comparison between the synchronized base, the current local
snapshot and the current remote snapshot.

| Situation | Required result |
| --- | --- |
| Only remote changed | Import remote state and update the base |
| Only local changed | Keep the pending local change; generate a sparse write |
| Disjoint local and remote field changes | Merge and retain only the still-pending local fields |
| Same field changed to the same value | Converge without conflict |
| Same field changed differently | Preserve both and surface an explicit conflict |
| Remote deleted, local unchanged | Apply a tombstone |
| Remote deleted, local edited | Preserve the local work and record a deletion conflict |
| Local deleted, remote edited | Require resolution before deleting the new remote state |
| Record absent from an incremental page | No deletion inference |
| Cursor expired | Rebaseline the collection while retaining dirty records/outbox |
| Old local revision acknowledged | Acknowledge that operation only; retain later edits |
| Account disconnected during request | Ignore stale-generation responses; do not recreate the account |

Conservative conflicts are preferable to silent overwrites. A preflight read
is not an atomic compare-and-set. Provider conditional-write guarantees must
be documented and tested independently.

## Writes, retries and crashes

- Persist a mutation's intent and operation ID before transmission.
- Do not automatically replay a task creation after a timeout or lost response.
  Graph has no documented task `transactionId`. `client-request-id` is tracing.
- A Graph create can carry a namespaced open-extension marker in the same
  request. Implement and test recovery lookup before using it to resume an
  ambiguous create. Until then keep the operation unresolved, without a retry.
- A deterministic CalDAV resource URL plus `If-None-Match: *` can help reconcile
  creates; read back and compare UID/payload before concluding success.
- CalDAV updates and deletes use the observed ETag with `If-Match`; `412`
  becomes a conflict. Refetch if the server normalizes the object.
- Current Graph task documentation shows ETags but does not establish the
  complete conditional-update contract. Do not advertise atomic conflict
  prevention before a live stale-ETag test. Keep patches sparse and preserve
  unresolved outcomes.
- HTTP 401/403 is an authentication/authorization failure, never a tombstone.
  Honor `Retry-After`; schedule retries without blocking the UI.
- Failed list discovery or a partial response must never trigger mass deletion.
- Operations are serialized per account/list and generation. A disconnect or
  credential revocation cannot authorize a late write from an old worker.

## Graph adapter

Use `https://graph.microsoft.com/v1.0/me/todo` with delegated access. Keep task
consent optional in the existing Microsoft setup. Do not silently increase
permissions for existing mail-only accounts or require mail access for a future
tasks-only account.

Read list and task delta collections separately. Retain returned next/delta
URLs verbatim, while validating HTTPS, approved origin, API path and collection
scope before sending a bearer token. Reject foreign account/list cursors,
userinfo, fragments and unbounded responses. Encode opaque IDs as path segments.

Basic CRUD comes before checklist, attachment and recurrence workflows. Preserve
HTML notes and unrelated provider properties with sparse patches. The initial
adapter fails a page explicitly for unknown status/importance enums; the worker
must retain its previous checkpoint and surface the unsupported data, without
inferring deletion or substituting a known default. Carry remote date/time and
zone pairs without machine-local conversion. App-only use is a separate
qualification: current Microsoft endpoint documentation is not uniform.

The host admits write targets using current list metadata and permissions;
flagged-email/read-only lists must not enter the writable outbox. The initial
adapter's mutation methods take IDs and do not enforce that admission policy.
Completion changes inspect recurrence, but that preflight is not atomic and
does not remove the unconditional read/write race.

Before acknowledging writes, define provider normalization rules: a civil date
sent to Graph returns as a wall-time/zone pair, and plain notes may return as
HTML. Advance the synchronized base to the observed server representation while
preserving later local revisions. Test this explicitly to prevent endless dirty
states, false conflicts or loss of edits made while the write was in flight.

A desktop client can pull on activation and periodically while running. A
future server may use renewable task subscriptions as hints to pull deltas;
webhooks do not replace reconciliation or durable state.

## CalDAV and mailbox.org/OX adapter

Discover current principal, calendar home and VTODO-capable collections. Accept
an exact collection URL for servers/accounts where discovery is limited. Keep
URLs opaque and bind allowed credential origins explicitly. Redirects must not
forward credentials to an unapproved host.

Use VTODO-filtered calendar queries, collection sync tokens when advertised,
and ETag comparison as the fallback. Honor per-resource response statuses in
DAV multistatus bodies. Invalid sync tokens require a fresh baseline, not
discarding local data. Bound XML, nesting, text and resource sizes; reject DTDs
and external entity processing.

The iCalendar codec must handle folded lines, escaped text, named-zone dates,
all-day dates, unknown properties and nested components. Update only the
requested fields, preserving UID and original unedited content. Refuse writes
whose semantics cannot be preserved, including unsupported recurrence instances
or delegation. Collection creation, sharing and scheduling are independent
capabilities.

mailbox.org preset:

- Discovery root: `https://dav.mailbox.org/`.
- Username: the main mailbox email address.
- Credential: a dedicated Calendar/address-book (CalDAV/CardDAV) app password.
- Exact-list fallback: the task-list Properties URL, whose suffix is opaque.
- Conservative initial features: personal basic tasks; recurrence, participants,
  shared/public task lists, relations and attachments need explicit live checks.

OX's older/deprecated CalDAV limitation document is evidence for conservative
defaults, not proof that every current deployment has identical limitations.
Unknown-field preservation in CrispOffice cannot prevent server-side loss.

## Native OX, EWS and later backends

Native OX uses the HTTP Tasks and Folders modules, typically beneath `/ajax`.
Confirm the host API base, deployment version and external-client authentication
policy before enabling it. Native OAuth scopes are `read_tasks`/`write_tasks`
where supported; a DAV app password must not be assumed valid for this API.
Incremental OX task updates must include deletions (`ignore=false`) and retain
server timestamps for concurrency. Preserve task ACL/participant semantics.

On-premises EWS Tasks uses task folders/items and appropriate properties on the
existing native Exchange connection boundary. It is a separate provider from
cloud To Do and from Mail; include ChangeKey/concurrent-update and move tests.

Vikunja uses its v2 REST API for new work. Planner is another Graph model. Each
provider needs its own mapping, capability tests and live qualification before
appearing as a supported production connection.

## Studio and credential integration

Native Tasks UI must expose local tasks, account/list selection, completion,
dates, notes, important/today/upcoming views, search, pending status and conflicts.
Do not label a local Today view as synchronized Microsoft My Day membership.

Reuse system-browser sign-in where appropriate and store long-lived credentials
in the platform vault, separately from the task database. Handle reconnect,
revocation and Forget-account behavior explicitly. Background scheduling and
notifications must be user-configurable; opening a workspace is not permission
to create shared tasks, email participants or mirror lists across providers.

Native desktop is the first host. Browser/mobile support needs its own OAuth,
CORS, storage and background-execution design; portable Dart compilation alone
does not establish these integrations.

## Validation and release gates

Use the pinned Flutter 3.47.8 / compatible bundled Dart runtime. Preserve
existing package versions and dependency locks except deliberate workspace
changes. Each increment gets formatting, analysis, deterministic behavior tests
and a package changelog. Compile portable public imports to JavaScript.

Test protocol parsing and failure behavior with fixtures, then persistence with
crash/restart and concurrent-edit scenarios, then host integration. Include
malicious continuation URLs, truncated responses, resource bounds, duplicate
pages, unknown status values, null clears, DST dates, HTML notes and lost write
responses. Record actual commands/outcomes and honest remaining limits.

Live qualification uses designated disposable lists and supplied test accounts.
Do not create, change, or delete a user's existing tasks just to run tests.
Documentation must distinguish compile/fixture checks from actual cloud/server
interoperability and installed-platform acceptance.

Microsoft acceptance additionally covers complete/reopen recurrence guards,
unsupported-enum recovery without checkpoint advancement, civil-date and HTML
normalization, moves between selected/unselected lists, list deletion, and loss
of shared-list access. Keep `conditionalWrites` disabled until stale-ETag tests
establish the actual service contract.
