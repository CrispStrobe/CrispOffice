import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_outbox.dart';

StudioMailDraftAccount _identity(String name, {String provider = 'imap'}) =>
    StudioMailDraftAccount(
      provider: provider,
      endpoint: switch (provider) {
        'imap' => 'imaps://mail.example.test:1993',
        'ews' => 'https://exchange.example.test/EWS/Exchange.asmx',
        'gmail' => 'https://gmail.googleapis.com/gmail/v1',
        _ => 'https://graph.microsoft.com/v1.0',
      },
      login: switch (provider) {
        'ews' => '["DOMAIN","$name"]',
        'graph' => '["exact-tenant","$name@example.test"]',
        _ => '$name@example.test',
      },
      sender: '$name@example.test',
    );

MailSavedHeaderSearch _search(
  List<StudioMailDraftAccount> accounts, {
  String id = 'saved-report',
  String name = 'Report follow-up',
  String query = '(from:alice OR subject:report) is:unread',
}) => MailSavedHeaderSearch(
  id: id,
  name: name,
  query: query,
  accountIds: [for (final account in accounts) account.account.value],
);

Matcher _problem(MailProblemCode code) => throwsA(
  isA<StudioMailDraftStoreException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

void _sameDefinition(
  MailSavedHeaderSearch actual,
  MailSavedHeaderSearch expected,
) {
  expect(actual.id, expected.id);
  expect(actual.name, expected.name);
  expect(actual.query, expected.query);
  expect(actual.accountIds, expected.accountIds);
  expect(actual.revision, expected.revision);
}

Future<SqliteMailRepository> _openDirectory(Directory directory) async {
  final result = await openNativeMailStore(
    appDirectory: directory,
    profile: NativeStudioMailLocalAccountStore.profile,
  );
  expect(result, isA<MailSuccess<SqliteMailRepository>>());
  return (result as MailSuccess<SqliteMailRepository>).value;
}

void main() {
  late Directory directory;
  late NativeStudioMailLocalAccountStore store;
  late StudioMailDraftAccount first;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('saved-mail-search-');
    store = NativeStudioMailLocalAccountStore(appDirectory: directory);
    first = _identity('Writer');
    await store.remember(first);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'reopening preserves exact criteria and fixed mixed-provider scope',
    () async {
      final identities = [
        _identity('graph-reader', provider: 'graph'),
        first,
        _identity('ews-reader', provider: 'ews'),
        _identity('gmail-reader', provider: 'gmail'),
      ];
      for (final identity in identities) {
        await store.remember(identity);
      }
      final saved = await store.saveSavedSearch(
        _search(
          identities,
          name: 'Berichte متابعة',
          query: '(subject:"Quarterly report" OR from:alice) NOT is:read',
        ),
      );
      expect(saved.revision, greaterThan(0));
      final laterAccount = _identity('added-after-saving');
      await store.remember(laterAccount);

      final reopened = NativeStudioMailLocalAccountStore(
        appDirectory: directory,
      );
      final loaded = (await reopened.loadSavedSearches()).single;
      _sameDefinition(loaded, saved);
      expect(loaded.accountIds, isNot(contains(laterAccount.account.value)));
      expect(await reopened.load(), hasLength(5));
      expect(() => loaded.accountIds.clear(), throwsUnsupportedError);
    },
  );

  test(
    'forgotten accounts remain explicit and cannot silently narrow a saved query',
    () async {
      final other = _identity('Second');
      await store.remember(other);
      final saved = await store.saveSavedSearch(_search([first, other]));
      final row = (await store.load()).singleWhere(
        (account) => account.id == other.account.value,
      );
      await store.forget(row);
      _sameDefinition((await store.loadSavedSearches()).single, saved);

      await expectLater(
        store.saveSavedSearch(
          saved.copyWith(query: 'is:flagged'),
          expectedRevision: saved.revision,
        ),
        _problem(MailProblemCode.conflict),
      );
      await expectLater(
        store.saveSavedSearch(_search([other], id: 'missing', name: 'Missing')),
        _problem(MailProblemCode.conflict),
      );
      _sameDefinition((await store.loadSavedSearches()).single, saved);

      final narrowed = await store.saveSavedSearch(
        saved.copyWith(accountIds: [first.account.value]),
        expectedRevision: saved.revision,
      );
      expect(narrowed.accountIds, [first.account.value]);
      expect(narrowed.revision, greaterThan(saved.revision));
    },
  );

  test(
    'reconnecting the exact identity restores an unavailable definition',
    () async {
      final saved = await store.saveSavedSearch(_search([first]));
      await store.forget((await store.load()).single);
      await store.remember(_identity('writer'));
      await expectLater(
        store.saveSavedSearch(saved, expectedRevision: saved.revision),
        _problem(MailProblemCode.conflict),
      );

      await store.remember(first);
      final changed = await store.saveSavedSearch(
        saved.copyWith(query: 'is:flagged'),
        expectedRevision: saved.revision,
      );
      expect(changed.accountIds, [first.account.value]);
      expect(changed.query, 'is:flagged');
    },
  );

  test(
    'a redirected directory row refuses writes without rewriting either catalog',
    () async {
      final saved = await store.saveSavedSearch(_search([first]));
      final valid = (await store.load()).single;
      final raw = await _openDirectory(directory);
      try {
        final inserted = await raw.rememberLocalAccount(
          MailLocalAccountRecord(
            id: 'redirected-account-id',
            provider: valid.provider,
            endpoint: valid.endpoint,
            login: valid.login,
            sender: valid.sender,
            lastConnectedAt: valid.lastConnectedAt,
          ),
        );
        expect(inserted, isA<MailSuccess<MailUnit>>());
      } finally {
        await raw.close();
      }

      await expectLater(
        store.saveSavedSearch(
          saved.copyWith(name: 'Must not commit'),
          expectedRevision: saved.revision,
        ),
        _problem(MailProblemCode.permissionDenied),
      );
      _sameDefinition((await store.loadSavedSearches()).single, saved);
      final check = await _openDirectory(directory);
      try {
        final rows =
            (await check.listLocalAccounts()
                    as MailSuccess<List<MailLocalAccountRecord>>)
                .value;
        expect(rows.map((row) => row.id), contains('redirected-account-id'));
        expect(rows, hasLength(2));
      } finally {
        await check.close();
      }
    },
  );

  test(
    'a stale native instance cannot replace or delete a newer definition',
    () async {
      final saved = await store.saveSavedSearch(_search([first]));
      final second = NativeStudioMailLocalAccountStore(appDirectory: directory);
      final stale = (await second.loadSavedSearches()).single;
      final updated = await store.saveSavedSearch(
        saved.copyWith(name: 'Updated name', query: 'subject:updated'),
        expectedRevision: saved.revision,
      );

      await expectLater(
        second.saveSavedSearch(
          stale.copyWith(query: 'subject:stale'),
          expectedRevision: stale.revision,
        ),
        _problem(MailProblemCode.conflict),
      );
      await expectLater(
        second.deleteSavedSearch(stale.id, expectedRevision: stale.revision),
        _problem(MailProblemCode.conflict),
      );
      _sameDefinition((await second.loadSavedSearches()).single, updated);
    },
  );

  test(
    'delete and recreate never reauthorize callbacks holding an old revision',
    () async {
      final original = await store.saveSavedSearch(_search([first]));
      await store.deleteSavedSearch(
        original.id,
        expectedRevision: original.revision,
      );
      final replacement = await store.saveSavedSearch(
        _search([first], name: 'Recreated', query: 'subject:new'),
      );
      expect(replacement.id, original.id);
      expect(replacement.revision, greaterThan(original.revision));
      await expectLater(
        store.deleteSavedSearch(
          original.id,
          expectedRevision: original.revision,
        ),
        _problem(MailProblemCode.conflict),
      );
      await expectLater(
        store.saveSavedSearch(original, expectedRevision: original.revision),
        _problem(MailProblemCode.conflict),
      );
      _sameDefinition((await store.loadSavedSearches()).single, replacement);
    },
  );

  test(
    'simultaneous native instances retain every independent definition',
    () async {
      final second = NativeStudioMailLocalAccountStore(appDirectory: directory);
      final created = await Future.wait([
        for (var index = 0; index < 12; index++)
          (index.isEven ? store : second).saveSavedSearch(
            _search([first], id: 'search-$index', name: 'Search $index'),
          ),
      ]);
      final reopened = NativeStudioMailLocalAccountStore(
        appDirectory: directory,
      );
      final all = await reopened.loadSavedSearches();
      expect(all, hasLength(12));
      expect(
        all.map((search) => search.id).toSet(),
        created.map((search) => search.id).toSet(),
      );
      expect(all.map((search) => search.revision).toSet(), hasLength(12));
      for (final saved in created) {
        _sameDefinition(
          all.singleWhere((search) => search.id == saved.id),
          saved,
        );
      }
    },
  );

  test(
    'simultaneous replacements admit exactly one matching revision',
    () async {
      final saved = await store.saveSavedSearch(_search([first]));
      final second = NativeStudioMailLocalAccountStore(appDirectory: directory);
      Future<MailProblemCode?> update(
        NativeStudioMailLocalAccountStore owner,
        String query,
      ) async {
        try {
          await owner.saveSavedSearch(
            saved.copyWith(query: query),
            expectedRevision: saved.revision,
          );
          return null;
        } on StudioMailDraftStoreException catch (error) {
          return error.code;
        }
      }

      final outcomes = await Future.wait([
        update(store, 'subject:first'),
        update(second, 'subject:second'),
      ]);
      expect(outcomes.where((code) => code == null), hasLength(1));
      expect(
        outcomes.where((code) => code == MailProblemCode.conflict),
        hasLength(1),
      );
      final current = (await second.loadSavedSearches()).single;
      expect(
        current.query,
        outcomes.first == null ? 'subject:first' : 'subject:second',
      );
      expect(current.revision, saved.revision + 1);
    },
  );

  test(
    'case-insensitive duplicate names preserve both original definitions',
    () async {
      final firstSaved = await store.saveSavedSearch(
        _search([first], name: 'Reports'),
      );
      final secondSaved = await store.saveSavedSearch(
        _search([first], id: 'another-search', name: 'Invoices'),
      );
      await expectLater(
        store.saveSavedSearch(
          _search([first], id: 'duplicate', name: 'REPORTS'),
        ),
        _problem(MailProblemCode.conflict),
      );
      await expectLater(
        store.saveSavedSearch(
          secondSaved.copyWith(name: 'reports'),
          expectedRevision: secondSaved.revision,
        ),
        _problem(MailProblemCode.conflict),
      );
      final loaded = await store.loadSavedSearches();
      expect(loaded, hasLength(2));
      _sameDefinition(
        loaded.singleWhere((search) => search.id == firstSaved.id),
        firstSaved,
      );
      _sameDefinition(
        loaded.singleWhere((search) => search.id == secondSaved.id),
        secondSaved,
      );
    },
  );

  test(
    'deleting a definition preserves accounts, another search, draft, Outbox and saved mail',
    () async {
      final saved = await store.saveSavedSearch(_search([first]));
      final retainedSearch = await store.saveSavedSearch(
        _search([first], id: 'keep-search', name: 'Keep this search'),
      );
      final owner = await openStudioMailDraftStore(
        first,
        appDirectory: directory,
      );
      final mailbox = MailMailboxId('Inbox', account: first.account);
      final header = MailHeaderRecord(
        id: MailMessageId('retained-header'),
        remote: MailImapIdentity(mailbox: mailbox, uidValidity: 47, uid: 3),
        envelope: MailEnvelope(
          subject: 'Retained report',
          from: const [MailAddress('author@example.test')],
        ),
        flags: const MailMessageFlags(isRead: false, isFlagged: true),
      );
      final rawMessage = utf8.encode(
        'Subject: Retained report\r\n\r\nKeep this body.',
      );
      final session = MailAccountSession(first.account);
      late MailOutboxEntry queued;
      try {
        await owner.load();
        queued = await (owner as StudioMailOutboxStore).enqueueOutbox(
          const StudioMailDraft(
            to: 'recipient@example.test',
            subject: 'Queued before deletion',
            body: 'This has not been submitted.',
          ),
          first.sender,
        );
        await owner.save(
          const StudioMailDraft(
            to: 'recipient@example.test',
            subject: 'Unfinished',
            body: 'Keep my draft.',
          ),
          submissionUncertain: true,
        );
        final cache = (owner as StudioMailMailboxStoreOwner).mailboxStore;
        final lease = session.begin();
        await cache.saveView(
          MailMailbox(id: mailbox, displayName: 'Inbox'),
          [header],
          hasMore: true,
          lease: lease,
        );
        await cache.cacheMessage(
          header,
          MailMessage(
            raw: MailBytes(rawMessage),
            envelope: header.envelope,
            body: const MailBody(plainText: 'Keep this body.'),
            localId: header.id,
            remoteIdentity: header.remote,
          ),
          lease: lease,
        );
      } finally {
        session.dispose();
        await owner.close();
      }

      await store.deleteSavedSearch(saved.id, expectedRevision: saved.revision);
      final reopened = NativeStudioMailLocalAccountStore(
        appDirectory: directory,
      );
      _sameDefinition(
        (await reopened.loadSavedSearches()).single,
        retainedSearch,
      );
      expect((await reopened.load()).single.id, first.account.value);
      final restored = await openStudioMailDraftStore(
        first,
        appDirectory: directory,
      );
      try {
        final draft = (await restored.load())!;
        expect(draft.draft.body, 'Keep my draft.');
        expect(draft.submissionUncertain, isTrue);
        final outbox =
            (await (restored as StudioMailOutboxStore).loadOutbox()).single;
        expect(outbox.id, queued.id);
        expect(outbox.state, MailOutboxState.queued);
        expect(outbox.attemptNumber, 0);
        expect(outbox.prepared.wire.bytes, queued.prepared.wire.bytes);
        final cache = (restored as StudioMailMailboxStoreOwner).mailboxStore;
        final view = (await cache.loadView(mailbox))!;
        expect(view.headers.single.id, header.id);
        expect(view.hasMore, isTrue);
        final message = (await cache.loadMessage(header))!;
        expect(message.body.plainText, 'Keep this body.');
        expect(message.raw.bytes, rawMessage);
      } finally {
        await restored.close();
      }
    },
  );

  for (final invalid
      in <String, MailSavedHeaderSearch Function(MailSavedHeaderSearch)>{
        'empty name': (search) => search.copyWith(name: ''),
        'blank name': (search) => search.copyWith(name: '  '),
        'incomplete Boolean query': (search) =>
            search.copyWith(query: 'subject:report OR'),
        'duplicate account': (search) => search.copyWith(
          accountIds: [...search.accountIds, ...search.accountIds],
        ),
        'empty scope': (search) => search.copyWith(accountIds: []),
        'negative revision': (search) => search.copyWith(revision: -1),
      }.entries) {
    test(
      'invalid ${invalid.key} is rejected without changing stored criteria',
      () async {
        final saved = await store.saveSavedSearch(_search([first]));
        await expectLater(
          store.saveSavedSearch(
            invalid.value(saved),
            expectedRevision: saved.revision,
          ),
          _problem(MailProblemCode.invalidInput),
        );
        _sameDefinition((await store.loadSavedSearches()).single, saved);
        final changed = await store.saveSavedSearch(
          saved.copyWith(query: 'is:flagged'),
          expectedRevision: saved.revision,
        );
        expect(changed.revision, saved.revision + 1);
      },
    );
  }

  test(
    'invalid update and deletion revision arguments preserve the definition',
    () async {
      final saved = await store.saveSavedSearch(_search([first]));
      await expectLater(
        store.saveSavedSearch(saved),
        _problem(MailProblemCode.invalidInput),
      );
      await expectLater(
        store.saveSavedSearch(saved, expectedRevision: saved.revision + 1),
        _problem(MailProblemCode.invalidInput),
      );
      await expectLater(
        store.deleteSavedSearch(saved.id, expectedRevision: 0),
        _problem(MailProblemCode.invalidInput),
      );
      await expectLater(
        store.deleteSavedSearch('', expectedRevision: saved.revision),
        _problem(MailProblemCode.invalidInput),
      );
      _sameDefinition((await store.loadSavedSearches()).single, saved);
    },
  );

  test(
    'an existing native owner rejects saved-search access and later recovers',
    () async {
      final saved = await store.saveSavedSearch(_search([first]));
      final held = await _openDirectory(directory);
      try {
        await expectLater(
          store.loadSavedSearches(),
          _problem(MailProblemCode.conflict),
        );
        await expectLater(
          store.deleteSavedSearch(saved.id, expectedRevision: saved.revision),
          _problem(MailProblemCode.conflict),
        );
      } finally {
        await held.close();
      }
      _sameDefinition((await store.loadSavedSearches()).single, saved);
    },
  );

  test(
    'separate app directories cannot borrow account or search catalogs',
    () async {
      final saved = await store.saveSavedSearch(_search([first]));
      final otherDirectory = await Directory.systemTemp.createTemp(
        'other-mail-search-',
      );
      try {
        final other = NativeStudioMailLocalAccountStore(
          appDirectory: otherDirectory,
        );
        expect(await other.loadSavedSearches(), isEmpty);
        await expectLater(
          other.saveSavedSearch(_search([first])),
          _problem(MailProblemCode.conflict),
        );
        await other.remember(first);
        final separate = await other.saveSavedSearch(
          _search([first], query: 'subject:separate'),
        );
        expect(separate.id, saved.id);
        expect(separate.query, isNot(saved.query));
        _sameDefinition((await store.loadSavedSearches()).single, saved);
      } finally {
        await otherDirectory.delete(recursive: true);
      }
    },
  );
}
