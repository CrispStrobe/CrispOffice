import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_desktop_menu.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/studio_settings.dart';
import 'package:quds_office_studio/studio_strings.dart';
import 'package:quds_office_studio/studio_window.dart';
import 'package:quds_office_studio/studio_zotero.dart';
import 'package:quds_office_studio/suite_workspace.dart';

import 'support/studio_document_mode.dart';

const _strings = StudioStrings(StudioLanguage.en);

final class _SavePicker extends FilePicker {
  int saves = 0;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saves++;
    return null;
  }
}

_SavePicker _savePicker() {
  final picker = _SavePicker();
  FilePicker.platform = picker;
  addTearDown(() => FilePicker.platform = FilePickerIO());
  return picker;
}

final class _UnavailableTransport extends StudioZoteroTransport {
  @override
  bool get supportsLocal => true;

  @override
  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async =>
      ZoteroHttpResponse(statusCode: 503, headers: const {}, body: '');
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Finder _switcher(String label) => find.byWidgetPredicate(
  (widget) => widget is StudioAppSwitcher && widget.label == label,
);

Future<WordEditorController> _studio(
  WidgetTester tester, {
  Map<String, String> shortcuts = const {},
  WidgetBuilder? mail,
  StudioZoteroTransport Function()? zotero,
}) async {
  final preferences = StudioRibbonPreferences(persist: false);
  final previousSupported = StudioWindow.supported;
  StudioWindow.supported = false;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    preferences.dispose();
    StudioWindow.supported = previousSupported;
    messenger.setMockMethodCallHandler(SystemChannels.menu, null);
    await tester.binding.setSurfaceSize(null);
  });
  final settings = StudioSettings.defaults().copyWith({
    StudioSettingKeys.shortcuts: shortcuts,
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Liberation Sans'),
      home: SuiteWorkspace(
        initialWord: (
          name: 'Shortcut target.docx',
          document: WmlDocument.empty(text: 'Formatting target'),
        ),
        settingsStore: StudioSettingsStore(
          backend: MemoryStudioSettingsBackend(
            StudioSettingsStore.encode(settings),
          ),
        ),
        ribbonPreferences: preferences,
        zoteroTransportFactory: zotero,
        mailBuilder: mail == null
            ? null
            : (_, chrome) => Builder(
                builder: (context) => Column(
                  children: [
                    chrome(context),
                    Expanded(child: mail(context)),
                  ],
                ),
              ),
      ),
    ),
  );
  await _frames(tester);
  await selectStudioDocumentMode(tester, OfficeInteractionMode.editing);
  final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
  final word = editor.controller;
  word.proofing.enabled = false;
  word.proofing.configure(OfficeProofingService(providers: []));
  word.selectAll();
  await _frames(tester);
  return word;
}

List<VoidCallback> _reservedBindings(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = true,
  bool shift = false,
  bool alt = false,
  bool meta = false,
}) {
  final workspace = find.descendant(
    of: find.byType(SuiteWorkspace),
    matching: find.byType(CallbackShortcuts),
  );
  final bindings = tester.widget<CallbackShortcuts>(workspace.first).bindings;
  return [
    for (final entry in bindings.entries)
      if (entry.key case final SingleActivator activator)
        if (activator.trigger == key &&
            activator.control == control &&
            activator.shift == shift &&
            activator.alt == alt &&
            activator.meta == meta)
          entry.value,
  ];
}

Future<void> Function() _capturedDocumentShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
  PhysicalKeyboardKey physicalKey,
) {
  final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
  final dispatch = editor.controller.onShortcutKeyEvent!;
  // Capture the public host hook now, then replay its original chord after
  // navigation. The saved callback must validate its owner at invocation.
  return () async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      dispatch(
        KeyDownEvent(
          physicalKey: physicalKey,
          logicalKey: key,
          timeStamp: Duration.zero,
        ),
      );
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await _frames(tester);
  };
}

VoidCallback _nativeEdit(WidgetTester tester, String id) {
  final menus = tester.widget<StudioNativeMenus>(
    find.byType(StudioNativeMenus),
  );
  return menus.editGroups
      .expand((group) => group)
      .singleWhere((action) => action.id == id)
      .onSelected!;
}

