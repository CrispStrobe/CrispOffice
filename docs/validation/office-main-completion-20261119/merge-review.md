# Final reconciliation decisions

The release cutoff is **19 November 2026, 08:15:06 CET (07:15:06 UTC)**.
Its complete advertisement contains 392 refs: 213 fork branches, 175 pull-request
heads and four upstream branches. Main was `690e6ac8`; Notes `c320f283` and
thesaurus `df62b589` did not advance. The final incoming integration head is
`4624218f9468eeeac07f1f100ac0e4bb6b050a17`, which contains Mail
`71edec2de364805113d18e0f1d7edbb1f00467e5`, the canonical UID work from `99dd7307`,
and this continuation's earlier qualified TLS source `54c36e40` by ancestry.
The final ancestry audit replays the fixed cutoff against the published source.

## TLS implementation and API compatibility

Two independently developed TLS repairs converged during this continuation.
Incoming Mail replaced Socket-returning construction seams with a
`ClientConnection` interface and a `RawClientConnection` adapter. This branch
retains the existing Socket signatures and its actual raw-socket facade. It
incorporates the relevant ownership and cancellation safeguards from both:

- A pending TCP ConnectionTask and the original RawSocket stay cancellable
  during implicit TLS and STARTTLS. The TCP owner is also retained after a
  successful handshake, so abort does not wait for buffered TLS output to drain.
- A per-connection abort signal settles pending connect/upgrade callers even
  when the SDK handshake future remains unresolved. Generation checks still
  dispose of late sockets and prevent an old completion reviving a connection.
- STARTTLS preserves queued plaintext writes and subscription ownership, and
  records secure connection metadata after the upgrade succeeds.
- Partial writes, writable readiness, cancellation of an idle producer and
  failure after abort retain ordered sink behavior. The deterministic incoming
  raw-write tests target the adapter that production actually uses.
- Existing manual Socket I/O and Socket-returning overrides remain compatible.
  The pending-handshake cancellation guarantee applies to the default owned
  transport. Arbitrary injected socket implementations own their lifecycle.

The unused competing `client_connection.dart` is intentionally absent from the
resolved tree. Its relevant behavior is represented in `client_base.dart` and
`cancellable_socket.dart`. All incoming TLS cases are retained or adapted to the
selected interface, including successful handshakes, trust/hostname refusal,
credential sequencing, forced closure and partial-write controls. Two further
direct-API abort-completion regressions reproduce failures before the abort
signal repair. The earlier nine real-TLS tests are also retained.

Both TLS designs' original commits and review evidence remain in the merge
history. Their source-specific reports are not claims about this resolved tree.

## Raw FETCH parsing

The merge adopts canonical decimal-only UID syntax and its six incoming tests,
while preserving the earlier unsolicited FLAGS, EXPUNGE, resource-limit and
status-text repairs. Additional review reproduced a dispatch gap: malformed
FETCH separators could bypass the strict parser, allowing a tagged OK to turn
returned data into apparent missing messages.

FETCH detection now recognizes its untagged response position and the protocol's
atom delimiters. The existing strict parser rejects malformed tabs, attached
lists/quotes and literal prefixes; failures remain latched through tagged OK.
Header and body regressions retain an earlier valid response before the invalid
one, and provider regressions require failure instead of a tombstone page.
Negative controls preserve unrelated status text, FLAGS data and FETCHX atoms.

The frozen inventory includes 26 direct raw-parser cases and 69 native provider
cases. These numbers describe selection; passing qualification belongs to the
separately recorded committed-source results.

## Core/store controls and qualification boundary

The explicit equality/hash assertion from Mail is retained. The latest Python
launcher regression now tolerates a child disappearing while `/proc/.../stat`
is read, avoiding a race in the test observer without weakening its prohibition
on a surviving child. The complete core/store gate is rerun on the final source;
the older 199-case store result is not transferred across these changed inputs.

The native plan selects 60 suites and 35 strict analysis/formatting targets.
The Node plan selects seven suites. Store, native, and Node gates run sequentially
on a clean published source, with separate Python controls and an independent
raw-event/source/runtime audit. Prior 778-case and 795-case checkpoints and all
development attempts remain separately identified and add zero to final totals.

GitHub Actions are neither queried nor awaited. Publication uses non-forced
expected-head ref updates, followed by fetched-object verification. The user
has authorized the final normal merge of PR #173 into remote main.
