# Provider mutation evidence and throttling review

Reviewed 20 November 2026 against the integrated provider source and its existing
send/flag regression contracts. This is a source-review decision record;
execution results are reported separately in the validation README and receipts.

## Decision

A typed provider receipt distinguishes definite rejection from an operation
that might have reached the server. A problem code alone is insufficient. IMAP
marks the mutation boundary before its STORE/MOVE command; EWS before writing
the update request; cloud transport distinguishes failures before delivery from
failures after delivery may have begun. Missing evidence stays uncertain.

The initial conservative cloud draft excluded HTTP 429 from definite rejection.
The full transport cohort exposed that this also changed existing send behavior.
Primary provider documentation supports preserving the existing throttle
classification: Graph describes 429 requests as failed and gives Retry-After
recovery guidance; Gmail describes quota/concurrency rejection and delayed
acceptance until limits allow a later request. We therefore retain 429 as a
certified no-write quota failure, with its retry delay, in these provider
adapters. This is a provider-specific inference from the documented contracts,
not a universal assertion about every service using HTTP 429.

A foreground bulk run stops after a certified quota rejection and reports the
remaining identities as unattempted. It does not retry automatically. The
existing send outcome remains retryable. A documented missing-resource 410
response remains a definite rejection. Timeouts, server failures and unfamiliar
response statuses retain uncertainty, and no repeated write follows them.

## Primary sources

- [Microsoft Graph throttling guidance](https://learn.microsoft.com/en-us/graph/throttling)
- [Microsoft Graph error responses](https://learn.microsoft.com/en-us/graph/errors)
- [Gmail API error handling](https://developers.google.com/workspace/gmail/api/guides/handle-errors)

The initial manual review and failed transport run remain in the evidence
archive as diagnostics. Final acceptance must use the later source-bound core,
transport and host receipts after this correction.
