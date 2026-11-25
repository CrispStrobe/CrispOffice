# CrispOffice Tasks and synchronization roadmap

Approved scope: **25 November 2026**. Delivery is incremental on the repository's
`main` branch. This roadmap covers Microsoft To Do, standards-based CalDAV,
Nextcloud, ownCloud, mailbox.org/Open-Xchange, on-premises Exchange tasks, and
the additional dedicated task backends described below.

## Product goal

Add a Tasks workspace alongside Mail, with local task use, reliable offline
editing, and multiple connected accounts. A task retains its owning account and
list. A unified view must not silently copy work tasks into a personal service.
Explicit list-to-list bridging is a later feature with its own conflict and
deletion policy.

The first end-to-end acceptance scenario is: create a task in CrispOffice, see
it in Microsoft To Do, complete it there, observe completion in CrispOffice,
edit another task offline, and reconnect without lost changes or duplicates.
Repeat the same scenario against Nextcloud and mailbox.org before calling
those deployments qualified.

**A documented API, a fixture-tested adapter, and a live-qualified account are
different statuses.** See [progress](progress.md),
[implementation plan](implementation-plan.md), and
[provider evidence and qualification](provider-qualification.md).

## Current delivery

Implementation status on 25 November 2026

| Milestone | Delivered status |
| --- | --- |
| T0 | Roadmap and provider evidence saved to remote main. |
| T1 | Portable model, sparse patches and pure reconciliation implemented and tested. |
| T2 | Graph adapter and explicit task-consent configuration implemented and tested; host consent UI and live qualification remain. |
| T3 | CalDAV discovery, conditional writes, sync tokens and ETag fallback implemented and exercised with local fixtures. Live qualification is T6. |
| T4 | SQLite inbound store and resumable pull worker implemented. Editable local state, outbox and push recovery remain. |
| T5-T9 | Planned. |

The first series passed **132 targeted tests** across mail consent, task
core, Graph and the CalDAV codec. The
[progress record](progress.md) tracks the later CalDAV provider and SQLite store
checks. Live Microsoft, Nextcloud, ownCloud and mailbox.org qualification
remains a separate milestone.

## Backend choices

| Backend | Planned connection | Scope and qualification boundary |
| --- | --- | --- |
| Microsoft To Do / Microsoft 365 / Outlook.com | Microsoft Graph v1.0, delegated `Tasks.ReadWrite` | Personal and eligible work/school accounts; list/task deltas and basic task writes first. |
| Nextcloud Tasks | Generic CalDAV with iCalendar VTODO | First reference server for the standards-based provider; optional Login Flow v2 onboarding. |
| mailbox.org / Open-Xchange | CalDAV preset, `https://dav.mailbox.org/` | Personal task lists first; dedicated DAV app password; advanced capabilities require deployed-server evidence. |
| ownCloud Classic / Infinite Scale | Generic CalDAV when VTODO is advertised | Validate the exact edition, installed groupware, and version. Infinite Scale groupware was explicitly work in progress in November 2026. |
| Radicale / Baikal | Generic CalDAV | Smaller self-hosted interoperability targets; test rather than assuming protocol identity guarantees behavior. |
| Exchange Server on premises | Separate EWS Tasks provider | Reuse suitable native EWS infrastructure; task folders and properties are separate from Mail. |
| Native Open-Xchange HTTP API | Optional deployment-specific JSON adapter | For hosts that support external API authentication; mailbox.org native API availability is not established by generic OX documentation. |
| Vikunja | Dedicated REST v2 adapter | Richer task backend; implement against its public API after the common model and synchronization boundaries stabilize. |
| Microsoft Planner | Separate Graph Planner adapter | Assigned team work is distinct from the To Do resource model. |

Graph is the Microsoft cloud path. Exchange Online began EWS disablement in
October 2026 and schedules final shutdown for 1 April 2027. That retirement
does not remove the on-premises Exchange requirement.

## Existing foundations

- Pure Dart engine and Flutter Studio host remain separate. Task protocol and
  reconciliation code must not import Flutter or `dart:ui`.
- Microsoft mail already has desktop browser OAuth, S256 PKCE, token refresh,
  and a host token-source boundary. Task authorization must be an explicit
  opt-in; default mail permissions must not silently expand.
