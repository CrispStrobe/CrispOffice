## Unreleased

- Coalesce superseded requests before they enter the isolate mailbox, retain
  remote queue slots until acknowledged, and preserve progress for other keys.
- Reject over-limit text before it can cancel a valid in-flight request.

## 0.1.0

- Introduce an optional German GECToR decoder and proofing provider with exact
  source mapping, authenticated bundle inputs, an injected inference boundary,
  and a persistent bounded worker. Model/native artifacts are installed by the
  host; this package does not enable automatic checking or download models.
