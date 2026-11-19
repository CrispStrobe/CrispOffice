/// Synthetic archive crash fixture. The parent terminates this process with
/// SIGKILL at an observed barrier; no exception or graceful close simulates it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';

enum ArchiveCrashScenario { afterContent, afterIndex, beforeCommit, committed }

final archiveCrashProfile = MailProfileId(
  'crash-boundaries',
  hostId: 'archive-native-tests',
);
final archiveCrashTime = DateTime.utc(2026, 11, 19, 12);
const archiveCrashOrigin = MailArchiveOrigin(
  source: 'Synthetic native archive',
  folder: '/Durability',
  sourceMessageId: 'fixture',
);

MailMessage archiveCrashMessage({required bool pending}) {
  final word = pending ? 'pendingledger' : 'baselineledger';
  final subject = '$word café مرحبا';
  final raw = Uint8List.fromList([
    ...utf8.encode(
      'From: sender@example.invalid\r\n'
      'To: recipient@example.invalid\r\n'
      'Subject: $subject\r\n'
      'Message-ID: <$word@example.invalid>\r\n'
      'Content-Type: application/octet-stream\r\n'
      'Content-Transfer-Encoding: binary\r\n\r\n'
      '$word original bytes\r\n',
    ),
    0,
    127,
    128,
    254,
    255,
    13,
    10,
  ]);
  return MailMessage(
    raw: MailBytes(raw),
    envelope: MailEnvelope(
      subject: subject,
      messageId: '<$word@example.invalid>',
      from: const [MailAddress('sender@example.invalid')],
      to: const [MailAddress('recipient@example.invalid')],
      bcc: const [MailAddress('blind@example.invalid')],
      sentAt: archiveCrashTime.subtract(const Duration(days: 5)),
    ),
    body: MailBody(plainText: '$word searchable original'),
  );
}

T _required<T>(MailResult<T> result, String operation) => switch (result) {
  MailSuccess<T>(:final value) => value,
  MailFailure<T>(:final problem) => throw StateError(
    '$operation failed: ${problem.code.name}',
  ),
};

Future<Never> _barrier(ArchiveCrashScenario scenario) async {
  stdout.writeln('READY ${scenario.name} $pid');
  await stdout.flush();
  return Completer<Never>().future;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Expected a synthetic container and crash scenario.');
    exitCode = 2;
    return;
  }
  SqliteMailArchive? archive;
  try {
    final scenario = ArchiveCrashScenario.values.byName(arguments[1]);
    final checkpoint = switch (scenario) {
      ArchiveCrashScenario.afterContent => MailArchiveCheckpoint.afterContent,
      ArchiveCrashScenario.afterIndex => MailArchiveCheckpoint.afterIndex,
      ArchiveCrashScenario.beforeCommit => MailArchiveCheckpoint.beforeCommit,
      ArchiveCrashScenario.committed => null,
    };
    final opened = _required(
      await openNativeMailArchive(
        appDirectory: Directory(arguments[0]),
        profile: archiveCrashProfile,
        clock: () => archiveCrashTime.add(const Duration(minutes: 1)),
        faultInjector: (observed) async {
          if (observed == checkpoint) await _barrier(scenario);
        },
      ),
      'open',
    );
    archive = opened;
    _required(
      await opened.archiveMessage(
        archiveCrashMessage(pending: true),
        origin: archiveCrashOrigin,
      ),
      'archive',
    );
    if (scenario == ArchiveCrashScenario.committed) await _barrier(scenario);
    throw StateError('Selected archive crash barrier did not suspend.');
  } on Object catch (error, stack) {
    stderr.writeln(
      'ARCHIVE_CRASH_FIXTURE_FAILURE ${error.runtimeType}: $error',
    );
    stderr.writeln(stack);
    exitCode = 3;
  } finally {
    await archive?.close();
  }
}
