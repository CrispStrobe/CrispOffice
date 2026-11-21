import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/studio_settings.dart';
import 'package:quds_office_studio/studio_settings_backend_io.dart';
import 'package:quds_office_studio/studio_web_data_store.dart';
import 'package:quds_office_studio/suite_workspace.dart';

/// [StudioWebDataStore] in memory, as Cache Storage behaves (whole entries).
final class _MemoryWebStore implements StudioWebDataStore {
  final entries = <String, Uint8List>{};
  bool refuse = false;

  @override
  Future<Uint8List?> read(String key) async => entries[key];

  @override
  Future<bool> write(String key, Uint8List bytes) async {
    if (refuse) return false;
    entries[key] = Uint8List.fromList(bytes);
    return true;
  }

  @override
  Future<void> delete(String key) async => entries.remove(key);
}

StudioSettings _changed() => StudioSettings.defaults().copyWith({
  StudioSettingKeys.language: 'ar',
  StudioSettingKeys.look: 'dark',
  StudioSettingKeys.lengthUnit: 'inches',
  StudioSettingKeys.wordRulers: false,
  StudioSettingKeys.showComments: true,
  StudioSettingKeys.pdfFitPolicy: 'page',
  StudioSettingKeys.pdfNightMode: true,
  StudioSettingKeys.checkAsYouType: false,
  StudioSettingKeys.detectLanguage: false,
  StudioSettingKeys.arabicContext: false,
  StudioSettingKeys.checkingMode: 'onPause',
  StudioSettingKeys.checkSpellingWhileTyping: false,
  StudioSettingKeys.checkGrammarWhileTyping: false,
  StudioSettingKeys.pauseMilliseconds: 2700,
  StudioSettingKeys.backgroundCheck: false,
  StudioSettingKeys.hideTypingErrors: false,
  StudioSettingKeys.personalWords: {
    'de-DE': ['Quds', 'CrispOffice'],
    'ar': ['قدس'],
  },
});

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crispoffice-settings-');
    file = File('${directory.path}/settings/studio-settings.json');
  });

  tearDown(() async => directory.delete(recursive: true));

  StudioSettingsStore store() =>
      StudioSettingsStore(backend: FileStudioSettingsBackend(file));

  group('round trip', () {
    test('a fresh install loads defaults and writes nothing', () async {
      final settings = await store().load();
      expect(settings, StudioSettings.defaults());
      expect(settings.choice(StudioSettingKeys.language), 'en');
      expect(settings.flag(StudioSettingKeys.checkAsYouType), isTrue);
      expect(file.existsSync(), isFalse);
    });

    test('every value survives save and load', () async {
      final first = store();
      await first.load();
      await first.save(_changed());
      expect(first.saveError, isNull);

      final second = store();
      final loaded = await second.load();
      expect(second.source, StudioSettingsSource.stored);
      expect(second.repaired, isEmpty);
      expect(loaded, _changed());
      expect(
        loaded.choiceOf(
          StudioSettingKeys.lengthUnit,
          OfficeLengthUnit.values,
          OfficeLengthUnit.millimeters,
        ),
        OfficeLengthUnit.inches,
      );
      expect(
        loaded.choiceOf(
          StudioSettingKeys.look,
          SuiteLook.values,
          SuiteLook.light,
        ),
        SuiteLook.dark,
      );
      expect(loaded.personalWords, {
        'ar': ['قدس'],
        'de-DE': ['CrispOffice', 'Quds'],
      });
      final json = jsonDecode(file.readAsStringSync()) as Map;
      expect(json['format'], StudioSettingsStore.format);
      expect(json['version'], StudioSettingsStore.version);
    });

    test('writes are atomic: no temporary file remains, the last save '
        'wins and a failing write is reported, not thrown', () async {
      final settings = store();
      await settings.load();
      final saves = [
        for (final language in ['de', 'ar', 'en', 'de'])
          settings.save(
            StudioSettings.defaults().copyWith({
              StudioSettingKeys.language: language,
            }),
          ),
      ];
      await Future.wait(saves);
      await settings.flush();
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      expect((await store().load()).choice(StudioSettingKeys.language), 'de');

      // A directory where the document should be: the write fails.
      final blocked = File('${directory.path}/blocked/doc.json');
      Directory(blocked.path).createSync(recursive: true);
      final failing = StudioSettingsStore(
        backend: FileStudioSettingsBackend(blocked),
      );
      await failing.save(_changed());
      expect(failing.saveError, isNotNull);
    });

    test('an oversized dictionary preserves the last good document and '
        'a later valid save recovers', () async {
      final backend = MemoryStudioSettingsBackend();
      final settings = StudioSettingsStore(backend: backend);
      await settings.load();
      final lastGood = _changed();
      await settings.save(lastGood);
      final lastGoodDocument = backend.contents;
      final lastGoodWrites = backend.writes;
      final oversized = lastGood.copyWith({
        StudioSettingKeys.personalWords: {
          'en': List<String>.generate(
            10000,
            (index) => index.toString().padLeft(5, '0').padRight(100, 'x'),
          ),
        },
      });
      expect(oversized.personalWords['en'], hasLength(10000));
      expect(
        StudioSettingsStore.encode(oversized).length,
        greaterThan(StudioSettingsStore.maxBytes),
      );

      await settings.save(oversized);
      await settings.flush();
      expect(
        settings.saveError,
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('size limit'),
        ),
      );
      expect(settings.source, StudioSettingsSource.stored);
      expect(backend.writes, lastGoodWrites);
      expect(backend.contents, lastGoodDocument);

      final reloaded = StudioSettingsStore(backend: backend);
      expect(await reloaded.load(), lastGood);
      expect(reloaded.source, StudioSettingsSource.stored);
      expect(backend.quarantined, isNull);

      final recovered = lastGood.copyWith({StudioSettingKeys.language: 'de'});
      await settings.save(recovered);
      expect(settings.saveError, isNull);
      expect(backend.writes, lastGoodWrites + 1);
      expect(await reloaded.load(), recovered);
    });

    test('stores preferences only, never secrets', () async {
      final text = StudioSettingsStore.encode(_changed());
      final keys = ((jsonDecode(text) as Map)['settings'] as Map).keys;
      expect(keys.toSet(), StudioSettings.specs.keys.toSet());
      for (final key in keys.cast<String>()) {
        expect(
          key.toLowerCase(),
          isNot(matches(RegExp('password|secret|token|credential|oauth'))),
        );
      }
    });
  });

  group('corrupt or unknown values', () {
    for (final (name, bytes) in <(String, List<int>)>[
      ('not JSON', utf8.encode('{"format": "crispoffice-studio')),
      ('not an object', utf8.encode('[1, 2, 3]')),
      ('invalid UTF-8', [0xff, 0xfe, 0x7b, 0x00, 0xc3]),
      (
        'a foreign document',
        utf8.encode('{"format": "other", "version": 1, "settings": {}}'),
      ),
      (
        'settings that are not an object',
        utf8.encode(
          '{"format": "crispoffice-studio-settings", "version": 1, '
          '"settings": "dark"}',
        ),
      ),
    ]) {
      test('$name: defaults, the file is set aside, saving works', () async {
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        final settings = store();
        expect(await settings.load(), StudioSettings.defaults());
        expect(settings.source, StudioSettingsSource.corrupt);
        expect(File('${file.path}.corrupt').readAsBytesSync(), bytes);

        await settings.save(_changed());
        expect(await store().load(), _changed());
      });
    }

    test('invalid values fall back one by one; valid ones stay', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'format': StudioSettingsStore.format,
          'version': 1,
          'settings': {
            StudioSettingKeys.language: 'fr',
            StudioSettingKeys.look: 'dark',
            StudioSettingKeys.wordRulers: 'no',
            StudioSettingKeys.showNotes: true,
            StudioSettingKeys.pdfFitPolicy: 3,
            StudioSettingKeys.personalWords: {
              'de-DE': ['ok', 42, '', 'x' * 500],
              'not a language!': ['dropped'],
              'en-US': 'not a list',
            },
          },
        }),
      );
      final settings = store();
      final loaded = await settings.load();
      expect(settings.source, StudioSettingsSource.stored);
      expect(loaded.choice(StudioSettingKeys.language), 'en');
      expect(loaded.choice(StudioSettingKeys.look), 'dark');
      expect(loaded.flag(StudioSettingKeys.wordRulers), isTrue);
      expect(loaded.flag(StudioSettingKeys.showNotes), isTrue);
      expect(loaded.choice(StudioSettingKeys.pdfFitPolicy), 'width');
      expect(loaded.personalWords, {
        'de-DE': ['ok'],
      });
      expect(
        settings.repaired,
        unorderedEquals([
          StudioSettingKeys.language,
          StudioSettingKeys.wordRulers,
          StudioSettingKeys.pdfFitPolicy,
        ]),
      );
    });

    test('proofing schedule values are validated and map to the session', () {
      final defaults = StudioSettings.defaults();
      expect(defaults.proofingSchedule, const WordProofingSchedule());
      final repaired = <String>[];
      final settings = StudioSettings.fromSettingsJson({
        StudioSettingKeys.checkingMode: 'sometimes',
        StudioSettingKeys.pauseMilliseconds: 100,
        StudioSettingKeys.checkSpellingWhileTyping: 'yes',
        StudioSettingKeys.hideTypingErrors: false,
      }, repaired: repaired);
      expect(repaired, {
        StudioSettingKeys.checkingMode,
        StudioSettingKeys.pauseMilliseconds,
        StudioSettingKeys.checkSpellingWhileTyping,
      });
      expect(
        settings.proofingSchedule,
        const WordProofingSchedule(hideTypingErrors: false),
      );
      for (final invalid in <Object>[299, 5001, 1500.5, 'fast', double.nan]) {
        expect(
          () =>
              defaults.copyWith({StudioSettingKeys.pauseMilliseconds: invalid}),
          throwsArgumentError,
        );
      }
      // Integral JSON numbers are accepted.
      expect(
        defaults
            .copyWith({StudioSettingKeys.pauseMilliseconds: 2000.0})
            .proofingSchedule
            .pause,
        const Duration(seconds: 2),
      );
      final changed = _changed();
      expect(
        changed.proofingSchedule,
        const WordProofingSchedule(
          mode: WordProofingMode.onPause,
          checkSpelling: false,
          checkGrammar: false,
          pause: Duration(milliseconds: 2700),
          backgroundCheck: false,
          hideTypingErrors: false,
        ),
      );
      expect(
        defaults
            .copyWith(
              StudioSettings.proofingScheduleJson(changed.proofingSchedule),
            )
            .proofingSchedule,
        changed.proofingSchedule,
      );
    });

    test('copyWith rejects invalid values', () {
      expect(
        () => StudioSettings.defaults().copyWith({
          StudioSettingKeys.language: 'xx',
        }),
        throwsArgumentError,
      );
      expect(
        () => StudioSettings.defaults().copyWith({'no.such.key': true}),
        throwsArgumentError,
      );
    });

    test('unknown keys from a newer app are kept across saves', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'format': StudioSettingsStore.format,
          'version': 1,
          'settings': {
            StudioSettingKeys.look: 'highContrast',
            'future.option': {'nested': true},
          },
        }),
      );
      final settings = store();
      final loaded = await settings.load();
      expect(loaded.unknown, {
        'future.option': {'nested': true},
      });
      await settings.save(loaded.copyWith({StudioSettingKeys.language: 'de'}));
      final saved = (jsonDecode(file.readAsStringSync()) as Map)['settings'];
      expect(saved['future.option'], {'nested': true});
      expect(saved[StudioSettingKeys.look], 'highContrast');
      expect(saved[StudioSettingKeys.language], 'de');
    });
  });

  group('schema version and migration', () {
    test('an unversioned (version 0) document is migrated and rewritten '
        'as the current version', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          StudioSettingKeys.language: 'de',
          StudioSettingKeys.showOutline: true,
        }),
      );
      final settings = store();
      final loaded = await settings.load();
      expect(settings.source, StudioSettingsSource.migrated);
      expect(loaded.choice(StudioSettingKeys.language), 'de');
      expect(loaded.flag(StudioSettingKeys.showOutline), isTrue);
      await settings.save(loaded);
      final json = jsonDecode(file.readAsStringSync()) as Map;
      expect(json['version'], StudioSettingsStore.version);
      expect(json['settings'][StudioSettingKeys.language], 'de');
      final again = store();
      expect(await again.load(), loaded);
      expect(again.source, StudioSettingsSource.stored);
    });

    test('a newer version is read best effort and never overwritten', () async {
      file.parent.createSync(recursive: true);
      final newer = jsonEncode({
        'format': StudioSettingsStore.format,
        'version': StudioSettingsStore.version + 1,
        'settings': {
          StudioSettingKeys.language: 'ar',
          'v2.only': [1, 2],
        },
      });
      file.writeAsStringSync(newer);
      final settings = store();
      final loaded = await settings.load();
      expect(settings.source, StudioSettingsSource.newer);
      expect(settings.readOnly, isTrue);
      expect(loaded.choice(StudioSettingKeys.language), 'ar');
      await settings.save(_changed());
      expect(file.readAsStringSync(), newer);
    });

    test('an invalid version is corrupt', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'format': StudioSettingsStore.format,
          'version': 'one',
          'settings': {},
        }),
      );
      final settings = store();
      expect(await settings.load(), StudioSettings.defaults());
      expect(settings.source, StudioSettingsSource.corrupt);
    });
  });

  group('web backend (Cache Storage layer)', () {
    test('round trip, corrupt bytes and a refusing browser', () async {
      final web = _MemoryWebStore();
      StudioSettingsStore create() => StudioSettingsStore(
        backend: WebDataStoreStudioSettingsBackend(
          web,
          key: 'settings/studio-settings.json',
        ),
      );
      final first = create();
      await first.load();
      await first.save(_changed());
      expect(web.entries.keys, ['settings/studio-settings.json']);
      expect(await create().load(), _changed());

      web.entries['settings/studio-settings.json'] = Uint8List.fromList([
        0xff,
        0x00,
      ]);
      final corrupt = create();
      expect(await corrupt.load(), StudioSettings.defaults());
      expect(corrupt.source, StudioSettingsSource.corrupt);
      expect(web.entries, contains('settings/studio-settings.json.corrupt'));

      web.refuse = true;
      await corrupt.save(_changed());
      expect(corrupt.saveError, isNotNull);
    });

    test('ribbon preferences persist through a settings backend', () async {
      final backend = MemoryStudioSettingsBackend();
      final first = StudioRibbonPreferences(backend: backend);
      await first.load();
      first
        ..setShowGroupLabels(false)
        ..setVisible('tabs.word', 'review', false);
      await first.flush();
      first.dispose();
      final restored = StudioRibbonPreferences(backend: backend);
      await restored.load();
      expect(restored.showGroupLabels, isFalse);
      expect(restored.isVisible('tabs.word', 'review'), isFalse);
      restored.dispose();
    });
  });

  testWidgets('the workspace restores stored settings and saves changes', (
    tester,
  ) async {
    final backend = MemoryStudioSettingsBackend(
      StudioSettingsStore.encode(
        StudioSettings.defaults().copyWith({
          StudioSettingKeys.language: 'ar',
          StudioSettingKeys.look: 'dark',
          StudioSettingKeys.personalWords: {
            'de-DE': ['Quds'],
          },
        }),
      ),
    );
    final ribbon = StudioRibbonPreferences(persist: false);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      ribbon.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SuiteWorkspace(
          ribbonPreferences: ribbon,
          settingsStore: StudioSettingsStore(backend: backend),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Restored: Arabic UI (right to left); nothing rewritten unchanged.
    expect(
      tester
          .widget<Directionality>(
            find
                .descendant(
                  of: find.byType(SuiteWorkspace),
                  matching: find.byType(Directionality),
                )
                .first,
          )
          .textDirection,
      TextDirection.rtl,
    );
    expect(backend.writes, 0);

    // A change made in the workspace is saved.
    final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
    editor.controller.proofing.vocabulary.addWord('Strobe', language: 'de-DE');
    editor.controller.proofing.enabled = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final saved = (jsonDecode(backend.contents!) as Map)['settings'] as Map;
    expect(saved[StudioSettingKeys.language], 'ar');
    expect(saved[StudioSettingKeys.look], 'dark');
    expect(saved[StudioSettingKeys.checkAsYouType], isFalse);
    expect(saved[StudioSettingKeys.personalWords], {
      'de-DE': ['Quds', 'Strobe'],
    });
  });

  testWidgets('proofing schedule settings are restored, applied at once '
      'from the Settings dialog and saved', (tester) async {
    final backend = MemoryStudioSettingsBackend(
      StudioSettingsStore.encode(
        StudioSettings.defaults().copyWith({
          StudioSettingKeys.checkingMode: 'onPause',
          StudioSettingKeys.pauseMilliseconds: 2500,
          StudioSettingKeys.hideTypingErrors: false,
        }),
      ),
    );
    final ribbon = StudioRibbonPreferences(persist: false);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      ribbon.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SuiteWorkspace(
          ribbonPreferences: ribbon,
          settingsStore: StudioSettingsStore(backend: backend),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final proofing = tester
        .widget<QudsWordEditor>(find.byType(QudsWordEditor))
        .controller
        .proofing;
    expect(
      proofing.schedule,
      const WordProofingSchedule(
        mode: WordProofingMode.onPause,
        pause: Duration(milliseconds: 2500),
        hideTypingErrors: false,
      ),
    );
    expect(backend.writes, 0);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    Finder key(String value) => find.byKey(ValueKey<String>(value));

    // Mode: "Only when I click Check document".
    final mode = key('studio-setting-proofing-mode');
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Only when I click Check document').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(proofing.schedule.mode, WordProofingMode.manual);
    // The dependent switches are disabled in manual mode.
    final grammar = key('studio-setting-check-grammar');
    await tester.ensureVisible(grammar);
    expect(tester.widget<SwitchListTile>(grammar).onChanged, isNull);

    // Back to "While typing", then turn grammar off and hiding on.
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('While typing (recommended)').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(grammar);
    await tester.tap(grammar);
    await tester.pump();
    final hide = key('studio-setting-hide-typing-errors');
    await tester.ensureVisible(hide);
    await tester.tap(hide);
    await tester.pump();
    expect(
      proofing.schedule,
      const WordProofingSchedule(
        checkGrammar: false,
        pause: Duration(milliseconds: 2500),
      ),
    );
    // The pause slider snaps to tenths of a second.
    final slider = key('studio-setting-proofing-pause');
    await tester.ensureVisible(slider);
    tester.widget<Slider>(slider).onChanged!(1234);
    await tester.pump();
    expect(proofing.schedule.pause, const Duration(milliseconds: 1200));

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Close'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final saved = (jsonDecode(backend.contents!) as Map)['settings'] as Map;
    expect(saved[StudioSettingKeys.checkingMode], 'whileTyping');
    expect(saved[StudioSettingKeys.checkGrammarWhileTyping], isFalse);
    expect(saved[StudioSettingKeys.checkSpellingWhileTyping], isTrue);
    expect(saved[StudioSettingKeys.pauseMilliseconds], 1200);
    expect(saved[StudioSettingKeys.backgroundCheck], isTrue);
    expect(saved[StudioSettingKeys.hideTypingErrors], isTrue);
    expect(saved[StudioSettingKeys.checkAsYouType], isTrue);
  });
}
