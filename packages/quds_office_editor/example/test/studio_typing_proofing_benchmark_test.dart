// Typing/proofing benchmark for the Studio Word view.
//
// Skipped unless QUDS_TYPING_BENCHMARK=1. It types 300 characters through the
// real IME path into a ~20-page German/English/Arabic document while the
// Studio's ordinary proofing providers and a counting language detector are
// active, and prints one `TYPING_BENCHMARK {json}` line with:
//   * per-keystroke handler time (IME update through controller listeners),
//   * the following frame (build/layout/paint) time,
//   * UI-isolate time spent in timers between keystrokes (proofing passes),
//   * proofing passes, paragraphs sent to providers, language detections,
//   * rebuild counts of the Studio status line, review strip, workspace,
//     ribbon and Word editor, and the number of status label changes.
// Widget tests run in debug JIT with fake time; absolute numbers are higher
// than a release build, so compare runs made under similar machine load.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/suite_workspace.dart';

final bool _enabled = Platform.environment['QUDS_TYPING_BENCHMARK'] == '1';

final class _CountingProvider extends OfficeProofingProvider {
  _CountingProvider(this.inner, this.stats);

  final OfficeProofingProvider inner;
  final _Stats stats;

  @override
  String get id => inner.id;

  @override
  int get configurationRevision => inner.configurationRevision;

  @override
  bool supportsLanguage(String language) => inner.supportsLanguage(language);

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    stats.providerCalls++;
    final watch = Stopwatch()..start();
    try {
      return await inner.check(request);
    } finally {
      stats.providerMicros += watch.elapsedMicroseconds;
    }
  }

  @override
  Future<void> dispose() => inner.dispose();
}

/// Script-only stand-in for the bundled CLD3 model. It answers Latin text by
/// a word list and counts every classifier call and text.
final class _CountingIdentifier implements LanguageIdentifier {
  _CountingIdentifier(this.stats);

  final _Stats stats;

  @override
  bool get isAvailable => true;

  @override
  Future<List<List<LanguageGuess>>> identify(List<String> texts) async {
    stats.detectorCalls++;
    stats.detectorTexts += texts.length;
    // An isolate round trip; fake time in widget tests.
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return [
      for (final text in texts)
        RegExp(r'\b(the|and|with|is)\b').hasMatch(text)
            ? const [LanguageGuess('en', 0.99)]
            : const [LanguageGuess('de', 0.99)],
    ];
  }
}

final class _Stats {
  int providerCalls = 0;
  int providerMicros = 0;
  int detectorCalls = 0;
  int detectorTexts = 0;
  int passes = 0;
  int sessionNotifications = 0;
  int controllerNotifications = 0;
  final rebuilds = <String, int>{};
  final labels = <String>[];
}

const _german = [
  'Die Gemeinde hat im vergangenen Jahr einen neuen Haushaltsplan beschlossen, '
      'der die Sanierung der Schulen und den Ausbau der Radwege vorsieht.',
  'Viele Bürgerinnen und Bürger haben sich an der Diskussion beteiligt und '
      'ihre Vorschläge schriftlich eingereicht, obwohl die Frist sehr kurz war.',
  'Das Projekt wird in drei Abschnitten umgesetzt; der erste Abschnitt '
      'beginnt im Frühjahr und soll bis zum Herbst abgeschlossen sein.',
  'Ein Feler in der Planung führte dazu, dass die Kosten deutlich höher '
      'ausfielen als ursprünglich angenommen wurde.',
];
const _english = [
  'The committee reviewed the proposal and agreed that the timeline is '
      'realistic, provided that the funding arrives before the summer.',
  'Several residents asked whether the new cycle lanes will connect the '
      'school with the station, and the planners confirmed this.',
  'The final report will be published in both languages and is available '
      'to everyone who registered for the public consultation.',
];
const _arabic = [
  'ناقشت اللجنة المقترح الجديد ووافقت على الجدول الزمني بشرط وصول التمويل قبل الصيف.',
  'سأل عدد من السكان عن مسارات الدراجات الجديدة وهل ستربط المدرسة بالمحطة.',
  'سينشر التقرير النهائي باللغتين ويكون متاحا لكل من سجل في الاستشارة العامة.',
];

