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
    fail('Live tag operation failed: ${problem.code.name}');
  }
  return (result as MailSuccess<T>).value;
}

void main() {
  final login = Platform.environment['MBOX_LOGIN'];
  final password = Platform.environment['MBOX_PW'];
  test(
    'live IMAP header tags persist and search locally',
    () async {
      final profile = MailProfileId('live-tags', hostId: 'live-test');
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
      final repository = _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase.memory(),
          profile: profile,
        ),
      );
      try {
        final boxes = _value(await provider.listMailboxes(lease));
        final inbox = boxes.firstWhere(
          (box) => box.id.value.toUpperCase() == 'INBOX',
        );
        final page = _value(
          await provider.fetchHeaders(inbox.id, limit: 5, lease: lease),
        );
        final header = page.messages.first;
        _value(
          await repository.createAccount(
            MailStoreAccount(
              id: account,
              provider: MailProviderKind.imap,
              displayName: 'Live',
            ),
          ),
        );
        final cached = studioMailCachedHeader(header);
        _value(
          await repository.saveMailboxView(
            inbox,
            [cached],
            expectedRevision: null,
            hasMore: page.next != null,
            lease: lease,
          ),
        );
        final cachedId = cached.id;
        _value(
          await repository.setMessageTags(account, cachedId, [
            'Live',
            'Parity',
          ]),
        );
        final loaded = _value(
          await repository.loadMessageTags(account, cachedId),
        );
        expect(loaded.map((tag) => tag.name), ['Live', 'Parity']);
        final view = _value(await repository.loadMailboxView(inbox.id))!;
        expect(view.headers.single.tags, ['Live', 'Parity']);
        final result = _value(
          await repository.searchCachedHeaders(account, 'tag:live'),
        );
        expect(result.hits.single.header.id, cachedId);
        expect(result.hits.single.header.tags, ['Live', 'Parity']);
        expect(
          _value(await repository.searchCachedHeaders(account, 'tag:liv')).hits,
          isEmpty,
        );
      } finally {
        await repository.close();
        session.dispose();
      }
    },
    skip:
        login == null || login.isEmpty || password == null || password.isEmpty,
  );
}
