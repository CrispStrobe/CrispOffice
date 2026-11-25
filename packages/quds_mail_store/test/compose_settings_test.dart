@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:quds_mail_store/src/schema/database.dart';
import 'package:quds_mail_store/src/schema/flag_journal_schema.dart';
import 'package:quds_mail_store/src/schema/membership_observation_schema.dart';
import 'package:quds_mail_store/src/schema/move_identity_schema.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('compose-profile', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _other = MailAccountId('other', profile: _profile);

MailComposeSettings _settings({
  MailAccountId? account,
  int revision = 0,
  String signature = 'Best wishes\nشكراً 📨',
  List<MailQuickText>? quickTexts,
}) => MailComposeSettings(
  account: account ?? _account,
  revision: revision,
  signature: signature,
  signatureForNewMessages: true,
  quickTexts:
      quickTexts ??
      const [
        MailQuickText(
          id: 'thanks',
          name: 'Thanks',
          text: 'Thank you!\r\n\tمرحبا 📨',
        ),
        MailQuickText(
          id: 'meeting',
          name: 'Meeting',
          text: 'Please choose a time.',
        ),
      ],
);

MailComposeSettings _extendedSettings({MailAccountId? account}) =>
    _settings(account: account).copyWith(
      senderIdentities: const [
        MailSenderIdentity(
          id: 'work',
          name: 'Work',
          address: 'sender@example.test',
          displayName: 'مرحبا 📨',
          replyTo: 'reply@example.test',
        ),
        MailSenderIdentity(
          id: 'alternate',
          name: 'Alternate',
          address: 'alias@example.test',
        ),
      ],
      defaultSenderIdentityId: 'work',
      templates: const [
        MailMessageTemplate(
          id: 'follow-up',
          name: 'Follow-up',
          to: 'to@example.test',
          cc: 'copy@example.test',
          bcc: 'private@example.test',
          subject: 'Meeting 📨',
          body: '<b>literal</b>\r\n\$name\tمرحبا',
          senderIdentityId: 'work',
        ),
        MailMessageTemplate(id: 'blank', name: 'Blank', to: 'unfinished@'),
      ],
    );

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

Future<void> _register(
  SqliteMailRepository store, [
  MailAccountId? account,
]) async => _value(
  await store.createAccount(
    MailStoreAccount(
      id: account ?? _account,
      provider: MailProviderKind.imap,
      displayName: 'Synthetic account',
      credentialReference: 'opaque-credential',
    ),
  ),
);

Future<SqliteMailRepository> _open(
  sqlite.Database database, {
  MailStoreFaultInjector? fault,
  MailStoreLimits limits = const MailStoreLimits(),
  QueryInterceptor? interceptor,
}) async {
  QueryExecutor executor = NativeDatabase.opened(
    database,
    closeUnderlyingOnClose: false,
  );
  if (interceptor != null) executor = executor.interceptWith(interceptor);
  return _value(
    await SqliteMailRepository.open(
      executor: executor,
      profile: _profile,
      faultInjector: fault,
      limits: limits,
    ),
  );
}

MailDraft _draft(MailAccountId account) => MailDraft(
  id: 'draft',
  account: account,
  revision: 1,
  envelope: MailEnvelope(subject: 'Keep unsent work'),
  body: const MailBody(plainText: 'Original text with no signature'),
);

MailOutboxEntry _outbox(MailAccountId account) => MailOutboxEntry.queued(
  id: 'queue',
  prepared: MailPreparedMessage(
    account: account,
    draftId: 'draft',
    draftRevision: 1,
    wire: MailBytes(Uint8List.fromList([1, 2, 3, 4])),
    envelope: MailTransportEnvelope(
      sender: 'sender@example.test',
      recipients: ['recipient@example.test', 'hidden@example.test'],
    ),
  ),
  now: DateTime.utc(2026, 11, 21),
);

Future<void> _seedLocalWork(
  SqliteMailRepository store,
  MailAccountId account,
) async {
  _value(await store.saveDraft(_draft(account), expectedRevision: null));
  _value(
    await store.saveOutbox(
      _outbox(account),
      expectedState: null,
      expectedAttemptId: null,
    ),
  );
}

Future<void> _expectLocalWork(
  SqliteMailRepository store,
  MailAccountId account,
) async {
  expect(
    MailStoreCodec.encodeDraft(
      _value(await store.loadDraft(account, 'draft'))!,
    ).data,
    MailStoreCodec.encodeDraft(_draft(account)).data,
  );
  final queued = _value(await store.recoverOutbox(account)).single;
  expect(queued.prepared.wire.bytes, [1, 2, 3, 4]);
  expect(queued.prepared.envelope.recipients, [
    'recipient@example.test',
    'hidden@example.test',
  ]);
  expect(queued.state, MailOutboxState.queued);
}

