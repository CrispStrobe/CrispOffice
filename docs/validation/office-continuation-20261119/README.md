# Office continuation — 19 November 2026

## Reconciliation and current state

This continuation resumes the interrupted Mail/Office integration from the
user-supplied transcript. The user requested incremental remote checkpoints,
reconciliation of incoming commits, branches and pull requests, local validation
without querying or waiting for GitHub Actions, and completion on remote main.

The initial captured main was `b070e228a749e22cc8ce2098029a76ab5fb8eccb`.
PR #183 was already merged; its original branch still ended at
`f2b0769cf5533fd4e7ee335adab532c98c677857`. The post-F2 failure archive described
in the transcript was not published on that branch and is not claimed as
recovered evidence here.

Two later remote heads contained unique fixes and complete, separately
attributed qualification records:

| Incoming head | Retained record |
| --- | --- |
| `1b6d280b6ed41a1e01736a88f6d02431057c8611` | [Office synchronization](../office-main-sync-20261119/README.md), including its 1,026-execution fourth delta at `5c18db77` |
| `c63558c0b3bc713361771cc29b0d89ecf2fa09a7` | [Host integration](../office-main-integration-20261119/host-final/README.md), including its 1,285-execution checkpoint at `9833831a` |

Those counts remain historical executions on their recorded source. They are
not added to the fresh continuation result. Main's newer Arabic morphology/T2
rules and session-only IMAP/SMTP example remain present.

The initial capture contains 436 actual origin refs (229 branches, 190 pull
heads and 17 tags); HEAD and four peeled-tag advertisements are aliases. At
captured main, 406 refs were ancestors and 28 were covered by 14 independently
reverified historical equivalence proofs. The two heads above were the only
remaining gaps. Four upstream refs retained from the earlier capture were also
ancestors. The final receipt reruns this audit against the integrated commit.

The first reconciliation checkpoint is saved remotely at
`10bd0cc4aa720acda4f52d0da882c57b05446435`, with tree
`7679eef3ed733e1409d5be5061a5e25241e700de`. Publication used existing remote
objects plus hash-verified new blobs, a non-forced expected-head update and
fetched tree readback. The recovered histories and subsequent development
state are additionally saved at `e80beb2ed2fe70397a5a8fff5c9e908b04862f78`
(tree `09f094eaff1988fe436c0beeca016b94e714365b`); that checkpoint is explicitly
unqualified. The reviewed Mail ownership and Word boundary fixes are saved at
`4ed8154a41bef8688b3ce2e89e96e52f9a49120d`. The
[incremental publication map](incoming/publication-map.json) records identical
local/published trees; local author commit objects are retained in the accompanying
bundle. [PR #193](https://github.com/CrispStrobe/quds_office_suite/pull/193)
is the continuation merge vehicle.

## Merge decisions

- Keep main's Arabic morphology imports, long-lived analyzer wiring, T2 rules
  and live Mail workspace while adding the two continuation histories.
- Retain explicit checking, scheduled, paused, partial and completed review
  states in the compact footer. Narrow layouts retain status text in the
  tooltip and keep the proofing action usable.
- Apply Word language edits to the selected fragment's active language slot,
  preserving its inactive Latin/complex-script language and unrelated native
  metadata. Existing engine callers can still explicitly clear both slots.
  Inheritance, Unicode letter classification, undo/redo and DOCX round trips
  remain covered by both incoming test families.
- Keep selected Latin/complex-script boundaries when applying an already
  stored language or resetting an inherited slot. Run coalescing respects those
  routing boundaries, including after formatting, undo/redo and DOCX save.
- Preserve combining hamza and maddah in extended Arabic phrase comparison,
  matching the existing ordinary comparison behavior and exact UTF-16 offsets.
- Retain the current abortable dictionary downloads, post-progress cancellation
  guard and both independently authored installer control suites.
- Restore the saved `.eml` reader as a separate component accessible from the
  current account-aware example. Keep the delayed picker/read, replacement,
  localized error and disposal regressions.
- Own live Mail clients throughout setup and abort detached sessions promptly.
  Delayed discovery, folder/body reads, drafts and sends are checked against
  their original session before updating the UI or submitting a message.
- Preserve source-specific failed attempts, historical raw evidence and runtime
  preparation records without relabeling them as current passes.

## Late bounded continuation heads

Before freezing, PRs #191 and #192 appeared while main remained `b070e228`.
Their fixed observed heads, `3119a4598e61f061e7b7633ea4a352d841332b9e` and
`409258f91484039d771d1fe56f097bef6f2d27ea`, are retained as incoming parents.
This later observation remains separate from the initial 436-ref capture.

The union retains the incoming full-Unicode boundaries for Arabic phrase,
double-future, date and year rules; their mixed-script/identifier controls
reproduced nine failures before the fix. It also adds the immediate dictionary
progress-callback cancellation guard and success/removal control, the accurate
live-inbox empty-reader prompt, and distinct additional live Mail behaviors.
The current stronger session ownership, selected-language boundary and compact
footer fixes remain intact. Duplicate stale saved-reader tests are represented
by the adapted reader/workspace suites; their original files remain in the
incoming commit histories. Current AyaSpell implementation and wording remain
unchanged. The [path and coverage audit](incoming/late-pr191-pr192-coverage.json)
records every decision. Source-specific red and green logs are retained in the
[late development archive](development/late-concurrent-evidence.index.json);
the 311 Arabic and 31 live Mail passes remain development evidence.

## Fresh local qualification

**In progress.** Focused development checks precede the frozen-source run and
are recorded separately. The accepted result must bind the committed source,
exact test selections and verified runtime before and after execution. No
historical test executions are used as fresh results. The frozen selections are
142 native suite files and 23 Node suite files, plus the independent core/store
launcher; all 30 ordinary Studio suites are included. Analysis and formatting
cover every changed Dart input and the relevant current-main morphology inputs.

The pinned runtime is Flutter 3.47.8 / Dart 3.13.7 with enforced offline
dependency resolution. Native inputs include freshly built Linux Hunspell,
three ownership fixtures, hash-verified AyaSpell files, Poppler, freshly built
Arabic morphology and the four-file pinned `noprob` bundle. The preparation
archive records their hashes and rebuild instructions; preparing a runtime is
not product-test acceptance.

## Scope boundaries

Controlled protocol tests, local Linux native tests and browser compilation do
not establish live-provider acceptance, OAuth/PKCE or token-refresh hosts,
platform credential-vault integration, other operating systems, installed
desktop/device packaging or actual browser persistence. The session-only
IMAP/SMTP example does not complete the durable repository-driven mailbox or
queued/reconciled submission roadmap. Large-mailbox discovery remains bounded
by simple SEARCH count and byte budgets; ESEARCH/PARTIAL remains separate.

GitHub Actions are not queried, dispatched, awaited or used as acceptance.
