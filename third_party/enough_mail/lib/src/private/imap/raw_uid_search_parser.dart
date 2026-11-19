// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import '../../imap/response.dart';
import '../util/protocol_resource_limit.dart';
import 'imap_response.dart';
import 'response_parser.dart';

/// Strict discovery for one closed UID interval, without extension expansion.
class RawUidSearchParser extends ResponseParser<List<int>> {
  /// Creates a parser with a bounded result count and accepted UID interval.
  RawUidSearchParser({
    required this.firstUid,
    required this.lastUid,
    required this.maxUids,
  });

  /// Lowest accepted UID.
  final int firstUid;

  /// Highest accepted UID.
  final int lastUid;

  /// Maximum number of unique UIDs accepted from the complete response.
  final int maxUids;

  final Set<int> _uids = {};
  bool _received = false;
  bool _failed = false;

  static final RegExp _searchAtom = RegExp(
    r'^\*[\x00-\x20\x7f-\uffff]*(?:SEARCH|ESEARCH)'
    r'(?=$|[\x00-\x20\x7f-\uffff(){}"%*\\\]])',
    caseSensitive: false,
  );

  @override
  List<int>? parse(ImapResponse imapResponse, Response<List<int>> response) {
    if (_failed) {
      throw const FormatException('Invalid bounded UID SEARCH response');
    }
    if (!response.isOkStatus) {
      return null;
    }
    if (!_received) {
      _failed = true;
      throw const FormatException('Missing bounded UID SEARCH response');
    }
    return List<int>.unmodifiable(_uids.toList()..sort());
  }

  @override
  bool parseUntagged(ImapResponse imapResponse, Response<List<int>>? response) {
    try {
      return _parseUntagged(imapResponse);
    } on Object {
      _failed = true;
      rethrow;
    }
  }

  bool _parseUntagged(ImapResponse response) {
    if (_failed) {
      throw const FormatException('Invalid bounded UID SEARCH response');
    }
    final line = response.first.rawLine ?? '';
    // Match only the response atom. Status prose and distinct atoms such as
    // SEARCHX cannot establish discovery or invalidate an actual SEARCH.
    if (!_searchAtom.hasMatch(line)) {
      return false;
    }
    // A literal, repeated result, ESEARCH, extension data or malformed prefix
    // cannot be silently ignored and thereby become authority for deletions.
    if (_received ||
        !response.isSimple ||
        response.first.literal != null ||
        line.length < 8 ||
        line.substring(0, 8).toUpperCase() != '* SEARCH') {
      throw const FormatException('Invalid bounded UID SEARCH shape');
    }
    _received = true;
    var offset = 8;
    while (offset < line.length) {
      if (line.codeUnitAt(offset++) != 32 || offset == line.length) {
        throw const FormatException('Invalid bounded UID SEARCH separator');
      }
      final first = line.codeUnitAt(offset);
      if (first < 49 || first > 57) {
        throw const FormatException('Invalid bounded UID SEARCH number');
      }
      var uid = 0;
      var digits = 0;
      while (offset < line.length && line.codeUnitAt(offset) != 32) {
        final digit = line.codeUnitAt(offset++) - 48;
        if (digit < 0 || digit > 9 || ++digits > 10) {
          throw const FormatException('Invalid bounded UID SEARCH number');
        }
        uid = uid * 10 + digit;
      }
      if (uid < firstUid || uid > lastUid || uid > 0xffffffff) {
        throw const FormatException('Bounded UID SEARCH number out of range');
      }
      if (_uids.contains(uid)) {
        throw const FormatException('Duplicate bounded UID SEARCH number');
      }
      if (_uids.length >= maxUids) {
        throw const ProtocolResourceLimit('UID SEARCH result limit exceeded');
      }
      _uids.add(uid);
    }
    return true;
  }
}
