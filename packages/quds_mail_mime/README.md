# Quds Mail MIME

`QudsMimeCodec` reads saved RFC messages without a mailbox account, database,
filesystem or network service. It returns Quds DTOs; enough_mail types remain
inside the adapter. The dependency is the reviewed MPL fork under
`third_party/enough_mail`, accessed through its public `mime_core.dart` entry.

```dart
final result = const QudsMimeCodec().parse(bytes);
final exactOriginal = result.original?.copyBytes();
```

Use `MailReadBudget.preview()` for compact previews. Raw-limit rejection does
not retain a second oversized copy. After a size-admitted input, source remains
available on partial, unsupported, malformed and limit-rejected results.

The codec scans MIME byte ranges before projecting bounded headers with
enough_mail. It limits raw size, cumulative header bytes, logical field size,
parts and depth. It validates transfer syntax and computes decoded length before
allocation, counting all alternatives toward cumulative decoded/body limits.
The upstream serializer is not used for raw export or identity attachments.
Canonical composition and network submission are separate later capabilities.

Supported transfer encodings are strict Base64, quoted-printable, 7bit, 8bit and
binary. Character sets use the fork's strict decoder; malformed or unknown text
gets a diagnostic and source fallback. HTML remains **untrusted** until the UI
sanitizer handles it. A CID is metadata, not permission to fetch a resource.

Multipart/alternative chooses the last supported plain/HTML alternative;
multipart/related honors `start`; mixed content uses the first body subtree.
Attached messages remain opaque read-only attachments. No signature verification
or decryption is implied by preserving signed/encrypted source bytes.

This is a synchronous bounded reader, not a streaming parser. Cancellation is
checked before work and at scan/decode boundaries; a host needing mid-flight UI
cancellation must schedule it on an isolate or worker. Device-specific memory
qualification remains separate from native/browser correctness tests.

Tests contain independently authored synthetic mail using `example.invalid`.
Run `dart test`, `dart test --platform chrome`, and compile/run
`test/compile/portable_import.dart` on both the VM and JavaScript.
