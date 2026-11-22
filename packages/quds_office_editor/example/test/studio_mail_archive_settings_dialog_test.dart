import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_archive_destination.dart';
import 'package:quds_office_studio/studio_mail_archive_settings_dialog.dart';
import 'package:quds_office_studio/studio_mail_archive_settings_store.dart';
import 'package:quds_office_studio/studio_mail_archive_settings_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
final _owner = MailAccountId(
  'durable-local-owner',
  profile: MailProfileId('mail-profile', hostId: 'studio'),
);
final _provider = MailAccountId(
  'live-connection',
  profile: MailProfileId('provider-profile', hostId: 'transport'),
);
final _foreign = MailAccountId('another-owner', profile: _owner.profile);

typedef _Write = ({
  MailArchiveDestinationSettings settings,
  int expectedRevision,
});

MailArchiveDestinationSettings _settings({
  String? destination,
  int revision = 7,
  MailAccountId? account,
}) {
  final owner = account ?? _owner;
  return MailArchiveDestinationSettings(
    account: owner,
    revision: revision,
    destination: destination == null
        ? null
        : MailMailboxId(destination, account: owner),
  );
}

MailMailbox _folder(
  String id, {
  String name = 'Archive',
  MailAccountId? account,
  bool label = false,
}) => MailMailbox(
  id: MailMailboxId(id, account: account ?? _provider),
  displayName: name,
  isLabel: label,
);

final class _Store implements StudioMailArchiveSettingsStore {
  _Store(this.value);

  MailArchiveDestinationSettings value;
  MailAccountId owner = _owner;
  int reads = 0;
  final writes = <_Write>[];
  Future<MailArchiveDestinationSettings> Function()? onLoad;
  Future<MailArchiveDestinationSettings> Function(_Write)? onSave;

  @override
  MailAccountId get account => owner;

  @override
  Future<MailArchiveDestinationSettings> loadArchiveSettings() async {
    reads++;
    return onLoad == null ? value : await onLoad!();
  }

  @override
  Future<MailArchiveDestinationSettings> saveArchiveSettings(
    MailArchiveDestinationSettings settings, {
    required int expectedRevision,
  }) async {
    final request = (settings: settings, expectedRevision: expectedRevision);
    writes.add(request);
    if (onSave != null) return onSave!(request);
    if (expectedRevision != value.revision || settings.account != owner) {
      throw StateError('private concurrent-write detail');
    }
    value = MailArchiveDestinationSettings(
      account: owner,
      destination: settings.destination,
      revision: expectedRevision + 1,
    );
    return value;
  }
}

final class _Outcome {
  bool? result;
}

Finder _key(String suffix) =>
    find.byKey(ValueKey('studio-mail-archive-settings-$suffix'));

void _enabled(WidgetTester tester, String suffix, bool enabled) {
  expect(_key(suffix), findsOneWidget);
  final button = tester.widget<ButtonStyleButton>(_key(suffix));
  expect(button.onPressed != null, enabled, reason: '$suffix enabled state');
}

