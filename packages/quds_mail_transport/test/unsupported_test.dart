@TestOn('js')
library;

import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'account',
  profile: MailProfileId('profile', hostId: 'web-host.test'),
);
final _mailbox = MailMailboxId('INBOX', account: _account);
final _identity = MailImapIdentity(mailbox: _mailbox, uidValidity: 1, uid: 1);

MailImapConfiguration _configuration() => MailImapConfiguration(
  account: _account,
  endpoint: MailServerEndpoint(host: 'imap.example.test', port: 993),
  username: 'reader@example.test',
  credential: MailCredentialReference(account: _account, key: 'host-vault-ref'),
);

void main() {
  test(
    'public JavaScript entry returns typed unsupported for every provider method',
    () async {
      final vault = _UnexpectedVault();
      final codec = _UnexpectedCodec();
      final provider = createMailImapProvider(
        configuration: _configuration(),
        credentialStore: vault,
        codec: codec,
      );
      expect(provider.account, _account);
      final lease = MailAccountSession(_account).begin();
      _unsupported(await provider.capabilities(lease));
      _unsupported(
        await (provider as MailFlagObserver).observeFlags(
          _identity,
          lease: lease,
        ),
      );
      _unsupported(await provider.listMailboxes(lease));
      _unsupported(
        await provider.fetchHeaders(_mailbox, limit: 1, lease: lease),
      );
      _unsupported(
        await provider.fetchMessage(
          _identity,
          budget: const MailReadBudget.preview(),
          lease: lease,
        ),
      );
      _unsupported(
        await provider.pullChanges(_mailbox, limit: 1, lease: lease),
      );
      for (final operation in <MailOperation>[
        MailSetRead(id: 'read', message: _identity, read: true),
        MailSetFlagged(id: 'flag', message: _identity, flagged: true),
        MailMove(
          id: 'move',
          message: _identity,
          destination: MailMailboxId('Archive', account: _account),
        ),
        MailDelete(id: 'delete', message: _identity),
      ]) {
        final result = await provider.apply(operation, lease);
        _unsupported(result);
        expect(
          MailBulkFlagAttempt.fromResult(result).outcome,
          MailBulkFlagOutcome.failed,
        );
      }
      expect(vault.calls, 0);
      expect(codec.calls, 0);
    },
  );

  test(
    'default public factory remains unsupported without requiring a codec',
    () async {
      final vault = _UnexpectedVault();
      final provider = createMailImapProvider(
        configuration: _configuration(),
        credentialStore: vault,
      );
      _unsupported(
        await provider.fetchMessage(
          _identity,
          budget: const MailReadBudget(),
          lease: MailAccountSession(_account).begin(),
        ),
      );
      expect(vault.calls, 0);
    },
  );

  test(
    'unsupported factory still validates bounds without accessing host services',
    () {
      final vault = _UnexpectedVault();
      final codec = _UnexpectedCodec();
      expect(
        () => createMailImapProvider(
          configuration: _configuration(),
          credentialStore: vault,
          codec: codec,
          limits: const MailTransportLimits(operationTimeout: Duration.zero),
        ),
        throwsArgumentError,
      );
      expect(vault.calls, 0);
      expect(codec.calls, 0);
    },
  );
}

void _unsupported<T>(MailResult<T> result) {
  expect(result, isA<MailFailure<T>>());
  final problem = (result as MailFailure<T>).problem;
  expect(problem.code, MailProblemCode.unsupported);
  expect(problem.retryAfter, isNull);
}

final class _UnexpectedCodec implements MailCodec {
  int calls = 0;

  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) {
    calls++;
    throw StateError('Unsupported transport must not invoke a message codec.');
  }
}

final class _UnexpectedVault implements MailCredentialStore {
  int calls = 0;

  Never _unexpected() {
    calls++;
    throw StateError('Unsupported transport must not access host credentials.');
  }

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
