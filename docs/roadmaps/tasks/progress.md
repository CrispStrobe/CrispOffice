# Tasks implementation progress

Started 2026-11-25 from remote main
`c9362e533cc62d5616fee207e196bc3c15d4c8d5`.

## Checkpoint 0 — plan

- Added the approved multi-provider [roadmap](README.md),
  [engineering plan](implementation-plan.md), and
  [provider qualification record](provider-qualification.md).
- Included Microsoft To Do, Nextcloud, ownCloud, mailbox.org/OX CalDAV,
  lightweight DAV servers, on-premises EWS, native OX, Vikunja and Planner.
- Documented account isolation, offline recovery, uncertain writes, field
  preservation, credential persistence, and the difference between fixtures and
  live qualification.
- Reviewed repository contribution rules and current public mail auth boundary.

Implementation starts with portable reconciliation, a Graph provider, a CalDAV
codec/profile foundation, and opt-in Microsoft task consent. Desktop Tasks UI,
durable task synchronization and live account qualification remain outstanding.

No user task service has been connected or modified for this planning checkpoint.

Remote plan commit: `77be5cf8c37b2fbc83bf5cc2a3fed716b1109eff`.

## Checkpoint 1 — explicit Microsoft task consent

- Added `MailOAuthConfiguration.includeTasks`, defaulting to false. Opted-in
  Microsoft authorization and refresh request `Tasks.ReadWrite`; Gmail rejects
  the option. Existing mail-only scopes are unchanged.
- Verified that an explicit token grant missing task permission is rejected and
  a downgraded refresh clears the unusable credentials.
- Updated the mail provider setup notes and package changelog. The current Mail
  dialog does not enable this flag automatically; Tasks UI integration remains
  a later milestone.
- Validation: formatter clean; targeted analyzer clean; **37 OAuth and real
  loopback fixture tests passed**. No real Microsoft login or task was used.
- Runtime and commands are recorded in
  [the validation record](../../validation/tasks-20261125/README.md).

## Validation and remote checkpoints

Each following entry records the completed scope, actual checks, remaining
limits and remote commit. A checkpoint is not a claim that the entire roadmap
is finished.
