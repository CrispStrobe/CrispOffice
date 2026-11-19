/// A real restore process killed after the first confirmed atomic message.
/// Synchronous progress suspends before the next original is inspected, while
/// native archive ownership remains held. No exception simulates termination.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';

final restoreCrashProfile = MailProfileId(
  'restore-crash',
  hostId: 'archive-restore-tests',
);

final class RestoreCrashCodec implements MailCodec {
  const RestoreCrashCodec();

  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    return MailParseResult(
      status: MailParseStatus.complete,
      message: MailMessage(
        raw: MailBytes(bytes),
        envelope: MailEnvelope(subject: 'Restored crash fixture'),
        body: const MailBody(plainText: 'restoredledger fixture body'),
      ),
    );
  }
}

T _required<T>(MailResult<T> result) => switch (result) {
  MailSuccess(:final value) => value,
  MailFailure(:final problem) => throw StateError(problem.code.name),
};

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Expected a synthetic export and destination directory.');
    exitCode = 2;
    return;
  }
  final archive = _required(
    await openNativeMailArchive(
      appDirectory: Directory(arguments[1]),
      profile: restoreCrashProfile,
    ),
  );
  try {
    final restorer = NativeMailArchiveRestorer(
      archive: archive,
      codec: const RestoreCrashCodec(),
    );
    final preview = _required(await restorer.inspect(Directory(arguments[0])));
    await restorer.restore(
      preview,
      onProgress: (event) {
        if (event.phase == MailArchiveRestorePhase.message &&
            event.saved == 1) {
          // Stdout's default sink is blocking. The parent sees this only after
          // the database returned success with the complete origin set.
          stdout.writeln('READY $pid');
          while (true) {
            sleep(const Duration(seconds: 1));
          }
        }
      },
    );
    stderr.writeln('Unexpected restore fixture completion.');
    exitCode = 3;
  } finally {
    await archive.close();
  }
}
