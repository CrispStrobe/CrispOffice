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
    fail('Live rule operation failed: ${problem.code.name}');
  }
  return (result as MailSuccess<T>).value;
}

void main() {
  final login = Platform.environment['MBOX_LOGIN'];
  final password = Platform.environment['MBOX_PW'];
  test(
    'live IMAP headers drive persisted ordered local-tag rules',
    () async {
      final profile = MailProfileId('live-rules', hostId: 'live-test');
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
        final address = header.envelope.from.first.address;
        final cached = studioMailCachedHeader(header);
        _value(
          await repository.createAccount(
            MailStoreAccount(
              id: account,
              provider: MailProviderKind.imap,
              displayName: 'Live',
            ),
          ),
        );
        _value(
          await repository.saveMailboxView(
            inbox,
            [cached],
            expectedRevision: null,
            hasMore: page.next != null,
            lease: lease,
          ),
        );
        final rule = MailRule.parse(
          id: 'live-rule',
          name: 'Live sender',
          query: 'from:$address',
          addTags: const ['LiveRule'],
        );
        _value(
          await repository.replaceMailRules(account, [rule], lease: lease),
        );
        expect(_value(await repository.listMailRules(account)).single, rule);

        final matches = _value(
          await repository.searchCachedHeaders(account, rule.query),
        );
        expect(
          matches.hits.map((hit) => hit.header.id.value),
          contains(cached.id.value),
        );
        final set = MailRuleSet.parse([rule]);
        final current = _value(
          await repository.loadMessageTags(account, cached.id),
        );
        final next = set.applyTags(
          matchedRuleIds: {rule.id},
          currentTags: current.map((tag) => tag.name),
        );
        expect(next.map((tag) => tag.name), ['LiveRule']);
        _value(
          await repository.setMessageTagsBatch(account, {
            cached.id: next.map((tag) => tag.name),
          }, lease: lease),
        );
        final tagged = _value(
          await repository.searchCachedHeaders(account, 'tag:liverule'),
        );
        expect(tagged.hits.single.header.id, cached.id);

        final second = _value(
          await repository.loadMessageTags(account, cached.id),
        );
        expect(second.map((tag) => tag.name), ['LiveRule']);
        expect(
          set
              .applyTags(
                matchedRuleIds: {rule.id},
                currentTags: second.map((tag) => tag.name),
              )
              .map((tag) => tag.name),
          ['LiveRule'],
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