- Built-in cloud credentials are currently session-only. Persistent Tasks
  sign-in requires a host-owned OS credential store and lifecycle integration.
- Existing mail storage/coordinator patterns are useful references. Tasks get
  their own models, local IDs, pending operations, and provider bindings.
- Package public boundaries are respected: no cross-package `lib/src` imports.

## Delivery milestones

Statuses here describe the plan; actual completed checks and commits belong in
[progress.md](progress.md).

| ID | Deliverable | Acceptance gate | Dependencies |
| --- | --- | --- | --- |
| T0 | Roadmap, evidence, provider scope, recovery rules | Sources linked; unverified capabilities explicit; plan saved to remote main | None |
| T1 | Portable task core and reconciliation | Typed immutable models; civil/timed dates; explicit patches; disjoint merge, conflict, delete and identity-isolation tests | T0 |
| T2 | Graph provider and opt-in Microsoft task consent | Bounded list/task reads and deltas; real basic CRUD; strict cursor/account validation; no automatic ambiguous write replay | T1 |
| T3 | CalDAV codec, profiles, and provider | VTODO-only discovery; raw-preserving bounded parsing; ETags and conditional writes; sync-token/ETag recovery; Nextcloud and mailbox presets | T1 |
| T4 | Durable task store and synchronization worker | Transactional changes/cursors; persisted outbox; crash/restart recovery; local revision acknowledgments; disconnect generations | T1-T3 |
| T5 | Native Studio Tasks workspace and account setup | Local use, selected-list sync, editing/completion, search/views, conflict/retry states, secure credential persistence | T4 |
| T6 | Live Microsoft/Nextcloud/mailbox qualification | End-to-end scenarios on disposable lists; task dates, permissions, conflicts and revocation; explicit deployment evidence | T5 and test accounts |
| T7 | Extended task fidelity and other DAV servers | Reminders, steps/subtasks, recurrence, categories, attachments, shared lists enabled only with round-trip coverage | T6 |
| T8 | EWS Tasks and additional native providers | On-premises Exchange tasks; host-supported native OX; Vikunja; Planner, each independently qualified | T4 and applicable test hosts |
| T9 | Optional bridge and continuously running sync | Explicit list pairs, loop prevention, source attribution, independent deletion policy; renewable webhooks where useful | T6-T8 |

T1-T3 may develop in parallel once their public contracts are agreed. A package
can land as a complete bounded library before the desktop feature exists.
T4-T6 must not be marked done merely because protocol fixtures pass.

## Task coverage

Minimum initial product coverage is title, notes, due date, importance/priority
and completion. Preserve other remote fields on unrelated edits. The Graph
adapter already maps start dates and reminders; their UI and live round-trip
qualification remain ahead. Subsequent work adds categories, recurrence, steps,
genuine subtasks, attachments and links back to CrispOffice documents or mail.

The normalized model must distinguish:

- A local task ID from an account/list-scoped remote ID.
- Civil all-day dates from wall-clock times with explicit zones and UTC instants.
- A missing patch field from a deliberate null/clear.
- To Do checklist steps from independent nested tasks.
- A remote tombstone from an item absent from one partial page.
- A server-acknowledged write from a request with an unknown outcome.
- A provider feature supported by protocol from a feature enabled in this app.

Microsoft My Day membership and a complete To Do UI replica are not implied by
basic API support. Planner data has a separate provider. For OX, locally
preserving unknown properties cannot prevent the server from dropping them;
refetch after writes and report substantive normalization or loss.

## Incremental save policy

1. Commit and push the plan before implementation commits.
2. Keep each code checkpoint buildable and honestly scoped; no placeholder
   success or TODO method bodies.
3. Run focused formatting, analysis and behavior checks for changed packages.
4. Stage only the completed increment, including its package changelog and
   progress entry. Preserve unrelated concurrent work.
5. Fetch before pushing and integrate a moved remote head without force-pushing
   or discarding another contributor's changes.
6. Push each completed increment to remote `main` and record the resulting SHA.
7. Save any blocked validation and precise next step in this roadmap so work
   can continue from GitHub even if the local workspace disappears.

No passwords, tokens, personal tasks, SDK archives, package caches or live test
data belong in commits. Use independent MIT-compatible implementation code;
interoperating with a server does not require importing its implementation.
