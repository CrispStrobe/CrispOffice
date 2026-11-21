import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';

import '../../../../quds_mail_store/test/support/outbox_widget_database.dart';

/// Completes repository work while advancing the widget test's fake clock.
/// Drift can defer a transaction to a zero-duration timer even with its
/// synchronous SQLite executor; blindly awaiting it would stop that clock.
/// Native file I/O also needs real time, so bound elapsed time rather than
/// counting fake-clock turns, which can finish before the operating system does.
Future<T> awaitOutboxOperation<T>(WidgetTester tester, Future<T> future) async {
  var complete = false;
  T? result;
  Object? failure;
  StackTrace? stack;
  future.then(
    (value) {
      result = value;
      complete = true;
    },
    onError: (Object error, StackTrace trace) {
      failure = error;
      stack = trace;
      complete = true;
    },
  );
  const timeout = Duration(seconds: 15);
  final elapsed = Stopwatch()..start();
  while (!complete && elapsed.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 1));
    if (!complete) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
  }
  elapsed.stop();
  if (!complete) {
    throw StateError('Outbox fixture operation did not complete within 15 s.');
  }
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
  return result as T;
}

Future<void> pumpOutboxWidgets(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

/// Real synchronous SQLite, with a separate adapter lifetime for each Mail host.
/// File reopen and ownership leases are covered by the native storage suite.
final class SqliteOutboxFixture {
  SqliteOutboxFixture._(this.identity);

  final StudioMailDraftAccount identity;
  late final SqliteMailRepository repository;
  final adapters = <SqliteStudioMailDraftStore>[];
  MailStoreCheckpoint? failNextCheckpoint;

  static Future<SqliteOutboxFixture> create(
    StudioMailDraftAccount identity,
  ) async {
    final fixture = SqliteOutboxFixture._(identity);
    fixture.repository = await openOutboxWidgetDatabase(
      profile: identity.profile,
      faultInjector: (checkpoint) {
        if (fixture.failNextCheckpoint == checkpoint) {
          fixture.failNextCheckpoint = null;
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    );
    _value(
      await fixture.repository.createAccount(
        MailStoreAccount(
          id: identity.account,
          provider: identity.provider,
          displayName: 'Outbox widget fixture',
        ),
      ),
    );
    return fixture;
  }

  Future<StudioMailDraftStore> open(StudioMailDraftAccount account) async {
    expectSync(account.account, identity.account);
    expectSync(account.provider, identity.provider);
    final adapter = SqliteStudioMailDraftStore(
      repository: repository,
      account: identity.account,
    );
    adapters.add(adapter);
    return adapter;
  }

  Future<SqliteStudioMailDraftStore> openLoaded() async {
    final adapter = await open(identity) as SqliteStudioMailDraftStore;
    await adapter.load();
    return adapter;
  }

  Future<void> close() async {
    for (final adapter in adapters.reversed) {
      await adapter.close();
    }
    await repository.close();
  }

  static T _value<T>(MailResult<T> result) {
    expectSync(result, isA<MailSuccess<T>>());
    return (result as MailSuccess<T>).value;
  }
}

StudioMailDraft outboxFixtureDraft({String subject = 'Frozen مرحبًا'}) =>
    StudioMailDraft(
      to: 'to@example.test',
      cc: 'copy@example.test',
      bcc: 'hidden@example.test',
      subject: subject,
      body: 'The original body <safe> & unchanged.',
    );
