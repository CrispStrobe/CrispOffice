@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';

final class _Vault implements MailCredentialStore {
  _Vault(this.reference, this.secret);
  final MailCredentialReference reference;
  final MailBytes secret;
  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  ) async =>
      reference.account == this.reference.account &&
          reference.key == this.reference.key
      ? MailSuccess(
          MailCredentialRecord(reference: reference, opaqueData: secret),
        )
      : const MailSuccess(null);
  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async =>
      const MailSuccess(MailUnit.value);
  @override
  Future<MailResult<MailUnit>> delete(
    MailCredentialReference reference,
  ) async => const MailSuccess(MailUnit.value);
  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async =>
      const MailSuccess(MailUnit.value);
}

T _value<T>(MailResult<T> result) {
  if (result case MailFailure<T>(:final problem)) {
    fail('Live conversation operation failed: ${problem.code.name}');
  }
  return (result as MailSuccess<T>).value;
}

void main() {
  final login = Platform.environment['MBOX_LOGIN'];
  final password = Platform.environment['MBOX_PW'];
  test(
    'live IMAP header keeps one persisted cross-folder conversation key',
    () async {
      final profile = MailProfileId('live-conversations', hostId: 'live-test');
      final account = MailAccountId('mailbox', profile: profile);
      final reference = MailCredentialReference(account: account, key: 'imap');
      final provider = createMailImapProvider(
        configuration: MailImapConfiguration(
          account: account,
          endpoint: MailServerEndpoint(
            host: 'imap.mailbox.org',
            port: 993,
            tls: MailTlsMode.implicitTls,
          ),
          username: login!,
          credential: reference,
        ),
        credentialStore: _Vault(
          reference,
          MailBytes(Uint8List.fromList(utf8.encode(password!))),
        ),
        limits: const MailTransportLimits(
          maxPageSize: 20,
          maxDiscoveredUids: 100000,
          maxProtocolLineBytes: 1024 * 1024,
          maxResponseBytes: 128 * 1024 * 1024,
          operationTimeout: Duration(seconds: 60),
        ),
      );
      final session = MailAccountSession(account);
      final lease = session.begin();
      final directory = await Directory.systemTemp.createTemp(
        'live-conversations-',
      );
      final file = File('${directory.path}/mail.sqlite3');
      SqliteMailRepository? repository;
      try {
        var repo = _value(
          await SqliteMailRepository.open(
            executor: NativeDatabase(file),
            profile: profile,
          ),
        );
        repository = repo;
        _value(
          await repo.createAccount(
            MailStoreAccount(
              id: account,
              provider: MailProviderKind.imap,
              displayName: 'Live',
            ),
          ),
        );
        final boxes = _value(await provider.listMailboxes(lease));
        final inbox = boxes.firstWhere(
          (box) => box.id.value.toUpperCase() == 'INBOX',
        );
        final other = boxes.firstWhere(
          (box) =>
              box.id.value.toUpperCase() != 'INBOX' &&
              box.id.value.toUpperCase().contains('SENT'),
          orElse: () =>
              boxes.firstWhere((box) => box.id.value.toUpperCase() != 'INBOX'),
        );
        final page = _value(
          await provider.fetchHeaders(inbox.id, limit: 20, lease: lease),
        );
        final header = page.messages.firstWhere(
          (item) =>
              item.envelope.messageId != null ||
              item.envelope.inReplyTo != null ||
              item.envelope.references.isNotEmpty,
        );
        final cached = studioMailCachedHeader(header);
        final root = header.envelope.references.isNotEmpty
            ? header.envelope.references.first
            : header.envelope.inReplyTo ?? header.envelope.messageId!;
        final expected = MailConversationKey.fromEnvelope(
          header.envelope,
          fallbackId: cached.id.value,
        );
        _value(
          await repo.saveMailboxView(
            inbox,
            [cached],
            expectedRevision: null,
            hasMore: page.next != null,
            lease: lease,
          ),
        );
        final reply = MailHeaderRecord(
          id: MailMessageId('live-reply'),
          remote: MailImapIdentity(mailbox: other.id, uidValidity: 9, uid: 1),
          envelope: MailEnvelope(
            subject: 'Re: ${header.envelope.subject}',
            messageId: '<live-reply@example.test>',
            references: [root],
          ),
        );
        _value(
          await repo.saveMailboxView(
            other,
            [reply],
            expectedRevision: null,
            hasMore: false,
            lease: lease,
          ),
        );
        final inboxHeaders = _value(
          await repo.loadMailboxView(inbox.id),
        )!.headers;
        final otherHeaders = _value(
          await repo.loadMailboxView(other.id),
        )!.headers;
        expect(inboxHeaders.single.conversationId, expected);
        expect(otherHeaders.single.conversationId, expected);
        await repo.close();
        repository = null;

        repo = _value(
          await SqliteMailRepository.open(
            executor: NativeDatabase(file),
            profile: profile,
          ),
        );
        repository = repo;
        final reopened = _value(await repo.loadMailboxView(inbox.id))!.headers;
        expect(reopened.single.conversationId, expected);
      } finally {
        await repository?.close();
        await directory.delete(recursive: true);
        session.dispose();
      }
    },
    skip:
        login == null || login.isEmpty || password == null || password.isEmpty,
  );
}