Future<void> _press(
  WidgetTester tester,
  String suffix, {
  bool settle = true,
}) async {
  await tester.ensureVisible(_key(suffix));
  await tester.tap(_key(suffix));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<_Outcome> _show(
  WidgetTester tester,
  _Store store, {
  Future<List<MailMailbox>> Function()? loadFolders,
  bool Function()? isCurrent,
  StudioStrings strings = _strings,
  Size size = const Size(1000, 900),
  double scale = 1,
  bool settle = true,
  String accountLabel = 'Operator@example.test',
}) async {
  final outcome = _Outcome();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              outcome.result = await showStudioMailArchiveSettings(
                context,
                strings: strings,
                accountLabel: accountLabel,
                providerAccount: _provider,
                store: store,
                loadFolders: loadFolders ?? () async => [_folder('Archive')],
                isCurrent: isCurrent ?? () => true,
              );
            },
            child: const Text('Account Archive settings'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Account Archive settings'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }
  return outcome;
}

void main() {
  testWidgets(
    'save maps the chosen exact provider route to its stable owner with CAS',
    (tester) async {
      final store = _Store(_settings());
      final outcome = await _show(
        tester,
        store,
        loadFolders: () async => [
          _folder('Archive'),
          _folder('archive'),
          _folder(' Archive '),
        ],
      );
      _enabled(tester, 'save', false);
      await _press(tester, 'folder-2');
      _enabled(tester, 'save', true);
      expect(store.writes, isEmpty);
      await _press(tester, 'save');
      expect(outcome.result, isTrue);
      expect(_key('dialog'), findsNothing);
      expect(store.writes, hasLength(1));
      final written = store.writes.single;
      expect(written.expectedRevision, 7);
      expect(written.settings.revision, 7);
      expect(written.settings.account, _owner);
      expect(
        written.settings.destination,
        MailMailboxId(' Archive ', account: _owner),
      );
      expect(written.settings.destination!.account, isNot(_provider));
      expect(store.value.revision, 8);
    },
  );

  testWidgets(
    'clear preserves account identity and advances the observed revision',
    (tester) async {
      final store = _Store(_settings(destination: 'Archive', revision: 12));
      final outcome = await _show(tester, store);
      await _press(tester, 'clear');
      expect(outcome.result, isTrue);
      expect(store.writes.single.expectedRevision, 12);
      expect(store.writes.single.settings.account, _owner);
      expect(store.writes.single.settings.destination, isNull);
      expect(store.value.revision, 13);
    },
  );

  testWidgets('cancel discards a changed selection without a write', (
    tester,
  ) async {
    final original = _settings(destination: 'Old');
    final store = _Store(original);
    final outcome = await _show(tester, store);
    await _press(tester, 'folder-0');
    await _press(tester, 'cancel');
    expect(outcome.result, isFalse);
    expect(store.writes, isEmpty);
    expect(store.value, same(original));
  });

  testWidgets(
    'missing saved route requires explicit repair despite matching display names',
    (tester) async {
      final store = _Store(_settings(destination: ' Archive '));
      final outcome = await _show(
        tester,
        store,
        loadFolders: () async => [_folder('Archive', name: ' Archive ')],
      );
      expect(_key('missing'), findsOneWidget);
      expect(tester.widget<ListTile>(_key('folder-0')).selected, isFalse);
      _enabled(tester, 'save', false);
      _enabled(tester, 'clear', true);
      expect(store.writes, isEmpty);
      await _press(tester, 'folder-0');
      await _press(tester, 'save');
      expect(outcome.result, isTrue);
      expect(store.value.destination!.value, 'Archive');
    },
  );

  testWidgets(
    'catalog failure still permits clearing a known saved preference',
    (tester) async {
      final store = _Store(_settings(destination: 'Unavailable'));
      final outcome = await _show(
        tester,
        store,
        loadFolders: () async => throw StateError('secret provider response'),
      );
      expect(find.text(_strings.mailArchiveSettingsLoadFailed), findsOneWidget);
      expect(find.textContaining('secret provider response'), findsNothing);
      _enabled(tester, 'save', false);
      _enabled(tester, 'clear', true);
      await _press(tester, 'clear');
      expect(outcome.result, isTrue);
      expect(store.writes.single.expectedRevision, 7);
      expect(store.value.destination, isNull);
    },
  );

  testWidgets(
    'empty folder catalog has no implicit destination and supports clearing',
    (tester) async {
      final store = _Store(_settings(destination: 'Archive'));
      final outcome = await _show(tester, store, loadFolders: () async => []);
      expect(_key('missing'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      _enabled(tester, 'save', false);
      _enabled(tester, 'clear', true);
      await _press(tester, 'clear');
      expect(outcome.result, isTrue);
    },
  );

  testWidgets(
    'account preference works with no message selection or loaded mailbox',
    (tester) async {
      final store = _Store(_settings());
      final outcome = await _show(
        tester,
        store,
        loadFolders: () async => [
          _folder('INBOX', name: 'Current empty folder'),
        ],
      );
      expect(_key('clear'), findsNothing);
      await _press(tester, 'folder-0');
      await _press(tester, 'save');
      expect(outcome.result, isTrue);
      expect(store.value.destination!.value, 'INBOX');
    },
  );

  for (final catalog in <String, List<MailMailbox>>{
    'duplicate': [_folder('Archive'), _folder('Archive', name: 'Other')],
    'foreign': [_folder('Archive'), _folder('Elsewhere', account: _foreign)],
    'malformed': [_folder('Archive'), _folder('bad\u0085route')],
  }.entries) {
    testWidgets('${catalog.key} catalog is never partially offered', (
      tester,
    ) async {
      final store = _Store(_settings(destination: 'Archive'));
      await _show(tester, store, loadFolders: () async => catalog.value);
      expect(_key('error'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      _enabled(tester, 'save', false);
      _enabled(tester, 'clear', true);
      expect(store.writes, isEmpty);
    });
  }

  testWidgets('labels are excluded and a saved label is presented as missing', (
    tester,
  ) async {
    final store = _Store(_settings(destination: 'Label'));
    await _show(
      tester,
      store,
      loadFolders: () async => [
        _folder('Label', name: 'Important', label: true),
        _folder('Ordinary', name: 'Reports'),
      ],
    );
    expect(find.text('Important'), findsNothing);
    expect(find.text('Reports'), findsOneWidget);
    expect(_key('missing'), findsOneWidget);
    _enabled(tester, 'save', false);
  });

  testWidgets(
    'failed settings load writes nothing and recovers by explicit reload',
    (tester) async {
      final store = _Store(_settings())
        ..onLoad = () async => throw StateError('secret storage failure');
      var catalogs = 0;
      await _show(
        tester,
        store,
        loadFolders: () async {
          catalogs++;
          return [_folder('Archive')];
        },
      );
      expect(catalogs, 0);
      expect(find.text(_strings.mailArchiveSettingsLoadFailed), findsOneWidget);
      expect(find.textContaining('secret storage failure'), findsNothing);
      _enabled(tester, 'save', false);
      expect(_key('clear'), findsNothing);
      store.onLoad = null;
      await _press(tester, 'reload');
      expect(store.reads, 2);
      expect(catalogs, 1);
      expect(_key('error'), findsNothing);
      await _press(tester, 'folder-0');
      await _press(tester, 'save');
      expect(store.writes, hasLength(1));
    },
  );

  testWidgets('foreign settings cannot populate or clear another account', (
    tester,
  ) async {
    final store = _Store(_settings(account: _foreign, destination: 'Archive'));
    var catalogs = 0;
    await _show(
      tester,
      store,
      loadFolders: () async {
        catalogs++;
        return [_folder('Archive')];
      },
    );
    expect(catalogs, 0);
    expect(_key('saved'), findsNothing);
    expect(_key('clear'), findsNothing);
    _enabled(tester, 'save', false);
    expect(store.writes, isEmpty);
  });

  for (final ownerChange in [false, true]) {
    testWidgets(
      'late settings load refuses ${ownerChange ? 'owner replacement' : 'retired session'}',
      (tester) async {
        final pending = Completer<MailArchiveDestinationSettings>();
        final store = _Store(_settings())..onLoad = () => pending.future;
        var current = true;
        var catalogs = 0;
        await _show(
          tester,
          store,
          settle: false,
          isCurrent: () => current,
          loadFolders: () async {
            catalogs++;
            return [_folder('Archive')];
          },
        );
        if (ownerChange) {
          store.owner = _foreign;
        } else {
          current = false;
        }
        pending.complete(_settings());
        await tester.pumpAndSettle();
        expect(catalogs, 0);
        expect(
          find.text(
            _strings.mailArchiveDestinationFailure(
              StudioMailArchiveDestinationFailure.stale,
            ),
          ),
          findsOneWidget,
        );
        _enabled(tester, 'save', false);
        _enabled(tester, 'reload', false);
        expect(store.writes, isEmpty);
      },
    );
  }

  testWidgets('late catalog cannot populate a retired account dialog', (
    tester,
  ) async {
    final pending = Completer<List<MailMailbox>>();
    final store = _Store(_settings(destination: 'Archive'));
    var current = true;
    await _show(
      tester,
      store,
      settle: false,
      isCurrent: () => current,
      loadFolders: () => pending.future,
    );
    current = false;
    pending.complete([_folder('Archive')]);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    _enabled(tester, 'save', false);
    _enabled(tester, 'clear', false);
    expect(store.writes, isEmpty);
  });

  for (final waitingForCatalog in [false, true]) {
    testWidgets(
      'cancel while ${waitingForCatalog ? 'catalog' : 'settings'} loads ignores late completion',
      (tester) async {
        final settings = Completer<MailArchiveDestinationSettings>();
        final folders = Completer<List<MailMailbox>>();
        final store = _Store(_settings());
        if (!waitingForCatalog) store.onLoad = () => settings.future;
        final outcome = await _show(
          tester,
          store,
          settle: false,
          loadFolders: () => folders.future,
        );
        await _press(tester, 'cancel');
        expect(outcome.result, isFalse);
        if (waitingForCatalog) {
          folders.complete([_folder('Archive')]);
        } else {
          settings.complete(_settings());
        }
        await tester.pumpAndSettle();
        expect(_key('dialog'), findsNothing);
        expect(store.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'captured save action cannot write after the current session is lost',
    (tester) async {
      final store = _Store(_settings());
      var current = true;
      await _show(tester, store, isCurrent: () => current);
      await _press(tester, 'folder-0');
      current = false;
      await _press(tester, 'save');
      expect(store.writes, isEmpty);
      expect(_key('dialog'), findsOneWidget);
    },
  );

  testWidgets('conflicting revision requires reload before any retry', (
    tester,
  ) async {
    final store = _Store(_settings(destination: 'Archive', revision: 4));
    final outcome = await _show(tester, store);
    store.value = _settings(destination: 'New elsewhere', revision: 5);
    await _press(tester, 'save');
    expect(outcome.result, isNull);
    expect(store.writes.single.expectedRevision, 4);
    expect(store.value.destination!.value, 'New elsewhere');
    expect(find.text(_strings.mailArchiveSettingsSaveFailed), findsOneWidget);
    expect(
      find.textContaining('private concurrent-write detail'),
      findsNothing,
    );
    _enabled(tester, 'save', false);
    _enabled(tester, 'clear', false);
    await _press(tester, 'save');
    expect(store.writes, hasLength(1));
    await _press(tester, 'reload');
    expect(_key('missing'), findsOneWidget);
    await _press(tester, 'folder-0');
    await _press(tester, 'save');
    expect(outcome.result, isTrue);
    expect(store.writes.last.expectedRevision, 5);
    expect(store.value.revision, 6);
  });

  testWidgets('failed clear keeps the saved destination and requires reload', (
    tester,
  ) async {
    final store = _Store(_settings(destination: 'Archive'))
      ..onSave = (_) async => throw StateError('private transaction failure');
    await _show(tester, store);
    await _press(tester, 'clear');
    expect(store.value.destination!.value, 'Archive');
    expect(store.writes.single.settings.destination, isNull);
    expect(find.text(_strings.mailArchiveSettingsSaveFailed), findsOneWidget);
    expect(find.textContaining('private transaction failure'), findsNothing);
    _enabled(tester, 'save', false);
    _enabled(tester, 'clear', false);
    _enabled(tester, 'reload', true);
  });

  for (final invalid in <String, MailArchiveDestinationSettings>{
    'unchanged revision': _settings(destination: 'Archive', revision: 7),
    'skipped revision': _settings(destination: 'Archive', revision: 9),
    'wrong route': _settings(destination: 'Elsewhere', revision: 8),
    'foreign owner': _settings(
      destination: 'Archive',
      revision: 8,
      account: _foreign,
    ),
  }.entries) {
    testWidgets(
      'invalid save acknowledgement ${invalid.key} cannot close successfully',
      (tester) async {
        final store = _Store(_settings())..onSave = (_) async => invalid.value;
        final outcome = await _show(tester, store);
        await _press(tester, 'folder-0');
        await _press(tester, 'save');
        expect(outcome.result, isNull);
        expect(_key('dialog'), findsOneWidget);
        expect(
          find.text(_strings.mailArchiveSettingsSaveFailed),
          findsOneWidget,
        );
        _enabled(tester, 'save', false);
        expect(store.writes, hasLength(1));
      },
    );
  }

  testWidgets('pending save accepts one write and blocks route dismissal', (
    tester,
  ) async {
    final pending = Completer<MailArchiveDestinationSettings>();
    final store = _Store(_settings())..onSave = (_) => pending.future;
    final outcome = await _show(tester, store);
    await _press(tester, 'folder-0');
    await tester.tap(_key('save'));
    await tester.tap(_key('save'));
    await tester.pump();
    expect(store.writes, hasLength(1));
    _enabled(tester, 'save', false);
    _enabled(tester, 'cancel', false);
    _enabled(tester, 'reload', false);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_key('dialog'), findsOneWidget);
    expect(outcome.result, isNull);
    pending.complete(_settings(destination: 'Archive', revision: 8));
    await tester.pumpAndSettle();
    expect(outcome.result, isTrue);
  });

  testWidgets(
    'late save acknowledgement cannot close a retired account dialog',
    (tester) async {
      final pending = Completer<MailArchiveDestinationSettings>();
      final store = _Store(_settings())..onSave = (_) => pending.future;
      var current = true;
      final outcome = await _show(tester, store, isCurrent: () => current);
      await _press(tester, 'folder-0');
      await _press(tester, 'save', settle: false);
      current = false;
      pending.complete(_settings(destination: 'Archive', revision: 8));
      await tester.pumpAndSettle();
      expect(outcome.result, isNull);
      expect(_key('dialog'), findsOneWidget);
      expect(
        find.text(
          _strings.mailArchiveDestinationFailure(
            StudioMailArchiveDestinationFailure.stale,
          ),
        ),
        findsOneWidget,
      );
      _enabled(tester, 'save', false);
      await _press(tester, 'cancel');
      expect(outcome.result, isFalse);
    },
  );

  for (final language in StudioLanguage.values) {
    for (final enlarged in [false, true]) {
      testWidgets(
        '${language.name} ${enlarged ? 'enlarged save' : 'compact cancel'} remains accessible without overflow',
        (tester) async {
          final strings = StudioStrings(language);
          final store = _Store(_settings(destination: 'Archive/2026'));
          final outcome = await _show(
            tester,
            store,
            strings: strings,
            size: enlarged ? const Size(440, 760) : const Size(360, 640),
            scale: enlarged ? 1.7 : 1,
            accountLabel: 'Long.Account.Identity+Reports@example.test',
            loadFolders: () async => [
              _folder(
                'Archive/2026',
                name: 'Research reports and correspondence',
              ),
            ],
          );
          expect(tester.takeException(), isNull);
          expect(find.text(strings.mailArchiveSettingsTitle), findsOneWidget);
          expect(
            Directionality.of(
              tester.element(find.text(strings.mailArchiveSettingsTitle)),
            ),
            language == StudioLanguage.ar
                ? TextDirection.rtl
                : TextDirection.ltr,
          );
          expect(
            tester.widget<Text>(_key('saved')).textDirection,
            TextDirection.ltr,
          );
          _enabled(tester, 'save', true);
          await tester.ensureVisible(_key('folder-0'));
          expect(tester.takeException(), isNull);
          await _press(tester, enlarged ? 'save' : 'cancel');
          expect(outcome.result, enlarged);
          expect(store.writes, hasLength(enlarged ? 1 : 0));
          if (enlarged) {
            expect(
              store.writes.single.settings.destination!.value,
              'Archive/2026',
            );
            expect(store.writes.single.expectedRevision, 7);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
