import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/studio_settings.dart';
import 'package:quds_office_studio/studio_strings.dart';
import 'package:quds_office_studio/studio_window.dart';
import 'package:quds_office_studio/suite_workspace.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _mailTarget = ValueKey('mail-shortcut-focus-target');

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Finder _switcher(String label) => find.byWidgetPredicate(
  (widget) => widget is StudioAppSwitcher && widget.label == label,
);

Future<void> _controlShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  try {
    await tester.sendKeyEvent(key);
  } finally {
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await _frames(tester);
}

void main() {
  testWidgets(
    'Mail focus isolates hidden Word shortcuts and closing Mail restores one dispatch',
    (tester) async {
      final previousSupported = StudioWindow.supported;
      StudioWindow.supported = false;
      final preferences = StudioRibbonPreferences(persist: false);
      final mailFocus = FocusNode(debugLabel: 'mail-shortcut-fixture');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.menu,
        (_) async => null,
      );
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        mailFocus.dispose();
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
              name: 'Untouched.docx',
              document: WmlDocument.empty(
                text: 'Keep this Word text unchanged.',
              ),
            ),
            ribbonPreferences: preferences,
            settingsStore: StudioSettingsStore(
              backend: MemoryStudioSettingsBackend(),
            ),
            mailBuilder: (_, chrome) => Builder(
              builder: (context) => Column(
                children: [
                  chrome(context),
                  Expanded(
                    child: Focus(
                      key: _mailTarget,
                      focusNode: mailFocus,
                      child: const Center(child: Text('Mail keyboard target')),
                    ),
                  ),
                ],
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
      final document = word.document;
      final contentRevision = word.contentRevision;
      final text = document.paragraphs.single.text;
      final selection = (
        word.caret.selectionAnchorParagraph,
        word.caret.selectionAnchor,
        word.caret.paragraphIndex,
        word.caret.logicalIndex,
      );
      expect(document.trackRevisions, isFalse);
      expect(
        document.paragraphs.single.inlines.whereType<WmlRun>().map(
          (run) => run.properties.bold,
        ),
        [false],
      );
      expect(word.canUndo, isFalse);
      expect(word.isDirty, isFalse);

      await tester.tap(_switcher(_strings.mail));
      await _frames(tester);
      expect(find.byKey(_mailTarget), findsOneWidget);
      expect(find.byType(QudsWordEditor), findsNothing);
      expect(
        tester
            .widget<QudsWordEditor>(
              find.byType(QudsWordEditor, skipOffstage: false),
            )
            .controller,
        same(word),
        reason: 'Mail leaves the existing Word controller mounted but hidden.',
      );
      mailFocus.requestFocus();
      await _frames(tester);
      expect(mailFocus.hasPrimaryFocus, isTrue);

      for (final shortcut in [
        (key: LogicalKeyboardKey.keyE, shift: true),
        (key: LogicalKeyboardKey.keyB, shift: false),
        // The workspace has a separate modifier-only direction handler.
        (key: LogicalKeyboardKey.shiftRight, shift: false),
      ]) {
        await _controlShortcut(tester, shortcut.key, shift: shortcut.shift);
        expect(mailFocus.hasPrimaryFocus, isTrue);
        expect(word.document, same(document));
        expect(word.contentRevision, contentRevision);
        expect(document.paragraphs.single.text, text);
        expect(document.trackRevisions, isFalse);
        expect(
          document.paragraphs.single.inlines.whereType<WmlRun>().map(
            (run) => run.properties.bold,
          ),
          [false],
        );
        expect(word.canUndo, isFalse);
        expect(word.isDirty, isFalse);
        expect((
          word.caret.selectionAnchorParagraph,
          word.caret.selectionAnchor,
          word.caret.paragraphIndex,
          word.caret.logicalIndex,
        ), selection);
      }

      // Return through the Mail title bar's real Documents switcher. Word's
      // shortcuts must work again without a duplicate toggle or history entry.
      await tester.tap(_switcher(_strings.documents));
      await _frames(tester);
      expect(find.byKey(_mailTarget), findsNothing);
      final returnedEditor = tester.widget<QudsWordEditor>(
        find.byType(QudsWordEditor),
      );
      expect(returnedEditor.controller, same(word));
      returnedEditor.focusNode!.requestFocus();
      word.selectAll();
      await _frames(tester);
      expect(returnedEditor.focusNode!.hasPrimaryFocus, isTrue);

      await _controlShortcut(tester, LogicalKeyboardKey.keyB);
      expect(
        word.document.paragraphs.single.inlines.whereType<WmlRun>().map(
          (run) => run.properties.bold,
        ),
        [true],
      );
      expect(word.canUndo, isTrue);
      word.undo();
      await _frames(tester);
      expect(
        word.document.paragraphs.single.inlines.whereType<WmlRun>().map(
          (run) => run.properties.bold,
        ),
        [false],
      );
      expect(word.canUndo, isFalse, reason: 'Ctrl+B creates exactly one edit.');

      await _controlShortcut(tester, LogicalKeyboardKey.keyE, shift: true);
      expect(word.document.trackRevisions, isTrue);
      expect(word.canUndo, isTrue);
      word.undo();
      await _frames(tester);
      expect(word.document.trackRevisions, isFalse);
      expect(
        word.canUndo,
        isFalse,
        reason: 'Ctrl+Shift+E creates exactly one edit after Mail closes.',
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
