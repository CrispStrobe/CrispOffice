import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/studio_settings.dart';
import 'package:quds_office_studio/studio_strings.dart';
import 'package:quds_office_studio/studio_window.dart';
import 'package:quds_office_studio/studio_zotero.dart';
import 'package:quds_office_studio/suite_workspace.dart';

import 'support/studio_document_mode.dart';

const _strings = StudioStrings(StudioLanguage.en);

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

List<VoidCallback> _bindings(
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

void _focusChrome(WidgetTester tester) {
  final settings = find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == 'Settings',
  );
  Focus.of(tester.element(settings)).requestFocus();
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
  bool chrome = false,
}) async {
  if (chrome) {
    _focusChrome(tester);
    await _frames(tester);
  }
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  try {
    await tester.sendKeyEvent(key);
  } finally {
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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
    expect(_bindings(tester, LogicalKeyboardKey.keyB), hasLength(1));
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
    expect(_bindings(tester, LogicalKeyboardKey.keyB), isEmpty);
    expect(
      _bindings(tester, LogicalKeyboardKey.keyB, control: false, meta: true),
      isEmpty,
    );
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
        expect(_bindings(tester, LogicalKeyboardKey.keyB), hasLength(1));
        expect(_bindings(tester, key, alt: true), hasLength(1));
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
    await _studio(
      tester,
      shortcuts: {'edit.redo': 'ctrl+alt+${LogicalKeyboardKey.keyQ.keyId}'},
    );
    expect(_bindings(tester, LogicalKeyboardKey.keyY), isEmpty);
    expect(
      _bindings(tester, LogicalKeyboardKey.keyY, control: false, meta: true),
      isEmpty,
    );
    expect(_bindings(tester, LogicalKeyboardKey.keyZ, shift: true), isEmpty);
    expect(
      _bindings(
        tester,
        LogicalKeyboardKey.keyZ,
        control: false,
        meta: true,
        shift: true,
      ),
      isEmpty,
    );
    expect(_bindings(tester, LogicalKeyboardKey.keyQ, alt: true), hasLength(1));
  });

  scenario('reassigned zoom removes old equals and keypad aliases', (
    tester,
  ) async {
    await _studio(
      tester,
      shortcuts: {'view.zoomIn': 'ctrl+alt+${LogicalKeyboardKey.keyQ.keyId}'},
    );
    expect(_bindings(tester, LogicalKeyboardKey.equal), isEmpty);
    expect(_bindings(tester, LogicalKeyboardKey.numpadAdd), isEmpty);
    expect(_bindings(tester, LogicalKeyboardKey.add), isEmpty);
    expect(_bindings(tester, LogicalKeyboardKey.keyQ, alt: true), hasLength(1));
  });

  scenario('reassigned save removes both platform defaults', (tester) async {
    await _studio(
      tester,
      shortcuts: {'file.save': 'ctrl+alt+${LogicalKeyboardKey.keyQ.keyId}'},
    );
    expect(_bindings(tester, LogicalKeyboardKey.keyS), isEmpty);
    expect(
      _bindings(tester, LogicalKeyboardKey.keyS, control: false, meta: true),
      isEmpty,
    );
    expect(_bindings(tester, LogicalKeyboardKey.keyQ, alt: true), hasLength(1));
  });

  scenario('explicit configurable override keeps incoming precedence', (
    tester,
  ) async {
    await _studio(
      tester,
      shortcuts: {'file.save': 'ctrl+${LogicalKeyboardKey.keyB.keyId}'},
    );
    expect(_bindings(tester, LogicalKeyboardKey.keyB), hasLength(1));
    expect(_bindings(tester, LogicalKeyboardKey.keyS), isEmpty);
  });

  scenario('captured Word mutations refuse other app targets', (tester) async {
    final word = await _studio(tester);
    final indent = _bindings(tester, LogicalKeyboardKey.keyM).single;
    final paragraph = word.document.paragraphs.single;
    final before = paragraph.properties.indent.left;
    for (final label in [
      _strings.spreadsheets,
      _strings.presentations,
      _strings.pdf,
    ]) {
      await tester.tap(_switcher(label));
      await _frames(tester);
      indent();
      expect(paragraph.properties.indent.left, before);
      expect(word.canUndo, isFalse);
    }
  });

  scenario('page break refuses preview-only document mutation', (tester) async {
    final word = await _studio(tester);
    final pageBreak = _bindings(tester, LogicalKeyboardKey.enter).single;
    await selectStudioDocumentMode(tester, OfficeInteractionMode.viewing);
    final paragraph = word.document.paragraphs.single;
    final before = paragraph.properties.pageBreakBefore;
    pageBreak();
    await _frames(tester);
    expect(paragraph.properties.pageBreakBefore, before);
    expect(word.document.paragraphs, hasLength(1));
    expect(word.canUndo, isFalse);
  });

  scenario('captured Word mutation refuses a covering modal route', (
    tester,
  ) async {
    final word = await _studio(tester);
    final indent = _bindings(tester, LogicalKeyboardKey.keyM).single;
    final paragraph = word.document.paragraphs.single;
    final before = paragraph.properties.indent.left;
    final settings = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Settings',
    );
    await tester.tap(settings);
    await _frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    indent();
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
    _bindings(tester, LogicalKeyboardKey.keyF).single();
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
    _bindings(tester, LogicalKeyboardKey.keyB).single();
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
    final select = _bindings(tester, LogicalKeyboardKey.keyA).single;
    final cite = _bindings(tester, LogicalKeyboardKey.keyC, alt: true).single;
    word.caret
      ..collapseSelection()
      ..logicalIndex = 2;
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
        _bindings(tester, key).single();
      }
      final runs = comment.paragraphs.single.inlines.whereType<WmlRun>();
      expect(runs.map((run) => run.properties.bold), [true]);
      expect(runs.map((run) => run.properties.italic), [true]);
      expect(runs.map((run) => run.properties.underline), [
        WmlUnderline.single,
      ]);
      _bindings(tester, LogicalKeyboardKey.keyM).single();
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
    final select = _bindings(tester, LogicalKeyboardKey.keyA).single;
    word.caret
      ..collapseSelection()
      ..logicalIndex = 2;
    word.refresh();
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
    expect(word.caret.selectionAnchor, isNull);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await dialog;
    await _frames(tester);
  });
}
