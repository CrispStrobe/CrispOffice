@TestOn('js')
library;

import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:test/test.dart';

final class _UnavailableHost implements MailCredentialStore, MailCodec {
  int calls = 0;
  Never _unexpected() {
    calls++;
    throw StateError('Browser EWS must not touch vault or codec');
  }

  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) => _unexpected();
  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  ) async => _unexpected();
  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async =>
      _unexpected();
  @override
  Future<MailResult<MailUnit>> delete(
    MailCredentialReference reference,
  ) async => _unexpected();
  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async =>
      _unexpected();
}

void main() {
  test(
    'public browser EWS import and every operation are vault-free unsupported',
    () async {
      final account = MailAccountId(
        'exchange',
        profile: MailProfileId('profile', hostId: 'browser'),
      );
      final mailbox = MailMailboxId('folder', account: account);
      final remote = MailOpaqueIdentity(
        account: account,
        provider: MailProviderKind.ews,
        value: 'item',
      );
      final host = _UnavailableHost();
      final provider = createMailEwsProvider(
        configuration: MailEwsConfiguration(
          account: account,
          endpoint: Uri.https('exchange.example.test', '/EWS/Exchange.asmx'),
          username: 'reader',
          credential: MailCredentialReference(account: account, key: 'vault'),
        ),
        credentialStore: host,
        codec: host,
      );
      final lease = MailAccountSession(account).begin();
      void unsupported<T>(MailResult<T> result) => expect(
        (result as MailFailure<T>).problem.code,
        MailProblemCode.unsupported,
      );
      unsupported(await provider.capabilities(lease));
      unsupported(
        await (provider as MailFlagObserver).observeFlags(remote, lease: lease),
      );
      unsupported(await provider.listMailboxes(lease));
      unsupported(
        await (provider as MailMembershipObserver).observeMembership(
          remote,
          lease: lease,
        ),
      );
      unsupported(await provider.fetchHeaders(mailbox, limit: 1, lease: lease));
      unsupported(await provider.pullChanges(mailbox, limit: 1, lease: lease));
      unsupported(
        await provider.fetchMessage(
          remote,
          budget: const MailReadBudget(),
          lease: lease,
        ),
      );
      for (final command in <MailOperation>[
        MailSetRead(id: 'read', message: remote, read: true),
        MailSetFlagged(id: 'flag', message: remote, flagged: true),
        MailMove(id: 'move', message: remote, destination: mailbox),
        MailDelete(id: 'delete', message: remote),
      ]) {
        final result = await provider.apply(command, lease);
        unsupported(result);
        expect(
          MailBulkFlagAttempt.fromResult(result).outcome,
          MailBulkFlagOutcome.failed,
        );
      }
      final sent = await provider.submit(
        MailPreparedMessage(
          account: account,
          draftId: 'draft',
          draftRevision: 0,
          wire: MailBytes(Uint8List.fromList([1])),
          envelope: MailTransportEnvelope(
            sender: 'a@b.test',
            recipients: ['c@d.test'],
          ),
        ),
        attemptId: 'attempt',
        lease: lease,
      );
      expect(sent.outcome, MailSubmissionOutcome.rejected);
      expect(sent.problem?.code, MailProblemCode.unsupported);
      expect(host.calls, 0);
    },
  );
}
