import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';

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
    throw StateError('Mail operation failed: ${problem.code.name}');
  }
  return (result as MailSuccess<T>).value;
}

Future<void> main() async {
  final login = Platform.environment['MBOX_LOGIN'];
  final password = Platform.environment['MBOX_PW'];
  if (login == null || login.isEmpty || password == null || password.isEmpty) {
    stderr.writeln('MBOX_LOGIN and MBOX_PW are required.');
    exitCode = 2;
    return;
  }

  final profile = MailProfileId('live-body-search', hostId: 'live-tool');
  final account = MailAccountId('mailbox', profile: profile);
  final reference = MailCredentialReference(account: account, key: 'imap');
  final vault = _Vault(
    reference,
    MailBytes(Uint8List.fromList(utf8.encode(password))),
  );
  final provider = createMailImapProvider(
    configuration: MailImapConfiguration(
      account: account,
      endpoint: MailServerEndpoint(
        host: 'imap.mailbox.org',
        port: 993,
        tls: MailTlsMode.implicitTls,
      ),
      username: login,
      credential: reference,
    ),
    credentialStore: vault,
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
      (mailbox) =>
          mailbox.id.value.toUpperCase() == 'INBOX' ||
          mailbox.displayName.toUpperCase() == 'INBOX',
      orElse: () => mailboxes.first,
    );
    final page = _value(
      await provider.fetchHeaders(inbox.id, limit: 10, lease: lease),
    );
    if (page.messages.isEmpty) {
      throw StateError('The live mailbox returned no headers.');
    }

    MailMessage? message;
    MailHeaderRecord? header;
    for (final candidate in page.messages) {
      final candidateMessage = _value(
        await provider.fetchMessage(
          candidate.remote,
          budget: const MailReadBudget(),
          lease: lease,
        ),
      );
      final plain = candidateMessage.body.plainText;
      if (plain != null && plain.trim().isNotEmpty) {
        message = candidateMessage;
        header = candidate;
        break;
      }
    }
    if (message == null || header == null) {
      throw StateError(
        'No readable plain-text body was found in the newest headers.',
      );
    }

    final selectedHeader = header;
    final body = message.body.plainText!;
    final line = body
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .firstWhere(
          (value) => value.length >= 8 && value.contains(RegExp(r'[A-Za-z]')),
          orElse: () => body.trim(),
        );
    final term = (line.length > 40 ? line.substring(0, 40) : line)
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"');
    if (term.isEmpty) {
      throw StateError(
        'The live message body did not contain a searchable phrase.',
      );
    }

    final repository = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.memory(),
        profile: profile,
      ),
    );
    try {
      _value(
        await repository.createAccount(
          MailStoreAccount(
            id: account,
            provider: MailProviderKind.imap,
            displayName: 'Live mailbox',
          ),
        ),
      );
      _value(
        await repository.saveMailboxView(
          inbox,
          [selectedHeader],
          expectedRevision: null,
          hasMore: page.next != null,
          lease: lease,
        ),
      );
      _value(
        await repository.cacheMessage(account, selectedHeader.id, message),
      );
      final hit = _value(
        await repository.searchCachedHeaders(account, 'body:"$term"'),
      );
      if (hit.hits.length != 1 ||
          hit.hits.single.header.id != selectedHeader.id) {
        throw StateError('Live body search did not return the cached message.');
      }
      if (!selectedHeader.envelope.subject.toLowerCase().contains(
        term.toLowerCase(),
      )) {
        final headerOnly = _value(
          await repository.searchCachedHeaders(account, '"$term"'),
        );
        if (headerOnly.hits.any(
          (result) => result.header.id == selectedHeader.id,
        )) {
          throw StateError(
            'A bare term unexpectedly searched the retained body.',
          );
        }
      }
      stdout.writeln(
        'Live IMAP body search passed: account ${account.value}, '
        'mailbox ${inbox.displayName}, subject length '
        '${selectedHeader.envelope.subject.length}, '
        'body length ${body.length}, scanned ${hit.scannedCount}.',
      );
    } finally {
      await repository.close();
    }
  } finally {
    session.dispose();
  }
}
