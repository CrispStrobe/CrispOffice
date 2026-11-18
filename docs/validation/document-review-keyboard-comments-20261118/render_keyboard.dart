// Reproducible visual fixtures using the real shared editor and delivered keys.
// From packages/quds_office_editor/example, with FLUTTER_ROOT set:
// QUDS_REVIEW_VISUAL_OUTPUT=<absolute screenshot directory> flutter test --no-pub \
//   ../../../docs/validation/document-review-keyboard-comments-20261118/render_keyboard.dart
// These two visual cases are excluded from the behavior regression count.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _captureKey = ValueKey<String>('keyboard-review-capture');
const _menuKey = Key('office-context-menu');
final _events = <Map<String, Object?>>[];

class _VisualProvider extends OfficeProofingProvider {
  _VisualProvider({this.gate});
  final Completer<void>? gate;

  @override
  String get id => 'keyboard-visual-fixture';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (request.text.startsWith('The remaining') && gate != null) {
      await gate!.future;
    }
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: [
        for (final match in RegExp('schedual').allMatches(request.text))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            ruleId: 'visual.spelling',
            start: match.start,
            end: match.end,
            message: 'Check the spelling of schedual.',
            category: OfficeProofingCategory.spelling,
            replacements: const ['schedule', 'timetable'],
          ),
      ],
    );
  }
}

WmlParagraph _paragraph(String text, {bool title = false}) => WmlParagraph(
  properties: WmlParagraphProps(
    spacingAfter: title ? 20 : 14,
    lineSpacing: 1.4,
  ),
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(
        asciiFont: 'Liberation Sans',
        fontSizeHalfPoints: title ? 38 : 26,
        bold: title,
        color: title ? '17324D' : '243447',
      ),
    ),
  ],
);

WmlDocument _document() => WmlDocument(
  proofingLanguage: 'en-US',
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 520, height: 650),
      margins: const WmlPageMargins(top: 48, bottom: 48, left: 46, right: 46),
      blocks: [
        _paragraph('Delivery review', title: true),
        _paragraph('Please confirm the schedual before we share this update.'),
        _paragraph(
          'Writing suggestions remain beside the document. Review a finding, '
          'choose a correction, and keep editing with the keyboard.',
        ),
        _paragraph(
          'The remaining paragraph can keep checking while earlier findings '
          'stay available for review.',
        ),
      ],
    ),
  ],
);

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool alt = false,
  bool shift = false,
}) async {
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  try {
    await tester.sendKeyEvent(key);
  } finally {
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }
  _events.add({
    'event': 'key',
    'key': key.keyLabel,
    'alt': alt,
    'shift': shift,
  });
  await _frames(tester);
}

class _Harness {
  _Harness({this.gate}) : provider = _VisualProvider(gate: gate) {
    controller = WordEditorController(
      document: _document(),
      config: const OfficeSurfaceConfig(showRulers: false),
      proofingService: OfficeProofingService(providers: [provider]),
    );
  }

  final Completer<void>? gate;
  final _VisualProvider provider;
  late final WordEditorController controller;
  final focus = FocusNode(debugLabel: 'keyboard-visual-document');

  Future<void> mount(WidgetTester tester, {required String subtitle}) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Liberation Sans',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF315A83),
            ),
          ),
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: const Color(0xFFEDF2F7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Document review demonstration',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(subtitle, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: QudsWordEditor(
                    controller: controller,
                    focusNode: focus,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await _frames(tester);
    controller.caret
      ..paragraphIndex = 1
      ..logicalIndex = 0
      ..collapseSelection();
    controller.refreshView();
    focus.requestFocus();
    await _frames(tester);
  }

  Future<void> close(WidgetTester tester) async {
    if (gate != null && !gate!.isCompleted) gate!.complete();
    await _frames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus.dispose();
    await tester.binding.setSurfaceSize(null);
  }
}

