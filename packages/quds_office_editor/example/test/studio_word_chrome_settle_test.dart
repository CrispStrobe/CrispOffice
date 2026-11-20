import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/suite_workspace.dart';

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _dialogFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await _frames(tester);
}

void main() {
  testWidgets(
    'the trailing Word chrome refresh requests an idle frame and shows the latest heading',
    (tester) async {
      final preferences = StudioRibbonPreferences(persist: false);
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        preferences.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Liberation Sans'),
          // Suppress the editor's continuous caret ticker so unrelated
          // animation cannot supply the idle frame. Modal routes stay outside
          // this home subtree and retain their ordinary transitions.
          home: TickerMode(
            enabled: false,
            child: SuiteWorkspace(ribbonPreferences: preferences),
          ),
        ),
      );
      await _frames(tester);
      final word = tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller;
      word.proofing.enabled = false;
      word.proofing.configure(OfficeProofingService(providers: []));
      const heading = 'Chrome heading';
      word.document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(
                properties: WmlParagraphProps(headingLevel: 1),
                inlines: [WmlRun(text: heading)],
              ),
            ],
          ),
        ],
      );
      word.commands.clear();
      word.markClean();
      word.caret
        ..paragraphIndex = 0
        ..logicalIndex = heading.length
        ..collapseSelection();
      word.relayout();
      word.refresh();
      await _frames(tester);

      // The outline is host chrome; the document text itself is painted by
      // the editor and does not create a matching Text widget.
      await tester.tap(find.byTooltip('Settings'));
      await _dialogFrames(tester);
      final outline = find.widgetWithText(
        SwitchListTile,
        'Show document outline',
      );
      await tester.ensureVisible(outline);
      await tester.tap(outline);
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await _dialogFrames(tester);
      // Release restored editing focus before the idle assertions.
      FocusManager.instance.primaryFocus?.unfocus();
      await _frames(tester);
      expect(find.text(heading), findsOneWidget);

      // The first edit changes Undo/dirty state and rebuilds immediately.
      // Subsequent text in the same heading leaves the chrome selector equal.
      word.insertText('A');
      await _frames(tester);
      await tester.pump(const Duration(seconds: 1));
      await _frames(tester);
      expect(find.text('${heading}A'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);

      word.insertText('B');
      await _frames(tester);
      expect(word.document.paragraphs.single.text, '${heading}AB');
      expect(find.text('${heading}A'), findsOneWidget);
      expect(find.text('${heading}AB'), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Observe the timer before pump draws a frame. The production timer
      // was registered first, so it runs before this same-deadline observer.
      await tester.pump(const Duration(milliseconds: 399));
      expect(tester.binding.hasScheduledFrame, isFalse);
      bool? refreshRequestedFrame;
      Timer(const Duration(milliseconds: 1), () {
        refreshRequestedFrame = tester.binding.hasScheduledFrame;
      });
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        refreshRequestedFrame,
        isTrue,
        reason: 'The 400 ms refresh must not wait for another user action.',
      );
      await _frames(tester);
      expect(find.text('${heading}AB'), findsOneWidget);
      expect(find.text('${heading}A'), findsNothing);
      expect(tester.takeException(), isNull);

      // A later pending refresh is owned by this workspace and is cancelled
      // when it closes, without waking a disposed controller or widget.
      word.insertText('C');
      await _frames(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
      bool? disposedRefreshRequestedFrame;
      Timer(const Duration(milliseconds: 401), () {
        disposedRefreshRequestedFrame = tester.binding.hasScheduledFrame;
      });
      await tester.pump(const Duration(milliseconds: 401));
      expect(disposedRefreshRequestedFrame, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
