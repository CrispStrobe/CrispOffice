import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  for (final scenario in <({String name, String word, String locale, Size size, double scale, String candidate})>[
    (name: 'english-desktop', word: 'bank', locale: 'en-US', size: const Size(1200, 900), scale: 1, candidate: 'depository financial institution'),
    (name: 'german-desktop', word: 'Bank', locale: 'de-DE', size: const Size(1200, 900), scale: 1, candidate: 'Finanzinstitution'),
    (name: 'german-narrow-large-text', word: 'Bank', locale: 'de-DE', size: const Size(390, 844), scale: 1.5, candidate: 'Finanzinstitution'),
  ]) {
    testWidgets('real pack rendering ${scenario.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = BundledOfficeThesaurus.create();
      final warmed = await tester.runAsync(() async {
        await OfficeHostFonts.ensureRegistered();
        final sdk = Platform.environment['FLUTTER_ROOT']!;
        final icons = await File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
        final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons)));
        await loader.load();
        return service.lookup(OfficeThesaurusQuery(text: scenario.word, language: scenario.locale));
      });
      expect(warmed!.status, OfficeThesaurusStatus.ready);
      final controller = WordEditorController(
        document: WmlDocument.empty(text: scenario.word)..proofingLanguage = scenario.locale,
      );
      controller.selectAll();
      addTearDown(controller.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Liberation Sans', colorSchemeSeed: Colors.teal),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scenario.scale)),
            child: child!,
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('Quds offline thesaurus')),
            body: Builder(builder: (context) => Column(children: [
              TextButton(
                onPressed: () => showWordThesaurusDialog(context, controller: controller, service: service),
                child: const Text('Open thesaurus'),
              ),
              Expanded(child: QudsWordEditor(controller: controller, enableLiveProofing: false)),
            ])),
          ),
        ),
      ));
      await tester.tap(find.text('Open thesaurus'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final candidate = find.widgetWithText(ChoiceChip, scenario.candidate);
      await tester.scrollUntilVisible(candidate, 240,
        scrollable: find.descendant(of: find.byKey(const ValueKey('thesaurus-content')), matching: find.byType(Scrollable)).first,
        maxScrolls: 80);
      await Scrollable.ensureVisible(tester.element(candidate.first), alignment: .35);
      await tester.pump();
      await tester.tap(candidate.first);
      await tester.pump(const Duration(milliseconds: 100));
      // The first pump builds the newly enabled button and starts its color
      // transition. Advance another frame beyond that transition before QA.
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('thesaurus-replace'))).onPressed, isNotNull);
      final replaceLabel = find.descendant(
        of: find.byKey(const ValueKey('thesaurus-replace')),
        matching: find.byType(RichText),
      ).first;
      final paragraph = tester.renderObject<RenderParagraph>(replaceLabel);
      final expectedForeground = Theme.of(tester.element(replaceLabel)).colorScheme.onPrimary;
      debugPrint('Replace foreground after animation: '
          '${paragraph.text.style?.color?.toARGB32().toRadixString(16)}; '
          'theme onPrimary: ${expectedForeground.toARGB32().toRadixString(16)}');
      expect(paragraph.text.style?.color, expectedForeground,
          reason: 'An enabled Replace label must finish transitioning to the theme onPrimary color.');
      expect(controller.document.paragraphs.first.text, scenario.word);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['QUDS_THESAURUS_VISUAL_OUTPUT'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/${scenario.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('Close').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
