# Changelog

## 0.1.0 — 2026-11-25

- Add a portable Graph v1.0 To Do provider with injectable account-bound tokens
  and bounded HTTP request/response ports.
- Add list discovery, list/task delta pages, scoped opaque cursors, ID-only
  tombstones and final-event handling for repeated identities within a page.
- Add task reads, create, sparse updates and delete without automatic mutation
  retries or unsupported conditional-write claims.
- Embed stable operation metadata in create requests and provide bounded,
  read-only recovery scans for ambiguous create outcomes.
- Preserve timezone/wall-time values and unsupported provider data; guard
  completion/reopening of known recurring tasks.
- Add optional native HTTPS transport with redirects disabled, streaming byte
  limits, deadlines and credential-origin restrictions.
- Add deterministic provider/native policy tests and a portable JS import probe.
