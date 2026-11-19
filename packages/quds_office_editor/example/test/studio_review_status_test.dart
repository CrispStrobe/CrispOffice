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
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const QudsOfficeStudioApp());
  await tester.pump();
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

  testWidgets(
    'compact footer exposes partial and paused status and opens review',
    (tester) async {
      final provider = _StatusProvider(
        status: OfficeProofingStatus.unavailable,
      );
      final controller = await _studio(tester, provider);
      await _finish(tester, controller, controller.proofing.checkNow());
      expect(controller.proofing.summary.hasResults, isTrue);
      expect(controller.proofing.summary.complete, isFalse);
      expect(controller.proofing.summary.issues, isEmpty);
      final revision = controller.contentRevision;
      tester.view.physicalSize = const Size(390, 1000);
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final state in [
        (
          paused: false,
          label: '0 issues · partial check',
          icon: Icons.info_outline,
        ),
        (
          paused: true,
          label: 'Live checking paused',
          icon: Icons.pause_circle_outline,
        ),
      ]) {
        if (state.paused) controller.proofing.enabled = false;
        await tester.pump();
        final media = MediaQuery.of(
          tester.element(find.byType(QudsWordEditor)),
        );
        expect(media.size, const Size(390, 1000));
        expect(media.textScaler.scale(10), 14);
        final button = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              (widget.tooltip ?? '').startsWith(state.label),
        );
        expect(button.hitTestable(), findsOneWidget);
        expect(
          find.descendant(of: button, matching: find.byIcon(state.icon)),
          findsOneWidget,
        );
        if (!state.paused) {
          expect(
            tester.widget<IconButton>(button).tooltip,
            contains('Dictionary unavailable'),
          );
        }
        expect(tester.takeException(), isNull);
        expect(controller.reviewPaneVisible, isFalse);

        await tester.tap(button);
        await tester.pump();
        expect(controller.reviewPaneVisible, isTrue);
        expect(controller.reviewPaneTab, WordReviewPaneTab.proofing);
        expect(find.byKey(const ValueKey('word-review-pane')), findsOneWidget);
        expect(controller.contentRevision, revision);
        expect(provider.calls, 1);
        expect(tester.takeException(), isNull);
        controller.closeReviewPane();
        await tester.pump();
      }

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

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

  for (final language in [
    (
      steps: 0,
      name: 'English',
      partial: '0 issues · partial check',
      paused: 'Live checking paused',
      languageTooltip: 'Language and checking',
      changesTooltip: 'Review tracked changes',
    ),
    (
      steps: 1,
      name: 'German',
      partial: '0 Hinweise · teilweise geprüft',
      paused: 'Automatische Prüfung pausiert',
      languageTooltip: 'Sprache und Prüfung',
      changesTooltip: 'Nachverfolgte Änderungen prüfen',
    ),
    (
      steps: 2,
      name: 'Arabic',
      partial: '0 ملاحظات · تدقيق جزئي',
      paused: 'التدقيق التلقائي متوقف',
      languageTooltip: 'اللغة والتدقيق',
      changesTooltip: 'مراجعة التغييرات المتعقبة',
    ),
  ]) {
    testWidgets(
      '${language.name} compact footer keeps truthful status and reachable review actions',
      (tester) async {
        final controller = await _studio(
          tester,
          _StatusProvider(status: OfficeProofingStatus.unavailable),
          languageSteps: language.steps,
        );
        await _finish(tester, controller, controller.proofing.checkNow());
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        Finder compactStatus(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && (widget.tooltip ?? '').startsWith(label),
        );

        tester.view.physicalSize = const Size(390, 900);
        await tester.binding.setSurfaceSize(const Size(390, 900));
        await tester.pump();
        final status = compactStatus(language.partial);
        expect(status.hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: status,
            matching: find.byIcon(Icons.info_outline),
          ),
          findsOneWidget,
        );
        expect(
          find.byTooltip(language.languageTooltip).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(status);
        await tester.pump();
        expect(controller.reviewPaneVisible, isTrue);
        expect(controller.reviewPaneTab, WordReviewPaneTab.proofing);
        expect(tester.takeException(), isNull);
        controller.closeReviewPane();
        await tester.pump();

        // At the transition to text actions, long translated labels remain
        // bounded, while their full status remains available in a tooltip.
        tester.view.physicalSize = const Size(820, 900);
        await tester.binding.setSurfaceSize(const Size(820, 900));
        await tester.pump();
        _expectStatus(language.partial, Icons.info_outline);
        expect(_statusButton(language.partial).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        controller.proofing.enabled = false;
        tester.view.physicalSize = const Size(390, 900);
        await tester.binding.setSurfaceSize(const Size(390, 900));
        await tester.pump();
        final paused = compactStatus(language.paused);
        expect(paused.hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: paused,
            matching: find.byIcon(Icons.pause_circle_outline),
          ),
          findsOneWidget,
        );
        final changes = find.byTooltip(language.changesTooltip);
        expect(changes.hitTestable(), findsOneWidget);
        await tester.tap(changes);
        await tester.pump();
        expect(controller.reviewPaneVisible, isTrue);
        expect(controller.reviewPaneTab, WordReviewPaneTab.changes);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
