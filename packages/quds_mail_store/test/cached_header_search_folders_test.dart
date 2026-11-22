@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('folder-search', hostId: 'office');
final _account = MailAccountId('account', profile: _profile);
final _inbox = MailMailboxId('inbox', account: _account);
final _archive = MailMailboxId('archive', account: _account);
final _other = MailMailboxId('other', account: _account);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailHeaderRecord _header(String id, {String subject = 'Report'}) =>
    MailHeaderRecord(
      id: MailMessageId(id),
      remote: MailOpaqueIdentity(
        account: _account,
        provider: MailProviderKind.gmail,
        value: id,
      ),
      envelope: MailEnvelope(subject: subject),
      flags: const MailMessageFlags(isRead: false),
    );

final class _SearchProbe extends QueryInterceptor {
  int maximumArguments = 0;
  bool bodyRead = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (args.length > maximumArguments) maximumArguments = args.length;
    bodyRead |=
        RegExp(r'\bblobs\b|\bdrafts\b|\boutbox\b').hasMatch(statement) ||
        (statement.contains('cached_messages') &&
            RegExp(r'\bdata\b|\braw_hash\b').hasMatch(statement));
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  late sqlite.Database database;
  late SqliteMailRepository store;
  late _SearchProbe probe;

  Future<void> view(
    MailMailboxId mailbox,
    List<MailHeaderRecord> headers,
  ) async {
    _value(
      await store.saveMailboxView(
        MailMailbox(id: mailbox, displayName: 'Same label', isLabel: true),
        headers,
        expectedRevision: null,
        hasMore: false,
        lease: MailAccountSession(_account).begin(),
      ),
    );
  }

