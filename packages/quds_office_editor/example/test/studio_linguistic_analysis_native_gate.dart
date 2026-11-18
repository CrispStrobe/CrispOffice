// Explicit real-model integration gate. Not an automatically discovered test:
// From the workspace root:
// flutter test --no-pub packages/quds_office_editor/example/test/studio_linguistic_analysis_native_gate.dart
// Missing host assets fail; no conditional skips or synthetic fallback.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_linguistic_analysis.dart';
import 'package:quds_office_studio/studio_spacy_config.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

class _ObservedTransport implements SpacyTransport {
  _ObservedTransport(this.delegate);
  final SpacyTransport delegate;
  LinguisticAnalysisResult? result;
  Object? error;
  var disposed = false;
  @override
  SpacyBackendIdentity get identity => delegate.identity;
  @override
  Future<LinguisticAnalysisResult> analyze(
    LinguisticAnalysisRequest request,
  ) async {
    try {
      return result = await delegate.analyze(request);
    } on Object catch (failure) {
      error = failure;
      rethrow;
    }
  }

  @override
  void cancel(String key) => delegate.cancel(key);
  @override
  Future<void> dispose() async {
    await delegate.dispose();
    disposed = true;
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final elapsed = Stopwatch()..start();
  // Isolate/FFI events require real event-loop turns. Widget callbacks and their
  // continuations also need the Flutter test clock pumped; runAsync alone does
  // not flush that fake clock. This is a bounded integration harness wait.
  while (!ready() && elapsed.elapsed < const Duration(seconds: 20)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(ready(), isTrue, reason: description);
}

void main() {
  testWidgets(
    'real installed model reaches the manual view and exact source selection',
    (tester) async {
      for (final variable in [
        'QUDS_SPACY_BUNDLE',
        'QUDS_SPACY_LIBRARY',
        'QUDS_SPACY_LIBRARY_SHA256',
        'CRISPEMBED_SPACY',
        'FLUTTER_ROOT',
      ]) {
        expect(
          Platform.environment[variable],
          isNotNull,
          reason: '$variable is required for this explicit real-model gate.',
        );
      }
      tester.view.physicalSize = const Size(1100, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final bytes = await File(
          'packages/quds_office_editor/example/fonts/Tajawal-Regular.ttf',
        ).readAsBytes();
        final loader = FontLoader('StudioAnalysisQA')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        final icons = await File(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      });
      final panelKey = GlobalKey();
      const text = '😀 Vorlauf. Die Katze schläft.';
      const selected = 'Die Katze schläft.';
      final origin = text.indexOf(selected);
      final controller = WordEditorController(
        document: WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: text)]),
              ],
            ),
          ],
        )..proofingLanguage = 'de-DE',
        config: const OfficeSurfaceConfig(autofocus: false),
      );
      controller.documentCaret
        ..selectionAnchor = origin
        ..logicalIndex = text.length;
      _ObservedTransport? transport;
      Object? startupError;
      await tester.pumpWidget(
        RepaintBoundary(
          key: panelKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'StudioAnalysisQA',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff2b579a),
              ),
            ),
            home: Scaffold(
              backgroundColor: const Color(0xffedf0f4),
              body: StudioLinguisticAnalysisDialog(
                controller: controller,
                transportFactory: () async {
                  try {
                    return transport = _ObservedTransport(
                      await openStudioSpacyTransport(),
                    );
                  } on Object catch (error) {
                    startupError = error;
                    rethrow;
                  }
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Analyze text'));
      await tester.pump();
      await _waitFor(
        tester,
        () =>
            transport?.result != null ||
            transport?.error != null ||
            startupError != null,
        'Actual worker must complete or report an explicit failure.',
      );
      expect(startupError, isNull);
      expect(transport?.error, isNull);
      final result = transport!.result!;
      expect(
        result.status,
        LinguisticAnalysisStatus.success,
        reason: result.message,
      );
      expect(result.request.text, selected);
      expect(result.request.startOffset, origin);
      expect(result.tokens.map((token) => token.text), [
        'Die',
        'Katze',
        'schläft',
        '.',
      ]);
      expect(result.tokens[1].lemma, 'Katze');
      expect(result.tokens[2].lemma, 'schlafen');
      expect(result.sentences.single.text, selected);
      expect(
        find.text('4 tokens · 1 sentence · de_core_news_sm 3.8.0'),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final output = File(
          Platform.environment['QUDS_SPACY_PANEL_OUTPUT'] ??
              'docs/validation/native-spacy-w5-20261117/analysis-panel.png',
        );
        if (await output.exists()) {
          throw StateError(
            'Preserve the existing panel evidence; choose a new QUDS_SPACY_PANEL_OUTPUT.',
          );
        }
        final boundary =
            panelKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final encoded = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (encoded == null) throw StateError('Panel PNG encoding failed.');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(encoded.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      final row = find.byKey(const ValueKey('analysis-token-1'));
      await tester.tap(
        find.descendant(of: row, matching: find.byType(IconButton)),
      );
      await tester.pump();
      expect(controller.documentCaret.selectionAnchor, origin + 4);
      expect(controller.documentCaret.logicalIndex, origin + 9);
      expect(controller.document.paragraphs.first.text, text);
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await _waitFor(
        tester,
        () => transport!.disposed,
        'Actual worker must finish safe shutdown.',
      );
      controller.dispose();
    },
  );
}
