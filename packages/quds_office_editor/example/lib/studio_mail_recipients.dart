/// Validated recipient groups for a foreground Studio composition.
///
/// Fields accept bare ASCII mailboxes separated by commas or semicolons. This
/// deliberately does not parse display names, groups, comments or SMTPUTF8.
/// The first occurrence wins across To, Cc and Bcc, in that order. Mailbox local
/// parts remain case-sensitive; DNS domains compare case-insensitively.
final class StudioMailRecipients {
  StudioMailRecipients._(List<String> to, List<String> cc, List<String> bcc)
    : to = List.unmodifiable(to),
      cc = List.unmodifiable(cc),
      bcc = List.unmodifiable(bcc),
      envelope = List.unmodifiable([...to, ...cc, ...bcc]);

  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final List<String> envelope;

  /// Includes repeated entries, before deduplication, to bound parsing work.
  static const maxRecipients = 100;
  static const maxInputLength = maxRecipients * 256;

  static StudioMailRecipients? tryParse({
    required String to,
    String cc = '',
    String bcc = '',
  }) {
    final fields = [to, cc, bcc];
    if (to.length + cc.length + bcc.length > maxInputLength ||
        fields.any(
          (field) => field.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e),
        )) {
      return null;
    }
    final seen = <String>{};
    var count = 0;
    List<String>? parseField(String value) {
      if (value.trim().isEmpty) return const [];
      final entries = value.split(RegExp('[,;]'));
      count += entries.length;
      if (count > maxRecipients) return null;
      final result = <String>[];
      for (final entry in entries) {
        final address = entry.trim();
        if (!isSupportedAddress(address)) return null;
        if (seen.add(identityKey(address))) result.add(address);
      }
      return result;
    }

    final toAddresses = parseField(to);
    if (toAddresses == null) return null;
    final ccAddresses = parseField(cc);
    if (ccAddresses == null) return null;
    final bccAddresses = parseField(bcc);
    if (bccAddresses == null || seen.isEmpty) return null;
    return StudioMailRecipients._(toAddresses, ccAddresses, bccAddresses);
  }

  /// One complete ASCII dot-atom mailbox with a DNS host, without whitespace.
  static bool isSupportedAddress(String address) {
    if (address.length > 254 ||
        address.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
      return false;
    }
    final parts = address.split('@');
    if (parts.length != 2) return false;
    final local = parts[0];
    final domain = parts[1];
    if (local.isEmpty ||
        local.length > 64 ||
        local.startsWith('.') ||
        local.endsWith('.') ||
        local.contains('..') ||
        !RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(local)) {
      return false;
    }
    final labels = domain.split('.');
    final labelPattern = RegExp(
      r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
    );
    return domain.length <= 253 && labels.every(labelPattern.hasMatch);
  }

  /// Comparison key for a supported mailbox; never folds its local part.
  static String identityKey(String address) {
    if (!isSupportedAddress(address)) {
      throw const FormatException('Unsupported Studio Mail recipient.');
    }
    final at = address.indexOf('@');
    return '${address.substring(0, at)}@${address.substring(at + 1).toLowerCase()}';
  }
}
