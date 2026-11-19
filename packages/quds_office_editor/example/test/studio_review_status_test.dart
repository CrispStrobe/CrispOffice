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
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = viewport;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(const QudsOfficeStudioApp());
  await tester.pump();
  expect(
    MediaQuery.sizeOf(tester.element(find.byType(QudsWordEditor))),
    viewport,
  );
  final controller = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  controller.proofing.enabled = false;
  controller.proofing.configure(OfficeProofingService(providers: [provider]));
  controller.proofing.configureManual(null);
  controller.document = WmlDocument.empty(text: 'A short document.')
    ..proofingLanguage = 'en-US';
  controller.refresh();
  await tester.pump();
  for (final tooltip in ['Language', 'Sprache'].take(languageSteps)) {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
  }
  controller.proofing.enabled = true;
  await tester.pump();
  addTearDown(() {
    controller.proofing.enabled = false;
    if (provider.release != null && !provider.release!.isCompleted) {
      provider.release!.complete();
    }
  });
  return controller;
}

Future<void> _finish(
  WidgetTester tester,
  WordEditorController controller,
  Future<WordProofingSummary> pending,
) async {
  for (var tick = 0; tick < 30 && controller.proofing.checking; tick++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(controller.proofing.checking, isFalse);
  await pending;
  await tester.pump();
}

Finder _statusButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is TextButton),
);

void _expectStatus(String label, IconData icon) {
  final button = _statusButton(label);
  expect(button, findsOneWidget);
  expect(
    find.descendant(of: button, matching: find.byIcon(icon)),
    findsOneWidget,
  );
}

Finder _compactStatusButton(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is IconButton &&
      (widget.tooltip == label ||
          (widget.tooltip?.startsWith('$label\n') ?? false)),
);

void _expectCompactStatus(String label, IconData icon) {
  final button = _compactStatusButton(label);
  expect(button, findsOneWidget);
  expect(
    find.descendant(of: button, matching: find.byIcon(icon)),
    findsOneWidget,
  );
  expect(_statusButton(label), findsNothing);
}

