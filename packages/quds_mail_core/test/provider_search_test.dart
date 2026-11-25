import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

void main() {
  final account = MailAccountId(
    'account',
    profile: MailProfileId('profile', hostId: 'host'),
  );
  final mailbox = MailMailboxId('INBOX', account: account);

  test('search request bounds literal text, limits and UTC received dates', () {
    expect(
      MailProviderSearchRequest(
        mailbox: mailbox,
        query: 'hello OR from:x',
      ).isValid,
      isTrue,
    );
    for (final text in [
      '',
      '   ',
      'x\r\nFrom: y',
      'x\u0085y',
      String.fromCharCode(0xd800),
      'x' * 513,
    ]) {
      expect(
        MailProviderSearchRequest(mailbox: mailbox, query: text).isValid,
        isFalse,
      );
    }
    for (final count in [0, -1, 101]) {
      expect(
        MailProviderSearchRequest(
          mailbox: mailbox,
          query: 'hello',
          maxResults: count,
        ).isValid,
        isFalse,
      );
    }
    for (final date in [
      DateTime(2026),
      DateTime.utc(1969),
      DateTime.utc(2026, 1, 1, 0, 0, 0, 1),
    ]) {
      expect(
        MailProviderSearchRequest(
          mailbox: mailbox,
          query: 'hello',
          receivedAfter: date,
        ).isValid,
        isFalse,
      );
    }
    expect(
      MailProviderSearchRequest(
        mailbox: mailbox,
        query: 'hello',
        receivedAfter: DateTime.utc(2026),
        receivedBefore: DateTime.utc(2026),
      ).isValid,
      isFalse,
    );
    expect(
      MailProviderSearchRequest(
        mailbox: mailbox,
        query: 'hello',
        receivedAfter: DateTime.utc(2026),
        receivedBefore: DateTime.utc(2027),
      ).isValid,
      isTrue,
    );
  });

  MailHeaderRecord header(MailAccountId owner, {String id = 'id'}) =>
      MailHeaderRecord(
        id: MailMessageId(id),
        remote: MailOpaqueIdentity(
          account: owner,
          provider: MailProviderKind.graph,
          value: id,
        ),
        envelope: MailEnvelope(subject: 'Private subject'),
      );

  test(
    'result owns headers, enforces ownership and does not leak mail text',
    () {
      final rows = [header(account)];
      final result = MailProviderSearchResult(
        mailbox: mailbox,
        messages: rows,
        hasMore: false,
      );
      rows.clear();
      expect(result.messages, hasLength(1));
      expect(() => result.messages.clear(), throwsUnsupportedError);
      expect(result.toString(), isNot(contains('Private')));
      expect(
        MailProviderSearchRequest(mailbox: mailbox, query: 'Secret').toString(),
        isNot(contains('Secret')),
      );
      expect(
        () => MailProviderSearchResult(
          mailbox: mailbox,
          messages: [header(MailAccountId('other', profile: account.profile))],
          hasMore: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => MailProviderSearchResult(
          mailbox: mailbox,
          messages: [header(account), header(account)],
          hasMore: false,
        ),
        throwsArgumentError,
      );
    },
  );

  test('exact, estimated and unknown counts have distinct invariants', () {
    expect(
      () => MailProviderSearchResult(
        mailbox: mailbox,
        messages: [header(account)],
        hasMore: false,
        totalCount: 0,
        countPrecision: MailSearchCountPrecision.exact,
      ),
      throwsArgumentError,
    );
    expect(
      () => MailProviderSearchResult(
        mailbox: mailbox,
        messages: [],
        hasMore: false,
        totalCount: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => MailProviderSearchResult(
        mailbox: mailbox,
        messages: [],
        hasMore: false,
        countPrecision: MailSearchCountPrecision.estimate,
      ),
      throwsArgumentError,
    );
    expect(
      () => MailProviderSearchResult(
        mailbox: mailbox,
        messages: [],
        hasMore: false,
        totalCount: -1,
        countPrecision: MailSearchCountPrecision.estimate,
      ),
      throwsArgumentError,
    );
    final estimate = MailProviderSearchResult(
      mailbox: mailbox,
      messages: [header(account)],
      hasMore: false,
      totalCount: 0,
      countPrecision: MailSearchCountPrecision.estimate,
    );
    expect(estimate.countPrecision, MailSearchCountPrecision.estimate);
  });

  test('an exact complete count must match the returned cardinality', () {
    for (final rows in [
      <MailHeaderRecord>[],
      [header(account)],
    ]) {
      expect(
        () => MailProviderSearchResult(
          mailbox: mailbox,
          messages: rows,
          hasMore: false,
          totalCount: 5,
          countPrecision: MailSearchCountPrecision.exact,
        ),
        throwsArgumentError,
      );
      final complete = MailProviderSearchResult(
        mailbox: mailbox,
        messages: rows,
        hasMore: false,
        totalCount: rows.length,
        countPrecision: MailSearchCountPrecision.exact,
      );
      expect(complete.totalCount, complete.messages.length);
    }
  });
}
