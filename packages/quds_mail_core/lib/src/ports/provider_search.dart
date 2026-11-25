import '../model/identity.dart';
import '../model/result.dart';
import '../sync/cancellation.dart';
import 'provider.dart';

enum MailProviderSearchField { body, subject, from, to }

/// The provider's reported cardinality must not be presented as exact unless
/// the provider actually observed an exact result count.
enum MailSearchCountPrecision { exact, estimate, unknown }

/// A bounded, read-only search of one exact provider folder or label.
///
/// [query] is literal authored text, never user-supplied provider grammar.
/// Provider indexing/tokenization rules still apply: this is not a promise of
/// byte-for-byte substring matching. Adapters reject unsupported fields or
/// literals that their query grammar cannot represent safely.
final class MailProviderSearchRequest {
  const MailProviderSearchRequest({
    required this.mailbox,
    required this.query,
    this.field = MailProviderSearchField.body,
    this.receivedAfter,
    this.receivedBefore,
    this.maxResults = 50,
  });

  static const maxQueryCodeUnits = 512;
  static const maxResultLimit = 100;

  final MailMailboxId mailbox;
  final String query;
  final MailProviderSearchField field;

  /// Inclusive lower and exclusive upper bounds on received time. Bounds must
  /// be UTC, at whole-second precision, and within years 1970 through 9999.
  final DateTime? receivedAfter;
  final DateTime? receivedBefore;
  final int maxResults;

  bool get isValid =>
      query.trim().isNotEmpty &&
      query.length <= maxQueryCodeUnits &&
      _validText(query) &&
      mailbox.value.isNotEmpty &&
      mailbox.value.length <= 2048 &&
      _validText(mailbox.value) &&
      maxResults >= 1 &&
      maxResults <= maxResultLimit &&
      _validDate(receivedAfter) &&
      _validDate(receivedBefore) &&
      (receivedAfter == null ||
          receivedBefore == null ||
          receivedAfter!.isBefore(receivedBefore!));

  static bool _validDate(DateTime? value) =>
      value == null ||
      value.isUtc &&
          value.year >= 1970 &&
          value.year <= 9999 &&
          value.millisecond == 0 &&
          value.microsecond == 0;

  static bool _validText(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x20 || (unit >= 0x7f && unit <= 0x9f)) return false;
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= value.length) return false;
        final low = value.codeUnitAt(i);
        if (low < 0xdc00 || low > 0xdfff) return false;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'MailProviderSearchRequest(redacted)';
}

/// One bounded provider result. Headers remain owned by the searched account;
/// displaying them does not import them into the cache or mutate provider mail.
final class MailProviderSearchResult {
  MailProviderSearchResult({
    required this.mailbox,
    required List<MailHeaderRecord> messages,
    required this.hasMore,
    this.totalCount,
    this.countPrecision = MailSearchCountPrecision.unknown,
  }) : messages = List<MailHeaderRecord>.unmodifiable(messages) {
    final identities = <MailRemoteIdentity>{};
    final localIds = <MailMessageId>{};
    if (messages.length > MailProviderSearchRequest.maxResultLimit ||
        messages.any(
          (item) =>
              item.remote.account != mailbox.account ||
              item.remote is MailImapIdentity &&
                  (item.remote as MailImapIdentity).mailbox != mailbox ||
              !identities.add(item.remote) ||
              !localIds.add(item.id),
        ) ||
        (totalCount != null &&
            (totalCount! < 0 || totalCount! > 0x1fffffffffffff)) ||
        ((countPrecision == MailSearchCountPrecision.unknown) !=
            (totalCount == null)) ||
        (countPrecision == MailSearchCountPrecision.exact &&
            (totalCount! < messages.length ||
                (hasMore && totalCount! <= messages.length)))) {
      throw ArgumentError('Invalid provider search result.');
    }
  }

  final MailMailboxId mailbox;
  final List<MailHeaderRecord> messages;

  /// True when a continuation, look-ahead match, or provider search cap leaves
  /// additional possible matches outside this bounded result.
  final bool hasMore;
  final int? totalCount;
  final MailSearchCountPrecision countPrecision;

  @override
  String toString() => 'MailProviderSearchResult(redacted)';
}

/// Optional provider-side capability. Unsupported adapters do not implement
/// this port, and unsupported fields return a typed failure before mail IO.
abstract interface class MailProviderSearch {
  Set<MailProviderSearchField> get searchFields;

  Future<MailResult<MailProviderSearchResult>> search(
    MailProviderSearchRequest request, {
    required MailOperationLease lease,
  });
}
