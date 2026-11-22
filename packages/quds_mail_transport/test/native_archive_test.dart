import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:test/test.dart';

import 'support/imap_fixture.dart';

void main() {
  test('Archive resolves the unique selectable special-use folder', () async {
    final fixture = ImapFixture()
      ..mailboxResponses = [
        '* LIST () "/" "INBOX"',
        '* LIST () "/" "Archive"',
        '* LIST (\\All) "/" "All Mail"',
        '* LIST (\\Archive \\Noselect) "/" "Container"',
        '* LIST (\\Archive \\NonExistent) "/" "Removed"',
        '* LIST (\\Archive) "/" "Archiv/2026"',
      ];
    final result = await fixture.provider().resolveArchiveDestination(
      MailAccountSession(fixture.account).begin(),
    );
    final folder = (result as MailSuccess<MailMailbox>).value;
    expect(folder.id, MailMailboxId('Archiv/2026', account: fixture.account));
    expect(folder.displayName, '2026');
    expect(
      fixture.commands.where((command) => command.startsWith('LIST ')),
      hasLength(1),
    );
    expect(
      fixture.commands.any(
        (command) =>
            command.startsWith('SELECT ') || command.startsWith('UID '),
      ),
      isFalse,
    );
  });

  for (final responses in [
    ['* LIST () "/" "Archive"'],
    ['* LIST (\\All) "/" "All Mail"'],
    ['* LIST (\\Archive \\Noselect) "/" "Container"'],
    ['* LIST (\\Archive) "/" "First"', '* LIST (\\Archive) "/" "Second"'],
  ]) {
    test('Archive refuses missing or ambiguous metadata: $responses', () async {
      final fixture = ImapFixture()..mailboxResponses = responses;
      final result = await fixture.provider().resolveArchiveDestination(
        MailAccountSession(fixture.account).begin(),
      );
      expect(
        (result as MailFailure<MailMailbox>).problem.code,
        MailProblemCode.unsupported,
      );
      expect(result.problem.mutationMayHaveOccurred, isFalse);
      expect(
        fixture.commands.where((command) => command.startsWith('UID ')),
        isEmpty,
      );
    });
  }

  test('Archive cannot reuse an ambiguous duplicate folder identity', () async {
    final fixture = ImapFixture()
      ..mailboxResponses = [
        '* LIST () "/" "Same"',
        '* LIST (\\Archive) "/" "Same"',
      ];
    final result = await fixture.provider().resolveArchiveDestination(
      MailAccountSession(fixture.account).begin(),
    );
    expect(
      (result as MailFailure<MailMailbox>).problem.code,
      MailProblemCode.providerFailure,
    );
  });

  test('Archive discovery honors mailbox limits', () async {
    final fixture = ImapFixture()
      ..mailboxResponses = [
        '* LIST () "/" "INBOX"',
        '* LIST (\\Archive) "/" "Archiv"',
      ];
    final result = await fixture
        .provider(limits: const MailTransportLimits(maxMailboxes: 1))
        .resolveArchiveDestination(MailAccountSession(fixture.account).begin());
    expect(
      (result as MailFailure<MailMailbox>).problem.code,
      MailProblemCode.quotaExceeded,
    );
  });

  test('Archive without MOVE does not invent COPY/delete behavior', () async {
    final fixture = ImapFixture(supportsMove: false);
    final result = await fixture.provider().resolveArchiveDestination(
      MailAccountSession(fixture.account).begin(),
    );
    expect(
      (result as MailFailure<MailMailbox>).problem.code,
      MailProblemCode.unsupported,
    );
    expect(
      fixture.commands.where((command) => command.startsWith('LIST ')),
      isEmpty,
    );
  });

  test('foreign and retired resolver leases access no credentials', () async {
    final fixture = ImapFixture();
    final provider = fixture.provider();
    final foreign = MailAccountId('other', profile: fixture.account.profile);
    final foreignResult = await provider.resolveArchiveDestination(
      MailAccountSession(foreign).begin(),
    );
    expect(
      (foreignResult as MailFailure<MailMailbox>).problem.code,
      MailProblemCode.invalidInput,
    );
    final session = MailAccountSession(fixture.account);
    final lease = session.begin();
    session.dispose();
    final staleResult = await provider.resolveArchiveDestination(lease);
    expect(
      (staleResult as MailFailure<MailMailbox>).problem.code,
      MailProblemCode.staleOperation,
    );
    expect(fixture.credentials.loads, 0);
    expect(fixture.commands, isEmpty);
  });

  test('a late Archive folder reply cannot outlive the account', () async {
    final fixture = ImapFixture()
      ..mailboxResponses = ['* LIST (\\Archive) "/" "Archiv"'];
    final started = Completer<void>();
    final gate = Completer<void>();
    fixture.beforeReply = (command) async {
      if (!command.startsWith('LIST ')) return;
      started.complete();
      await gate.future;
    };
    final session = MailAccountSession(fixture.account);
    final pending = fixture.provider().resolveArchiveDestination(
      session.begin(),
    );
    await started.future;
    session.dispose();
    gate.complete();
    final result = await pending;
    expect(
      (result as MailFailure<MailMailbox>).problem.code,
      MailProblemCode.staleOperation,
    );
    expect(result.problem.mutationMayHaveOccurred, isFalse);
  });

  test(
    'Gmail Archive operation is unsupported before IMAP credentials',
    () async {
      final fixture = ImapFixture();
      final result = await fixture.provider().apply(
        MailArchive(
          id: 'archive',
          message: MailImapIdentity(
            mailbox: fixture.mailbox,
            uidValidity: 41,
            uid: 1,
          ),
        ),
        MailAccountSession(fixture.account).begin(),
      );
      expect(
        (result as MailFailure<MailUnit>).problem.code,
        MailProblemCode.unsupported,
      );
      expect(result.problem.mutationMayHaveOccurred, isFalse);
      expect(fixture.credentials.loads, 0);
      expect(fixture.commands, isEmpty);
    },
  );
}
