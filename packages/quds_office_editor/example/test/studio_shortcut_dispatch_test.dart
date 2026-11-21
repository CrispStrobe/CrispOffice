import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_find_pane.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/studio_settings.dart';
import 'package:quds_office_studio/studio_window.dart';
import 'package:quds_office_studio/suite_workspace.dart';

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool alt = false,
  bool meta = false,
}) async {
  final modifiers = [
    if (control) LogicalKeyboardKey.controlLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (meta) LogicalKeyboardKey.metaLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  try {
    await tester.sendKeyEvent(key);
  } finally {
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
  }
  await _frames(tester);
}

Future<WordEditorController> _studio(
  WidgetTester tester, {
  Map<String, String> overrides = const {},
}) async {
  final previousSupported = StudioWindow.supported;
  StudioWindow.supported = false;
  final preferences = StudioRibbonPreferences(persist: false);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    preferences.dispose();
    messenger.setMockMethodCallHandler(SystemChannels.menu, null);
    StudioWindow.supported = previousSupported;
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Liberation Sans'),
      home: SuiteWorkspace(
        initialWord: (
          name: 'Shortcuts.docx',
          document: WmlDocument.empty(text: 'Keep the document owner.'),
        ),
        ribbonPreferences: preferences,
        settingsStore: StudioSettingsStore(
          backend: MemoryStudioSettingsBackend(
            StudioSettingsStore.encode(
              StudioSettings.defaults().copyWith({
                StudioSettingKeys.shortcuts: overrides,
              }),
            ),
          ),
        ),
      ),
    ),
  );
  await _frames(tester);
  final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
  final word = editor.controller;
  word.proofing.enabled = false;
  word.proofing.configure(OfficeProofingService(providers: []));
  editor.focusNode!.requestFocus();
  word.selectAll();
  await _frames(tester);
  expect(editor.focusNode!.hasPrimaryFocus, isTrue);
  expect(word.canUndo, isFalse);
  return word;
}

List<(bool, bool)> _formats(WordEditorController word) => [
  for (final run in word.document.paragraphs.single.inlines.whereType<WmlRun>())
    (run.properties.bold, run.properties.italic),
];

Finder _switcher(String label) => find.byWidgetPredicate(
  (widget) => widget is StudioAppSwitcher && widget.label == label,
);

