import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';

/// A read-only, session-only smoke probe. Passwords are prompted, never accepted
/// on the command line, written to disk, or included in error output.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 || arguments.length > 3) {
    stderr.writeln(
      'Usage: dart run example/ews_probe.dart '
      'https://exchange.example/EWS/Exchange.asmx '
      r'DOMAIN\username [mailbox@example.com]',
    );
    exitCode = 64;
    return;
  }
  final account = MailAccountId(
    'exchange-probe',
    profile: MailProfileId('session', hostId: 'quds-ews-probe'),
  );
  final reference = MailCredentialReference(account: account, key: 'session');
  late final MailEwsConfiguration configuration;
  try {
    configuration = MailEwsConfiguration(
      account: account,
      endpoint: Uri.parse(arguments[0]),
      username: arguments[1],
      mailboxAddress: arguments.length == 3 ? arguments[2] : null,
      credential: reference,
    );
  } on Object {
    stderr.writeln('Invalid HTTPS endpoint, login, or mailbox address.');
    exitCode = 64;
    return;
  }
  stderr.write('Exchange password: ');
  String? password;
  final echo = stdin.hasTerminal ? stdin.echoMode : null;
  try {
    if (echo != null) stdin.echoMode = false;
    password = stdin.readLineSync(encoding: utf8);
  } finally {
    if (echo != null) stdin.echoMode = echo;
    stderr.writeln();
  }
  if (password == null || password.isEmpty) {
    stderr.writeln('A password is required.');
    exitCode = 64;
    return;
  }
  final vault = _SessionVault(reference, password);
  password = null;
  final session = MailAccountSession(account);
  final cancellation = MailCancellationSource();
  final signals = ProcessSignal.sigint.watch().listen((_) {
    cancellation.cancel();
  });
  final provider = createMailEwsProvider(
    configuration: configuration,
    credentialStore: vault,
  );
  final lease = session.begin(cancellation: cancellation.token);
  try {
    final capabilities = await provider.capabilities(lease);
    if (capabilities case MailFailure<MailCapabilities>(:final problem)) {
      _failed(problem);
      return;
    }
    final folders = await provider.listMailboxes(lease);
    if (folders case MailFailure<List<MailMailbox>>(:final problem)) {
      _failed(problem);
      return;
    }
    final mailboxes = (folders as MailSuccess<List<MailMailbox>>).value;
    stdout.writeln('Authenticated. Found ${mailboxes.length} mail folders.');
    if (mailboxes.isNotEmpty) {
      final page = await provider.pullChanges(
        mailboxes.first.id,
        limit: 10,
        lease: lease,
      );
      if (page case MailFailure<MailSyncPage>(:final problem)) {
        _failed(problem);
        return;
      }
      final changes = (page as MailSuccess<MailSyncPage>).value;
      stdout.writeln(
        'Read-only sync: ${changes.upserts.length} message headers, '
        '${changes.tombstones.length} removals, more=${changes.hasMore}.',
      );
    }
    stdout.writeln('No message was sent or modified.');
  } on Object {
    stderr.writeln('Probe failed. No server text or credentials are logged.');
    exitCode = 1;
  } finally {
    session.dispose();
    vault.clear();
    await signals.cancel();
  }
}

void _failed(MailProblem problem) {
  stderr.writeln('EWS operation failed: ${problem.code.name}.');
  exitCode = 1;
}

final class _SessionVault implements MailCredentialStore {
  _SessionVault(this.reference, String password)
    : _bytes = Uint8List.fromList(utf8.encode(password));

  final MailCredentialReference reference;
  final Uint8List _bytes;
  bool _cleared = false;

  void clear() {
    _cleared = true;
    _bytes.fillRange(0, _bytes.length, 0);
  }

  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference requested,
  ) async => MailSuccess(
    _cleared ||
            requested.account != reference.account ||
            requested.key != reference.key
        ? null
        : MailCredentialRecord(
            reference: reference,
            opaqueData: MailBytes(_bytes),
          ),
  );

  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async =>
      const MailFailure(MailProblem(MailProblemCode.unsupported));

  @override
  Future<MailResult<MailUnit>> delete(MailCredentialReference requested) async {
    if (requested.account != reference.account ||
        requested.key != reference.key) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    clear();
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async {
    if (account != reference.account) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    clear();
    return const MailSuccess(MailUnit.value);
  }
}
