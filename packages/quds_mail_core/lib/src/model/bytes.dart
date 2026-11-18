import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// An owned byte snapshot. Neither input mutation nor returned views can alter it.
///
/// A codec must enforce its raw/decoded budget before constructing a snapshot.
/// Hashes identify content integrity; they are not provider message identities.
final class MailBytes {
  MailBytes(Uint8List bytes)
    : _bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final Uint8List _bytes;
  String? _sha256;

  Uint8List get bytes => _bytes;
  int get length => _bytes.length;
  String get sha256 => _sha256 ??= crypto.sha256.convert(_bytes).toString();

  /// Creates a caller-owned copy for explicit export or an editable working copy.
  Uint8List copyBytes() => Uint8List.fromList(_bytes);
}
