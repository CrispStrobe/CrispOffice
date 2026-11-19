# Exact Dart SDK TLS ownership review

Pinned SDK: Dart 3.13.7. Source paths and SHA-256 identities are recorded in `tls-sdk-review.json`. No Dart execution was performed by this reviewer.

## Successful upgrade cleanup is safe

`SecureSocket.secure` calls `_detachRaw`, which sets the original `_Socket._raw` to null. `destroy()` then returns without touching the upgraded transport. Cancelling the old outer subscription cannot shut down receive once its raw field is null. The existing cleanup after a successful handshake is therefore safe.

## Historical T12 finding at ca00a8ff: stalled real handshake remains open

The same detachment happens before the TLS handshake future resolves. During that wait, abort has no closeable Socket owner for the raw TCP connection. `_RawSecureSocket.connect` returns its handshake completer future without an internal handshake timer. The provider can report timeout/cancellation, but a peer that never finishes TLS can keep the raw connection alive; the generation guard only closes a socket after eventual completion. Implicit TLS has the same ownership gap before SecureSocket.connect returns.

Using SecureSocket.startConnect alone is insufficient in this exact SDK: its cancellation delegates to the TCP connection task, and that task removes the successful socket from its connecting set before TLS starts.

Repair requires retaining a cancellable raw transport owner through the handshake, preserving normal trust verification. Acceptance needs a real loopback peer that stalls after TCP/STARTTLS and proves peer-observed closure on cancellation/timeout. The controlled socket-construction seam does not model SDK detachment and cannot establish this result.

## Resolution inspected at cdcfe878

The historical finding above is preserved. Commit `cdcfe878f01263f52c935d9ae0a90e6113a07e3f` now retains the TCP RawSocket across the entire RawSecureSocket handoff and secure lifetime. An explicit abort signal settles the wrapper future even if closing TCP does not complete the SDK handshake future. Old-wrapper disposal is disarmed only once the replacement owns TCP; generation checks reject late connection results.

The final real-loopback test log records 14 passes (exit 0), including both TLS modes with a peer that receives ClientHello and never replies. Cancellation and deadlines require peer-observed closure before fixture teardown, no early login, and successful fresh-connection retry. Separate successful handshakes and concrete trust/hostname rejection establish that ownership repair did not bypass validation. The three evidence fixes and deterministic partial-write limitations are recorded in `transport-review.json`.

Retained log: `tls-development-evidence/real-tls-reviewed.log`; SHA-256 `269c0e7e1f6c2cd27b268bc5fde6c63afecf4f607d05008af72ac70f279ab39e`. Final source manifest SHA-256 `5dc61c9d20bf2227236b489799b77c2765a24b04e8e7d6f8625e7186a0ebff48`. This reviewer inspected the author logs and source, but ran no Dart. The final integrated source-bound gate is still pending.
