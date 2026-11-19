# Exact Dart SDK TLS ownership review

Pinned SDK: Dart 3.13.7. Source paths and SHA-256 identities are recorded in `tls-sdk-review.json`. No Dart execution was performed by this reviewer.

## Successful upgrade cleanup is safe

`SecureSocket.secure` calls `_detachRaw`, which sets the original `_Socket._raw` to null. `destroy()` then returns without touching the upgraded transport. Cancelling the old outer subscription cannot shut down receive once its raw field is null. The existing cleanup after a successful handshake is therefore safe.

## T12: stalled real handshake remains open

The same detachment happens before the TLS handshake future resolves. During that wait, abort has no closeable Socket owner for the raw TCP connection. `_RawSecureSocket.connect` returns its handshake completer future without an internal handshake timer. The provider can report timeout/cancellation, but a peer that never finishes TLS can keep the raw connection alive; the generation guard only closes a socket after eventual completion. Implicit TLS has the same ownership gap before SecureSocket.connect returns.

Using SecureSocket.startConnect alone is insufficient in this exact SDK: its cancellation delegates to the TCP connection task, and that task removes the successful socket from its connecting set before TLS starts.

Repair requires retaining a cancellable raw transport owner through the handshake, preserving normal trust verification. Acceptance needs a real loopback peer that stalls after TCP/STARTTLS and proves peer-observed closure on cancellation/timeout. The controlled socket-construction seam does not model SDK detachment and cannot establish this result.
