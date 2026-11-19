## Unreleased

- Add bounded streaming MBOX import with explicit mboxrd/mboxo escaping,
  strict envelope framing, byte preservation, oversized-record continuation,
  typed per-record errors and cancellation of stalled input streams.
- Reject unsupported Content-Length MBOX variants and malformed preambles
  explicitly; never return a silently truncated record as an original message.

## 0.1.0

- Add a portable, bounded EML codec over the reviewed enough_mail MIME surface.
- Preserve exact original message bytes and immutable decoded attachment bytes.
- Reject resource-limit breaches and diagnose unsupported or malformed encoding.
- Define deterministic alternative/related body selection with original fixtures.