/// About twenty Letter pages: 180 paragraphs of 20–30 words each.
WmlDocument _document() {
  final paragraphs = <WmlBlock>[];
  for (var i = 0; i < 180; i++) {
    final String text;
    final WmlRunProps props;
    switch (i % 6) {
      case 0 || 1 || 2:
        text = '${_german[i % _german.length]} (${i + 1})';
        props = WmlRunProps();
      case 3:
        text = '${_english[i % _english.length]} (${i + 1})';
        props = WmlRunProps(proofingLanguage: 'en-US');
      case 4:
        text = _arabic[i % _arabic.length];
        props = WmlRunProps(complexScript: true);
      default:
        text =
            '${_german[(i + 1) % _german.length]} '
            '${_german[(i + 2) % _german.length]}';
        props = WmlRunProps();
    }
    paragraphs.add(
      WmlParagraph(
        inlines: [WmlRun(text: text, properties: props)],
      ),
    );
  }
  return WmlDocument(sections: [WmlSection(blocks: paragraphs)])
    ..proofingLanguage = 'de-DE'
    ..complexScriptLanguage = 'ar-SA';
}

/// 300 characters: 150 at ~10/s, a 100-character burst at ~33/s, a pause,
/// then 50 more at ~8/s. Deterministic jitter.
List<({String char, Duration gap})> _script() {
  const text =
      'Wir haben heute die Ergebnisse besprochen und einen Feler im Bericht '
      'gefunden, der morgen korrigiert wird. Die Kommission bittet um eine '
      'kurze Stellungnahme bis Freitag, damit die Unterlagen rechtzeitig '
      'verschickt werden koennen. Danach folgt die Abstimmung im Rat, die '
      'oeffentlich ist und im Internet uebertragen wird, wie immer am Abend.';
  final random = math.Random(7);
  final steps = <({String char, Duration gap})>[];
  for (var i = 0; i < 300; i++) {
    final int ms;
    if (i < 150) {
      ms = 80 + random.nextInt(46); // 8–12.5 chars/s
    } else if (i < 250) {
      ms = 25 + random.nextInt(11); // burst
    } else {
      ms = 110 + random.nextInt(30);
    }
    final pause = i == 250 ? 1200 : 0; // a thinking pause mid-paragraph
    steps.add((
      char: text[i % text.length],
      gap: Duration(milliseconds: ms + pause),
    ));
  }
  return steps;
}

final _labelPattern = RegExp(
  r'writing issue|Waiting to check|Checking…|Not checked yet|partial check|'
  r'No writing issues|Live checking paused',
);

String? _visibleLabel() {
  for (final element
      in find
          .byWidgetPredicate((w) => w is Text || w is IconButton)
          .evaluate()) {
    final widget = element.widget;
    final data = widget is Text
        ? widget.data
        : (widget as IconButton).tooltip?.split('\n').first;
    if (data != null && _labelPattern.hasMatch(data)) return data;
  }
  return null;
}

double _percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * p).round();
  return sorted[index];
}

Map<String, Object> _distribution(List<double> values) => {
  'p50': double.parse(_percentile(values, .5).toStringAsFixed(2)),
  'p95': double.parse(_percentile(values, .95).toStringAsFixed(2)),
  'max': double.parse(
    (values.isEmpty ? 0 : values.reduce(math.max)).toStringAsFixed(2),
  ),
  'total': double.parse(
    values.fold<double>(0, (a, b) => a + b).toStringAsFixed(1),
  ),
};

