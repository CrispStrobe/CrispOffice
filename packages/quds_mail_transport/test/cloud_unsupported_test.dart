@TestOn('js')
library;

import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:test/test.dart';

final class _Host implements MailCloudTokenSource, MailCodec {
  int calls = 0;
  Never unexpected() {
    calls++;
    throw StateError('The browser must not access a native credential host.');
  }

  @override
  Future<MailResult<MailCloudAccessToken>> accessToken(
    MailOperationLease lease, {
    bool forceRefresh = false,
  }) async => unexpected();

  @override
  void dispose() => unexpected();

  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) => unexpected();
}

void main() {
  for (final service in MailCloudService.values) {
    test(
      '${service.name} public browser boundary is explicitly unsupported',
      () async {
        final account = MailAccountId(
          'cloud',
          profile: MailProfileId('test', hostId: 'browser'),
        );
        final lease = MailAccountSession(account).begin();
        final host = _Host();
        final provider = createMailCloudProvider(
          configuration: MailCloudConfiguration(
            account: account,
            service: service,
            mailboxAddress: 'owner@example.test',
          ),
          tokenSource: host,
          codec: host,
        );
        void unsupported<T>(MailResult<T> result) => expect(
          (result as MailFailure<T>).problem.code,
          MailProblemCode.unsupported,
        );
        final folder = MailMailboxId('folder', account: account);
        final identity = MailOpaqueIdentity(
          account: account,
          provider: service == MailCloudService.gmail
              ? MailProviderKind.gmail
              : MailProviderKind.graph,
          value: 'message',
        );
        unsupported(await provider.capabilities(lease));
        unsupported(
          await (provider as MailFlagObserver).observeFlags(
            identity,
            lease: lease,
          ),
        );
        unsupported(await provider.listMailboxes(lease));
        unsupported(
          await (provider as MailMembershipObserver).observeMembership(
            identity,
            lease: lease,
          ),
        );
        unsupported(
          await provider.fetchHeaders(folder, limit: 1, lease: lease),
        );
        unsupported(await provider.pullChanges(folder, limit: 1, lease: lease));
        unsupported(
          await provider.fetchMessage(
            identity,
            budget: const MailReadBudget(),
            lease: lease,
          ),
        );
        for (final operation in <MailOperation>[
          MailSetRead(id: 'read', message: identity, read: true),
          MailSetFlagged(id: 'flag', message: identity, flagged: true),
          MailMove(id: 'move', message: identity, destination: folder),
          MailDelete(id: 'delete', message: identity),
        ]) {
          final result = await provider.apply(operation, lease);
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
              sender: 'owner@example.test',
              recipients: ['recipient@example.test'],
            ),
          ),
          attemptId: 'attempt',
          lease: lease,
        );
        expect(sent.outcome, MailSubmissionOutcome.rejected);
        expect(sent.problem?.code, MailProblemCode.unsupported);
        unsupported(
          await authorizeMailCloud(
            configuration: MailOAuthConfiguration(
              service: service,
              clientId: 'client',
            ),
            account: account,
            openBrowser: (_) async => host.unexpected(),
            lease: lease,
          ),
        );
        provider.dispose();
        expect(host.calls, 0);
      },
    );
  }
}
