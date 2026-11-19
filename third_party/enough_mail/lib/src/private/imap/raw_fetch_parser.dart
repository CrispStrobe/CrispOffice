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

  /// Maximum number of accepted complete literal records.
  final int maxMessages;

  /// Maximum size of an individual exact literal.
  final int maxLiteralBytes;
  final List<RawImapMessage> _messages = [];
  final Set<int> _uids = {};
  final Set<int> _bodySequences = {};
  final Map<int, int> _bodyUidsBySequence = {};
  final Map<int, List<String>> _laterFlagsByUid = {};
  final Set<int> _pendingNotificationUids = {};
  final Set<int> _pendingNotificationSequences = {};
  bool _notificationSequenceOverflow = false;
  bool _sawSequenceNotification = false;
  bool _sawExpunge = false;
  bool _uncorrelatedFlagsAfterExpunge = false;
  bool _failed = false;

  @override
  RawImapFetchResult? parse(
    ImapResponse imapResponse,
    Response<RawImapFetchResult> response,
  ) {
    if (_failed) {
      throw const FormatException('Invalid raw FETCH response');
    }
    if (response.isOkStatus) {
      // A FLAGS-only response is a valid unsolicited update, but it cannot
      // stand in for a requested literal. In particular, an observed in-range
      // UID must not become a sync tombstone when its literal was omitted.
      if (_pendingNotificationUids.isNotEmpty) {
        throw const FormatException('Missing notified raw FETCH literal');
      }
      if (_uncorrelatedFlagsAfterExpunge) {
        // Even full literal coverage cannot confirm a mutation using stale
        // flags when a later update's sequence identity was renumbered.
        throw const FormatException('Ambiguous flags after IMAP EXPUNGE');
      }
      final fullRange = _messages.length == lastUid - firstUid + 1;
      if (!fullRange &&
          (_notificationSequenceOverflow ||
              _pendingNotificationSequences.isNotEmpty ||
              (_sawSequenceNotification && _sawExpunge))) {
        // IMAP4rev1 updates can omit UID. A returned sequence can establish
        // that its literal is present, unless EXPUNGE renumbered sequences.
        // Otherwise a sparse range is ambiguous: fail instead of fabricating
        // absence. A completely returned UID range is unambiguous regardless.
        throw const FormatException('Ambiguous raw FETCH flag notification');
      }
    }
    return response.isOkStatus
        ? RawImapFetchResult([
            for (final message in _messages)
              if (_laterFlagsByUid[message.uid] case final flags?)
                RawImapMessage(
                  uid: message.uid,
                  bytes: message.bytes,
                  flags: flags,
                )
              else
                message,
          ])
        : null;
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
    // Generic status responses carry human-readable text, which can contain
    // the word FETCH without being a FETCH data response. Leave status/closure
    // handling to the client instead of interpreting it as a data prefix.
    if (RegExp(
      r'^\* +(?:OK|NO|BAD|PREAUTH|BYE)(?: |$)',
      caseSensitive: false,
    ).hasMatch(line)) {
      return false;
    }
    if (RegExp(
      r'^\* +[1-9][0-9]* +EXPUNGE(?: |$)',
      caseSensitive: false,
    ).hasMatch(line)) {
      _sawExpunge = true;
      // Do not apply a later UID-less update through a stale sequence map.
      _bodyUidsBySequence.clear();
      return false;
    }
    // Recognize FETCH at the untagged response position, including malformed
    // structural delimiters. RFC 3501 section 9 defines these atom-specials;
    // FETCHX remains a different atom, and FETCH inside unrelated data is not
    // a response prefix. Strict parsing below rejects non-SP delimiters.
    if (!RegExp(
      r'^\*[\x00-\x20\x7f]+'
      r'(?:[^\x00-\x20\x7f]+[\x00-\x20\x7f]+)?'
      r'FETCH(?=[\x00-\x20\x7f(){\x22\x5c%*\x5d]|$)',
      caseSensitive: false,
    ).hasMatch(line)) {
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
    final values = imapResponse.iterate(strict: true).values;
    // One response has exactly one sequence and one FETCH field list. Ignoring
    // trailing siblings can lose a UID and turn malformed input into a sync
    // tombstone, so reject the complete operation instead of taking a prefix.
    if (values.length != 3 ||
        values[0].value != '*' ||
        values[0].children != null ||
        values[0].data != null ||
        values[1].value != sequence.toString() ||
        values[1].children != null ||
        values[1].data != null ||
        values[2].value?.toUpperCase() != 'FETCH' ||
        values[2].data != null) {
      throw const FormatException('Invalid raw FETCH response shape');
    }
    final fields = values[2].children;
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
          if (value == null ||
              flag.data != null ||
              flag.children != null ||
              value.length > 256 ||
              flags.length >= 128) {
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
          final uidText = value.value ?? '';
          // RFC 3501 section 9: uniqueid = nz-number = digit-nz *DIGIT.
          // Integer parsing alone also accepts signed and hexadecimal forms.
          if (!RegExp(r'^[1-9][0-9]*$').hasMatch(uidText)) {
            throw const FormatException('Invalid raw FETCH UID');
          }
          uid = int.tryParse(uidText);
          if (uid == null ||
              uid < 1 ||
              uid > 0xffffffff ||
              value.data != null ||
              value.children != null) {
            throw const FormatException('Invalid raw FETCH UID');
          }
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
    if (bytes == null && flags != null) {
      // RFC 3501 section 5.2 permits unsolicited FLAGS updates, including
      // during FETCH. They are bounded by the connection's response budget
      // and do not consume the requested literal count or its UID set.
      if (uid != null) {
        if (_uids.contains(uid)) {
          _laterFlagsByUid[uid] = flags;
        } else if (uid >= firstUid && uid <= lastUid) {
          _pendingNotificationUids.add(uid);
          if (_pendingNotificationUids.length > maxMessages) {
            throw const FormatException(
              'Raw FETCH notification limit exceeded',
            );
          }
        }
      } else {
        _sawSequenceNotification = true;
        final knownUid = _bodyUidsBySequence[sequence];
        if (knownUid != null) {
          _laterFlagsByUid[knownUid] = flags;
        } else if (_sawExpunge) {
          _uncorrelatedFlagsAfterExpunge = true;
        }
        if (!_bodySequences.contains(sequence)) {
          if (_pendingNotificationSequences.length < maxMessages) {
            _pendingNotificationSequences.add(sequence);
          } else if (!_pendingNotificationSequences.contains(sequence)) {
            // Retain bounded state even for many unrelated notifications.
            // Full UID coverage can still prove that no literal is missing.
            _notificationSequenceOverflow = true;
          }
        }
      }
      return true;
    }
    if (_messages.length >= maxMessages) {
      throw const FormatException('Raw FETCH message limit exceeded');
    }
    if (uid == null ||
        uid < firstUid ||
        uid > lastUid ||
        bytes == null ||
        !_uids.add(uid)) {
      throw const FormatException('Invalid raw FETCH identity or literal');
    }
    _bodySequences.add(sequence);
    _bodyUidsBySequence[sequence] = uid;
    _laterFlagsByUid.remove(uid);
    _pendingNotificationUids.remove(uid);
    _pendingNotificationSequences.remove(sequence);
    _messages.add(RawImapMessage(uid: uid, bytes: bytes, flags: flags));
    return true;
  }
}
