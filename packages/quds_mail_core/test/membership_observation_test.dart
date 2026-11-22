import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('membership-observation', hostId: 'mail-tests');
final _account = MailAccountId('account', profile: _profile);
final _otherAccount = MailAccountId('other', profile: _profile);
final _inbox = MailMailboxId('INBOX', account: _account);
final _imap = MailImapIdentity(mailbox: _inbox, uidValidity: 7, uid: 19);

MailOpaqueIdentity _opaque(MailProviderKind provider) => MailOpaqueIdentity(
  account: _account,
  provider: provider,
  value: 'exact-message',
);

void main() {
  for (final deleted in [false, true]) {
    test('IMAP preserves exact generation and Deleted=$deleted', () {
      final observation = MailMembershipObservation.imap(
        identity: _imap,
        isDeleted: deleted,
      );
      expect(observation.kind, MailMembershipObservationKind.present);
      expect(observation.identity, _imap);
      expect(observation.mailboxes, [_inbox]);
      expect(observation.isDeleted, deleted);
      expect(observation.deletionMailbox, isNull);
      expect(() => observation.mailboxes.clear(), throwsUnsupportedError);
    });
  }

  test('Gmail snapshots all exact labels without retaining mutable input', () {
    final trash = MailMailboxId('TRASH', account: _account);
    final labels = [_inbox, trash];
    final observation = MailMembershipObservation.folders(
      identity: _opaque(MailProviderKind.gmail),
      mailboxes: labels,
      deletionMailbox: trash,
    );
    labels.clear();
    expect(observation.mailboxes, [_inbox, trash]);
    expect(observation.isDeleted, isTrue);
    expect(observation.deletionMailbox, trash);
  });

  test('Gmail empty labels remain a complete empty observation', () {
    final observation = MailMembershipObservation.folders(
      identity: _opaque(MailProviderKind.gmail),
      mailboxes: const [],
      deletionMailbox: MailMailboxId('TRASH', account: _account),
    );
    expect(observation.kind, MailMembershipObservationKind.present);
    expect(observation.mailboxes, isEmpty);
    expect(observation.isDeleted, isFalse);
  });

  for (final provider in [MailProviderKind.graph, MailProviderKind.ews]) {
    test('$provider current parent does not invent Deleted Items identity', () {
      final observation = MailMembershipObservation.folders(
        identity: _opaque(provider),
        mailboxes: [_inbox],
      );
      expect(observation.isDeleted, isNull);
      expect(observation.mailboxes, [_inbox]);
    });
    for (final deleted in [false, true]) {
      test('$provider uses resolved Deleted Items membership=$deleted', () {
        final trash = MailMailboxId('opaque-deleted-folder', account: _account);
        final observation = MailMembershipObservation.folders(
          identity: _opaque(provider),
          mailboxes: [deleted ? trash : _inbox],
          deletionMailbox: trash,
        );
        expect(observation.isDeleted, deleted);
      });
    }
    for (final count in [0, 2]) {
      test('$provider refuses $count current parent folders', () {
        expect(
          () => MailMembershipObservation.folders(
            identity: _opaque(provider),
            mailboxes: [
              for (var i = 0; i < count; i++)
                MailMailboxId('folder-$i', account: _account),
            ],
          ),
          throwsArgumentError,
        );
      });
    }
  }

  for (final identity in [
    _imap,
    _opaque(MailProviderKind.gmail),
    _opaque(MailProviderKind.graph),
    _opaque(MailProviderKind.ews),
  ]) {
    test(
      '${identity.provider} missing retains only the requested identity',
      () {
        final observation = MailMembershipObservation.missing(
          identity: identity,
        );
        expect(observation.identity, identity);
        expect(observation.kind, MailMembershipObservationKind.missing);
        expect(observation.mailboxes, isEmpty);
        expect(observation.isDeleted, isNull);
        expect(observation.deletionMailbox, isNull);
      },
    );
  }

  test(
    'changed generation retains original identity with no replacement UID',
    () {
      final observation = MailMembershipObservation.identityChanged(
        identity: _imap,
      );
      expect(observation.identity, _imap);
      expect(observation.kind, MailMembershipObservationKind.identityChanged);
      expect(observation.mailboxes, isEmpty);
      expect(observation.isDeleted, isNull);
    },
  );

  for (final invalid in [
    'foreign folder',
    'duplicate folder',
    'foreign deletion',
    'gmail deletion',
  ]) {
    test('refuses $invalid evidence', () {
      expect(
        () => MailMembershipObservation.folders(
          identity: _opaque(MailProviderKind.gmail),
          mailboxes: [
            _inbox,
            if (invalid == 'foreign folder')
              MailMailboxId('folder', account: _otherAccount),
            if (invalid == 'duplicate folder') _inbox,
          ],
          deletionMailbox: switch (invalid) {
            'foreign deletion' => MailMailboxId(
              'TRASH',
              account: _otherAccount,
            ),
            'gmail deletion' => MailMailboxId('trash', account: _account),
            _ => null,
          },
        ),
        throwsArgumentError,
      );
    });
  }

  test(
    'refuses unsupported JMAP provider instead of implying implemented recovery',
    () {
      expect(
        () => MailMembershipObservation.missing(
          identity: _opaque(MailProviderKind.jmap),
        ),
        throwsArgumentError,
      );
    },
  );

  for (final invalid in [
    'mailbox count',
    'identifier',
    'metadata',
    'message identifier',
  ]) {
    test('bounds $invalid before evidence can be retained', () {
      expect(
        () => MailMembershipObservation.folders(
          identity: invalid == 'message identifier'
              ? MailOpaqueIdentity(
                  account: _account,
                  provider: MailProviderKind.gmail,
                  value: 'x' * 2049,
                )
              : _opaque(MailProviderKind.gmail),
          mailboxes: switch (invalid) {
            'mailbox count' => [
              for (var i = 0; i < 1001; i++)
                MailMailboxId('label-$i', account: _account),
            ],
            'identifier' => [MailMailboxId('x' * 2049, account: _account)],
            'metadata' => [
              for (var i = 0; i < 100; i++)
                MailMailboxId('$i-${'x' * 1024}', account: _account),
            ],
            _ => [_inbox],
          },
        ),
        throwsArgumentError,
      );
    });
  }
}
