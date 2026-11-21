// The Studio typing benchmark in profile mode (or any mode) on a real
// desktop embedder, for timeline evidence: every keystroke's handler is a
// `KEY_HANDLER` timeline span (with `KEY <index>` arguments), phases and
// listeners are timed through WordEditorController.debugEditPhase, and the
// whole run is recorded with traceAction (GC, frame build/raster).
//
//   xvfb-run flutter drive --profile -d linux \
//     --driver=test_driver/typing_profile_driver.dart \
//     --target=integration_test/typing_profile_test.dart
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';

import '../test/studio_typing_proofing_benchmark_test.dart' as bench;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typing profile', (tester) async {
    WordEditorController.debugTimeListeners = true;
    await tester.pumpWidget(const QudsOfficeStudioApp());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
    final controller = editor.controller;
    controller.proofing.enabled = true;
    controller.document = bench.typingBenchmarkDocument();
    controller.refresh();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    const paragraphIndex = 90;
    final length = controller.document.paragraphs
        .elementAt(paragraphIndex)
        .text
        .length;
    controller.caret
      ..paragraphIndex = paragraphIndex
      ..logicalIndex = length
      ..selectionAnchor = length
      ..selectionAnchorParagraph = paragraphIndex;
    controller.refreshView();
    await tester.pump();

    final frames = <ui.FrameTiming>[];
    void onTimings(List<ui.FrameTiming> timings) => frames.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    var current = <String, double>{};
    WordEditorController.debugEditPhase = (phase, micros) {
      current[phase] = (current[phase] ?? 0) + micros / 1000;
    };
    final keys = <Map<String, Object>>[];
    await binding.traceAction(() async {
      var text = controller.input.value.text;
      var at = controller.input.value.selection.extentOffset;
      if (at < 0) at = text.length;
      for (final step in bench.typingBenchmarkScript()) {
        text = text.replaceRange(at, at, step.char);
        at++;
        current = <String, double>{};
        final watch = Stopwatch()..start();
        final task = developer.TimelineTask()
          ..start('KEY_HANDLER', arguments: {'key': '${keys.length}'});
        controller.input.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: at),
          ),
        );
        task.finish();
        final handler = watch.elapsedMicroseconds / 1000;
        await tester.pump();
        keys.add({
          'handlerMs': handler,
          'phases': {
            for (final e in current.entries)
              if (e.value > 0.2)
                e.key: double.parse(e.value.toStringAsFixed(2)),
          },
        });
        await Future<void>.delayed(step.gap);
      }
    }, reportKey: 'timeline');
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    WordEditorController.debugEditPhase = null;
    WordEditorController.debugTimeListeners = false;
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['keys'] = keys;
    binding.reportData!['frames'] = [
      for (final f in frames)
        {
          'buildMs': f.buildDuration.inMicroseconds / 1000,
          'rasterMs': f.rasterDuration.inMicroseconds / 1000,
          'totalMs': f.totalSpan.inMicroseconds / 1000,
        },
    ];
  });
}
