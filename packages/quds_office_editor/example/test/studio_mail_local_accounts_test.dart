import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';

StudioMailDraftAccount _identity(
  String provider, {
  String sender = 'Writer@example.test',
}) => StudioMailDraftAccount(
  provider: provider,
  endpoint: switch (provider) {
    'imap' => 'imaps://imap.example.test:1993',
    'ews' => 'https://exchange.example.test/EWS/Exchange.asmx',
    'gmail' => 'https://gmail.googleapis.com/gmail/v1',
    _ => 'https://graph.microsoft.com/v1.0',
  },
  login: switch (provider) {
    'ews' => '["DOMAIN","exact-user"]',
    'graph' => '["exact-tenant","$sender"]',
    _ => sender,
  },
  sender: sender,
);

void main() {
  late Directory directory;
  late NativeStudioMailLocalAccountStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'studio-offline-accounts-',
    );
    store = NativeStudioMailLocalAccountStore(appDirectory: directory);
  });
  tearDown(() => directory.delete(recursive: true));

  for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
    test(
      '$provider reconnect metadata opens the same durable draft after restart',
      () async {
        final identity = _identity(provider);
        final connected = await openStudioMailDraftStore(
          identity,
          appDirectory: directory,
        );
        await connected.load();
        await connected.save(
          const StudioMailDraft(
            to: 'reader@example.test',
            subject: 'Retained offline',
            body: 'Unfinished',
          ),
          submissionUncertain: true,
        );
        await store.remember(identity);
        await connected.close();
        final restarted = NativeStudioMailLocalAccountStore(
          appDirectory: directory,
        );
        final row = (await restarted.load()).single;
        final restoredIdentity = studioMailLocalAccountIdentity(row);
        expect(restoredIdentity.account, identity.account);
        expect(restoredIdentity.endpoint, identity.endpoint);
        expect(restoredIdentity.login, identity.login);
        final offline = await openStudioMailDraftStore(
          restoredIdentity,
          appDirectory: directory,
        );
        final draft = (await offline.load())!;
        expect(draft.draft.subject, 'Retained offline');
        expect(draft.submissionUncertain, isTrue);
        await offline.close();
        await restarted.forget(row);
        expect(await restarted.load(), isEmpty);
        final untouched = await openStudioMailDraftStore(
          identity,
          appDirectory: directory,
        );
        expect((await untouched.load())!.draft.body, 'Unfinished');
        await untouched.close();
        await restarted.remember(identity);
        expect(await restarted.load(), hasLength(1));
      },
    );
  }

  test(
    'parallel directory instances preserve each successful connection',
    () async {
      final other = NativeStudioMailLocalAccountStore(appDirectory: directory);
      await Future.wait([
        for (var i = 0; i < 12; i++)
          (i.isEven ? store : other).remember(
            _identity('imap', sender: 'user$i@example.test'),
          ),
      ]);
      expect(await store.load(), hasLength(12));
      expect(await other.load(), hasLength(12));
    },
  );

  test(
    'case, tenant, custom port and EWS endpoint remain part of draft identity',
    () {
      final first = _identity('graph');
      final second = StudioMailDraftAccount(
        provider: 'graph',
        endpoint: first.endpoint,
        login: '["other-tenant","Writer@example.test"]',
        sender: first.sender,
      );
      expect(first.account, isNot(second.account));
      expect(
        _identity('imap').account,
        isNot(_identity('imap', sender: 'writer@example.test').account),
      );
      final custom = _identity('imap');
      expect(custom.endpoint, 'imaps://imap.example.test:1993');
      expect(_identity('ews').endpoint, endsWith('/EWS/Exchange.asmx'));
    },
  );

  test(
    'mismatched persisted id fails closed without rewriting the directory',
    () async {
      await store.remember(_identity('ews'));
      final original = (await store.load()).single;
      final opened = await openNativeMailStore(
        appDirectory: directory,
        profile: NativeStudioMailLocalAccountStore.profile,
      );
      final raw = (opened as MailSuccess<SqliteMailRepository>).value;
      final inserted = await raw.rememberLocalAccount(
        MailLocalAccountRecord(
          id: 'redirected-id',
          provider: original.provider,
          endpoint: original.endpoint,
          login: original.login,
          sender: original.sender,
          lastConnectedAt: original.lastConnectedAt,
        ),
      );
      expect(inserted, isA<MailSuccess<MailUnit>>());
      await raw.close();
      await expectLater(
        store.load(),
        throwsA(
          isA<StudioMailDraftStoreException>().having(
            (error) => error.code,
            'code',
            MailProblemCode.permissionDenied,
          ),
        ),
      );
      await expectLater(
        store.remember(_identity('gmail')),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      final inspected = await openNativeMailStore(
        appDirectory: directory,
        profile: NativeStudioMailLocalAccountStore.profile,
      );
      final check = (inspected as MailSuccess<SqliteMailRepository>).value;
      final rows =
          (await check.listLocalAccounts()
                  as MailSuccess<List<MailLocalAccountRecord>>)
              .value;
      expect(rows.map((row) => row.id), contains('redirected-id'));
      expect(rows, hasLength(2));
      await check.close();
    },
  );

  test(
    'a held directory owner reports conflict and recovers after release',
    () async {
      final opened = await openNativeMailStore(
        appDirectory: directory,
        profile: NativeStudioMailLocalAccountStore.profile,
      );
      final held = (opened as MailSuccess<SqliteMailRepository>).value;
      await expectLater(
        store.load(),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      await held.close();
      expect(await store.load(), isEmpty);
    },
  );
}
