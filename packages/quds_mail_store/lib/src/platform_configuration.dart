import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'errors.dart';

/// Opaque, path-safe identity; framing prevents ambiguous concatenations.
String mailStoreNamespace(
  MailProfileId profile, {
  String namespace = 'native',
}) {
  if (namespace.isEmpty || namespace.length > 256) {
    throw const MailStoreStorageException(MailProblemCode.invalidInput);
  }
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(<String>[
            'quds-mail-store-v1',
            namespace,
            profile.hostId,
            profile.value,
          ]),
        ),
      )
      .toString();
}

/// Resolve only explicit same-origin HTTP(S) assets. No CDN default is used.
Uri mailStoreAssetUri(Uri asset, {required Uri baseUri}) {
  final resolved = baseUri.resolveUri(asset);
  if ((baseUri.scheme != 'https' && baseUri.scheme != 'http') ||
      resolved.scheme != baseUri.scheme ||
      resolved.host != baseUri.host ||
      resolved.port != baseUri.port ||
      resolved.userInfo.isNotEmpty ||
      resolved.fragment.isNotEmpty ||
      resolved.path.isEmpty ||
      resolved.path.endsWith('/')) {
    throw const MailStoreStorageException(MailProblemCode.invalidInput);
  }
  return resolved;
}
