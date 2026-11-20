# Cached mailbox workspace — implementation and local qualification

**Date:** 20 November 2026 (Europe/Berlin). **Status:** implementation in progress;
this initial record does not claim final acceptance. GitHub Actions, workflow
runs and status checks are neither queried nor awaited.

## Intent and acceptance boundary

Connect the existing durable Mail repository to native foreground browsing for
IMAP, EWS, Gmail and Microsoft 365. Retain the latest successfully saved ordered
header window for each visited folder and the exact bodies/attachments opened
explicitly by the user. Reopen those views from the verified-account chooser
without credentials or a provider connection.

The cached view is dated and bounded to the existing 1,000-header foreground
window. It is not authoritative synchronization or proof of current server
state. Browse continuations never replace synchronization cursors. Unified
inbox, durable remote action UI, background synchronization, provider Drafts,
installed-platform and live-provider qualification remain subsequent work.

## Initial reconciliation

Restored main at `bb5320a50f288d95844a6d60cfd72eab13a9befc`. The intake covers
22 live fork heads, 40 recent PR heads and eight upstream references (four
branches and four PR heads). All prior heads are ancestors or independently
rechecked historical equivalents. The only new implementation is draft PR
#261, Word outline/list-level editing at
`3c87debcd4d50cac88981ec39255c3c6890fe8fa`.

The working branch fast-forwarded to that head before mail implementation;
its source and tests are complete enough for independent local qualification.
Its author's in-progress validation remains explicitly separate from the fresh
Word/compiler/style/native-preservation checks performed in this continuation.

Incremental remote branch: `work/mail-cached-workspace-20261120`. Publication
uses expected-head, non-forced branch updates and verifies Git tree identity.
The final acceptance and publication records will be added after actual checks.

## Retained first qualification checkpoint

The first complete store gate passed 686 native store cases, 67 core cases on
the VM and 67 on Node, 46 portable store cases on Node, strict analysis/format,
48 evidence-runner controls, and browser entry/worker compilation. The first
shared cohort passed 96 Mail UI cases and 486 MIME/transport cases. Focused
native account-bridge and offline UI/chooser checks also passed. These are
recorded baseline runs, not final acceptance of subsequent review corrections.

Independent review then demonstrated two concrete issues: automatic cached
content can consume shared quota and block a later draft save without a local
recovery action; cached-body JSON needs a type/size preflight before transfer
and decode. The probe, original runs and review findings are preserved. Bounded
explicit cache cleanup and metadata preflight are being added and will receive
fresh qualification before merge. Host review also tightened account-owner and
fetched-message identity checks and separated view/body persistence warnings.

The current [evidence archive](evidence.tar.xz) is an incremental checkpoint of
raw runs, failures, runtime receipts, source manifests and independent Word
qualification. [evidence-files.json](evidence-files.json) records the size and
SHA-256 of every verified member. Final publication will replace it with the
complete indexed archive while Git history retains this earlier checkpoint.
