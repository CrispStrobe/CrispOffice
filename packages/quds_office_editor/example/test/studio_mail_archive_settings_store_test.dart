import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_archive_settings_store.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_outbox.dart';

StudioMailDraftAccount _identity({String sender = 'sender@example.test'}) =>
    StudioMailDraftAccount(
      provider: 'imap',
      endpoint: 'imaps://mail.example.test:993',
      login: sender,
      sender: sender,
    );

Matcher _failure(MailProblemCode code) => throwsA(
  isA<StudioMailDraftStoreException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

void main() {
  final identity = _identity();
  late Directory directory;
  final opened = <StudioMailDraftStore>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mail-archive-settings-');
  });
  tearDown(() async {
    for (final store in opened.reversed) {
      await store.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  Future<StudioMailDraftStore> open([StudioMailDraftAccount? account]) async {
    final store = await openStudioMailDraftStore(
      account ?? identity,
      appDirectory: directory,
    );
    opened.add(store);
    return store;
  }

  test(
    'native preference survives reopen without creating drafts or crossing accounts',
    () async {
      final owner = await open();
      final settingsStore = owner as StudioMailArchiveSettingsStore;
      expect(await owner.load(), isNull);
      final defaults = await settingsStore.loadArchiveSettings();
      expect(defaults.account, identity.account);
      final saved = await settingsStore.saveArchiveSettings(
        defaults.copyWith(
          destination: MailMailboxId(
            ' Archive/أرشيف 📨 ',
            account: identity.account,
          ),
        ),
        expectedRevision: 0,
      );
      expect(await owner.load(), isNull);
      await owner.close();
      final reopened = await open();
      final restored = await (reopened as StudioMailArchiveSettingsStore)
          .loadArchiveSettings();
      expect(restored.destination, saved.destination);
      expect(restored.revision, 1);
      final other =
          (await open(_identity(sender: 'other@example.test')))
              as StudioMailArchiveSettingsStore;
      expect((await other.loadArchiveSettings()).destination, isNull);
      await expectLater(
        other.saveArchiveSettings(restored, expectedRevision: 1),
        _failure(MailProblemCode.permissionDenied),
      );
    },
  );

  test('reset retains its fence and rejects stale caller revisions', () async {
    final settingsStore = (await open()) as StudioMailArchiveSettingsStore;
    final defaults = await settingsStore.loadArchiveSettings();
    final saved = await settingsStore.saveArchiveSettings(
      defaults.copyWith(
        destination: MailMailboxId('Exact', account: settingsStore.account),
      ),
      expectedRevision: 0,
    );
    final reset = await settingsStore.saveArchiveSettings(
      saved.copyWith(clearDestination: true),
      expectedRevision: 1,
    );
    expect(reset.revision, 2);
    expect(reset.destination, isNull);
    await expectLater(
      settingsStore.saveArchiveSettings(saved, expectedRevision: 1),
      _failure(MailProblemCode.conflict),
    );
    await expectLater(
      settingsStore.saveArchiveSettings(reset, expectedRevision: 0),
      _failure(MailProblemCode.invalidInput),
    );
  });

  test(
    'close drains an accepted preference write and preserves uncertain drafts',
    () async {
      final owner = await open();
      await owner.load();
      await owner.save(
        const StudioMailDraft(
          to: 'reader@example.test',
          subject: 'Original',
          body: 'Retained',
        ),
        submissionUncertain: true,
      );
      final settingsStore = owner as StudioMailArchiveSettingsStore;
      final settings = await settingsStore.loadArchiveSettings();
      final pending = settingsStore.saveArchiveSettings(
        settings.copyWith(
          destination: MailMailboxId('Exact', account: settingsStore.account),
        ),
        expectedRevision: 0,
      );
      final closing = owner.close();
      await pending;
      await closing;
      await expectLater(
        settingsStore.loadArchiveSettings(),
        _failure(MailProblemCode.unavailable),
      );
      final reopened = await open();
      expect((await reopened.load())!.submissionUncertain, isTrue);
      expect(
        (await (reopened as StudioMailArchiveSettingsStore)
                .loadArchiveSettings())
            .destination
            ?.value,
        'Exact',
      );
    },
  );

  test(
    'changing a destination preserves already queued MIME and recipients',
    () async {
      final owner = await open();
      await owner.load();
      const draft = StudioMailDraft(
        to: 'reader@example.test',
        bcc: 'hidden@example.test',
        subject: 'Queued',
        body: 'Exact content',
      );
      await owner.save(draft, submissionUncertain: false);
      final outbox = owner as StudioMailOutboxStore;
      final queued = await outbox.enqueueOutbox(draft, identity.sender);
      final settingsStore = owner as StudioMailArchiveSettingsStore;
      final settings = await settingsStore.loadArchiveSettings();
      await settingsStore.saveArchiveSettings(
        settings.copyWith(
          destination: MailMailboxId('Exact', account: settingsStore.account),
        ),
        expectedRevision: 0,
      );
      await owner.close();
      final reopened = await open();
      final retained =
          (await (reopened as StudioMailOutboxStore).loadOutbox()).single;
      expect(retained.prepared.wire.sha256, queued.prepared.wire.sha256);
      expect(
        retained.prepared.envelope.recipients,
        queued.prepared.envelope.recipients,
      );
      expect(retained.state, queued.state);
    },
  );
}
