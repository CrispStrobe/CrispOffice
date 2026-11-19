// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

/// Envelope headers only; MIME content headers cannot demand an omitted body.
const String rawImapHeaderItem =
    'BODY[HEADER.FIELDS '
    '(DATE FROM TO CC BCC REPLY-TO SUBJECT MESSAGE-ID IN-REPLY-TO REFERENCES)]';

/// One exact IMAP literal, without MIME decoding or newline normalization.
class RawImapMessage {
  /// Creates an immutable snapshot of the received literal and flags.
  RawImapMessage({
    required this.uid,
    required Uint8List bytes,
    required List<String>? flags,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
       flags = flags == null ? null : List.unmodifiable(flags);

  /// Stable UID; a caller must also retain the selected UIDVALIDITY.
  final int uid;

  /// Exact complete `BODY[HEADER.FIELDS ...]` or `BODY[]` server literal.
  final Uint8List bytes;

  /// Null means no FLAGS data item was received; empty means no flags are set.
  final List<String>? flags;
}

/// Result of a bounded UID FETCH for exact header or complete-message literals.
class RawImapFetchResult {
  /// Retains the bounded set of fetched messages.
  RawImapFetchResult(List<RawImapMessage> messages)
    : messages = List.unmodifiable(messages);

  /// Returned UIDs are unique and inside the requested numeric interval.
  final List<RawImapMessage> messages;
}
