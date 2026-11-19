import 'dart:async';
import 'dart:io';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';

Future<void> main(List<String> arguments) async {
  final profile = MailProfileId('profile', hostId: 'office');
  final opened = await openNativeMailStore(
    appDirectory: Directory(arguments.single),
    profile: profile,
  );
  if (opened case MailSuccess(:final value)) {
    final saved = await value.createAccount(
      MailStoreAccount(
        id: MailAccountId('account', profile: profile),
        provider: MailProviderKind.imap,
        displayName: 'Crash checkpoint',
      ),
    );
    if (saved is! MailSuccess<MailUnit>) exit(2);
    stdout.writeln('READY');
    await stdout.flush();
    await Completer<void>().future;
  } else {
    exit(3);
  }
}
