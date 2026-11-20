@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:test/test.dart';

import '../tool/transaction_crash_fixture.dart' as fixture;

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

Future<SqliteMailRepository> _open(Directory directory) async => _value(
  await openNativeMailStore(
    appDirectory: directory,
    profile: fixture.crashProfile,
    clock: () => fixture.crashTime.add(const Duration(seconds: 3)),
  ),
);

Future<void> _seed(Directory directory) async {
  final store = await _open(directory);
  try {
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: fixture.crashAccount,
          provider: MailProviderKind.imap,
          displayName: 'Synthetic transaction crash account',
        ),
      ),
    );
    final header = fixture.crashHeader(1);
    _value(
      await store.commitSyncPage(
        MailSyncPage(
          mailbox: fixture.crashMailbox,
          upserts: [header],
          tombstones: const [],
          next: MailCursor(
            mailbox: fixture.crashMailbox,
            value: 'baseline-cursor',
          ),
          hasMore: false,
        ),
        expectedCursor: null,
        lease: MailAccountSession(fixture.crashAccount).begin(),
      ),
    );
    _value(
      await store.saveMailboxView(
        MailMailbox(id: fixture.crashMailbox, displayName: 'Baseline folder'),
        [header],
        expectedRevision: null,
        hasMore: false,
        lease: MailAccountSession(fixture.crashAccount).begin(),
      ),
    );
    _value(
      await store.cacheMessage(
        fixture.crashAccount,
        header.id,
        MailMessage(
          raw: fixture.crashBytes([77, 73, 77, 69, 0, 255]),
          localId: header.id,
          remoteIdentity: header.remote,
          envelope: header.envelope,
          body: const MailBody(plainText: 'Baseline cached message'),
        ),
      ),
    );
    _value(
      await store.saveDraft(fixture.crashDraft(0), expectedRevision: null),
    );
    _value(
      await store.saveOutbox(
        fixture.crashQueued(),
        expectedState: null,
        expectedAttemptId: null,
      ),
    );
  } finally {
    await store.close();
  }
}

Future<void> _killAtBarrier(
  Directory directory,
  fixture.TransactionCrashScenario scenario,
) async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:quds_mail_store/quds_mail_store_native.dart'),
  );
  final package = File.fromUri(library!).parent.parent;
  // The test runner can be dartvm; invoke the adjacent official dart CLI so the
  // child receives the same normal native-assets hook setup as other consumers.
  final dart = p.join(p.dirname(Platform.resolvedExecutable), 'dart');
  final process = await Process.start(dart, [
    'run',
    p.join(package.path, 'tool/transaction_crash_fixture.dart'),
    directory.path,
    scenario.name,
  ], workingDirectory: package.path);
  final errors = StringBuffer();
  final output = <String>[];
  final ready = Completer<int>();
  var exited = false;
  int? ownerPid;
  final exit = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .listen(errors.write);
  final stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) {
          output.add(line);
          final prefix = 'READY ${scenario.name} ';
          if (line.startsWith(prefix) && !ready.isCompleted) {
            final reported = int.tryParse(line.substring(prefix.length));
            if (reported == null || reported <= 0) {
              ready.completeError(
                StateError('Invalid child process identity: $line'),
              );
            } else {
              ownerPid = reported;
              ready.complete(reported);
            }
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
        onDone: () {
          if (!ready.isCompleted) {
            ready.completeError(
              StateError(
                'Child ended before READY. stdout: ${output.join('\n')} stderr: $errors',
              ),
            );
          }
        },
      );
  try {
    final child = await ready.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TestFailure(
        'No ${scenario.name} barrier. stdout: ${output.join('\n')} stderr: $errors',
      ),
    );
    expect(exited, isFalse);
    // Signal the process that owns the actual SQLite connection, as identified
    // by the fixture itself, even if a future dart CLI uses a separate launcher.
    expect(Process.killPid(child, ProcessSignal.sigkill), isTrue);
    final code = await exit.timeout(const Duration(seconds: 5));
    expect(
      code,
      isNot(0),
      reason: 'SIGKILL must terminate abnormally. stderr: $errors',
    );
    if (child == process.pid) expect(code, -9);
    print(
      'SIGKILL ${scenario.name}; owner=$child launcher=${process.pid} exit=$code',
    );
    if (errors.isNotEmpty) {
      print('CHILD_STDERR ${scenario.name}: $errors');
    }
    expect(errors.toString(), isNot(contains('CRASH_FIXTURE_FAILURE')));
    expect(errors.toString(), isNot(contains('Unhandled exception')));
  } finally {
    if (!exited) {
      if (ownerPid case final child?) {
        Process.killPid(child, ProcessSignal.sigkill);
      }
      process.kill(ProcessSignal.sigkill);
      await exit.timeout(const Duration(seconds: 5));
    }
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }
}

