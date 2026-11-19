import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('range-tests', hostId: 'office');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('INBOX', account: _account);

MailSyncPage _page(
  MailImapSyncRange range, {
  List<MailHeaderRecord> upserts = const [],
  List<MailRemoteIdentity> tombstones = const [],
}) => MailSyncPage(
  mailbox: _mailbox,
  upserts: upserts,
  tombstones: tombstones,
  next: MailCursor(mailbox: _mailbox, value: 'next'),
  hasMore: false,
  imapRange: range,
);

MailHeaderRecord _header(MailRemoteIdentity remote) => MailHeaderRecord(
  id: MailMessageId('message'),
  remote: remote,
  envelope: MailEnvelope(subject: 'Observed survivor'),
);

void main() {
  test('inclusive ranges support the full IMAP UID space and single UIDs', () {
    final full = MailImapSyncRange(
      mailbox: _mailbox,
      uidValidity: 0xffffffff,
      firstUid: 1,
      lastUid: 0xffffffff,
    );
    final first = MailImapIdentity(
      mailbox: _mailbox,
      uidValidity: 0xffffffff,
      uid: 1,
    );
    final last = MailImapIdentity(
      mailbox: _mailbox,
      uidValidity: 0xffffffff,
      uid: 0xffffffff,
    );
    final page = _page(full, upserts: [_header(first)], tombstones: [last]);
    expect(page.imapRange, same(full));
    expect(full.mailbox, _mailbox);
    expect(full.uidValidity, 0xffffffff);
    expect(full.firstUid, 1);
    expect(full.lastUid, 0xffffffff);
    expect(page.upserts.single.remote, first);
    expect(page.tombstones.single, last);
    expect(
      _page(
        MailImapSyncRange(
          mailbox: _mailbox,
          uidValidity: 0xffffffff,
          firstUid: 0xffffffff,
          lastUid: 0xffffffff,
        ),
        upserts: [_header(last)],
      ).upserts.single.remote,
      last,
    );
  });

  for (final (label, validity, first, last) in <(String, int, int, int)>[
    ('zero UIDVALIDITY', 0, 1, 1),
    ('negative UIDVALIDITY', -1, 1, 1),
    ('overflow UIDVALIDITY', 0x100000000, 1, 1),
    ('zero first UID', 1, 0, 1),
    ('negative first UID', 1, -1, 1),
    ('overflow first UID', 1, 0x100000000, 0x100000000),
    ('zero last UID', 1, 1, 0),
    ('negative last UID', 1, 1, -1),
    ('overflow last UID', 1, 1, 0x100000000),
    ('reversed UIDs', 1, 100, 99),
  ]) {
    test('range rejects $label', () {
      expect(
        () => MailImapSyncRange(
          mailbox: _mailbox,
          uidValidity: validity,
          firstUid: first,
          lastUid: last,
        ),
        throwsArgumentError,
      );
    });
  }

  test('range scope must match the page even when the page is empty', () {
    for (final other in [
      MailMailboxId('Archive', account: _account),
      MailMailboxId(
        'INBOX',
        account: MailAccountId('other', profile: _profile),
      ),
      MailMailboxId(
        'INBOX',
        account: MailAccountId(
          'account',
          profile: MailProfileId('range-tests', hostId: 'other-host'),
        ),
      ),
    ]) {
      expect(
        () => _page(
          MailImapSyncRange(
            mailbox: other,
            uidValidity: 1,
            firstUid: 1,
            lastUid: 100,
          ),
        ),
        throwsArgumentError,
      );
    }
  });

  final range = MailImapSyncRange(
    mailbox: _mailbox,
    uidValidity: 7,
    firstUid: 100000,
    lastUid: 4000000000,
  );
  final invalid = <(String, MailRemoteIdentity)>[
    (
      'HTTPS identity',
      MailOpaqueIdentity(
        account: _account,
        provider: MailProviderKind.graph,
        value: 'opaque-message',
      ),
    ),
    (
      'different UIDVALIDITY',
      MailImapIdentity(mailbox: _mailbox, uidValidity: 8, uid: 100000),
    ),
    (
      'UID below range',
      MailImapIdentity(mailbox: _mailbox, uidValidity: 7, uid: 99999),
    ),
    (
      'UID above range',
      MailImapIdentity(mailbox: _mailbox, uidValidity: 7, uid: 4000000001),
    ),
    (
      'different mailbox',
      MailImapIdentity(
        mailbox: MailMailboxId('Archive', account: _account),
        uidValidity: 7,
        uid: 100000,
      ),
    ),
  ];
  for (final (label, remote) in invalid) {
    test('authoritative range rejects $label in upserts and tombstones', () {
      expect(
        () => _page(range, upserts: [_header(remote)]),
        throwsArgumentError,
      );
      expect(() => _page(range, tombstones: [remote]), throwsArgumentError);
    });
  }

  test('range pages retain immutable survivor and tombstone snapshots', () {
    final remote = MailImapIdentity(
      mailbox: _mailbox,
      uidValidity: 7,
      uid: 100000,
    );
    final headers = [_header(remote)];
    final tombstones = <MailRemoteIdentity>[];
    final page = _page(range, upserts: headers, tombstones: tombstones);
    headers.clear();
    tombstones.add(remote);
    expect(page.upserts, hasLength(1));
    expect(page.tombstones, isEmpty);
    expect(() => page.upserts.clear(), throwsUnsupportedError);
    expect(() => page.tombstones.add(remote), throwsUnsupportedError);
  });
}
