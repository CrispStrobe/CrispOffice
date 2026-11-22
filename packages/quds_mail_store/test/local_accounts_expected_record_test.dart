@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('selected-directory', hostId: 'test-office');
final _now = DateTime.utc(2026, 11, 22, 12);

MailLocalAccountRecord _record({
  String id = 'selected',
  MailProviderKind provider = MailProviderKind.imap,
  String endpoint = 'imaps://imap.example.test:993',
  String login = 'operator@example.test',
  String sender = 'sender@example.test',
  DateTime? time,
  int revision = 0,
}) => MailLocalAccountRecord(
  id: id,
  provider: provider,
  endpoint: endpoint,
  login: login,
  sender: sender,
  lastConnectedAt: time ?? _now,
  revision: revision,
);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

void _sameSnapshot(
  MailLocalAccountRecord actual,
  MailLocalAccountRecord expected,
) {
  expect(actual.hasSameIdentity(expected), isTrue);
  expect(actual.revision, expected.revision);
  expect(actual.lastConnectedAt, expected.lastConnectedAt);
}

Future<MailLocalAccountRecord> _selected(SqliteMailRepository store) async =>
    _value(await store.listLocalAccounts()).single;

Future<void> _counterIsUnchanged(
  SqliteMailRepository store,
  int previousRevision,
) async {
  _value(await store.rememberLocalAccount(_record(id: 'counter-probe')));
  final probe = _value(
    await store.listLocalAccounts(),
  ).singleWhere((row) => row.id == 'counter-probe');
  expect(probe.revision, previousRevision + 1);
}