  Future<void> sync(
    MailMailboxId mailbox,
    List<MailHeaderRecord> headers,
  ) async {
    _value(
      await store.commitSyncPage(
        MailSyncPage(
          mailbox: mailbox,
          upserts: headers,
          tombstones: const [],
          next: MailCursor(mailbox: mailbox, value: 'done'),
          hasMore: false,
        ),
        expectedCursor: null,
        lease: MailAccountSession(_account).begin(),
      ),
    );
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    probe = _SearchProbe();
    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.opened(
          database,
          closeUnderlyingOnClose: false,
        ).interceptWith(probe),
        profile: _profile,
      ),
    );
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.gmail,
          displayName: 'Account',
        ),
      ),
    );
  });
  tearDown(() async {
    await store.close();
    database.close();
  });

  test(
    'folder membership is filtered before candidate count and keyset scan',
    () async {
      await view(_inbox, [_header('001'), _header('002')]);
      await view(_archive, [_header('100'), _header('101')]);
      await sync(_inbox, [_header('001')]);
      await sync(_archive, [_header('100')]);
      probe.bodyRead = false;
      final first = _value(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: [_archive],
          scanLimit: 1,
        ),
      );
      expect(first.totalCount, 2);
      expect(first.scannedCount, 1);
      expect(first.hits.single.header.id.value, '100');
      expect(first.hits.single.folders.map((folder) => folder.id), [_archive]);
      expect(first.browsed.map((summary) => summary.mailbox.id), [_archive]);
      expect(first.synchronized.map((summary) => summary.mailbox.id), [
        _archive,
      ]);
      expect(first.missingMailboxIds, isEmpty);
      final second = _value(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: [_archive],
          cursor: first.nextCursor,
          scanLimit: 1,
        ),
      );
      expect(second.hits.single.header.id.value, '101');
      expect(second.nextCursor, isNull);
      expect(probe.bodyRead, isFalse);
    },
  );

  test(
    'one canonical label message is returned once with selected provenance only',
    () async {
      final shared = _header('shared');
      await view(_inbox, [shared]);
      await view(_archive, [shared]);
      await view(_other, [shared]);
      await sync(_archive, [shared]);
      final page = _value(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: [_inbox, _archive],
        ),
      );
      expect(page.totalCount, 1);
      expect(page.scannedCount, 1);
      expect(page.hits, hasLength(1));
      expect(page.hits.single.folders.map((folder) => folder.id), [
        _archive,
        _inbox,
      ]);
      expect(page.hits.single.folders.map((folder) => folder.displayName), [
        'Same label',
        'Same label',
      ]);
    },
  );

  test(
    'cursor accepts reordered identical set and rejects a different or all-folder scope',
    () async {
      await view(_inbox, [_header('a'), _header('b')]);
      await view(_archive, [_header('c')]);
      final first = _value(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: [_inbox, _archive],
          scanLimit: 1,
        ),
      );
      expect(first.nextCursor, isNotNull);
      final next = _value(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: [_archive, _inbox],
          cursor: first.nextCursor,
          scanLimit: 1,
        ),
      );
      expect(next.hits.single.header.id.value, 'b');
      _problem(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: [_inbox],
          cursor: first.nextCursor,
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.searchCachedHeaders(_account, '', cursor: first.nextCursor),
        MailProblemCode.conflict,
      );
      final all = _value(
        await store.searchCachedHeaders(_account, '', scanLimit: 1),
      );
      _problem(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: [_inbox, _archive],
          cursor: all.nextCursor,
        ),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'known empty and uncached catalog folders differ from missing identities',
    () async {
      await view(_inbox, [_header('a')]);
      await view(_archive, []);
      database.execute(
        'INSERT INTO mailboxes(account,id,display_name,is_label) VALUES(?,?,?,0)',
        [_account.value, _other.value, 'Unvisited folder'],
      );
      final missing = MailMailboxId('missing', account: _account);
      final empty = _value(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: [_archive, _other, missing],
        ),
      );
      expect(empty.totalCount, 0);
      expect(empty.scannedCount, 0);
      expect(empty.hits, isEmpty);
      expect(empty.missingMailboxIds, [missing]);
      expect(() => empty.missingMailboxIds.clear(), throwsUnsupportedError);
      final partial = _value(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: [_inbox, missing],
        ),
      );
      expect(partial.hits.single.header.id.value, 'a');
      expect(partial.missingMailboxIds, [missing]);
      final catalog = _value(await store.listCachedSearchMailboxes(_account));
      expect(catalog.map((folder) => folder.id), [_archive, _inbox, _other]);
      expect(() => catalog.clear(), throwsUnsupportedError);
      _problem(
        await store.listCachedSearchMailboxes(_account, limit: 2),
        MailProblemCode.quotaExceeded,
      );
      _problem(
        await store.listCachedSearchMailboxes(_account, limit: 0),
        MailProblemCode.invalidInput,
      );
    },
  );

  test(
    'missing exact folder IDs are neither wildcard SQL nor account-wide fallback',
    () async {
      await view(_inbox, [_header('a')]);
      for (final id in ['INBOX', ' inbox ', "%') OR 1=1 --"]) {
        final selected = MailMailboxId(id, account: _account);
        final page = _value(
          await store.searchCachedHeaders(_account, '', mailboxIds: [selected]),
        );
        expect(page.hits, isEmpty);
        expect(page.totalCount, 0);
        expect(page.missingMailboxIds, [selected]);
      }
    },
  );

  test(
    'rejects empty duplicate overlong and foreign-account folder sets',
    () async {
      final foreign = MailAccountId('different', profile: _profile);
      final foreignOwner = MailAccountId(
        _account.value,
        profile: MailProfileId(_profile.value, hostId: 'another-host'),
      );
      for (final scope in <List<MailMailboxId>>[
        [],
        [_inbox, _inbox],
        [MailMailboxId('inbox', account: foreign)],
        [MailMailboxId('inbox', account: foreignOwner)],
        [MailMailboxId('m' * 1025, account: _account)],
        [MailMailboxId('bad\uD800', account: _account)],
        List.generate(
          1001,
          (index) => MailMailboxId('$index', account: _account),
        ),
      ]) {
        _problem(
          await store.searchCachedHeaders(_account, '', mailboxIds: scope),
          MailProblemCode.invalidInput,
        );
      }
    },
  );

  test(
    'one thousand folders stay bounded and paginate at the full SQL parameter ceiling',
    () async {
      await view(_inbox, [_header('a'), _header('b')]);
      final scope = [
        _inbox,
        ...List.generate(
          999,
          (index) => MailMailboxId('missing-$index', account: _account),
        ),
      ];
      final first = _value(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: scope,
          scanLimit: 1,
        ),
      );
      expect(first.missingMailboxIds, hasLength(999));
      final second = _value(
        await store.searchCachedHeaders(
          _account,
          '',
          mailboxIds: scope,
          cursor: first.nextCursor,
          scanLimit: 1,
        ),
      );
      expect(second.hits.single.header.id.value, 'b');
      expect(second.nextCursor, isNull);
      expect(probe.maximumArguments, 2003);
      expect(first.totalCount, 2);
    },
  );
}
