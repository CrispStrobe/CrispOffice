# Mail account navigation semantic merge

Source worktree: `/workspace/scratch/7c69340222d3/concurrent-office-intake`.
Incoming heads: `d53f30f1874b38d36a791d1d3881583e4e42a2d6`
and `08c487722f5c931fca831c0cd133a2f6a5e533b9`.

The two branches change the same ownership boundaries. The combined code keeps
the newer explicit recovery policy for visible account changes and incorporates
the guarded asynchronous sign-in and atomic remembered-account refresh.

## Native IMAP

- Preserve `_navigationOwnerPending`: Disconnect and refresh cannot retire a
  selected account while its draft-owner factory or load is unresolved.
- Preserve observer handles when visible switching fails. The navigation path
  uses `_stopCachedViewForNavigation`; it does not clear cancellation handles
  before the cancellation succeeds.
- A retained owner drains observer cancellation, outstanding transport replies,
  durable flag receipts, and preceding close work before attempting owner close.
  Its explicit release button remains available on failure; Connect and further
  routing remain blocked while the owner is retained.
- Serialize draft restoration with `_draftRestoreInFlight`, completed in a
  `finally` block. Another Connect or provider setup waits for late acquisition
  and release, then rechecks retained owners before proceeding.
- Validate the target and host dependencies after asynchronous sign-in stages,
  draft factory/load, cache setup, and atomic catalog refresh. Fulfill the selected
  intent only after its guarded refresh succeeds, avoiding rejection of our own
  revision advance on later reconnect.
- Distinguish adopted owners from unadopted candidates. An adopted candidate may
  already own observers and pending receipts, so stale admission uses the held
  owner drain. A candidate already detached by another path is not closed twice.
  Failed selected candidates occupy the explicit retry owner, never both retry
  structures.

## EWS and cloud providers

- Preserve `_retiredDraftStore` and `_releaseRetiredAccount`, with failed observer
  handles retained until successful cancellation and durable receipts drained
  before owner close.
- Preserve disabled Connect/routing while an owner is held; the user explicitly
  retries Close. No failed destination is implicitly dispatched after recovery.
- Add guarded target/host checks, restoration serialization, late-owner release,
  and expected-record `rememberConnection` behavior. Track adoption to avoid a
  second close after host replacement already detached and queued the owner.
- A removed destination after successful source-owner release reports changed
  account. An owner release failure retains the storage failure and recovery UI.

## Reconciled test policies without removing probes

| Incoming older expectation | Retained behavior and equivalent coverage |
| --- | --- |
| A selected-target owner factory can be cancelled with Disconnect, then a second destination waits for its late owner. | The existing dedicated native release test continues asserting Disconnect is disabled through selected factory and load. The two late-owner drain probes now use an ordinary unselected connection, assert Disconnect is enabled there, and still require the old owner to close before a second connection or provider setup; the old candidate must never load. |
| A failed visible native owner close keeps the live source connection and a repeated account selection retries close. | The source transport is retired, its exact owner stays held, Connect is disabled, and the explicit release button is retried once unsuccessfully and once successfully. Only a fresh subsequent selection may navigate. |
| A failed provider owner close leaves Connect/Switch enabled to retry and automatically continue the destination. | Connect stays disabled and the failed destination is not dispatched. Explicit Close is retried once unsuccessfully and once successfully; the provider dialog remains until release succeeds. The pre-existing switch/close failure cases retain submission-uncertainty assertions. |

All other removed/revised-target, late authorization/headers/cache/owner,
host-replacement, atomic CAS, identity, refusal, and reconnect tests are retained.

The subsequent Zotero merge also carried Mail fixture repairs. Its reconnect
test now uses a catalog-capable owner and verifies separate owner acquisitions
and first-owner close, preserving the persistent-store revision semantics.
The raw-endpoint fixture repair is retained: it does not canonicalize a zero or
noncanonical port before validation. Two auto-merged assertions that considered
missing IMAP ports valid conflicted with both the native explicit-port contract
and the same suite's missing-port rejection. They now assert rejection for both
hostname and IPv6 endpoints without a port. Explicit IPv6, leading-zero ports,
zero ports, and noncanonical HTTPS default-port cases remain covered.

## Pre-acceptance checks

The six resolved Dart files have no conflict markers; the pinned Dart formatter
parsed them and `git diff --check` passed. These are merge hygiene checks, not a
runtime acceptance claim. Full local navigation acceptance follows the completed
Zotero merge, using Flutter 3.47.8 and the untouched exact dependency lockfile.

The isolated worktree resolved its own package configuration with
`dart pub get --offline --enforce-lockfile` under the pinned Flutter environment.
All 23 tracked pubspec/lock manifests had identical hashes before and afterward.
No dependency version changed, and the package configuration is rooted at this
isolated worktree rather than the main checkout running the broad engine gate.
