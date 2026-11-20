import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_flag_journal.dart';

/// Drain both Flutter's fake microtasks and the native executor while closing
/// a queue that has already performed work in a widget's fake async zone.
Future<void> settleMailJournal(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  var complete = false;
  Object? error;
  StackTrace? trace;
  unawaited(
    action().then(
      (_) => complete = true,
      onError: (Object failure, StackTrace stack) {
        error = failure;
        trace = stack;
        complete = true;
      },
    ),
  );
  for (var i = 0; i < 100 && !complete; i++) {
    await tester.pump(const Duration(milliseconds: 5));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  expect(complete, isTrue, reason: 'The real SQLite host queue must settle.');
}

/// A real file-backed SQLite repository with the same host owner/queue adapter.
/// All addresses and subjects are fixed synthetic fixtures; no transport exists.
final class TestMailFlagJournal {
  TestMailFlagJournal._(this.directory, this.identity);

  final Directory directory;
  final StudioMailDraftAccount identity;
  late SqliteMailRepository repository;
  late SqliteStudioMailDraftStore owner;
  DateTime now = DateTime.utc(2026, 11, 21, 12);
  int commits = 0;
  int? failCommit;
  bool failWrites = false;
  bool current = true;
  bool closed = false;
  final dispatched = <MailOperation>[];

  static Future<TestMailFlagJournal> create({
    MailProviderKind provider = MailProviderKind.imap,
    String accountName = 'journal',
    StudioMailDraftAccount? identity,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final fixture = TestMailFlagJournal._(
      Directory.systemTemp.createTempSync('studio-flag-journal-'),
      identity ??
          StudioMailDraftAccount(
            provider: provider.name,
            endpoint: provider == MailProviderKind.imap
                ? 'imaps://mail.example.test:993'
                : 'https://mail.example.test/${provider.name}',
            login: '$accountName@example.test',
            sender: '$accountName@example.test',
          ),
    );
    await fixture._open();
    success(
      await fixture.repository.createAccount(
        MailStoreAccount(
          id: fixture.account,
          provider: fixture.provider,
          displayName: 'Synthetic journal',
        ),
      ),
    );
    fixture.commits = 0;
    return fixture;
  }

  MailAccountId get account => identity.account;
  MailProviderKind get provider => identity.provider;
  StudioMailFlagJournalStore get store => owner.flagJournal;
  MailAccountId source([String session = 'connection-one']) => MailAccountId(
    session,
    profile: MailProfileId('ephemeral', hostId: 'test-transport'),
  );

  static T success<T>(MailResult<T> result) => switch (result) {
    MailSuccess<T>(:final value) => value,
    MailFailure<T>(:final problem) => throw StateError(
      'Fixture failed: ${problem.code.name}',
    ),
  };

  Future<void> _open() async {
    repository = success(
      await SqliteMailRepository.open(
        executor: NativeDatabase(File('${directory.path}/journal.sqlite3')),
        profile: identity.profile,
        clock: () => now,
        faultInjector: (point) {
          if (point != MailStoreCheckpoint.beforeCommit) return;
          commits++;
          if (failWrites || commits == failCommit) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      ),
    );
    owner = SqliteStudioMailDraftStore(
      repository: repository,
      account: identity.account,
      ownsRepository: true,
    );
    closed = false;
  }

  Future<void> reopen() async {
    await owner.close();
    failWrites = false;
    failCommit = null;
    await _open();
    commits = 0;
  }

  Future<void> dispose() async {
    if (!closed) {
      await owner.close();
      closed = true;
    }
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  MailBulkFlagPlan plan(
    String id, {
    int count = 3,
    MailAccountId? sourceAccount,
    MailBulkFlagAction action = MailBulkFlagAction.flag,
    String mailbox = 'INBOX',
  }) {
    final account = sourceAccount ?? source();
    final box = MailMailboxId(mailbox, account: account);
    return MailBulkFlagPlan(
      id: id,
      mailbox: box,
      provider: provider,
      action: action,
      messages: [
        for (var i = 0; i < count; i++)
          if (provider == MailProviderKind.imap)
            MailImapIdentity(mailbox: box, uidValidity: 71, uid: i + 1)
          else
            MailOpaqueIdentity(
              account: account,
              provider: provider,
              value: 'remote-${i + 1}',
            ),
      ],
    );
  }

  MailBulkFlagJournal bind(
    MailBulkFlagPlan plan, {
    List<String>? subjects,
    bool Function()? isCurrent,
  }) => store.bind(
    sourceAccount: plan.mailbox.account,
    provider: plan.provider,
    subjects:
        subjects ??
        [for (var i = 0; i < plan.messages.length; i++) 'Message ${i + 1}'],
    isCurrent: isCurrent ?? () => current,
  );

  Future<MailBulkFlagReport> run(
    String id, {
    int count = 3,
    List<String>? subjects,
    MailAccountId? sourceAccount,
    MailBulkFlagAction action = MailBulkFlagAction.flag,
    MailCancellationToken? cancellation,
    Future<MailBulkFlagAttempt> Function(MailOperation)? apply,
  }) async {
    now = now.add(const Duration(seconds: 1));
    final selected = plan(
      id,
      count: count,
      sourceAccount: sourceAccount,
      action: action,
    );
    final session = MailAccountSession(selected.mailbox.account);
    try {
      return await MailBulkFlagCoordinator().run(
        plan: selected,
        lease: session.begin(),
        isScopeCurrent: () => current,
        cancellation: cancellation,
        journal: bind(selected, subjects: subjects),
        apply: (operation, lease) async {
          dispatched.add(operation);
          return apply == null
              ? const MailBulkFlagAttempt.confirmed()
              : await apply(operation);
        },
      );
    } finally {
      session.dispose();
    }
  }

  Future<MailBulkFlagJournal> prepare(String id, {bool begin = false}) async {
    now = now.add(const Duration(seconds: 1));
    final selected = plan(id);
    final journal = bind(selected);
    success(await journal.prepare(selected));
    if (begin) success(await journal.beginAttempt(0));
    return journal;
  }
}