void main() {
  for (final language in [
    (steps: 0, name: 'English', partial: '0 issues · partial check'),
    (steps: 1, name: 'German', partial: '0 Hinweise · teilweise geprüft'),
    (steps: 2, name: 'Arabic', partial: '0 ملاحظات · تدقيق جزئي'),
  ]) {
    testWidgets(
      '${language.name} footer keeps unavailable proofing visibly partial',
      (tester) async {
        final provider = _StatusProvider(
          status: OfficeProofingStatus.unavailable,
        );
        final controller = await _studio(
          tester,
          provider,
          languageSteps: language.steps,
        );
        await _finish(tester, controller, controller.proofing.checkNow());
        final summary = controller.proofing.summary;
        expect(provider.calls, 1);
        expect(summary.hasResults, isTrue);
        expect(summary.complete, isFalse);
        expect(summary.issues, isEmpty);
        _expectStatus(language.partial, Icons.info_outline);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                (widget.message ?? '').contains('Dictionary unavailable'),
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('footer keeps skipped manual coverage partial until checked', (
    tester,
  ) async {
    final ordinary = _StatusProvider();
    final manual = _StatusProvider(id: 'manual-status');
    final controller = await _studio(tester, ordinary);
    controller.proofing.configureManual(
      OfficeProofingService(providers: [manual]),
    );
    await _finish(
      tester,
      controller,
      controller.proofing.checkNow(includeManualProviders: false),
    );
    expect(manual.calls, 0);
    expect(controller.proofing.summary.manualProvidersSkipped, isTrue);
    expect(controller.proofing.summary.complete, isFalse);
    expect(controller.proofing.summary.issues, isEmpty);
    _expectStatus('0 issues · partial check', Icons.info_outline);

    await _finish(tester, controller, controller.proofing.checkNow());
    expect(manual.calls, 1);
    expect(controller.proofing.summary.complete, isTrue);
    _expectStatus('No writing issues', Icons.check_circle_outline);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer labels paused checking after a complete clean result', (
    tester,
  ) async {
    final controller = await _studio(tester, _StatusProvider());
    await _finish(tester, controller, controller.proofing.checkNow());
    expect(controller.proofing.summary.complete, isTrue);
    _expectStatus('No writing issues', Icons.check_circle_outline);
    controller.proofing.enabled = false;
    await tester.pump();
    expect(controller.proofing.summary.hasResults, isTrue);
    _expectStatus('Live checking paused', Icons.pause_circle_outline);
    expect(find.text('No writing issues'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer labels a pending typing debounce as waiting', (
    tester,
  ) async {
    final provider = _StatusProvider();
    final controller = await _studio(tester, provider);
    await _finish(tester, controller, controller.proofing.checkNow());
    expect(controller.proofing.summary.complete, isTrue);
    final calls = provider.calls;
    controller.insertText('More ');
    await tester.pump();
    expect(controller.proofing.summary.scheduled, isTrue);
    expect(provider.calls, calls);
    _expectStatus('Waiting to check…', Icons.more_horiz);
    expect(find.text('No writing issues'), findsNothing);
    await _finish(tester, controller, controller.proofing.checkNow());
    expect(controller.proofing.summary.complete, isTrue);
    _expectStatus('No writing issues', Icons.check_circle_outline);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'footer stays checking while a real provider request is pending',
    (tester) async {
      final release = Completer<void>();
      final provider = _StatusProvider(release: release);
      final controller = await _studio(tester, provider);
      final pending = controller.proofing.checkNow();
      await tester.pump(const Duration(milliseconds: 1));
      expect(provider.calls, 1);
      expect(controller.proofing.summary.checking, isTrue);
      _expectStatus('Checking…', Icons.hourglass_top);
      expect(find.text('No writing issues'), findsNothing);
      release.complete();
      await _finish(tester, controller, pending);
      expect(controller.proofing.summary.complete, isTrue);
      _expectStatus('No writing issues', Icons.check_circle_outline);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact Arabic footer preserves partial and paused status tooltips',
    (tester) async {
      final provider = _StatusProvider(
        status: OfficeProofingStatus.unavailable,
      );
      final controller = await _studio(
        tester,
        provider,
        languageSteps: 2,
        viewport: const Size(760, 900),
      );
      await _finish(tester, controller, controller.proofing.checkNow());
      expect(provider.calls, 1);
      expect(controller.proofing.summary.complete, isFalse);
      expect(controller.proofing.summary.issues, isEmpty);
      _expectCompactStatus('0 ملاحظات · تدقيق جزئي', Icons.info_outline);
      final partial = tester.widget<IconButton>(
        _compactStatusButton('0 ملاحظات · تدقيق جزئي'),
      );
      expect(partial.tooltip, contains('Dictionary unavailable'));
      expect(_compactStatusButton('لا توجد ملاحظات'), findsNothing);
      controller.proofing.enabled = false;
      await tester.pump();
      expect(controller.proofing.summary.hasResults, isTrue);
      _expectCompactStatus(
        'التدقيق التلقائي متوقف',
        Icons.pause_circle_outline,
      );
      expect(_compactStatusButton('لا توجد ملاحظات'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact footer distinguishes waiting, checking and completed results',
    (tester) async {
      final ordinary = _StatusProvider();
      final controller = await _studio(
        tester,
        ordinary,
        viewport: const Size(760, 900),
      );
      await _finish(tester, controller, controller.proofing.checkNow());
      expect(controller.proofing.summary.complete, isTrue);
      _expectCompactStatus('No writing issues', Icons.check_circle_outline);
      final calls = ordinary.calls;
      controller.insertText('More ');
      await tester.pump();
      expect(controller.proofing.summary.scheduled, isTrue);
      expect(ordinary.calls, calls);
      _expectCompactStatus('Waiting to check…', Icons.more_horiz);
      expect(_compactStatusButton('No writing issues'), findsNothing);

      final release = Completer<void>();
      final blocked = _StatusProvider(id: 'compact-pending', release: release);
      addTearDown(() {
        controller.proofing.enabled = false;
        if (!release.isCompleted) release.complete();
      });
      controller.proofing.configure(
        OfficeProofingService(providers: [blocked]),
      );
      final pending = controller.proofing.checkNow();
      await tester.pump(const Duration(milliseconds: 1));
      expect(blocked.calls, 1);
      expect(controller.proofing.summary.checking, isTrue);
      _expectCompactStatus('Checking…', Icons.hourglass_top);
      expect(_compactStatusButton('No writing issues'), findsNothing);
      release.complete();
      await _finish(tester, controller, pending);
      expect(controller.proofing.summary.complete, isTrue);
      _expectCompactStatus('No writing issues', Icons.check_circle_outline);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