void main() {
  for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets(
      'the real Word caret retires both bold defaults and dispatches its remap once on $platform',
      (tester) async {
        final word = await _studio(
          tester,
          overrides: {
            'format.bold': 'ctrl+alt+${LogicalKeyboardKey.digit1.keyId}',
          },
        );
        await _press(tester, LogicalKeyboardKey.keyB, control: true);
        await _press(tester, LogicalKeyboardKey.keyB, meta: true);
        expect(_formats(word), [(false, false)]);
        expect(word.canUndo, isFalse);

        await _press(
          tester,
          LogicalKeyboardKey.digit1,
          control: true,
          alt: true,
        );
        expect(_formats(word), [(true, false)]);
        expect(word.canUndo, isTrue);
        word.undo();
        await _frames(tester);
        expect(_formats(word), [(false, false)]);
        expect(
          word.canUndo,
          isFalse,
          reason: 'The remap makes one history edit.',
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('an explicit remap wins over the focused editor default', (
    tester,
  ) async {
    final word = await _studio(
      tester,
      overrides: {'format.bold': 'ctrl+${LogicalKeyboardKey.keyI.keyId}'},
    );
    await _press(tester, LogicalKeyboardKey.keyI, control: true);
    expect(_formats(word), [(true, false)]);
    word.undo();
    expect(_formats(word), [(false, false)]);
    expect(word.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('remapped redo retires Ctrl Y and both Shift Z defaults', (
    tester,
  ) async {
    final word = await _studio(
      tester,
      overrides: {'edit.redo': 'ctrl+alt+${LogicalKeyboardKey.digit2.keyId}'},
    );
    word.applyRunFormat((properties) => properties.bold = true);
    word.applyRunFormat((properties) => properties.italic = true);
    word.undo();
    word.undo();
    expect(_formats(word), [(false, false)]);
    expect(word.canUndo, isFalse);
    expect(word.canRedo, isTrue);
    for (final meta in [false, true]) {
      await _press(tester, LogicalKeyboardKey.keyY, control: !meta, meta: meta);
      await _press(
        tester,
        LogicalKeyboardKey.keyZ,
        control: !meta,
        meta: meta,
        shift: true,
      );
    }
    expect(_formats(word), [(false, false)]);
    expect(word.canUndo, isFalse);
    await _press(tester, LogicalKeyboardKey.digit2, control: true, alt: true);
    expect(_formats(word), [(true, false)]);
    expect(
      word.canRedo,
      isTrue,
      reason: 'A single key must redo only one edit.',
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'body composition defers configured and retired formatting keys',
    (tester) async {
      final word = await _studio(
        tester,
        overrides: {
          'format.bold': 'ctrl+alt+${LogicalKeyboardKey.digit1.keyId}',
        },
      );
      const composition = TextRange(start: 0, end: 1);
      word.input.setValue(
        TextEditingValue(
          text: word.document.paragraphs.single.text,
          selection: const TextSelection.collapsed(offset: 1),
          composing: composition,
        ),
      );
      final revision = word.contentRevision;
      await _press(tester, LogicalKeyboardKey.keyB, control: true);
      await _press(tester, LogicalKeyboardKey.digit1, control: true, alt: true);
      expect(_formats(word), [(false, false)]);
      expect(word.contentRevision, revision);
      expect(word.input.composing, composition);
      expect(word.canUndo, isFalse);
      word.input.setValue(
        TextEditingValue(
          text: word.document.paragraphs.single.text,
          selection: const TextSelection.collapsed(offset: 1),
        ),
      );
      await _press(tester, LogicalKeyboardKey.digit1, control: true, alt: true);
      expect(_formats(word), [(true, false)]);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'native fields retain default editing and receive remapped edits',
    (tester) async {
      final word = await _studio(
        tester,
        overrides: {
          'format.bold': 'shift+${LogicalKeyboardKey.keyA.keyId}',
          'edit.selectAll': 'ctrl+alt+${LogicalKeyboardKey.digit3.keyId}',
        },
      );
      await _press(tester, LogicalKeyboardKey.keyF, control: true);
      final query = find
          .descendant(
            of: find.byType(StudioFindPane),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(query, 'needle');
      await _frames(tester);
      final edit = tester.widget<TextField>(query).controller!;
      edit.selection = const TextSelection.collapsed(offset: 6);
      await _press(tester, LogicalKeyboardKey.keyA, control: true);
      expect(
        edit.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      edit.selection = const TextSelection.collapsed(offset: 6);
      await _press(tester, LogicalKeyboardKey.digit3, control: true, alt: true);
      expect(
        edit.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      try {
        final handled = await tester.sendKeyDownEvent(
          LogicalKeyboardKey.keyA,
          character: 'A',
        );
        expect(
          handled,
          isFalse,
          reason: 'A disabled formatting key reaches text input.',
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      expect(_formats(word), [(false, false)]);
      expect(word.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('reserved Zotero chords reject formatting overrides', (
    tester,
  ) async {
    final word = await _studio(
      tester,
      overrides: {'format.bold': 'ctrl+alt+${LogicalKeyboardKey.keyC.keyId}'},
    );
    final shortcuts = tester.widget<CallbackShortcuts>(
      find
          .descendant(
            of: find.byType(SuiteWorkspace),
            matching: find.byType(CallbackShortcuts),
          )
          .first,
    );
    expect(
      shortcuts.bindings.containsKey(
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          alt: true,
        ),
      ),
      isTrue,
    );
    await _press(tester, LogicalKeyboardKey.keyB, control: true);
    expect(_formats(word), [(true, false)]);
    word.undo();
    expect(word.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'a configured Word chord stays inactive in another document app',
    (tester) async {
      final word = await _studio(
        tester,
        overrides: {'format.bold': 'ctrl+${LogicalKeyboardKey.keyI.keyId}'},
      );
      await tester.tap(_switcher('Spreadsheets'));
      await _frames(tester);
      final sheet = tester.widget<QudsSheetEditor>(
        find.byType(QudsSheetEditor),
      );
      sheet.focusNode!.requestFocus();
      await _frames(tester);
      await _press(tester, LogicalKeyboardKey.keyI, control: true);
      expect(_formats(word), [(false, false)]);
      expect(word.canUndo, isFalse);
      expect(sheet.controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  for (final application in ['Documents', 'Spreadsheets', 'Presentations']) {
    testWidgets('held configured shortcuts respect $application composition', (
      tester,
    ) async {
      final word = await _studio(
        tester,
        overrides: {
          'navigate.find': 'ctrl+alt+${LogicalKeyboardKey.digit4.keyId}',
        },
      );
      late OfficeController document;
      late OfficeInputBridge input;
      late FocusNode focus;
      if (application == 'Documents') {
        document = word;
        input = word.input;
        focus = tester
            .widget<QudsWordEditor>(find.byType(QudsWordEditor))
            .focusNode!;
      } else {
        await tester.tap(_switcher(application));
        await _frames(tester);
        if (application == 'Spreadsheets') {
          final editor = tester.widget<QudsSheetEditor>(
            find.byType(QudsSheetEditor),
          );
          document = editor.controller;
          input = editor.controller.cellEditor.bridge;
          focus = editor.focusNode!;
          focus.requestFocus();
          editor.controller.beginCellEdit(initial: 'Composing text');
        } else {
          final editor = tester.widget<QudsSlideEditor>(
            find.byType(QudsSlideEditor),
          );
          document = editor.controller;
          input = editor.controller.textEditor.bridge;
          focus = editor.focusNode!;
          focus.requestFocus();
          editor.controller.selectShape(
            editor.controller.slide.shapes.firstWhere(
              (shape) => shape.visual == null && shape.table == null,
            ),
          );
          editor.controller.beginTextEdit(initial: 'Composing text');
        }
      }
      focus.requestFocus();
      await _frames(tester);
      expect(focus.hasPrimaryFocus, isTrue);
      var findRequests = 0;
      document.onFindRequested = () => findRequests++;
      const composition = TextRange(start: 0, end: 1);
      const value = TextEditingValue(
        text: 'Composing text',
        selection: TextSelection.collapsed(offset: 1),
        composing: composition,
      );
      input.setValue(value);
      final revision = document.contentRevision;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit4);
      try {
        expect(findRequests, 0);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit4);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit4);
        expect(
          findRequests,
          0,
          reason: 'Repeats retain the document IME guard.',
        );
        expect(input.composing, composition);
        expect(document.contentRevision, revision);
        input.setValue(value.copyWith(composing: TextRange.empty));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit4);
        expect(findRequests, 1, reason: 'An eligible repeat dispatches once.');
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.digit4);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      expect(focus.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('standalone Word keeps its built-in shortcuts without a host', (
    tester,
  ) async {
    final word = WordEditorController(
      document: WmlDocument.empty(text: 'Standalone text.'),
    );
    final focus = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      word.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QudsWordEditor(
            controller: word,
            focusNode: focus,
            enableLiveProofing: false,
            showReviewStatus: false,
          ),
        ),
      ),
    );
    focus.requestFocus();
    word.selectAll();
    await _frames(tester);
    expect(word.onShortcutKeyEvent, isNull);
    await _press(tester, LogicalKeyboardKey.keyB, control: true);
    expect(_formats(word), [(true, false)]);
    await _press(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(_formats(word), [(false, false)]);
    expect(word.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
