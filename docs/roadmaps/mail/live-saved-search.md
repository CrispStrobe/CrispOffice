# Refreshable saved-mail search

This increment extends [saved searches](saved-searches.md) with a replacement
scan and optional foreground updates. It advances the discovery workflow in
the [ordered mail parity plan](README.md#desktop-mail-parity-ordered-increments).

## User workflow

Open **Search saved mail** from the native saved-account chooser and run a
query or reopen a saved definition. **Refresh results** checks the same account
scope against the currently retained headers. Results are replaced together,
so a changing account cannot leave a mixture of old and new matches on screen.
The controls remain available while reading a selected message.

Once a search has checked its local scope without errors, **Refresh every
30 seconds** enables automatic updates for this open dialog. This is a fresh
opt-in each time the dialog opens; saved definitions do not acquire background
execution permission. The next interval starts after the previous operation
finishes. It cannot create overlapping scans or a burst of missed updates.

An opened reader stays on the same retained message if its account identity,
message key and remote identity still occur in the replacement results. Refresh
does not reload that body. If the result disappears, the reader closes with an
explanation and returns to the updated list. Opening another result remains an
explicit local body read.

## Scope, bounds and recovery

- Automatic updates run only while the app is active and the dialog is open.
  App suspension fences the current replacement and cancels the timer. Resume
  waits a new full interval. Closing drains pending reads and releases owners.
- Query edits, scope edits and account-context changes synchronously revoke
  pending publication and turn off automatic updates. A saved search keeps its
  original explicit account IDs; newly added accounts do not silently join it.
  An unsaved search also retains the account list from its current opening;
  reload the directory or reopen the dialog to include newly remembered accounts.
- Refresh scans at most 100 sequential pages, each inspecting at most 500
  candidates and returning at most 100 hits, with a 1,000-result ceiling. Empty
  matching pages still consume the scan budget. **Search more** continues a
  partial scan where possible; refine the query at the result ceiling.
- Incomplete scans or account failures turn automatic updates off. Coverage
  retains the failed account and the already checked scope. An account that
  fails on a later page contributes no earlier staged hits. Healthy accounts
  can still contribute results. A read/close error retains an explicit retry
  path instead of retrying repeatedly without user action.
- A completed search holds no account store between reads. An unfinished
  manual scan is drained before refreshing, preserving exclusive repository
  ownership. A cancelled replacement cannot replace the previous completed
  result set. Host revocation prevents late message or result publication.

The query covers cached headers and their saved browse/synchronization folder
memberships. It does not contact IMAP, EWS, Gmail or Graph, request credentials,
download mail, search bodies/attachments, run server rules or change messages.
Header completeness is local and does not establish server completeness.
Another active owner of an account can make that account temporarily
unavailable; the UI reports that coverage failure rather than stealing its
lease. English, German and Arabic controls retain this distinction.

## Implementation and acceptance

`StudioMailCachedSearchRefreshBatch` is an immutable staged result set. The
collector reuses the existing scoped search session and enforces positive,
bounded budgets. Generation checks surround each page and precede publication;
the caller retains lifecycle and close/drain ownership. The dialog performs
the atomic result replacement and owns the foreground timer independently of
durable query-definition revisions.

The [work record](../../validation/mail-live-search-20261121/README.md) separates
source checkpoints from actual local execution and records incoming-history
preservation. GitHub Actions queue time is not an acceptance dependency.

This is a bounded foreground refresh workflow. A repository-event-driven
shared workspace, continuously synchronized unified inbox, arbitrary folder-set
selection, persistent cross-folder conversations, indexed body/server search,
categories and recoverable ordered rules remain subsequent increments.

The comparison remains capability-based: Microsoft's [edition matrix](https://support.microsoft.com/en-us/outlook/getstarted/feature-comparison-between-new-outlook-and-classic-outlook)
distinguishes classic and new Outlook; Thunderbird's [synchronization guide](https://support.mozilla.org/en-US/kb/imap-synchronization)
distinguishes headers from downloaded bodies; [eM Client's email features](https://www.emclient.com/features-email)
include broader organization and composition workflows. Checked 21 November
2026. These sources guide the roadmap, not a claim of complete product parity.