Future<void> _loadFonts() async {
  await OfficeHostFonts.ensureRegistered();
  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (sdk == null) throw StateError('FLUTTER_ROOT must name the test SDK.');
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  await icons.load();
}

String get _output =>
    Platform.environment['QUDS_REVIEW_VISUAL_OUTPUT'] ??
    '../../../docs/validation/document-review-keyboard-comments-20261118/screenshots';

Future<void> _save(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 120));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final picture = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: 1),
  ))!;
  try {
    final data = (await tester.runAsync(
      () => picture.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    await tester.runAsync(() async {
      await Directory(_output).create(recursive: true);
      await File('$_output/$name.png').writeAsBytes(data.buffer.asUint8List());
    });
  } finally {
    picture.dispose();
  }
  _events.add({'event': 'screenshot', 'file': '$name.png'});
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  tearDownAll(() async {
    await Directory(_output).create(recursive: true);
    await File(
      '$_output/../keyboard-visual-events.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(_events)}\n');
  });

  testWidgets('capture a keyboard-opened suggestion with its active action', (
    tester,
  ) async {
    final h = _Harness();
    try {
      await h.mount(
        tester,
        subtitle:
            'Alt+F7 selects a finding. Shift+F10 opens suggestions. Arrow keys choose an action.',
      );
      expect(h.controller.proofing.summary.complete, isTrue);
      expect(h.controller.proofing.summary.issues, hasLength(1));
      await _key(tester, LogicalKeyboardKey.f7, alt: true);
      final selected = h.controller.selectedProofingIssue!;
      expect(selected.finding.originalText, 'schedual');
      await _key(tester, LogicalKeyboardKey.f10, shift: true);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      final menu = find.byKey(_menuKey);
      expect(menu, findsOneWidget);
      expect(h.focus.hasPrimaryFocus, isFalse);
      final action = find.descendant(
        of: menu,
        matching: find.text('timetable'),
      );
      expect(action, findsOneWidget);
      final highlight = find
          .ancestor(of: action, matching: find.byType(ColoredBox))
          .first;
      expect(
        tester.widget<ColoredBox>(highlight).color,
        isNot(const Color(0x00000000)),
      );
      expect(h.controller.canUndo, isFalse);
      expect(find.byType(Dialog), findsNothing);
      _events.add({
        'event': 'keyboard_menu_observed',
        'source': selected.finding.originalText,
        'highlighted_action': 'timetable',
        'menu_owns_focus': !h.focus.hasPrimaryFocus,
        'document_unchanged': !h.controller.canUndo,
      });
      await _save(tester, 'keyboard-suggestions-desktop');
      await _key(tester, LogicalKeyboardKey.escape);
      expect(h.focus.hasPrimaryFocus, isTrue);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('capture actionable findings while a background check continues', (
    tester,
  ) async {
    final h = _Harness(gate: Completer<void>());
    try {
      await h.mount(
        tester,
        subtitle:
            'Earlier findings stay actionable while later text is checked. Check document remains available.',
      );
      expect(h.controller.proofing.checking, isTrue);
      expect(h.controller.proofing.summary.issues, hasLength(1));
      await _key(tester, LogicalKeyboardKey.f7, alt: true);
      final button = find.byKey(const ValueKey('live-proofing-check'));
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      final correction = find.byKey(const ValueKey('live-proofing-replace-0'));
      expect(tester.widget<OutlinedButton>(correction).onPressed, isNotNull);
      expect(find.byType(Dialog), findsNothing);
      _events.add({
        'event': 'background_check_observed',
        'checking': h.controller.proofing.checking,
        'checked_paragraphs':
            h.controller.proofing.summary.checkedParagraphCount,
        'total_paragraphs': h.controller.proofing.summary.paragraphCount,
        'check_document_enabled': true,
        'correction_enabled': true,
      });
      await _save(tester, 'keyboard-inflight-writing-desktop');
    } finally {
      await h.close(tester);
    }
  });
}
