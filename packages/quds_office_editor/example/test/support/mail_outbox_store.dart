import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';

final _activeFixtures = <NativeOutboxFixture>[];

/// The production native opener uses an isolate. Its database futures must be
/// allowed to complete in real async while widgets keep a deterministic clock.
Future<T> nativeOutboxIo<T>(
  WidgetTester tester,
  Future<T> Function() action,
) async => (await tester.runAsync(action)) as T;

Future<void> pumpNativeOutboxWidgets(WidgetTester tester) async {
  await tester.pump();
  for (var phase = 0; phase < 2; phase++) {
    for (var turn = 0; turn < 4; turn++) {
      await nativeOutboxIo(tester, () async {
        for (final fixture in _activeFixtures) {
          await fixture.repository.listAccounts();
        }
      });
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 350));
  }
}

/// Real native SQLite, with a separate adapter lifetime for each Mail host.
/// Provider/network seams remain controlled by the widget tests.
final class NativeOutboxFixture {
  NativeOutboxFixture._(this.identity, this.directory);

  final StudioMailDraftAccount identity;
  final Directory directory;
  late final SqliteMailRepository repository;
  final adapters = <SqliteStudioMailDraftStore>[];
  MailStoreCheckpoint? failNextCheckpoint;

  static Future<NativeOutboxFixture> create(
    StudioMailDraftAccount identity,
  ) async {
    final fixture = NativeOutboxFixture._(
      identity,
      await Directory.systemTemp.createTemp('outbox-widget-'),
    );
    fixture.repository = _value(
      await openNativeMailStore(
        appDirectory: fixture.directory,
        profile: identity.profile,
        faultInjector: (checkpoint) {
          if (fixture.failNextCheckpoint == checkpoint) {
            fixture.failNextCheckpoint = null;
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      ),
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
    _activeFixtures.add(fixture);
    return fixture;
  }

  Future<StudioMailDraftStore> open(StudioMailDraftAccount account) async {
    expect(account.account, identity.account);
    expect(account.provider, identity.provider);
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
    _activeFixtures.remove(this);
    for (final adapter in adapters.reversed) {
      await adapter.close();
    }
    await repository.close();
    await directory.delete(recursive: true);
  }

  static T _value<T>(MailResult<T> result) {
    expect(result, isA<MailSuccess<T>>());
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
