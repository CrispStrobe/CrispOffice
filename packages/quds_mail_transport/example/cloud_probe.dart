import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';

/// Read-only desktop sign-in/connection probe. No sends or mailbox writes.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 3 ||
      arguments.length > 4 ||
      !const {'gmail', 'microsoft365'}.contains(arguments.first)) {
    stderr.writeln(
      'Usage: dart run example/cloud_probe.dart '
      'gmail|microsoft365 CLIENT_ID MAILBOX [TENANT]',
    );
    exitCode = 64;
    return;
  }
  final service = arguments.first == 'gmail'
      ? MailCloudService.gmail
      : MailCloudService.microsoft365;
  final account = MailAccountId(
    'read-only-probe',
    profile: MailProfileId('cloud-probe', hostId: 'crispoffice'),
  );
  final session = MailAccountSession(account);
  final cancellation = MailCancellationSource();
  final interrupt = ProcessSignal.sigint.watch().listen((_) {
    cancellation.cancel();
    session.invalidate();
  });
  MailCloudTokenSource? tokens;
  MailCloudProvider? provider;
  void log(MailCloudLogEvent event) =>
      stdout.writeln(jsonEncode(event.toJson()));

  T value<T>(MailResult<T> result) => switch (result) {
    MailSuccess<T>(:final value) => value,
    MailFailure<T>(:final problem) => throw problem,
  };

  try {
    final registration = MailOAuthConfiguration(
      service: service,
      clientId: arguments[1],
      tenant: arguments.length == 4 ? arguments[3] : 'common',
      // Optional Google desktop registration metadata stays outside argv/logs.
      clientSecret: service == MailCloudService.gmail
          ? Platform.environment['CRISPOFFICE_GOOGLE_DESKTOP_CLIENT_SECRET']
          : null,
    );
    final configuration = MailCloudConfiguration(
      account: account,
      service: service,
      mailboxAddress: arguments[2],
    );
    final lease = session.begin(cancellation: cancellation.token);
    stdout.writeln(
      'Opening the system browser for read-only connection checks.',
    );
    tokens = value(
      await authorizeMailCloud(
        configuration: registration,
        account: account,
        lease: lease,
        openBrowser: (uri) async {
          final String command;
          final List<String> args;
          if (Platform.isMacOS) {
            command = 'open';
            args = [uri.toString()];
          } else if (Platform.isWindows) {
            command = 'rundll32';
            args = ['url.dll,FileProtocolHandler', uri.toString()];
          } else if (Platform.isLinux) {
            command = 'xdg-open';
            args = [uri.toString()];
          } else {
            return false;
          }
          final opened = await Process.run(command, args, runInShell: false);
          return opened.exitCode == 0;
        },
        log: log,
      ),
    );
    provider = createMailCloudProvider(
      configuration: configuration,
      tokenSource: tokens!,
      log: log,
    );
    final capabilities = value(await provider.capabilities(lease));
    final mailboxes = value(await provider.listMailboxes(lease));
    stdout.writeln('Connected; ${mailboxes.length} folders/labels available.');
    if (!capabilities.supports(MailCapability.mail)) {
      throw const MailProblem(MailProblemCode.unsupported);
    }
    if (mailboxes.isNotEmpty) {
      final page = value(
        await provider.fetchHeaders(mailboxes.first.id, limit: 5, lease: lease),
      );
      stdout.writeln(
        'Read ${page.messages.length} bounded headers successfully.',
      );
    }
    stdout.writeln(
      'Read-only probe completed; session credentials are discarded.',
    );
  } on MailProblem catch (problem) {
    stderr.writeln('Probe failed: ${problem.code.name}.');
    if (problem.retryAfter case final delay?) {
      stderr.writeln('Retry after at least ${delay.inSeconds} seconds.');
    }
    exitCode = 1;
  } on Object {
    stderr.writeln(
      'Probe could not complete; check client registration and desktop setup.',
    );
    exitCode = 1;
  } finally {
    cancellation.cancel();
    session.dispose();
    provider?.dispose();
    tokens?.dispose();
    await interrupt.cancel();
  }
}
