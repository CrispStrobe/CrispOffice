@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

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
    fail('Live mail operation failed: ${problem.code.name}');
  }
  return (result as MailSuccess<T>).value;
}

void main() {
  final login = Platform.environment['MBOX_LOGIN'];
  final password = Platform.environment['MBOX_PW'];
  testWidgets(
    'live IMAP HTML message renders through the safe rich view',
    (tester) async {
      MailParseResult? result;
      await tester.runAsync(() async {
        final profile = MailProfileId('live-html-render', hostId: 'live-test');
        final account = MailAccountId('mailbox', profile: profile);
        final reference = MailCredentialReference(
          account: account,
          key: 'imap',
        );
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
            maxPageSize: 100,
            maxDiscoveredUids: 100000,
            maxProtocolLineBytes: 1024 * 1024,
            maxResponseBytes: 128 * 1024 * 1024,
            operationTimeout: Duration(seconds: 60),
          ),
        );
        final session = MailAccountSession(account);
        final lease = session.begin();
        try {
          final mailboxes = _value(await provider.listMailboxes(lease));
          final inbox = mailboxes.firstWhere(
            (box) =>
                box.id.value.toUpperCase() == 'INBOX' ||
                box.displayName.toUpperCase() == 'INBOX',
            orElse: () => mailboxes.first,
          );
          final page = _value(
            await provider.fetchHeaders(inbox.id, limit: 20, lease: lease),
          );
          for (final header in page.messages) {
            final message = _value(
              await provider.fetchMessage(
                header.remote,
                budget: const MailReadBudget(),
                lease: lease,
              ),
            );
            final parse = MailParseResult(
              status: MailParseStatus.complete,
              message: message,
            );
            final presentation = buildMailPresentation(parse, preferHtml: true);
            if (presentation.usedHtml && presentation.safeHtml != null) {
              expect(presentation.safeHtml, isNotEmpty);
              expect(presentation.safeHtml, isNot(contains('<script')));
              expect(presentation.safeHtml, isNot(contains('javascript:')));
              expect(presentation.safeHtml, isNot(contains('onerror=')));
              expect(
                presentation.safeHtml!.contains(RegExp(r'<img[^>]+src=')),
                isFalse,
              );
              result = parse;
              break;
            }
          }
        } finally {
          session.dispose();
        }
      });
      expect(result, isNotNull, reason: 'No rendered HTML message found');
      final controller = MailReaderController(
        result: result!,
        preferHtml: true,
      );
      addTearDown(controller.dispose);
      expect(controller.presentation.safeHtml, isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MailMessageView(controller: controller, richHtml: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mail-rich-body')), findsOneWidget);
    },
    skip:
        login == null || login.isEmpty || password == null || password.isEmpty,
  );
}
