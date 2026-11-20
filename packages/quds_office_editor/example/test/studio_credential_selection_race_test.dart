import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/credentials/secure_storage_service.dart';
import 'package:quds_office_studio/studio_credential_settings.dart';
import 'package:quds_office_studio/studio_credential_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _DelayedSelection extends StudioCredentialStorage {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool fail = false;
  int selections = 0;

  @override
  Future<void> loadSelection() async {}

  @override
  Future<bool> vaultExists() async => false;

  @override
  Future<void> select(StudioCredentialMode next, {String? path}) async {
    selections++;
    entered.complete();
    await release.future;
    if (fail) throw StateError('Synthetic selected-store failure');
    mode = next;
  }
}

Future<void> _open(
  WidgetTester tester,
  StudioCredentialStorage manager,
  void Function(bool) onResult,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => onResult(
            await showStudioCredentialSettings(context, manager: manager),
          ),
          child: const Text('Open storage'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open storage'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a delayed system-store probe cannot cache under a newly selected mode',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'containsKey');
      entered.complete();
      await release.future;
      return false;
    });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
      messenger.setMockMethodCallHandler(channel, null);
    });
    final manager = StudioCredentialStorage();
    addTearDown(manager.dispose);
    await manager.loadSelection();
    final pendingSystem = manager.storage;
    await entered.future;
    await manager.select(StudioCredentialMode.session);
    release.complete();
    final original = await pendingSystem;
    final selected = await manager.storage;
    expect(original, isA<PlatformSecureStorage>());
    expect(selected, isA<InMemorySecureStorage>());
    expect(selected, isNot(same(original)));
    expect(selected.isPersistent, isFalse);
    expect(manager.mode, StudioCredentialMode.session);
  });

  testWidgets('selection stays open across barrier and back until committed',
      (tester) async {
    final manager = _DelayedSelection();
    addTearDown(manager.dispose);
    bool? result;
    await _open(tester, manager, (value) => result = value);
    await tester.tap(find.text('Use this store'));
    await tester.pump();
    await manager.entered.future;
    final dialogContext = tester.element(find.byType(AlertDialog));
    expect(ModalRoute.of(dialogContext)!.barrierDismissible, isFalse);
    expect(tester.widget<PopScope<bool>>(find.byType(PopScope<bool>)).canPop,
        isFalse);
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await Navigator.of(dialogContext).maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(result, isNull);
    expect(manager.selections, 1);
    manager.release.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Cancel before selection returns false without changing a store',
      (tester) async {
    final manager = _DelayedSelection();
    addTearDown(manager.dispose);
    bool? result;
    await _open(tester, manager, (value) => result = value);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(manager.selections, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('failed selection re-enables Cancel and leaves the dialog open',
      (tester) async {
    final manager = _DelayedSelection()..fail = true;
    addTearDown(manager.dispose);
    bool? result;
    await _open(tester, manager, (value) => result = value);
    await tester.tap(find.text('Use this store'));
    await tester.pump();
    await manager.entered.future;
    manager.release.complete();
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<PopScope<bool>>(find.byType(PopScope<bool>)).canPop,
        isTrue);
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
