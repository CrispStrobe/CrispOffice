## Unreleased

- Add opt-in bounded sentence segmentation for long manual German checks.
  Preflight the complete source, retain original UTF-16 edits, and publish only
  after every segment converges. Preserve request-wide deadlines, cancellation,
  protected text and original-start guards; bound actual forward tokens as
  corrections expand. The default single-sequence/reference path is unchanged.
- Accept same-number person forms authenticated by the verb table, so a plural
  `sind` label also agrees with `wir`. Preserve the conservative singular/plural,
  coordination, and sentence-boundary restrictions.
- Share the editor's personal vocabulary in the manual-provider setup example.
- Coalesce superseded requests before they enter the isolate mailbox, retain
  remote queue slots until acknowledged, and preserve progress for other keys.
- Reject over-limit text before it can cancel a valid in-flight request.

## 0.1.0

- Introduce an optional German GECToR decoder and proofing provider with exact
  source mapping, authenticated bundle inputs, an injected inference boundary,
  and a persistent bounded worker. Model/native artifacts are installed by the
  host; this package does not enable automatic checking or download models.
