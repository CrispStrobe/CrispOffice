/// Exact, bounded UIDPLUS evidence for a single-message UID MOVE.
///
/// The raw response code is parsed without constructing or expanding UID sets.
/// RFC 4315 forbids wildcards and extra UIDs; a singleton range is accepted only
/// when both endpoints are identical. An absent unrelated response code carries
/// no identity evidence. Malformed COPYUID must not degrade into guessed success.
({int uidValidity, int uid})? parseSingleCopyUid(
  String? responseCode, {
  required int sourceUid,
}) {
  if (responseCode == null) return null;
  if (responseCode.length < 7 ||
      responseCode.substring(0, 7).toUpperCase() != 'COPYUID' ||
      responseCode.length > 7 && responseCode[7] != ' ') {
    return null;
  }
  if (responseCode.length > 96) {
    throw const FormatException('Oversize single-message COPYUID.');
  }
  final match = RegExp(
    r'^COPYUID ([1-9][0-9]{0,9}) ([1-9][0-9]{0,9})(?::([1-9][0-9]{0,9}))? ([1-9][0-9]{0,9})(?::([1-9][0-9]{0,9}))?$',
    caseSensitive: false,
  ).firstMatch(responseCode);
  if (match == null || match.end != responseCode.length) {
    throw const FormatException('Invalid single-message COPYUID.');
  }
  final validity = int.parse(match[1]!);
  final source = int.parse(match[2]!);
  final target = int.parse(match[4]!);
  if (validity > 0xffffffff ||
      source > 0xffffffff ||
      target > 0xffffffff ||
      source != sourceUid ||
      (match[3] != null && int.parse(match[3]!) != source) ||
      (match[5] != null && int.parse(match[5]!) != target)) {
    throw const FormatException('COPYUID does not match the requested UID.');
  }
  return (uidValidity: validity, uid: target);
}
