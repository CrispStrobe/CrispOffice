// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import '../../imap/raw_fetch.dart';
import '../../imap/response.dart';
import 'imap_response.dart';
import 'response_parser.dart';

/// Parses only the explicitly requested raw literal and identity/flags fields.
class RawFetchParser extends ResponseParser<RawImapFetchResult> {
  /// No wildcard ranges, MIME projection, or partial literal acceptance.
  RawFetchParser({
    required this.firstUid,
    required this.lastUid,
    required this.headersOnly,
    required this.maxMessages,
    required this.maxLiteralBytes,
  });

  /// First accepted UID in the requested interval.
  final int firstUid;

  /// Last accepted UID in the requested interval.
  final int lastUid;

  /// Whether the literal contains only requested envelope headers.
  final bool headersOnly;

  /// Maximum number of accepted FETCH records.
  final int maxMessages;

  /// Maximum size of an individual exact literal.
  final int maxLiteralBytes;
  final List<RawImapMessage> _messages = [];
  final Set<int> _uids = {};
  bool _failed = false;

  @override
  RawImapFetchResult? parse(
    ImapResponse imapResponse,
    Response<RawImapFetchResult> response,
  ) {
    if (_failed) {
      throw const FormatException('Invalid raw FETCH response');
    }
    return response.isOkStatus ? RawImapFetchResult(_messages) : null;
  }

  @override
  bool parseUntagged(
    ImapResponse imapResponse,
    Response<RawImapFetchResult>? response,
  ) {
    try {
      return _parseUntagged(imapResponse);
    } on Object {
      _failed = true;
      rethrow;
    }
  }

  bool _parseUntagged(ImapResponse imapResponse) {
    if (_failed) {
      throw const FormatException('Invalid raw FETCH response');
    }
    final line = imapResponse.first.line ?? '';
    if (!RegExp(r'(?:^| )FETCH(?: |$)', caseSensitive: false).hasMatch(line)) {
      return false;
    }
    final prefix = RegExp(
      r'^\* +([1-9][0-9]*) +FETCH(?: |$)',
      caseSensitive: false,
    ).firstMatch(line);
    final sequence = prefix == null ? null : int.tryParse(prefix[1]!);
    if (sequence == null || sequence < 1 || sequence > 0xffffffff) {
      throw const FormatException('Invalid raw FETCH sequence prefix');
    }
    if (_messages.length >= maxMessages) {
      throw const FormatException('Raw FETCH message limit exceeded');
    }
    final values = imapResponse.iterate(strict: true).values;
    ImapValue? fetch;
    for (final value in values) {
      if (value.value?.toUpperCase() == 'FETCH') {
        fetch = value;
      }
    }
    final fields = fetch?.children;
    if (fields == null) {
      throw const FormatException('Invalid raw FETCH');
    }
    int? uid;
    Uint8List? bytes;
    List<String>? flags;
    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      final key = field.value?.toUpperCase();
      if (key == 'FLAGS') {
        if (flags != null || field.children == null) {
          throw const FormatException('Invalid raw FETCH flags');
        }
        flags = <String>[];
        for (final flag in field.children!) {
          final value = flag.value;
          if (value == null || value.length > 256 || flags.length >= 128) {
            throw const FormatException('Invalid raw FETCH flag');
          }
          flags.add(value);
        }
      } else {
        if (++index >= fields.length) {
          throw const FormatException('Missing raw FETCH value');
        }
        final value = fields[index];
        if (key == 'UID') {
          if (uid != null) {
            throw const FormatException('Duplicate raw FETCH UID');
          }
          uid = int.tryParse(value.value ?? '');
        } else if (key == (headersOnly ? rawImapHeaderItem : 'BODY[]')) {
          if (bytes != null || value.data == null) {
            throw const FormatException(
              'Expected one complete raw FETCH literal',
            );
          }
          bytes = value.data;
          if (bytes!.length > maxLiteralBytes) {
            throw const FormatException('Raw FETCH literal limit exceeded');
          }
        } else {
          // In particular, BODY[]<offset> is never a complete-message success.
          throw const FormatException('Unexpected raw FETCH field');
        }
      }
    }
    if (uid == null ||
        uid < firstUid ||
        uid > lastUid ||
        bytes == null ||
        !_uids.add(uid)) {
      throw const FormatException('Invalid raw FETCH identity or literal');
    }
    _messages.add(RawImapMessage(uid: uid, bytes: bytes, flags: flags));
    return true;
  }
}