sqlite.Database _legacyComposeDatabase(int version) {
  final legacy = sqlite.sqlite3.openInMemory();
  final schemas = <int, List<String>>{
    1: schemaV1,
    2: schemaV2,
    3: schemaV3,
    4: schemaV4,
    5: schemaV5,
    6: schemaV6,
    7: schemaV7,
    8: schemaV8,
    9: schemaV9,
    10: schemaV10,
    11: schemaV11,
    12: schemaV12,
    13: schemaV13,
    14: schemaV14,
    15: schemaV15,
    17: schemaV17,
    18: schemaV18,
    19: schemaV19,
    20: schemaV20,
  };
  for (final entry in schemas.entries) {
    if (entry.key > version) break;
    for (final sql in entry.value) {
      legacy.execute(sql);
    }
  }
  legacy.execute(
    'INSERT INTO store_profile(singleton,host_id,profile_id) VALUES(1,?,?)',
    [_profile.hostId, _profile.value],
  );
  legacy.execute(
    'INSERT INTO accounts(id,provider,display_name,state) VALUES(?,?,?,?)',
    [_account.value, 'imap', 'Legacy', 'loggedOut'],
  );
  legacy.execute(
    'INSERT INTO account_compose_settings(account,revision,signature,signature_new,signature_replies) VALUES(?,7,?,1,0)',
    [_account.value, 'Legacy 📨\r\nsignature'],
  );
  legacy.execute(
    'INSERT INTO account_quick_texts(account,position,id,name,name_key,text) VALUES(?,0,?,?,?,?)',
    [_account.value, 'text', 'Text', 'text', 'Unchanged'],
  );
  final encoded = MailStoreCodec.encodeDraft(_draft(_account));
  legacy.execute(
    'INSERT INTO drafts(account,id,revision,data) VALUES(?,?,?,?)',
    [_account.value, 'draft', 1, encoded.data],
  );
  legacy.userVersion = version;
  return legacy;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late sqlite.Database database;
  late SqliteMailRepository store;
  var failCommit = false;

  setUp(() async {
    failCommit = false;
    database = sqlite.sqlite3.openInMemory();
    store = await _open(
      database,
      fault: (point) {
        if (failCommit && point == MailStoreCheckpoint.beforeCommit) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    );
    await _register(store);
  });
  tearDown(() async {
    await store.close();
    database.close();
  });

  test(
    'loads revision-zero defaults only for an existing owned account',
    () async {
      final defaults = _value(await store.loadComposeSettings(_account));
      expect(defaults.account, _account);
      expect(defaults.revision, 0);
      expect(defaults.signature, isEmpty);
      expect(defaults.quickTexts, isEmpty);
      expect(defaults.signatureForNewMessages, isFalse);
      expect(defaults.signatureForReplies, isFalse);
      _problem(
        await store.loadComposeSettings(_other),
        MailProblemCode.unavailable,
      );
      final foreign = MailAccountId(
        _account.value,
        profile: MailProfileId(_profile.value, hostId: 'another-host'),
      );
      _problem(
        await store.loadComposeSettings(foreign),
        MailProblemCode.permissionDenied,
      );
      _problem(
        await store.saveComposeSettings(
          _settings(account: foreign),
          expectedRevision: 0,
        ),
        MailProblemCode.permissionDenied,
      );
    },
  );

  test(
    'round-trips exact Unicode, ordering, flags and independent revisions',
    () async {
      final saved = _value(
        await store.saveComposeSettings(_settings(), expectedRevision: 0),
      );
      expect(saved.revision, 1);
      final first = _value(await store.loadComposeSettings(_account));
      expect(first.signature, _settings().signature);
      expect(first.quickTexts.map((item) => item.id), ['thanks', 'meeting']);
      expect(first.quickTexts.first.text, _settings().quickTexts.first.text);
      expect(first.signatureForNewMessages, isTrue);
      expect(first.signatureForReplies, isFalse);
      expect(() => first.quickTexts.clear(), throwsUnsupportedError);
      final edited = _value(
        await store.saveComposeSettings(
          first.copyWith(
            signatureForNewMessages: false,
            signatureForReplies: true,
            quickTexts: first.quickTexts.reversed.toList(),
          ),
          expectedRevision: 1,
        ),
      );
      expect(edited.revision, 2);
      final restored = _value(await store.loadComposeSettings(_account));
      expect(restored.signatureForNewMessages, isFalse);
      expect(restored.signatureForReplies, isTrue);
      expect(restored.quickTexts.map((item) => item.id), ['meeting', 'thanks']);
      _problem(
        await store.saveComposeSettings(saved, expectedRevision: 1),
        MailProblemCode.conflict,
      );
      expect(_value(await store.loadComposeSettings(_account)).revision, 2);
    },
  );

  test(
    'requires matching caller revision and rejects stale first saves',
    () async {
      _problem(
        await store.saveComposeSettings(_settings(), expectedRevision: 1),
        MailProblemCode.invalidInput,
      );
      _problem(
        await store.saveComposeSettings(
          _settings(revision: 1),
          expectedRevision: 0,
        ),
        MailProblemCode.invalidInput,
      );
      _problem(
        await store.saveComposeSettings(_settings(), expectedRevision: -1),
        MailProblemCode.invalidInput,
      );
      _value(await store.saveComposeSettings(_settings(), expectedRevision: 0));
      _problem(
        await store.saveComposeSettings(_settings(), expectedRevision: 0),
        MailProblemCode.conflict,
      );
    },
  );

  test('two queued edits cannot consume the same revision', () async {
    final outcomes = await Future.wait([
      store.saveComposeSettings(
        _settings(signature: 'First'),
        expectedRevision: 0,
      ),
      store.saveComposeSettings(
        _settings(signature: 'Second'),
        expectedRevision: 0,
      ),
    ]);
    expect(
      outcomes.whereType<MailSuccess<MailComposeSettings>>(),
      hasLength(1),
    );
    expect(
      outcomes
          .whereType<MailFailure<MailComposeSettings>>()
          .single
          .problem
          .code,
      MailProblemCode.conflict,
    );
    expect(_value(await store.loadComposeSettings(_account)).revision, 1);
  });

  test(
    'failed saves roll back the signature, all snippets and revision',
    () async {
      failCommit = true;
      _problem(
        await store.saveComposeSettings(_settings(), expectedRevision: 0),
        MailProblemCode.storageFailure,
      );
      expect(_value(await store.loadComposeSettings(_account)).revision, 0);
      failCommit = false;
      final saved = _value(
        await store.saveComposeSettings(_settings(), expectedRevision: 0),
      );
      failCommit = true;
      _problem(
        await store.saveComposeSettings(
          saved.copyWith(signature: 'Replacement', quickTexts: []),
          expectedRevision: 1,
        ),
        MailProblemCode.storageFailure,
      );
      final retained = _value(await store.loadComposeSettings(_account));
      expect(retained.revision, 1);
      expect(retained.signature, saved.signature);
      expect(retained.quickTexts.map((item) => item.id), ['thanks', 'meeting']);
    },
  );

  test(
    'logout preserves settings and permits explicit offline edits',
    () async {
      final saved = _value(
        await store.saveComposeSettings(_settings(), expectedRevision: 0),
      );
      _value(await store.logout(MailAccountSession(_account)));
      final loaded = _value(await store.loadComposeSettings(_account));
      expect(loaded.signature, saved.signature);
      final edited = _value(
        await store.saveComposeSettings(
          loaded.copyWith(signature: 'Offline change'),
          expectedRevision: loaded.revision,
        ),
      );
      expect(edited.revision, 2);
      expect(
        _value(await store.listAccounts()).single.state,
        MailStoredAccountState.loggedOut,
      );
    },
  );

  test(
    'resetting compose tools preserves drafts, frozen Outbox and credentials',
    () async {
      await _seedLocalWork(store, _account);
      final saved = _value(
        await store.saveComposeSettings(_settings(), expectedRevision: 0),
      );
      final reset = _value(
        await store.saveComposeSettings(
          MailComposeSettings(account: _account, revision: saved.revision),
          expectedRevision: saved.revision,
        ),
      );
      expect(reset.revision, 2);
      expect(reset.signature, isEmpty);
      expect(reset.quickTexts, isEmpty);
      await _expectLocalWork(store, _account);
      expect(
        _value(await store.listAccounts()).single.credentialReference,
        'opaque-credential',
      );
      _problem(
        await store.saveComposeSettings(
          saved,
          expectedRevision: saved.revision,
        ),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'account removal clears only its tools and prevents stale resurrection',
    () async {
      await _register(store, _other);
      await _seedLocalWork(store, _other);
      final first = _value(
        await store.saveComposeSettings(_settings(), expectedRevision: 0),
      );
      final second = _value(
        await store.saveComposeSettings(
          _settings(account: _other, signature: 'Other account'),
          expectedRevision: 0,
        ),
      );
      _value(await store.removeAccount(_account));
      expect(
        database
            .select('SELECT account FROM account_compose_settings')
            .single['account'],
        _other.value,
      );
      expect(
        database
            .select('SELECT DISTINCT account FROM account_quick_texts')
            .single['account'],
        _other.value,
      );
      _problem(
        await store.loadComposeSettings(_account),
        MailProblemCode.unavailable,
      );
      _problem(
        await store.saveComposeSettings(
          first,
          expectedRevision: first.revision,
        ),
        MailProblemCode.unavailable,
      );
      expect(
        _value(await store.loadComposeSettings(_other)).signature,
        second.signature,
      );
      await _expectLocalWork(store, _other);
    },
  );

  test('schema rejects NULL and missing account ownership', () {
    for (final owner in [null, 'unknown-account']) {
      expect(
        () => database.execute(
          'INSERT INTO account_compose_settings(account,revision,signature,'
          'signature_new,signature_replies) VALUES(?,1,?,?,?)',
          [owner, 'Detached signature', 0, 0],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    expect(database.select('SELECT * FROM account_compose_settings'), isEmpty);
  });

  test(
    'profile removal deletes all compose text and retires every owner',
    () async {
      await _register(store, _other);
      for (final account in [_account, _other]) {
        _value(
          await store.saveComposeSettings(
            _settings(account: account),
            expectedRevision: 0,
          ),
        );
      }
      _value(await store.removeProfile());
      expect(
        database.select('SELECT * FROM account_compose_settings'),
        isEmpty,
      );
      expect(database.select('SELECT * FROM account_quick_texts'), isEmpty);
      _problem(
        await store.saveComposeSettings(_settings(), expectedRevision: 0),
        MailProblemCode.unavailable,
      );
    },
  );

  for (final (name, settings) in [
    ('malformed Unicode signature', _settings(signature: '\uD800')),
    ('oversized signature', _settings(signature: 'x' * 16385)),
    (
      'duplicate names',
      _settings(
        quickTexts: const [
          MailQuickText(id: 'one', name: 'Thanks', text: 'One'),
          MailQuickText(id: 'two', name: 'THANKS', text: 'Two'),
        ],
      ),
    ),
    (
      'too many snippets',
      _settings(
        quickTexts: [
          for (var i = 0; i < 33; i++)
            MailQuickText(id: '$i', name: '$i', text: ''),
        ],
      ),
    ),
    (
      'aggregate overflow',
      _settings(
        quickTexts: [
          for (var i = 0; i < 9; i++)
            MailQuickText(id: '$i', name: '$i', text: 'x' * 16384),
        ],
      ),
    ),
  ]) {
    test('rejects $name without saving partial preferences', () async {
      _problem(
        await store.saveComposeSettings(settings, expectedRevision: 0),
        MailProblemCode.invalidInput,
      );
      expect(_value(await store.loadComposeSettings(_account)).revision, 0);
    });
  }

  for (final (label, sql, args) in <(String, String, List<Object?>)>[
    (
      'invalid boolean',
      'UPDATE account_compose_settings SET signature_new=2',
      [],
    ),
    (
      'inexact revision',
      'UPDATE account_compose_settings SET revision=9007199254740992',
      [],
    ),
    (
      'zero stored revision',
      'UPDATE account_compose_settings SET revision=0',
      [],
    ),
    (
      'NUL in signature',
      'UPDATE account_compose_settings SET signature=?',
      ['a\u0000b'],
    ),
    (
      'malformed UTF-8',
      "UPDATE account_compose_settings SET signature=CAST(X'EDA080' AS TEXT)",
      [],
    ),
    (
      'oversized UTF-16 body',
      'UPDATE account_quick_texts SET text=? WHERE position=0',
      ['📨' * 8193],
    ),
    (
      'name key mismatch',
      "UPDATE account_quick_texts SET name_key='wrong' WHERE position=0",
      [],
    ),
    (
      'name whitespace',
      "UPDATE account_quick_texts SET name=' Thanks ' WHERE position=0",
      [],
    ),
    (
      'missing ordered position',
      'UPDATE account_quick_texts SET position=8 WHERE position=0',
      [],
    ),
    (
      'binary body',
      "UPDATE account_quick_texts SET text=X'010203' WHERE position=0",
      [],
    ),
  ]) {
    test(
      'rejects corrupt persisted $label and refuses to overwrite it',
      () async {
        final saved = _value(
          await store.saveComposeSettings(_settings(), expectedRevision: 0),
        );
        database.execute('PRAGMA ignore_check_constraints=ON');
        database.execute(sql, args);
        _problem(
          await store.loadComposeSettings(_account),
          MailProblemCode.storageFailure,
        );
        _problem(
          await store.saveComposeSettings(
            saved,
            expectedRevision: saved.revision,
          ),
          MailProblemCode.storageFailure,
        );
      },
    );
  }

  test('refuses overflow at the last exactly representable revision', () async {
    _value(await store.saveComposeSettings(_settings(), expectedRevision: 0));
    database.execute('UPDATE account_compose_settings SET revision=?', [
      MailComposeSettings.maxRevision,
    ]);
    final loaded = _value(await store.loadComposeSettings(_account));
    expect(loaded.revision, MailComposeSettings.maxRevision);
    _problem(
      await store.saveComposeSettings(
        loaded,
        expectedRevision: loaded.revision,
      ),
      MailProblemCode.quotaExceeded,
    );
    expect(
      _value(await store.loadComposeSettings(_account)).revision,
      MailComposeSettings.maxRevision,
    );
  });

  test(
    'preflights an oversized persisted signature before transferring it',
    () async {
      _value(await store.saveComposeSettings(_settings(), expectedRevision: 0));
      await store.close();
      database.execute('UPDATE account_compose_settings SET signature=?', [
        's' * 70000,
      ]);
      final probe = _TransferProbe();
      store = await _open(database, interceptor: probe);
      _problem(
        await store.loadComposeSettings(_account),
        MailProblemCode.storageFailure,
      );
      expect(probe.largeTextTransferred, isFalse);
    },
  );

  test(
    'preflights an excessive snippet count before transferring text',
    () async {
      _value(
        await store.saveComposeSettings(
          _settings(quickTexts: []),
          expectedRevision: 0,
        ),
      );
      await store.close();
      database.execute('PRAGMA ignore_check_constraints=ON');
      for (var i = 0; i < 33; i++) {
        database.execute(
          'INSERT INTO account_quick_texts(account,position,id,name,name_key,text) '
          'VALUES(?,?,?,?,?,?)',
          [_account.value, i, '$i', '$i', '$i', 'x' * 20000],
        );
      }
      final probe = _TransferProbe();
      store = await _open(database, interceptor: probe);
      _problem(
        await store.loadComposeSettings(_account),
        MailProblemCode.storageFailure,
      );
      expect(probe.largeTextTransferred, isFalse);
    },
  );

  for (final (label, limits) in [
    ('host metadata', const MailStoreLimits(maxMetadataCodeUnits: 120)),
    ('account logical bytes', const MailStoreLimits(maxAccountBytes: 512)),
  ]) {
    test('enforces $label quota atomically', () async {
      await store.close();
      store = await _open(database, limits: limits);
      final saved = _value(
        await store.saveComposeSettings(
          _settings(signature: 'Small', quickTexts: []),
          expectedRevision: 0,
        ),
      );
      _problem(
        await store.saveComposeSettings(
          saved.copyWith(signature: 'x' * 1000),
          expectedRevision: saved.revision,
        ),
        MailProblemCode.quotaExceeded,
      );
      final retained = _value(await store.loadComposeSettings(_account));
      expect(retained.signature, 'Small');
      expect(retained.revision, 1);
    });
  }

  test(
    'file reopen retains exact compose settings and revision guards',
    () async {
      final directory = await Directory.systemTemp.createTemp('compose-tools-');
      final file = File('${directory.path}/mail.sqlite3');
      Future<SqliteMailRepository> openFile() async => _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase(file),
          profile: _profile,
        ),
      );
      try {
        var disk = await openFile();
        await _register(disk);
        final saved = _value(
          await disk.saveComposeSettings(_settings(), expectedRevision: 0),
        );
        await disk.close();
        disk = await openFile();
        try {
          final restored = _value(await disk.loadComposeSettings(_account));
          expect(restored.signature, saved.signature);
          expect(restored.quickTexts.first.text, saved.quickTexts.first.text);
          expect(restored.revision, 1);
          final updated = _value(
            await disk.saveComposeSettings(
              restored.copyWith(signature: 'Second revision'),
              expectedRevision: restored.revision,
            ),
          );
          expect(updated.revision, 2);
          _problem(
            await disk.saveComposeSettings(
              saved,
              expectedRevision: saved.revision,
            ),
            MailProblemCode.conflict,
          );
        } finally {
          await disk.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  group('sender identity and template storage', () {
    test(
      'round-trips complete literal snapshots and independent revisions after reopen',
      () async {
        final saved = _value(
          await store.saveComposeSettings(
            _extendedSettings(),
            expectedRevision: 0,
          ),
        );
        await store.close();
        store = await _open(database);
        final restored = _value(await store.loadComposeSettings(_account));
        expect(restored.revision, saved.revision);
        expect(restored.defaultSenderIdentityId, 'work');
        expect(restored.senderIdentities.map((item) => item.id), [
          'work',
          'alternate',
        ]);
        expect(restored.senderIdentities.first.displayName, 'مرحبا 📨');
        expect(restored.senderIdentities.first.replyTo, 'reply@example.test');
        expect(restored.templates.first.bcc, 'private@example.test');
        expect(restored.templates.first.body, saved.templates.first.body);
        expect(restored.templates.first.senderIdentityId, 'work');
        expect(restored.templates.last.to, 'unfinished@');
        expect(restored.templates.last.senderIdentityId, isNull);
        expect(() => restored.senderIdentities.clear(), throwsUnsupportedError);
        expect(() => restored.templates.clear(), throwsUnsupportedError);
        final updated = _value(
          await store.saveComposeSettings(
            restored.copyWith(
              senderIdentities: restored.senderIdentities.reversed.toList(),
              templates: restored.templates.reversed.toList(),
              defaultSenderIdentityId: 'alternate',
            ),
            expectedRevision: restored.revision,
          ),
        );
        expect(updated.revision, 2);
        expect(
          _value(await store.loadComposeSettings(_account)).templates.first.id,
          'blank',
        );
        _problem(
          await store.saveComposeSettings(
            saved,
            expectedRevision: saved.revision,
          ),
          MailProblemCode.conflict,
        );
      },
    );

    test(
      'deleting referenced senders requires atomic explicit reference clearing',
      () async {
        final saved = _value(
          await store.saveComposeSettings(
            _extendedSettings(),
            expectedRevision: 0,
          ),
        );
        _problem(
          await store.saveComposeSettings(
            saved.copyWith(senderIdentities: []),
            expectedRevision: saved.revision,
          ),
          MailProblemCode.invalidInput,
        );
        final cleared = _value(
          await store.saveComposeSettings(
            saved.copyWith(
              senderIdentities: [],
              clearDefaultSenderIdentity: true,
              templates: saved.templates
                  .map((item) => item.copyWith(clearSenderIdentity: true))
                  .toList(),
            ),
            expectedRevision: saved.revision,
          ),
        );
        expect(cleared.revision, 2);
        final restored = _value(await store.loadComposeSettings(_account));
        expect(restored.defaultSenderIdentityId, isNull);
        expect(restored.senderIdentities, isEmpty);
        expect(
          restored.templates.map((item) => item.senderIdentityId),
          everyElement(isNull),
        );
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
      },
    );

    test(
      'failure rolls back senders, references, templates and the shared revision',
      () async {
        final saved = _value(
          await store.saveComposeSettings(
            _extendedSettings(),
            expectedRevision: 0,
          ),
        );
        failCommit = true;
        _problem(
          await store.saveComposeSettings(
            saved.copyWith(
              senderIdentities: [],
              templates: [],
              clearDefaultSenderIdentity: true,
              signature: 'Changed',
              quickTexts: [],
            ),
            expectedRevision: saved.revision,
          ),
          MailProblemCode.storageFailure,
        );
        final restored = _value(await store.loadComposeSettings(_account));
        expect(restored.revision, saved.revision);
        expect(restored.signature, saved.signature);
        expect(restored.quickTexts.length, saved.quickTexts.length);
        expect(
          restored.senderIdentities.first.address,
          saved.senderIdentities.first.address,
        );
        expect(restored.defaultSenderIdentityId, saved.defaultSenderIdentityId);
        expect(restored.templates.first.body, saved.templates.first.body);
      },
    );

    test(
      'logout keeps templates; account and profile removal erase only owned data',
      () async {
        await _register(store, _other);
        await _seedLocalWork(store, _other);
        _value(
          await store.saveComposeSettings(
            _extendedSettings(),
            expectedRevision: 0,
          ),
        );
        _value(
          await store.saveComposeSettings(
            _extendedSettings(account: _other),
            expectedRevision: 0,
          ),
        );
        _value(await store.logout(MailAccountSession(_account)));
        expect(
          _value(await store.loadComposeSettings(_account)).templates.length,
          2,
        );
        _value(await store.removeAccount(_account));
        for (final table in [
          'account_sender_identities',
          'account_message_templates',
        ]) {
          expect(
            database
                .select('SELECT DISTINCT account FROM $table')
                .single['account'],
            _other.value,
          );
        }
        _problem(
          await store.saveComposeSettings(
            _extendedSettings(),
            expectedRevision: 0,
          ),
          MailProblemCode.unavailable,
        );
        await _expectLocalWork(store, _other);
        _value(await store.removeProfile());
        for (final table in [
          'account_sender_identities',
          'account_message_templates',
        ]) {
          expect(database.select('SELECT * FROM $table'), isEmpty);
        }
      },
    );

    test(
      'reset and alias changes do not mutate drafts or frozen Outbox payloads',
      () async {
        await _seedLocalWork(store, _account);
        final saved = _value(
          await store.saveComposeSettings(
            _extendedSettings(),
            expectedRevision: 0,
          ),
        );
        _value(
          await store.saveComposeSettings(
            saved.copyWith(
              senderIdentities: [
                saved.senderIdentities.first.copyWith(
                  address: 'changed@example.test',
                ),
                saved.senderIdentities.last,
              ],
            ),
            expectedRevision: saved.revision,
          ),
        );
        await _expectLocalWork(store, _account);
        _value(
          await store.saveComposeSettings(
            MailComposeSettings(account: _account, revision: 2),
            expectedRevision: 2,
          ),
        );
        await _expectLocalWork(store, _account);
      },
    );

    test('a template cannot reference another account sender', () async {
      await _register(store, _other);
      _value(
        await store.saveComposeSettings(
          _extendedSettings(account: _other),
          expectedRevision: 0,
        ),
      );
      _problem(
        await store.saveComposeSettings(
          MailComposeSettings(
            account: _account,
            templates: _extendedSettings().templates,
          ),
          expectedRevision: 0,
        ),
        MailProblemCode.invalidInput,
      );
      _value(await store.saveComposeSettings(_settings(), expectedRevision: 0));
      expect(
        () => database.execute(
          'INSERT INTO account_message_templates(account,position,id,name,name_key,to_text,cc_text,bcc_text,subject,body,sender_identity) '
          'VALUES(?,0,?,?,?,?,?,?,?,?,?)',
          [_account.value, 't', 'T', 't', '', '', '', '', '', 'work'],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test(
      'new content contributes to host metadata and account-byte quotas',
      () async {
        await store.close();
        store = await _open(
          database,
          limits: const MailStoreLimits(maxMetadataCodeUnits: 500),
        );
        final saved = _value(
          await store.saveComposeSettings(
            MailComposeSettings(account: _account),
            expectedRevision: 0,
          ),
        );
        _problem(
          await store.saveComposeSettings(
            saved.copyWith(
              templates: [
                const MailMessageTemplate(
                  id: 't',
                  name: 'Template',
                  body: 'text',
                ).copyWith(body: 'x' * 1000),
              ],
            ),
            expectedRevision: saved.revision,
          ),
          MailProblemCode.quotaExceeded,
        );
        expect(_value(await store.loadComposeSettings(_account)).revision, 1);
        await store.close();
        store = await _open(
          database,
          limits: const MailStoreLimits(maxAccountBytes: 900),
        );
        _problem(
          await store.saveComposeSettings(
            _extendedSettings().copyWith(revision: 1),
            expectedRevision: 1,
          ),
          MailProblemCode.quotaExceeded,
        );
        expect(
          _value(await store.loadComposeSettings(_account)).templates,
          isEmpty,
        );
      },
    );

    for (final (label, sql, args) in <(String, String, List<Object?>)>[
      (
        'missing default identity',
        "UPDATE account_compose_settings SET default_sender_identity='missing'",
        [],
      ),
      (
        'default malformed UTF-8',
        "UPDATE account_compose_settings SET default_sender_identity=CAST(X'EDA080' AS TEXT)",
        [],
      ),
      (
        'identity malformed UTF-8',
        "UPDATE account_sender_identities SET display_name=CAST(X'EDA080' AS TEXT) WHERE position=0",
        [],
      ),
      (
        'identity header injection',
        'UPDATE account_sender_identities SET address=? WHERE position=0',
        ['a@example.test\r\nBcc: b@example.test'],
      ),
      (
        'identity ordering gap',
        'UPDATE account_sender_identities SET position=9 WHERE position=0',
        [],
      ),
      (
        'identity name key mismatch',
        "UPDATE account_sender_identities SET name_key='wrong' WHERE position=0",
        [],
      ),
      (
        'identity binary display name',
        "UPDATE account_sender_identities SET display_name=X'010203' WHERE position=0",
        [],
      ),
      (
        'template malformed UTF-8',
        "UPDATE account_message_templates SET body=CAST(X'EDA080' AS TEXT) WHERE position=0",
        [],
      ),
      (
        'template subject control',
        'UPDATE account_message_templates SET subject=? WHERE position=0',
        ['a\nBcc: b'],
      ),
      (
        'template recipient control',
        'UPDATE account_message_templates SET bcc_text=? WHERE position=0',
        ['a\nb'],
      ),
      (
        'template UTF-16 overflow',
        'UPDATE account_message_templates SET body=? WHERE position=0',
        ['📨' * 8193],
      ),
      (
        'template combined recipient overflow',
        'UPDATE account_message_templates SET to_text=?,cc_text=? WHERE position=0',
        ['x' * 20000, 'x' * 6000],
      ),
      (
        'template ordering gap',
        'UPDATE account_message_templates SET position=9 WHERE position=0',
        [],
      ),
      (
        'template name key mismatch',
        "UPDATE account_message_templates SET name_key='wrong' WHERE position=0",
        [],
      ),
      (
        'template binary body',
        "UPDATE account_message_templates SET body=X'010203' WHERE position=0",
        [],
      ),
    ]) {
      test('rejects corrupt $label and prevents overwrite', () async {
        final saved = _value(
          await store.saveComposeSettings(
            _extendedSettings(),
            expectedRevision: 0,
          ),
        );
        database.execute('PRAGMA ignore_check_constraints=ON');
        database.execute(sql, args);
        _problem(
          await store.loadComposeSettings(_account),
          MailProblemCode.storageFailure,
        );
        _problem(
          await store.saveComposeSettings(
            saved,
            expectedRevision: saved.revision,
          ),
          MailProblemCode.storageFailure,
        );
      });
    }

    test(
      'preflights oversized template bytes before transferring text',
      () async {
        _value(
          await store.saveComposeSettings(
            _extendedSettings(),
            expectedRevision: 0,
          ),
        );
        await store.close();
        database.execute(
          'UPDATE account_message_templates SET body=? WHERE position=0',
          ['x' * 70000],
        );
        final probe = _TransferProbe();
        store = await _open(database, interceptor: probe);
        _problem(
          await store.loadComposeSettings(_account),
          MailProblemCode.storageFailure,
        );
        expect(probe.largeTextTransferred, isFalse);
      },
    );

    test(
      'preflights excessive template count before transferring text',
      () async {
        _value(
          await store.saveComposeSettings(_settings(), expectedRevision: 0),
        );
        await store.close();
        database.execute('PRAGMA ignore_check_constraints=ON');
        for (var i = 0; i < 33; i++) {
          database.execute(
            'INSERT INTO account_message_templates(account,position,id,name,name_key,to_text,cc_text,bcc_text,subject,body) '
            'VALUES(?,?,?,?,?,?,?,?,?,?)',
            [_account.value, i, '$i', '$i', '$i', '', '', '', '', 'x' * 20000],
          );
        }
        final probe = _TransferProbe();
        store = await _open(database, interceptor: probe);
        _problem(
          await store.loadComposeSettings(_account),
          MailProblemCode.storageFailure,
        );
        expect(probe.largeTextTransferred, isFalse);
      },
    );
  });

  test(
    'schema 20 migration failure rolls back all new compose structures',
    () async {
      final legacy = _legacyComposeDatabase(20);
      try {
        final failed = await SqliteMailRepository.open(
          executor: NativeDatabase.opened(
            legacy,
            closeUnderlyingOnClose: false,
          ),
          profile: _profile,
          faultInjector: (point) {
            if (point == MailStoreCheckpoint.migrationCreated) {
              throw const MailStoreStorageException(
                MailProblemCode.storageFailure,
              );
            }
          },
        );
        _problem(failed, MailProblemCode.storageFailure);
        expect(legacy.userVersion, 20);
        expect(
          legacy
              .select('PRAGMA table_info(account_compose_settings)')
              .map((row) => row['name']),
          isNot(contains('default_sender_identity')),
        );
        expect(
          legacy.select(
            "SELECT name FROM sqlite_master WHERE name IN ('account_sender_identities','account_message_templates')",
          ),
          isEmpty,
        );
        expect(
          legacy
              .select('SELECT signature FROM account_compose_settings')
              .single['signature'],
          'Legacy 📨\r\nsignature',
        );
        final retried = await _open(legacy);
        try {
          expect(legacy.userVersion, 21);
          final retained = _value(await retried.loadComposeSettings(_account));
          expect(retained.revision, 7);
          expect(retained.quickTexts.single.text, 'Unchanged');
          expect(retained.senderIdentities, isEmpty);
        } finally {
          await retried.close();
        }
      } finally {
        legacy.close();
      }
    },
  );

  for (var version = 10; version <= 20; version++) {
    test(
      'schema $version retains existing compose settings when adding identities and templates',
      () async {
        final legacy = _legacyComposeDatabase(version);
        final encoded = MailStoreCodec.encodeDraft(_draft(_account));
        final migrated = await _open(legacy);
        try {
          expect(legacy.userVersion, 21);
          expect(legacy.select('PRAGMA foreign_key_check'), isEmpty);
          final old = _value(await migrated.loadComposeSettings(_account));
          expect(old.revision, 7);
          expect(old.signature, 'Legacy 📨\r\nsignature');
          expect(old.quickTexts.single.text, 'Unchanged');
          expect(old.senderIdentities, isEmpty);
          expect(old.templates, isEmpty);
          expect(old.defaultSenderIdentityId, isNull);
          final added = _value(
            await migrated.saveComposeSettings(
              old.copyWith(
                senderIdentities: _extendedSettings().senderIdentities,
                templates: _extendedSettings().templates,
                defaultSenderIdentityId: 'work',
              ),
              expectedRevision: old.revision,
            ),
          );
          expect(added.revision, 8);
          expect(added.signature, old.signature);
          expect(
            MailStoreCodec.encodeDraft(
              _value(await migrated.loadDraft(_account, 'draft'))!,
            ).data,
            encoded.data,
          );
        } finally {
          await migrated.close();
          legacy.close();
        }
      },
    );
  }

  for (var version = 1; version <= 9; version++) {
    test('schema $version upgrades additively and preserves authored work', () async {
      final legacy = sqlite.sqlite3.openInMemory();
      for (final schema in [
        schemaV1,
        schemaV2,
        schemaV3,
        schemaV4,
        schemaV5,
        schemaV6,
        schemaV7,
        schemaV8,
        schemaV9,
      ].take(version)) {
        for (final sql in schema) {
          legacy.execute(sql);
        }
      }
      legacy.execute(
        'INSERT INTO store_profile(singleton,host_id,profile_id) VALUES(1,?,?)',
        [_profile.hostId, _profile.value],
      );
      legacy.execute(
        'INSERT INTO accounts(id,provider,display_name,state) VALUES(?,?,?,?)',
        [_account.value, 'imap', 'Legacy account', 'loggedOut'],
      );
      final encoded = MailStoreCodec.encodeDraft(_draft(_account));
      legacy.execute(
        'INSERT INTO drafts(account,id,revision,data) VALUES(?,?,?,?)',
        [_account.value, 'draft', 1, encoded.data],
      );
      if (version == 9) {
        legacy.execute(
          'INSERT INTO saved_header_searches(id,name,name_key,query,revision) '
          "VALUES('search','Saved','saved','is:unread',1)",
        );
        legacy.execute(
          'INSERT INTO saved_header_search_accounts(search,position,account_id) '
          "VALUES('search',0,'verified')",
        );
        legacy.execute(
          'UPDATE store_profile SET saved_header_search_revision=1',
        );
      }
      legacy.userVersion = version;
      final migrated = await _open(legacy);
      try {
        expect(legacy.userVersion, 21);
        expect(legacy.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          _value(await migrated.loadComposeSettings(_account)).revision,
          0,
        );
        _value(
          await migrated.saveComposeSettings(_settings(), expectedRevision: 0),
        );
        expect(
          MailStoreCodec.encodeDraft(
            _value(await migrated.loadDraft(_account, 'draft'))!,
          ).data,
          encoded.data,
        );
        if (version == 9) {
          final search = _value(
            await migrated.listSavedHeaderSearches(),
          ).single;
          expect(search.query, 'is:unread');
          expect(search.accountIds, ['verified']);
          expect(search.revision, 1);
        }
      } finally {
        await migrated.close();
        legacy.close();
      }
    });
  }
}

final class _TransferProbe extends QueryInterceptor {
  bool largeTextTransferred = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runSelect(executor, statement, args);
    largeTextTransferred |= result.any(
      (row) => row.values.any(
        (value) =>
            value is String && value.length > 16384 ||
            value is Uint8List && value.length > 16384,
      ),
    );
    return result;
  }
}
