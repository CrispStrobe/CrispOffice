# Foreground bulk actions — compatibility entry

The executable contract for connected IMAP, EWS, Gmail and Microsoft 365 bulk
read/unread/flag/unflag actions is [bulk-flags.md](bulk-flags.md). It defines the
user path, loaded-visible selection, stop-after-current behavior, all four
outcomes, scope guards, nullable flags and the foreground/cache boundary.

This path is retained from the concurrent `work/mail-bulk-actions-20261120`
implementation. The integration consolidates that work with
`work/mail-bulk-flags-20261120`; it does not maintain two dispatch algorithms or
two sets of acceptance rules. The peer's `MailBulkFlagCoordinator`, certified
attempts, provider validation, `operationAt` and receipt accessors remain
available alongside `MailBulkFlagRunner`, using one private execution engine.
See the [portable API](bulk-flags.md#portable-execution-api) and the
[technical reconciliation record](../../validation/mail-bulk-flags-20261120/reconciliation.md)
for exact compatibility choices and preserved tests.

The original statement that every invoked provider failure must be uncertain
is superseded by explicit `MailProblem.mutationMayHaveOccurred` evidence.
For provider replies, `false` certifies no effect; `true` or absent evidence
remain uncertain. A coordinator's explicit failed attempt is also a certificate,
but contradictory possible-mutation evidence remains uncertain. Error codes
alone never establish non-mutation.

The [combined acceptance record](../../validation/mail-bulk-flags-20261120/README.md)
owns source-bound qualification and publication results. Earlier
[peer intake records](../../validation/mail-bulk-actions-20261120/intake-local.md)
remain historical evidence of their captured source, not qualification of the
combined runtime.

The [ordered continuation](bulk-flags.md#validation-and-continuation) retains
durable repository-driven sessions and a remote-command journal first, then
account-wide/unified discovery and conversations, broader commands and rules,
authoring/Office workflows and provider-specific productivity features.
Current receipts are in memory; they do not establish restart recovery, offline
replay or synchronized persistent-cache updates after each foreground change.