void _focusChrome(WidgetTester tester) {
  final settings = find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == 'Settings',
  );
  Focus.of(tester.element(settings)).requestFocus();
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = true,
  bool shift = false,
  bool alt = false,
  bool meta = false,
  bool chrome = false,
}) async {
  if (chrome) {
    _focusChrome(tester);
    await _frames(tester);
  }
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  try {
    if (key == LogicalKeyboardKey.add) {
      // Flutter's legacy Linux raw-key simulator has no logical Add mapping.
      // Deliver its explicit physical/logical pair through the modern handler.
      HardwareKeyboard.instance.handleKeyEvent(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.numpadAdd,
          logicalKey: key,
          timeStamp: Duration.zero,
        ),
      );
      HardwareKeyboard.instance.handleKeyEvent(
        KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.numpadAdd,
          logicalKey: key,
          timeStamp: Duration.zero,
        ),
      );
    } else {
      await tester.sendKeyEvent(key);
    }
  } finally {
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await _frames(tester);
}

Iterable<WmlRun> _runs(WordEditorController word) =>
    word.document.paragraphs.single.inlines.whereType<WmlRun>();

void main() {
  void scenario(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(
        name,
        body,
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );

  scenario('default chrome bold dispatches exactly once', (tester) async {
    final word = await _studio(tester);
    await _chord(tester, LogicalKeyboardKey.keyB, chrome: true);
    expect(_runs(word).map((run) => run.properties.bold), [true]);
    word.undo();
    expect(_runs(word).map((run) => run.properties.bold), [false]);
    expect(word.canUndo, isFalse);
  });

  scenario('reassigned bold removes old keys and applies once', (tester) async {
    final word = await _studio(
      tester,
      shortcuts: {'format.bold': 'ctrl+alt+${LogicalKeyboardKey.digit1.keyId}'},
    );
    await _chord(tester, LogicalKeyboardKey.keyB, chrome: true);
    await _chord(
      tester,
      LogicalKeyboardKey.keyB,
      control: false,
      meta: true,
      chrome: true,
    );
    expect(_runs(word).map((run) => run.properties.bold), [false]);
    expect(word.canUndo, isFalse);
    await _chord(tester, LogicalKeyboardKey.digit1, alt: true, chrome: true);
    expect(_runs(word).map((run) => run.properties.bold), [true]);
    word.undo();
    expect(word.canUndo, isFalse);
  });

  for (final key in [LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyR]) {
    scenario(
      'reserved Zotero ${key.keyLabel} survives a conflicting override',
      (tester) async {
        var connections = 0;
        final word = await _studio(
          tester,
          shortcuts: {'format.bold': 'ctrl+alt+${key.keyId}'},
          zotero: () {
            connections++;
            return _UnavailableTransport();
          },
        );
        await _chord(tester, LogicalKeyboardKey.keyB, chrome: true);
        expect(_runs(word).map((run) => run.properties.bold), [true]);
        word.undo();
        expect(_reservedBindings(tester, key, alt: true), hasLength(1));
        await _chord(tester, key, alt: true, chrome: true);
        expect(connections, 1);
        expect(_runs(word).map((run) => run.properties.bold), [false]);
        expect(word.canUndo, isFalse);
      },
    );
  }

  scenario('reassigned redo removes Ctrl Y and both Shift Z defaults', (
    tester,
  ) async {
    final word = await _studio(
      tester,
      shortcuts: {'edit.redo': 'ctrl+alt+${LogicalKeyboardKey.keyQ.keyId}'},
    );
    word.applyRunFormat((properties) => properties.bold = true);
    word.applyRunFormat((properties) => properties.italic = true);
    word.undo();
    word.undo();
    for (final meta in [false, true]) {
      await _chord(
        tester,
        LogicalKeyboardKey.keyY,
        control: !meta,
        meta: meta,
        chrome: true,
      );
      await _chord(
        tester,
        LogicalKeyboardKey.keyZ,
        control: !meta,
        meta: meta,
        shift: true,
        chrome: true,
      );
    }
    expect(word.canUndo, isFalse);
    await _chord(tester, LogicalKeyboardKey.keyQ, alt: true, chrome: true);
    expect(_runs(word).map((run) => run.properties.bold), [true]);
    expect(_runs(word).map((run) => run.properties.italic), [false]);
    expect(word.canRedo, isTrue);
  });

  scenario('reassigned zoom removes old equals and keypad aliases', (
    tester,
  ) async {
    final word = await _studio(
      tester,
      shortcuts: {'view.zoomIn': 'ctrl+alt+${LogicalKeyboardKey.keyQ.keyId}'},
    );
    final scale = word.viewport.scale;
    for (final key in [
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.numpadAdd,
      LogicalKeyboardKey.add,
    ]) {
      await _chord(tester, key, chrome: true);
      expect(word.viewport.scale, scale);
    }
    await _chord(tester, LogicalKeyboardKey.keyQ, alt: true, chrome: true);
    expect(word.viewport.scale, closeTo(scale + 0.1, 0.000001));
  });

  scenario('reassigned save removes both platform defaults', (tester) async {
    final picker = _savePicker();
    await _studio(
      tester,
      shortcuts: {'file.save': 'ctrl+alt+${LogicalKeyboardKey.keyQ.keyId}'},
    );
    await _chord(tester, LogicalKeyboardKey.keyS, chrome: true);
    await _chord(
      tester,
      LogicalKeyboardKey.keyS,
      control: false,
      meta: true,
      chrome: true,
    );
    expect(picker.saves, 0);
    await _chord(tester, LogicalKeyboardKey.keyQ, alt: true, chrome: true);
    expect(picker.saves, 1);
  });

  scenario('explicit configurable override keeps incoming precedence', (
    tester,
  ) async {
    final picker = _savePicker();
    final word = await _studio(
      tester,
      shortcuts: {'file.save': 'ctrl+${LogicalKeyboardKey.keyB.keyId}'},
    );
    await _chord(tester, LogicalKeyboardKey.keyS, chrome: true);
    expect(picker.saves, 0);
    await _chord(tester, LogicalKeyboardKey.keyB, chrome: true);
    expect(picker.saves, 1);
    expect(_runs(word).map((run) => run.properties.bold), [false]);
    expect(word.canUndo, isFalse);
  });

  scenario('captured Word mutations refuse other app targets', (tester) async {
    final word = await _studio(tester);
    final indent = _capturedDocumentShortcut(
      tester,
      LogicalKeyboardKey.keyM,
      PhysicalKeyboardKey.keyM,
    );
    final before = word.document.paragraphs.single.properties.indent.left;
    await indent();
    expect(
      word.document.paragraphs.single.properties.indent.left,
      isNot(before),
    );
    word.undo();
    expect(word.document.paragraphs.single.properties.indent.left, before);
    expect(word.canUndo, isFalse);
    final paragraph = word.document.paragraphs.single;
    for (final label in [
      _strings.spreadsheets,
      _strings.presentations,
      _strings.pdf,
    ]) {
      await tester.tap(_switcher(label));
      await _frames(tester);
      await indent();
      expect(paragraph.properties.indent.left, before);
      expect(word.canUndo, isFalse);
    }
  });

  scenario('page break refuses preview-only document mutation', (tester) async {
    final word = await _studio(tester);
    final pageBreak = _capturedDocumentShortcut(
      tester,
      LogicalKeyboardKey.enter,
      PhysicalKeyboardKey.enter,
    );
    await selectStudioDocumentMode(tester, OfficeInteractionMode.viewing);
    final paragraph = word.document.paragraphs.single;
    final before = paragraph.properties.pageBreakBefore;
    await pageBreak();
    await _frames(tester);
    expect(paragraph.properties.pageBreakBefore, before);
    expect(word.document.paragraphs, hasLength(1));
    expect(word.canUndo, isFalse);
  });

  scenario('captured Word mutation refuses a covering modal route', (
    tester,
  ) async {
    final word = await _studio(tester);
    final indent = _capturedDocumentShortcut(
      tester,
      LogicalKeyboardKey.keyM,
      PhysicalKeyboardKey.keyM,
    );
    final paragraph = word.document.paragraphs.single;
    final before = paragraph.properties.indent.left;
    final settings = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Settings',
    );
    await tester.tap(settings);
    await _frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await indent();
    expect(paragraph.properties.indent.left, before);
    expect(word.canUndo, isFalse);
  });

  scenario('custom text edit shortcut forwards to focused Find text', (
    tester,
  ) async {
    final word = await _studio(
      tester,
      shortcuts: {
        'edit.selectAll': 'ctrl+alt+${LogicalKeyboardKey.keyQ.keyId}',
      },
    );
    await _chord(tester, LogicalKeyboardKey.keyF, chrome: true);
    await _frames(tester);
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'native field text');
    await _frames(tester);
    final text = tester.widget<TextField>(field).controller!;
    final before = (
      word.caret.selectionAnchorParagraph,
      word.caret.selectionAnchor,
      word.caret.paragraphIndex,
      word.caret.logicalIndex,
    );
    await _chord(tester, LogicalKeyboardKey.keyQ, alt: true);
    expect(
      text.selection,
      const TextSelection(baseOffset: 0, extentOffset: 17),
    );
    expect((
      word.caret.selectionAnchorParagraph,
      word.caret.selectionAnchor,
      word.caret.paragraphIndex,
      word.caret.logicalIndex,
    ), before);
    await _chord(tester, LogicalKeyboardKey.keyB);
    expect(_runs(word).map((run) => run.properties.bold), [false]);
  });

  scenario('Mail native editing stays active and saved callbacks avoid Word', (
    tester,
  ) async {
    final text = TextEditingController(text: 'Mail text');
    addTearDown(text.dispose);
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      if (call.method == 'Clipboard.getData') {
        return {'text': copied ?? ''};
      }
      if (call.method == 'Clipboard.hasStrings') {
        return {'value': copied != null};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    var connections = 0;
    final word = await _studio(
      tester,
      mail: (_) => Material(child: TextField(controller: text)),
      zotero: () {
        connections++;
        return _UnavailableTransport();
      },
    );
    final select = _nativeEdit(tester, 'select-all');
    final cite = _reservedBindings(
      tester,
      LogicalKeyboardKey.keyC,
      alt: true,
    ).single;
    word.caret
      ..logicalIndex = 2
      ..collapseSelection();
    word.refresh();
    final before = (
      word.caret.selectionAnchorParagraph,
      word.caret.selectionAnchor,
      word.caret.paragraphIndex,
      word.caret.logicalIndex,
    );
    await tester.tap(_switcher(_strings.mail));
    await _frames(tester);
    final field = find.byType(TextField);
    await tester.tap(field);
    await _frames(tester);
    await _chord(tester, LogicalKeyboardKey.keyA);
    expect(text.selection, const TextSelection(baseOffset: 0, extentOffset: 9));
    await _chord(tester, LogicalKeyboardKey.keyC);
    expect(copied, 'Mail text');
    text.selection = const TextSelection.collapsed(offset: 1);
    select();
    expect(text.selection, const TextSelection(baseOffset: 0, extentOffset: 9));
    FocusManager.instance.primaryFocus?.unfocus();
    await _frames(tester);
    select();
    cite();
    expect(connections, 0);
    expect((
      word.caret.selectionAnchorParagraph,
      word.caret.selectionAnchor,
      word.caret.paragraphIndex,
      word.caret.logicalIndex,
    ), before);
    expect(word.canUndo, isFalse);
  });

  scenario(
    'comment bold italic underline remain valid while paragraph formatting is limited',
    (tester) async {
      final word = await _studio(tester);
      word.insertComment(text: 'Comment text');
      final comment = word.document.comments.single;
      word.beginCommentEdit(comment.id);
      word.selectAll();
      expect(word.isEditingComment, isTrue);
      final bodyIndent = word.document.paragraphs.single.properties.indent.left;
      final commentIndent = comment.paragraphs.single.properties.indent.left;
      for (final key in [
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.keyI,
        LogicalKeyboardKey.keyU,
      ]) {
        await _chord(tester, key, chrome: true);
      }
      final runs = comment.paragraphs.single.inlines.whereType<WmlRun>();
      expect(runs.map((run) => run.properties.bold), [true]);
      expect(runs.map((run) => run.properties.italic), [true]);
      expect(runs.map((run) => run.properties.underline), [
        WmlUnderline.single,
      ]);
      await _chord(tester, LogicalKeyboardKey.keyM, chrome: true);
      expect(
        word.document.paragraphs.single.properties.indent.left,
        bodyIndent,
      );
      expect(comment.paragraphs.single.properties.indent.left, commentIndent);
    },
  );

  scenario('saved edit callback forwards to a modal native text input', (
    tester,
  ) async {
    final word = await _studio(tester);
    final select = _nativeEdit(tester, 'select-all');
    word.caret
      ..logicalIndex = 2
      ..collapseSelection();
    word.refresh();
    final before = (
      word.caret.selectionAnchorParagraph,
      word.caret.selectionAnchor,
      word.caret.paragraphIndex,
      word.caret.logicalIndex,
    );
    final text = TextEditingController(text: 'Dialog text');
    addTearDown(text.dispose);
    final context = tester.element(find.byType(SuiteWorkspace));
    final dialog = showDialog<void>(
      context: context,
      builder: (_) =>
          AlertDialog(content: TextField(controller: text, autofocus: true)),
    );
    await _frames(tester);
    select();
    expect(
      text.selection,
      const TextSelection(baseOffset: 0, extentOffset: 11),
    );
    expect(word.caret.logicalIndex, 2);
    expect((
      word.caret.selectionAnchorParagraph,
      word.caret.selectionAnchor,
      word.caret.paragraphIndex,
      word.caret.logicalIndex,
    ), before);
    expect(word.caret.isCollapsed, isTrue);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await dialog;
    await _frames(tester);
  });
}
