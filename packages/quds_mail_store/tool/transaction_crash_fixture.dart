/// Subprocess fixture for real termination at durable Mail transaction barriers.
/// All data is synthetic. The test parent sends SIGKILL after the READY line;
/// this process never substitutes an exception or graceful close for a crash.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';

enum TransactionCrashScenario {
  afterSyncRecords,
  beforeSyncCursor,
  afterDraftBlobs,
  afterOutboxWrite,
  committedSubmitting,
  beforeMailboxViewCommit,
  committedMailboxView,
}

final crashProfile = MailProfileId('transactions', hostId: 'mail-crash-tests');
final crashAccount = MailAccountId('synthetic', profile: crashProfile);
final crashMailbox = MailMailboxId('inbox', account: crashAccount);
final crashTime = DateTime.utc(2026, 11, 18, 12);
const crashAttemptId = 'child-attempt';

MailBytes crashBytes(List<int> bytes) => MailBytes(Uint8List.fromList(bytes));

MailHeaderRecord crashHeader(int uid) => MailHeaderRecord(
  id: MailMessageId('message-$uid'),
  remote: MailImapIdentity(mailbox: crashMailbox, uidValidity: 1, uid: uid),
  envelope: MailEnvelope(
    subject: uid == 1 ? 'Baseline message' : 'Changed message',
  ),
);

MailDraft crashDraft(int revision) => MailDraft(
  id: 'draft',
  account: crashAccount,
  revision: revision,
  envelope: MailEnvelope(subject: 'Synthetic crash draft'),
  body: MailBody(plainText: revision == 0 ? 'Baseline draft' : 'Changed draft'),
  attachments: [
    MailAttachment(
      partPath: '1',
      mediaType: 'application/octet-stream',
      displayName: 'synthetic.bin',
      content: crashBytes(revision == 0 ? [0, 1, 2, 253, 254, 255] : [9, 8, 7]),
    ),
  ],
);

MailOutboxEntry crashQueued() => MailOutboxEntry.queued(
  id: 'outbox',
  prepared: MailPreparedMessage(
    account: crashAccount,
    draftId: 'draft',
    draftRevision: 0,
    wire: crashBytes([70, 114, 111, 109, 58, 13, 10, 13, 10, 0, 127, 255]),
    envelope: MailTransportEnvelope(
      sender: 'sender@example.invalid',
      recipients: ['recipient@example.invalid', 'blind@example.invalid'],
    ),
  ),
  now: crashTime,
);

T _required<T>(MailResult<T> result, String operation) => switch (result) {
  MailSuccess<T>(:final value) => value,
  MailFailure<T>(:final problem) => throw StateError(
    '$operation failed with ${problem.code.name}',
  ),
};

Future<Never> _ready(TransactionCrashScenario scenario) async {
  stdout.writeln('READY ${scenario.name} $pid');
  await stdout.flush();
  // The native database isolate remains live. Only the parent can release this
  // barrier by terminating this process; no cleanup runs before that signal.
  return Completer<Never>().future;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Expected app-container path and crash scenario.');
    exitCode = 2;
    return;
  }
  SqliteMailRepository? store;
  try {
    final scenario = TransactionCrashScenario.values.byName(arguments[1]);
    final target = switch (scenario) {
      TransactionCrashScenario.afterSyncRecords =>
        MailStoreCheckpoint.afterSyncRecords,
      TransactionCrashScenario.beforeSyncCursor =>
        MailStoreCheckpoint.beforeSyncCursor,
      TransactionCrashScenario.afterDraftBlobs =>
        MailStoreCheckpoint.afterDraftBlobs,
      TransactionCrashScenario.afterOutboxWrite =>
        MailStoreCheckpoint.afterOutboxWrite,
      TransactionCrashScenario.committedSubmitting => null,
      TransactionCrashScenario.beforeMailboxViewCommit =>
        MailStoreCheckpoint.beforeCommit,
      TransactionCrashScenario.committedMailboxView => null,
    };
    final opened = _required<SqliteMailRepository>(
      await openNativeMailStore(
        appDirectory: Directory(arguments[0]),
        profile: crashProfile,
        clock: () => crashTime.add(const Duration(seconds: 2)),
        faultInjector: (checkpoint) async {
          if (checkpoint == target) await _ready(scenario);
        },
      ),
      'open',
    );
    store = opened;
    switch (scenario) {
      case TransactionCrashScenario.beforeMailboxViewCommit:
      case TransactionCrashScenario.committedMailboxView:
        _required(
          await opened.saveMailboxView(
            MailMailbox(id: crashMailbox, displayName: 'Changed folder'),
            [crashHeader(2)],
            expectedRevision: 1,
            hasMore: true,
            lease: MailAccountSession(crashAccount).begin(),
          ),
          'mailbox view replacement',
        );
        if (scenario == TransactionCrashScenario.committedMailboxView) {
          await _ready(scenario);
        }
      case TransactionCrashScenario.afterSyncRecords:
      case TransactionCrashScenario.beforeSyncCursor:
        _required(
          await opened.commitSyncPage(
            MailSyncPage(
              mailbox: crashMailbox,
              upserts: [crashHeader(2)],
              tombstones: [crashHeader(1).remote],
              next: MailCursor(mailbox: crashMailbox, value: 'changed-cursor'),
              hasMore: false,
            ),
            expectedCursor: MailCursor(
              mailbox: crashMailbox,
              value: 'baseline-cursor',
            ),
            lease: MailAccountSession(crashAccount).begin(),
          ),
          'sync page',
        );
      case TransactionCrashScenario.afterDraftBlobs:
        _required(
          await opened.saveDraft(crashDraft(1), expectedRevision: 0),
          'draft replacement',
        );
      case TransactionCrashScenario.afterOutboxWrite:
      case TransactionCrashScenario.committedSubmitting:
        final active = crashQueued().beginAttempt(
          attemptId: crashAttemptId,
          now: crashTime.add(const Duration(seconds: 1)),
        );
        _required(
          await opened.saveOutbox(
            active,
            expectedState: MailOutboxState.queued,
            expectedAttemptId: null,
          ),
          'persist submitting',
        );
        if (scenario == TransactionCrashScenario.committedSubmitting) {
          await _ready(scenario);
        }
    }
    throw StateError('Crash barrier did not suspend the selected operation.');
  } on Object catch (error, stack) {
    stderr.writeln('CRASH_FIXTURE_FAILURE ${error.runtimeType}: $error');
    stderr.writeln(stack);
    exitCode = 3;
  } finally {
    await store?.close();
  }
}
