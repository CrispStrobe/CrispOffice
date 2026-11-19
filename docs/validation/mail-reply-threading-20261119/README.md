# Studio mail reply threading — 2026-11-19

## Continuation checkpoint

Status: implementation in progress. This is not a fresh Dart/Flutter acceptance
report. The current session has GitHub connector access but no executor,
terminal, Dart SDK or Flutter runtime. GitHub Actions are neither awaited nor
used as an acceptance gate.

The requested work resumes draft #216 at
`2638a2c96ea5e66ace5884896fe09de92a7ce380` after the durable archive restore-resume
milestone. A fresh remote audit found all fourteen external branch heads
unchanged, plus this task branch, and only open drafts #210, #211 and #216.
Main remains `5715d56053e93dc11e8b5165bd13f8db2a1f3917`.
Both draft continuation histories are already parents of #216's reconciliation
commit. Existing newer production implementations and historical evidence are
preserved. Historical equivalence proofs and test counts are not rerun or
claimed as fresh acceptance here.

## Selected increment

Carry safe reply-thread metadata from authoritative decoded mail through the
Studio draft, composer editing/retry and MIME construction. Existing replies
quote text but omit `In-Reply-To` and `References`. Forwards remain independent
messages. The implementation will bound untrusted identifiers and reference
chains, reject header injection, and keep existing plain-text quoting,
recipient validation and uncertain-send acknowledgement behavior.

Primary production scope: `studio_mail_reply.dart`,
`studio_mail_compose.dart`, `studio_mail_submission.dart` and a small typed
thread-metadata helper in the same Studio library. No archive schema,
dependency or provider API changes are planned. Focused adjacent regression
tests and current behavior documentation will accompany the code.

## Preservation and qualification

All checkpoint commits are fast-forward additions to
`work/mail-next-20261119`, with an expected previous head and no force updates.
Before final publication the remote inventory and source tree will be checked
again. Source review and any JavaScript reference-model checks will be reported
as such, separate from unexecuted Dart/Flutter tests and earlier author evidence.

The final merge disposition and remaining runtime qualification will be recorded
explicitly; this initial checkpoint does not claim either is complete.

## Implementation checkpoint

The immutable thread helper, reply builder, composer snapshot and shared MIME
submission builder are now implemented. Supported parent IDs are exact ASCII
angle-bracketed dot-atoms, at most 254 characters. A missing or unsupported
parent leaves the draft unthreaded. References are deduplicated exactly and
bounded to 900 ASCII value bytes, keeping the first valid ancestor and newest
contiguous tail before the current parent. More than 1,024 source reference
entries fall back to the valid parent alone. Forward drafts remain unthreaded.

Focused regression authoring and independent source review are in progress.
Fresh Dart/Flutter tests, analyzer and formatter have not run.

## Independent review correction

The source review found that dropping malformed References tokens individually
could retain an apparent ID from inside a whitespace-split comment. The helper
now discards the complete inherited chain on any unsupported token, retaining
only the validated immediate parent and never activating In-Reply-To fallback
for a nonempty References list. Absent and empty normalized lists remain
indistinguishable and are documented explicitly. Regression fixtures include
raw MIME with a comment containing an unrelated ID.

## Regression checkpoint

Added 28 focused regression declarations across the threading, reply and compose
suites, and strengthened two existing composer cases. Coverage includes exact
900-byte chains, maximum 254-byte parent/ancestor MIME round trips, adjacent-ID
rejection, source decoding, comment/injection rejection, ordinary/forward
isolation, edits and uncertain retries. All new and existing Dart/Flutter tests
remain unexecuted in this session. No prior execution count is reused.