Future<void> _checkBaseline(
  SqliteMailRepository store, {
  bool committedView = false,
}) async {
  expect(
    _value(await store.readCursor(fixture.crashMailbox))!.value,
    'baseline-cursor',
  );
  final headers = _value(await store.listHeaders(fixture.crashMailbox));
  expect(headers.map((header) => header.id.value), ['message-1']);
  expect(headers.single.envelope.subject, 'Baseline message');
  expect(
    _value(await store.search(fixture.crashAccount, 'Changed')),
    committedView ? hasLength(1) : isEmpty,
  );
  final view = _value(await store.loadMailboxView(fixture.crashMailbox))!;
  expect(view.revision, committedView ? 2 : 1);
  expect(view.hasMore, committedView);
  expect(
    view.mailbox.displayName,
    committedView ? 'Changed folder' : 'Baseline folder',
  );
  expect(
    view.headers.single.id.value,
    committedView ? 'message-2' : 'message-1',
  );
  final cached = _value(
    await store.loadCachedMessage(
      fixture.crashAccount,
      MailMessageId('message-1'),
    ),
  )!;
  expect(cached.raw.bytes, [77, 73, 77, 69, 0, 255]);
  expect(cached.body.plainText, 'Baseline cached message');
  final draft = _value(await store.loadDraft(fixture.crashAccount, 'draft'))!;
  expect(draft.revision, 0);
  expect(draft.body.plainText, 'Baseline draft');
  expect(draft.attachments.single.content.bytes, [0, 1, 2, 253, 254, 255]);
}

void main() {
  for (final scenario in fixture.TransactionCrashScenario.values) {
    test(
      'SIGKILL ${scenario.name} preserves the correct durable transaction boundary',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'mail-transaction-crash-',
        );
        try {
          await _seed(directory);
          await _killAtBarrier(directory, scenario);
          var store = await _open(directory);
          try {
            await _checkBaseline(
              store,
              committedView:
                  scenario ==
                  fixture.TransactionCrashScenario.committedMailboxView,
            );
            if (scenario.name.contains('Flag')) {
              final batch = _value(
                await store.loadFlagBatch(fixture.crashAccount, 'crash-flags'),
              );
              if (scenario ==
                  fixture.TransactionCrashScenario.beforeFlagIntentCommit) {
                expect(batch, isNull);
              } else {
                expect(batch, isNotNull);
                final acknowledged =
                    scenario ==
                        fixture.TransactionCrashScenario.committedFlagReceipt ||
                    scenario ==
                        fixture.TransactionCrashScenario.committedFlagFinish;
                final dispatched =
                    scenario ==
                        fixture
                            .TransactionCrashScenario
                            .committedFlagDispatch ||
                    scenario ==
                        fixture
                            .TransactionCrashScenario
                            .beforeFlagReceiptCommit;
                expect(batch!.report.confirmedCount, acknowledged ? 1 : 0);
                expect(batch.report.uncertainCount, dispatched ? 1 : 0);
                expect(
                  batch.report.unattemptedCount,
                  acknowledged || dispatched ? 2 : 3,
                );
                expect(batch.summary.complete, isTrue);
                expect(
                  batch.summary.interrupted,
                  scenario !=
                      fixture.TransactionCrashScenario.committedFlagFinish,
                );
                expect(batch.subjects, [
                  'First frozen subject',
                  'Second frozen subject',
                  'Third frozen subject',
                ]);
              }
            }
            final recovered = _value(
              await store.recoverOutbox(fixture.crashAccount),
            ).single;
            final committed =
                scenario ==
                fixture.TransactionCrashScenario.committedSubmitting;
            expect(
              recovered.state,
              committed ? MailOutboxState.uncertain : MailOutboxState.queued,
            );
            expect(recovered.canBeginAttempt, !committed);
            expect(
              recovered.attemptId,
              committed ? fixture.crashAttemptId : null,
            );
            expect(recovered.prepared.wire.bytes, [
              70,
              114,
              111,
              109,
              58,
              13,
              10,
              13,
              10,
              0,
              127,
              255,
            ]);
            expect(
              recovered.prepared.wireHash,
              fixture.crashQueued().prepared.wireHash,
            );
            expect(recovered.prepared.envelope.recipients, [
              'recipient@example.invalid',
              'blind@example.invalid',
            ]);
            if (scenario == fixture.TransactionCrashScenario.afterOutboxWrite) {
              // The killed transaction's attempt-history insertion must roll back
              // too. Reusing that never-committed identity is still permitted.
              _value(
                await store.saveOutbox(
                  recovered.beginAttempt(
                    attemptId: fixture.crashAttemptId,
                    now: fixture.crashTime.add(const Duration(seconds: 2)),
                  ),
                  expectedState: MailOutboxState.queued,
                  expectedAttemptId: null,
                ),
              );
            }
            if (committed) {
              await store.close();
              store = await _open(directory);
              final persisted = _value(
                await store.recoverOutbox(fixture.crashAccount),
              ).single;
              expect(persisted.state, MailOutboxState.uncertain);
              expect(persisted.canBeginAttempt, isFalse);
              expect(persisted.prepared.wireHash, recovered.prepared.wireHash);
            }
          } finally {
            await store.close();
          }
        } finally {
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
      skip: Platform.isWindows
          ? 'These crash boundaries require POSIX SIGKILL.'
          : false,
    );
  }
}