void main() {
  late SqliteMailRepository store;
  var failCommit = false;
  setUp(() async {
    failCommit = false;
    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.memory(),
        profile: _profile,
        faultInjector: (point) {
          if (failCommit && point == MailStoreCheckpoint.beforeCommit) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      ),
    );
  });
  tearDown(() => store.close());

  test(
    'null expectation retains fresh registration and refresh behavior',
    () async {
      _value(await store.rememberLocalAccount(_record(), expectedRecord: null));
      final first = await _selected(store);
      expect(first.revision, 1);
      final later = _now.add(const Duration(hours: 1));
      _value(
        await store.rememberLocalAccount(
          _record(time: later),
          expectedRecord: null,
        ),
      );
      final refreshed = await _selected(store);
      expect(refreshed.hasSameIdentity(first), isTrue);
      expect(refreshed.revision, first.revision + 1);
      expect(refreshed.lastConnectedAt, later);
    },
  );

  test(
    'exact snapshot refreshes once with a new connection time and revision',
    () async {
      _value(await store.rememberLocalAccount(_record()));
      final selected = await _selected(store);
      final later = _now.add(const Duration(minutes: 1));
      _value(
        await store.rememberLocalAccount(
          _record(time: later),
          expectedRecord: selected,
        ),
      );
      final refreshed = await _selected(store);
      expect(refreshed.hasSameIdentity(selected), isTrue);
      expect(refreshed.revision, selected.revision + 1);
      expect(refreshed.lastConnectedAt, later);
      await _counterIsUnchanged(store, refreshed.revision);
    },
  );

  test('guarded completion preserves a newer stored connection time', () async {
    _value(await store.rememberLocalAccount(_record()));
    final selected = await _selected(store);
    _value(
      await store.rememberLocalAccount(
        _record(time: _now.subtract(const Duration(days: 1))),
        expectedRecord: selected,
      ),
    );
    final refreshed = await _selected(store);
    expect(refreshed.lastConnectedAt, selected.lastConnectedAt);
    expect(refreshed.revision, selected.revision + 1);
  });

  test(
    'missing expected account never creates a shortcut or consumes a revision',
    () async {
      _problem(
        await store.rememberLocalAccount(
          _record(),
          expectedRecord: _record(revision: 1),
        ),
        MailProblemCode.conflict,
      );
      expect(_value(await store.listLocalAccounts()), isEmpty);
      await _counterIsUnchanged(store, 0);
    },
  );

  test(
    'late selected completion does not recreate a removed shortcut',
    () async {
      _value(await store.rememberLocalAccount(_record()));
      final selected = await _selected(store);
      _value(await store.forgetLocalAccount(selected));
      _problem(
        await store.rememberLocalAccount(
          _record(time: _now.add(const Duration(days: 1))),
          expectedRecord: selected,
        ),
        MailProblemCode.conflict,
      );
      expect(_value(await store.listLocalAccounts()), isEmpty);
      await _counterIsUnchanged(store, selected.revision);
    },
  );

  test(
    'same-clock removal and re-add cannot revive an earlier selected snapshot',
    () async {
      _value(await store.rememberLocalAccount(_record()));
      final selected = await _selected(store);
      _value(await store.forgetLocalAccount(selected));
      _value(await store.rememberLocalAccount(_record()));
      final replacement = await _selected(store);
      expect(replacement.hasSameIdentity(selected), isTrue);
      expect(replacement.lastConnectedAt, selected.lastConnectedAt);
      expect(replacement.revision, greaterThan(selected.revision));
      _problem(
        await store.rememberLocalAccount(
          _record(time: _now.add(const Duration(days: 1))),
          expectedRecord: selected,
        ),
        MailProblemCode.conflict,
      );
      _sameSnapshot(await _selected(store), replacement);
      await _counterIsUnchanged(store, replacement.revision);
    },
  );

  test(
    'replacement identity under the same id cannot be overwritten',
    () async {
      _value(await store.rememberLocalAccount(_record()));
      final selected = await _selected(store);
      _value(await store.forgetLocalAccount(selected));
      _value(
        await store.rememberLocalAccount(
          _record(sender: 'replacement@example.test'),
        ),
      );
      final replacement = await _selected(store);
      _problem(
        await store.rememberLocalAccount(_record(), expectedRecord: selected),
        MailProblemCode.conflict,
      );
      _sameSnapshot(await _selected(store), replacement);
      await _counterIsUnchanged(store, replacement.revision);
    },
  );

  test(
    'an intervening ordinary refresh invalidates a same-clock selection',
    () async {
      _value(await store.rememberLocalAccount(_record()));
      final selected = await _selected(store);
      _value(await store.rememberLocalAccount(_record()));
      final refreshed = await _selected(store);
      _problem(
        await store.rememberLocalAccount(_record(), expectedRecord: selected),
        MailProblemCode.conflict,
      );
      _sameSnapshot(await _selected(store), refreshed);
      await _counterIsUnchanged(store, refreshed.revision);
    },
  );

  for (final delta in [-1, 1]) {
    test(
      'expected revision offset $delta is rejected without metadata changes',
      () async {
        _value(await store.rememberLocalAccount(_record()));
        final selected = await _selected(store);
        _problem(
          await store.rememberLocalAccount(
            _record(time: _now.add(const Duration(hours: 1))),
            expectedRecord: _record(revision: selected.revision + delta),
          ),
          MailProblemCode.conflict,
        );
        _sameSnapshot(await _selected(store), selected);
        await _counterIsUnchanged(store, selected.revision);
      },
    );

    test(
      'expected timestamp offset $delta ms is rejected without metadata changes',
      () async {
        _value(await store.rememberLocalAccount(_record()));
        final selected = await _selected(store);
        _problem(
          await store.rememberLocalAccount(
            _record(time: _now.add(const Duration(hours: 1))),
            expectedRecord: _record(
              revision: selected.revision,
              time: _now.add(Duration(milliseconds: delta)),
            ),
          ),
          MailProblemCode.conflict,
        );
        _sameSnapshot(await _selected(store), selected);
        await _counterIsUnchanged(store, selected.revision);
      },
    );
  }

  for (final (label, foreign) in [
    ('id', _record(id: 'another', revision: 1)),
    ('login', _record(login: 'another@example.test', revision: 1)),
    ('sender', _record(sender: 'another@example.test', revision: 1)),
    (
      'endpoint',
      _record(endpoint: 'imaps://other.example.test:993', revision: 1),
    ),
    (
      'provider',
      _record(
        provider: MailProviderKind.ews,
        endpoint: 'https://ews.example.test/EWS/Exchange.asmx',
        revision: 1,
      ),
    ),
  ]) {
    test(
      'expected foreign $label cannot authorize the requested identity',
      () async {
        _value(await store.rememberLocalAccount(_record()));
        final selected = await _selected(store);
        _problem(
          await store.rememberLocalAccount(_record(), expectedRecord: foreign),
          MailProblemCode.conflict,
        );
        _sameSnapshot(await _selected(store), selected);
        await _counterIsUnchanged(store, selected.revision);
      },
    );
  }

  test(
    'malformed expected snapshot is refused before any directory mutation',
    () async {
      _value(await store.rememberLocalAccount(_record()));
      final selected = await _selected(store);
      _problem(
        await store.rememberLocalAccount(
          _record(),
          expectedRecord: _record(revision: -1),
        ),
        MailProblemCode.invalidInput,
      );
      _sameSnapshot(await _selected(store), selected);
      await _counterIsUnchanged(store, selected.revision);
    },
  );

  test(
    'concurrent completions of one selection admit exactly one refresh',
    () async {
      _value(await store.rememberLocalAccount(_record()));
      final selected = await _selected(store);
      final firstTime = _now.add(const Duration(minutes: 1));
      final secondTime = _now.add(const Duration(minutes: 2));
      final results = await Future.wait([
        store.rememberLocalAccount(
          _record(time: firstTime),
          expectedRecord: selected,
        ),
        store.rememberLocalAccount(
          _record(time: secondTime),
          expectedRecord: selected,
        ),
      ]);
      expect(results.whereType<MailSuccess<MailUnit>>(), hasLength(1));
      final rejected = results.whereType<MailFailure<MailUnit>>().single;
      expect(rejected.problem.code, MailProblemCode.conflict);
      final winner = await _selected(store);
      expect(winner.hasSameIdentity(selected), isTrue);
      expect(winner.revision, selected.revision + 1);
      expect(
        winner.lastConnectedAt,
        results.first is MailSuccess<MailUnit> ? firstTime : secondTime,
      );
      await _counterIsUnchanged(store, winner.revision);
    },
  );

  test(
    'failed transaction rolls back metadata and leaves the selection retryable',
    () async {
      _value(await store.rememberLocalAccount(_record()));
      final selected = await _selected(store);
      final later = _now.add(const Duration(hours: 1));
      failCommit = true;
      _problem(
        await store.rememberLocalAccount(
          _record(time: later),
          expectedRecord: selected,
        ),
        MailProblemCode.storageFailure,
      );
      _sameSnapshot(await _selected(store), selected);
      failCommit = false;
      _value(
        await store.rememberLocalAccount(
          _record(time: later),
          expectedRecord: selected,
        ),
      );
      final refreshed = await _selected(store);
      expect(refreshed.revision, selected.revision + 1);
      expect(refreshed.lastConnectedAt, later);
      await _counterIsUnchanged(store, refreshed.revision);
    },
  );

  test(
    'removed selection remains rejected after a file-backed reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mail-selected-account-',
      );
      final file = File('${directory.path}/mail.sqlite3');
      Future<SqliteMailRepository> open() async => _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase(file),
          profile: _profile,
        ),
      );
      try {
        var disk = await open();
        late final MailLocalAccountRecord selected;
        try {
          _value(await disk.rememberLocalAccount(_record()));
          selected = await _selected(disk);
          _value(await disk.forgetLocalAccount(selected));
        } finally {
          await disk.close();
        }
        disk = await open();
        try {
          _problem(
            await disk.rememberLocalAccount(
              _record(),
              expectedRecord: selected,
            ),
            MailProblemCode.conflict,
          );
          expect(_value(await disk.listLocalAccounts()), isEmpty);
          _value(await disk.rememberLocalAccount(_record()));
          final replacement = await _selected(disk);
          expect(replacement.revision, selected.revision + 1);
          _problem(
            await disk.rememberLocalAccount(
              _record(),
              expectedRecord: selected,
            ),
            MailProblemCode.conflict,
          );
          _sameSnapshot(await _selected(disk), replacement);
        } finally {
          await disk.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
