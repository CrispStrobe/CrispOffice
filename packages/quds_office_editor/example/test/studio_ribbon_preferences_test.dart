import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crispoffice-ribbon-');
    file = File('${directory.path}/preferences.json');
  });

  tearDown(() async => directory.delete(recursive: true));

  StudioRibbonPreferences create() =>
      StudioRibbonPreferences(file: () async => file);

  test(
    'persists display options and independent application/tab layouts',
    () async {
      final first = create();
      await first.load();
      first
        ..setCompact(false)
        ..setShowCommandLabels(true)
        ..setShowGroupLabels(false)
        ..setCollapsed(true)
        ..setVisible('tabs.word', 'review', false)
        ..setOrder('tabs.word', ['home', 'view', 'insert'])
        ..setVisible('groups.word.insert', 'illustrations', false)
        ..setOrder('groups.word.insert', ['zotero', 'text', 'insert']);
      await first.flush();
      first.dispose();

      final restored = create();
      await restored.load();
      expect(restored.compact, isFalse);
      expect(restored.showCommandLabels, isTrue);
      expect(restored.showGroupLabels, isFalse);
      expect(restored.collapsed, isTrue);
      expect(restored.isVisible('tabs.word', 'review'), isFalse);
      expect(restored.isVisible('tabs.powerpoint', 'review'), isTrue);
      expect(
        restored.isVisible('groups.word.insert', 'illustrations'),
        isFalse,
      );
      expect(
        restored.isVisible('groups.excel.insert', 'illustrations'),
        isTrue,
      );
      expect(
        restored.orderedIds('groups.word.insert', [
          'insert',
          'text',
          'zotero',
          'equations',
        ]),
        ['zotero', 'text', 'insert', 'equations'],
      );
      restored.dispose();
    },
  );

  test(
    'reset survives a restart and restores access to hidden groups',
    () async {
      final preferences = create();
      preferences
        ..setVisible('tabs.word', 'insert', false)
        ..setVisible('groups.word.insert', 'zotero', false)
        ..setOrder('tabs.word', ['review', 'home'])
        ..setCompact(false)
        ..setShowCommandLabels(true)
        ..setCollapsed(true)
        ..reset();
      await preferences.flush();
      preferences.dispose();
      final restored = create();
      await restored.load();
      expect(restored.isVisible('tabs.word', 'insert'), isTrue);
      expect(restored.isVisible('groups.word.insert', 'zotero'), isTrue);
      expect(restored.orderedIds('tabs.word', ['file', 'home', 'insert']), [
        'file',
        'home',
        'insert',
      ]);
      expect(restored.compact, isTrue);
      expect(restored.showCommandLabels, isFalse);
      expect(restored.showGroupLabels, isTrue);
      expect(restored.collapsed, isFalse);
      restored.dispose();
    },
  );

  for (final content in <String>[
    'not json',
    '{"version":2,"compact":false}',
    '[]',
    '{"version":1,"orders":[1],"hidden":{"tabs.word":false},"compact":"false"}',
  ]) {
    test(
      'malformed or future preferences keep usable defaults: $content',
      () async {
        await file.writeAsString(content);
        final preferences = create();
        await preferences.load();
        expect(preferences.compact, isTrue);
        expect(preferences.isVisible('tabs.word', 'insert'), isTrue);
        expect(
          preferences.orderedIds('tabs.word', ['file', 'home', 'insert']),
          ['file', 'home', 'insert'],
        );
        preferences.dispose();
      },
    );
  }

  test('late loading cannot overwrite a user edit', () async {
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'compact': false,
        'showCommandLabels': false,
      }),
    );
    final gate = Completer<File>();
    final preferences = StudioRibbonPreferences(file: () => gate.future);
    final loading = preferences.load();
    preferences.setShowCommandLabels(true);
    gate.complete(file);
    await loading;
    await preferences.flush();
    expect(preferences.showCommandLabels, isTrue);
    expect(preferences.compact, isTrue);
    preferences.dispose();
  });

  test('rapid queued edits persist the final value', () async {
    final gate = Completer<File>();
    final preferences = StudioRibbonPreferences(file: () => gate.future);
    preferences
      ..setCollapsed(true)
      ..setCollapsed(false)
      ..setShowCommandLabels(true)
      ..setVisible('tabs.word', 'insert', false)
      ..setVisible('tabs.word', 'insert', true);
    gate.complete(file);
    await preferences.flush();
    preferences.dispose();
    final restored = create();
    await restored.load();
    expect(restored.collapsed, isFalse);
    expect(restored.showCommandLabels, isTrue);
    expect(restored.isVisible('tabs.word', 'insert'), isTrue);
    restored.dispose();
  });

  test(
    'unavailable storage keeps session changes and later writes recover',
    () async {
      var failing = true;
      final preferences = StudioRibbonPreferences(
        file: () async {
          if (failing) throw const FileSystemException('Read-only location');
          return file;
        },
      );
      preferences.setShowCommandLabels(true);
      await preferences.flush();
      expect(preferences.showCommandLabels, isTrue);
      expect(preferences.saveError, isNotNull);
      failing = false;
      preferences.setCompact(false);
      await preferences.flush();
      expect(preferences.saveError, isNull);
      final restored = create();
      await restored.load();
      expect(restored.compact, isFalse);
      expect(restored.showCommandLabels, isTrue);
      preferences.dispose();
      restored.dispose();
    },
  );

  test(
    'unknown and duplicate IDs cannot remove newly available commands',
    () async {
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'orders': <String, Object?>{
            'groups.word.insert': ['zotero', 'old-group', 'zotero', 4],
          },
          'hidden': <String, Object?>{
            'groups.word.insert': ['old-group'],
          },
        }),
      );
      final preferences = create();
      await preferences.load();
      expect(
        preferences.orderedIds('groups.word.insert', [
          'insert',
          'zotero',
          'equations',
        ]),
        ['zotero', 'insert', 'equations'],
      );
      expect(preferences.isVisible('groups.word.insert', 'equations'), isTrue);
      preferences.dispose();
    },
  );
}