void main() {
  testWidgets(
    'typing benchmark (QUDS_TYPING_BENCHMARK=1)',
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 20)),
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const QudsOfficeStudioApp());
      await tester.pump();
      await tester.pump();
      final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
      final controller = editor.controller;
      final stats = _Stats();
      final vocabulary = controller.proofing.vocabulary;
      controller.proofing.configure(
        OfficeProofingService(
          providers: [
            for (final provider in <OfficeProofingProvider>[
              GermanSpellingProvider(vocabulary: vocabulary),
              GermanWritingRulesProvider(),
              ArabicWritingRulesProvider(),
            ])
              _CountingProvider(provider, stats),
          ],
        ),
      );
      controller.proofing.configureLanguageDetection(
        ParagraphLanguageDetector(_CountingIdentifier(stats)),
      );
      controller.proofing.enabled = true;
      controller.document = _document();
      controller.refresh();
      // Let the initial full check settle.
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final summary = controller.proofing.summary;
        if (summary.hasResults && !summary.checking && !summary.scheduled) {
          break;
        }
      }
      final initial = controller.proofing.summary;
      expect(initial.hasResults, isTrue);
      expect(initial.checking || initial.scheduled, isFalse);

      // Caret at the end of a German paragraph in the middle of the document.
      const paragraphIndex = 90;
      controller.caret.paragraphIndex = paragraphIndex;
      controller.caret.logicalIndex = controller.document.paragraphs
          .elementAt(paragraphIndex)
          .text
          .length;
      controller.caret.selectionAnchor = controller.caret.logicalIndex;
      controller.caret.selectionAnchorParagraph = paragraphIndex;
      controller.refreshView();
      editor.focusNode!.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(controller.input.isAttached, isTrue);

      var wasChecking = controller.proofing.checking;
      void onSession() {
        stats.sessionNotifications++;
        final checking = controller.proofing.checking;
        if (checking && !wasChecking) stats.passes++;
        wasChecking = checking;
      }

      void onController() => stats.controllerNotifications++;
      controller.proofing.addListener(onSession);
      controller.addListener(onController);
      final providerCallsBefore = stats.providerCalls;
      final detectorTextsBefore = stats.detectorTexts;
      final detectorCallsBefore = stats.detectorCalls;
      final providerMicrosBefore = stats.providerMicros;
      debugOnRebuildDirtyWidget = (element, _) {
        final widget = element.widget;
        String? key;
        if (widget is SuiteWorkspace) {
          key = 'workspace';
        } else if (widget is QudsWordEditor) {
          key = 'wordEditor';
        } else if (widget is StudioRibbonStrip) {
          key = 'ribbon';
        } else if (widget is WordReviewStatusBar) {
          key = 'wordReviewStatusBar';
        } else if (widget is IconButton &&
            _labelPattern.hasMatch(widget.tooltip ?? '')) {
          key = 'reviewStripLabel';
        } else if (widget is Text) {
          final data = widget.data ?? '';
          if (data.contains(' paragraphs · ')) {
            key = 'statusLine';
          } else if (_labelPattern.hasMatch(data)) {
            key = 'reviewStripLabel';
          }
        }
        if (key != null) stats.rebuilds[key] = (stats.rebuilds[key] ?? 0) + 1;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      final handler = <double>[];
      final frame = <double>[];
      final background = <double>[];
      var janky = 0;
      String? lastLabel = _visibleLabel();
      final script = _script();
      for (final step in script) {
        final value = controller.input.value;
        final at = value.selection.extentOffset.clamp(0, value.text.length);
        final next = TextEditingValue(
          text: value.text.replaceRange(at, at, step.char),
          selection: TextSelection.collapsed(offset: at + 1),
        );
        final watch = Stopwatch()..start();
        tester.testTextInput.updateEditingValue(next);
        await null; // the platform message completes in a microtask
        handler.add(watch.elapsedMicroseconds / 1000);
        watch
          ..reset()
          ..start();
        await tester.pump();
        frame.add(watch.elapsedMicroseconds / 1000);
        if (handler.last + frame.last > 1000 / 60) janky++;
        _recordLabel(stats, lastLabel, (l) => lastLabel = l);
        watch
          ..reset()
          ..start();
        await tester.pump(step.gap);
        background.add(watch.elapsedMicroseconds / 1000);
        _recordLabel(stats, lastLabel, (l) => lastLabel = l);
      }
      // Settle: the final check after typing stops.
      final settle = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        _recordLabel(stats, lastLabel, (l) => lastLabel = l);
        final summary = controller.proofing.summary;
        if (!summary.checking && !summary.scheduled) break;
      }
      final settleMs = settle.elapsedMilliseconds;
      controller.proofing.removeListener(onSession);
      controller.removeListener(onController);
      debugOnRebuildDirtyWidget = null;
      final typed = controller.document.paragraphs
          .elementAt(paragraphIndex)
          .text;
      expect(typed.length, greaterThan(300));
      final summary = controller.proofing.summary;
      expect(summary.hasResults, isTrue);
      expect(summary.checking || summary.scheduled, isFalse);
      final report = {
        'keystrokes': script.length,
        'paragraphs': controller.document.paragraphs.length,
        'pages': controller.pageCount,
        'handlerMs': _distribution(handler),
        'frameMs': _distribution(frame),
        'backgroundMsPerGap': _distribution(background),
        'jankyKeystrokeFrames': janky,
        'proofingPasses': stats.passes,
        'providerCalls': stats.providerCalls - providerCallsBefore,
        'providerMs': (stats.providerMicros - providerMicrosBefore) / 1000,
        'detectorCalls': stats.detectorCalls - detectorCallsBefore,
        'detectorTexts': stats.detectorTexts - detectorTextsBefore,
        'sessionNotifications': stats.sessionNotifications,
        'controllerNotifications': stats.controllerNotifications,
        'rebuilds': stats.rebuilds,
        'statusLabelChanges': stats.labels.length,
        'statusLabels': stats.labels.toSet().toList(),
        'settleMs': settleMs,
        'findings': summary.issues.length,
      };
      // ignore: avoid_print
      print('TYPING_BENCHMARK ${jsonEncode(report)}');
    },
  );
}

void _recordLabel(
  _Stats stats,
  String? previous,
  void Function(String?) update,
) {
  final label = _visibleLabel();
  if (label != previous) {
    stats.labels.add(label ?? '<none>');
    update(label);
  }
}
