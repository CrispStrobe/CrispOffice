import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';

final class _StatusProvider extends OfficeProofingProvider {
  _StatusProvider({
    this.id = 'studio-status',
    this.status = OfficeProofingStatus.success,
    this.release,
  });

  @override
  final String id;
  final OfficeProofingStatus status;
  final Completer<void>? release;
  int calls = 0;

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    calls++;
    if (release != null) await release!.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      message: status == OfficeProofingStatus.unavailable
          ? 'Dictionary unavailable for status regression.'
          : null,
    );
  }
}

Future<WordEditorController> _studio(
  WidgetTester tester,
  _StatusProvider provider, {
  int languageSteps = 0,
  Size viewport = const Size(1440, 900),
}) async {
  testWidgets('compact footer exposes partial status and opens Review', (
    tester,
  ) async {
    final provider = _StatusProvider(status: OfficeProofingStatus.unavailable);
    final controller = await _studio(
      tester,
      provider,
      viewport: const Size(760, 900),
    );
    await _finish(tester, controller, controller.proofing.checkNow());
    expect(provider.calls, 1);
    expect(controller.proofing.summary.hasResults, isTrue);
    expect(controller.proofing.summary.complete, isFalse);
    expect(controller.proofing.summary.issues, isEmpty);
    final button = _expectCompactStatus(
      tester,
      '0 issues · partial check',
      Icons.info_outline,
      detail: 'Dictionary unavailable',
    );
    expect(_compactStatusButton('No writing issues'), findsNothing);
    expect(controller.reviewPaneVisible, isFalse);
    await tester.tap(button);
    await tester.pump();
    expect(controller.reviewPaneVisible, isTrue);
    expect(controller.reviewPaneTab, WordReviewPaneTab.proofing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact footer replaces a clean result with paused status', (
    tester,
  ) async {
    final controller = await _studio(
      tester,
      _StatusProvider(),
      viewport: const Size(760, 900),
    );
    await _finish(tester, controller, controller.proofing.checkNow());
    expect(controller.proofing.summary.complete, isTrue);
    _expectCompactStatus(
      tester,
      'No writing issues',
      Icons.check_circle_outline,
    );
    controller.proofing.enabled = false;
    await tester.pump();
    expect(controller.proofing.summary.hasResults, isTrue);
    _expectCompactStatus(
      tester,
      'Live checking paused',
      Icons.pause_circle_outline,
    );
    expect(_compactStatusButton('No writing issues'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact footer exposes waiting until the pending check finishes',
    (tester) async {
      final provider = _StatusProvider();
      final controller = await _studio(
        tester,
        provider,
        viewport: const Size(760, 900),
      );
      await _finish(tester, controller, controller.proofing.checkNow());
      expect(controller.proofing.summary.complete, isTrue);
      final calls = provider.calls;
      controller.insertText('More ');
      await tester.pump();
      expect(controller.proofing.summary.scheduled, isTrue);
      expect(provider.calls, calls);
      _expectCompactStatus(tester, 'Waiting to check…', Icons.more_horiz);
      expect(_compactStatusButton('No writing issues'), findsNothing);
      await _finish(tester, controller, controller.proofing.checkNow());
      expect(controller.proofing.summary.complete, isTrue);
      _expectCompactStatus(
        tester,
        'No writing issues',
        Icons.check_circle_outline,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
