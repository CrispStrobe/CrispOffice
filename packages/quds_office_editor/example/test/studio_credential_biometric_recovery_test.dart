import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/credentials/biometric_secret_store.dart';
import 'package:quds_office_studio/credentials/secure_storage_web.dart';
import 'package:quds_office_studio/credentials/web_crypto_provider.dart';
import 'package:quds_office_studio/studio_credential_settings.dart';
import 'package:quds_office_studio/studio_credential_storage.dart';
import 'package:quds_office_studio/studio_credential_vault_unlock.dart';
import 'package:quds_office_studio/studio_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _password = 'synthetic recovery master password';
const _strings = StudioStrings(StudioLanguage.en);
const _preferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

/// Keeps persisted preferences separate from SharedPreferences' eager cache,
/// including a failed write followed by an actual process-cache reset.
final class _Preferences {
  final values = <String, Object>{};
  bool rejectEnable = false;
  bool rejectRemove = false;

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'getAll') return Map<String, Object>.of(values);
    final arguments = (call.arguments as Map<Object?, Object?>)
        .cast<String, Object?>();
    final key = arguments['key'] as String;
    if (call.method == 'remove') {
      if (rejectRemove) return false;
      values.remove(key);
      return true;
    }
    if (call.method == 'setBool' || call.method == 'setString') {
      final value = arguments['value']!;
      if (rejectEnable && call.method == 'setBool' && value == true) {
        return false;
      }
      values[key] = value;
      return true;
    }
    throw MissingPluginException(call.method);
  }
}

final class _Keychain implements BiometricSecretStore {
  String? secret;
  bool rejectDelete = false;
  int stores = 0;
  Completer<void>? entered;
  Completer<void>? release;
  bool delayStore = false;

  @override
  Future<BiometricUnlockAvailability> availability() async {
    if (!delayStore && release != null) {
      entered?.complete();
      await release!.future;
    }
    return BiometricUnlockAvailability.available;
  }

  @override
  Future<void> store(String value) async {
    stores++;
    secret = value;
    if (delayStore && release != null) {
      entered?.complete();
      await release!.future;
    }
  }

  @override
  Future<BiometricSecretRead> read({
    required String reason,
    String? cancelTitle,
    String? fallbackTitle,
  }) async => secret == null
      ? const BiometricSecretRead(BiometricSecretReadStatus.notFound)
      : BiometricSecretRead(BiometricSecretReadStatus.success, secret);

  @override
  Future<void> delete() async {
    if (rejectDelete) {
      throw StateError('Synthetic protected-item removal failure');
    }
    secret = null;
  }
}

final class _ThrowingBiometricManager extends StudioCredentialStorage {
  _ThrowingBiometricManager(_Harness harness)
    : super(biometrics: harness.keychain, vaultFactory: harness.openVault);

  @override
  Future<StudioVaultBiometricUnlock> unlockVaultWithBiometrics({
    required String reason,
    String? cancelTitle,
    String? fallbackTitle,
  }) async => throw StateError('Synthetic private backend detail');
}

final class _Harness {
  final preferences = _Preferences();
  final keychain = _Keychain();
  final backend = InMemoryWebStorageBackend();
  bool rejectVaultOpen = false;

  Future<WebEncryptedStorage> openVault() async {
    if (rejectVaultOpen) throw StateError('Synthetic private backend detail');
    return WebEncryptedStorage(
      backend,
      cryptoProvider: const PointycastleCryptoProvider(),
      newVaultIterations: 1000,
    );
  }

  StudioCredentialStorage manager() =>
      StudioCredentialStorage(biometrics: keychain, vaultFactory: openVault);

  Future<StudioCredentialStorage> createSelectedVault() async {
    final owner = manager();
    await owner.unlockVault(_password, create: true);
    await owner.select(StudioCredentialMode.encryptedVault);
    await (await owner.storage).write('mail', 'synthetic account password');
    return owner;
  }

  Future<void> failedEnrollment(StudioCredentialStorage manager) async {
    preferences.rejectEnable = true;
    keychain.rejectDelete = true;
    await expectLater(manager.enableBiometricUnlock(), throwsStateError);
    expect(keychain.secret, isNotNull);
    // Model the next process reading durable state, not the optimistic cache.
    SharedPreferences.resetStatic();
    preferences.rejectEnable = false;
    keychain.rejectDelete = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness harness;
  setUp(() {
    SharedPreferences.resetStatic();
    harness = _Harness();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _preferencesChannel,
          harness.preferences.handle,
        );
  });
  tearDown(() {
    SharedPreferences.resetStatic();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_preferencesChannel, null);
  });

  test(
    'failed enrollment rollback is retried on the next vault startup',
    () async {
      final first = await harness.createSelectedVault();
      addTearDown(first.dispose);
      await harness.failedEnrollment(first);
      final restarted = harness.manager();
      addTearDown(restarted.dispose);
      await restarted.loadSelection();
      await pumpEventQueue();
      expect(restarted.mode, StudioCredentialMode.encryptedVault);
      expect(harness.keychain.secret == null, isTrue);
      expect(await restarted.biometricUnlockEnabled(), isFalse);
      expect(restarted.vaultUnlocked, isFalse);
    },
  );

  test(
    'leaving the vault removes an item without a durable enable flag',
    () async {
      final manager = await harness.createSelectedVault();
      addTearDown(manager.dispose);
      await harness.failedEnrollment(manager);
      await manager.select(StudioCredentialMode.session);
      expect(harness.keychain.secret == null, isTrue);
      expect(await manager.biometricUnlockEnabled(), isFalse);
    },
  );

  test('a failed durable disable prevents writing a new unlock key', () async {
    final manager = await harness.createSelectedVault();
    addTearDown(manager.dispose);
    harness.preferences.rejectRemove = true;
    await expectLater(manager.enableBiometricUnlock(), throwsStateError);
    expect(harness.keychain.stores, 0);
    expect(harness.keychain.secret == null, isTrue);
  });

  test(
    'enrolment cannot reactivate a vault after selecting session storage',
    () async {
      final manager = await harness.createSelectedVault();
      addTearDown(manager.dispose);
      await manager.select(StudioCredentialMode.session);
      await expectLater(manager.enableBiometricUnlock(), throwsStateError);
      expect(harness.keychain.stores, 0);
      expect(harness.keychain.secret == null, isTrue);
      expect(await manager.biometricUnlockEnabled(), isFalse);
    },
  );

  for (final delayStore in [false, true]) {
    test(
      'a backend change during ${delayStore ? 'key storage' : 'availability'} fences enrolment',
      () async {
        final manager = await harness.createSelectedVault();
        addTearDown(manager.dispose);
        harness.keychain
          ..delayStore = delayStore
          ..entered = Completer<void>()
          ..release = Completer<void>();
        final enabling = manager.enableBiometricUnlock();
        final rejected = expectLater(enabling, throwsStateError);
        await harness.keychain.entered!.future;
        final switching = manager.select(StudioCredentialMode.session);
        await pumpEventQueue();
        expect(manager.mode, StudioCredentialMode.session);
        harness.keychain.release!.complete();
        await rejected;
        await switching;
        expect(harness.keychain.secret == null, isTrue);
        expect(await manager.biometricUnlockEnabled(), isFalse);
        expect(harness.keychain.stores, delayStore ? 1 : 0);
      },
    );
  }

  test(
    'vault-handle failure returns a failed outcome and keeps password access',
    () async {
      final first = await harness.createSelectedVault();
      addTearDown(first.dispose);
      await first.enableBiometricUnlock();
      final next = harness.manager();
      addTearDown(next.dispose);
      harness.rejectVaultOpen = true;
      await expectLater(
        next.unlockVaultWithBiometrics(reason: 'Synthetic unlock'),
        completion(StudioVaultBiometricUnlock.failed),
      );
      expect(next.vaultUnlocked, isFalse);
      expect(harness.keychain.secret, isNotNull);
      harness.rejectVaultOpen = false;
      await next.unlockVault(_password, create: false);
      expect(next.vaultUnlocked, isTrue);
    },
  );

  test('a malformed non-secret enable flag fails closed', () async {
    harness
            .preferences
            .values['flutter.${StudioCredentialStorage.preferenceKey}'] =
        jsonEncode({
          'mode': StudioCredentialMode.encryptedVault.name,
          'path': null,
        });
    harness
            .preferences
            .values['flutter.${StudioCredentialStorage.biometricPreferenceKey}'] =
        'malformed';
    final manager = harness.manager();
    addTearDown(manager.dispose);
    await expectLater(
      manager.unlockVaultWithBiometrics(reason: 'Synthetic unlock'),
      completion(StudioVaultBiometricUnlock.failed),
    );
    expect(manager.vaultUnlocked, isFalse);
  });

  testWidgets('failed removal stays visible and can be retried from settings', (
    tester,
  ) async {
    final manager = await harness.createSelectedVault();
    addTearDown(manager.dispose);
    await manager.enableBiometricUnlock();
    harness.keychain.rejectDelete = true;
    await expectLater(manager.disableBiometricUnlock(), throwsStateError);
    expect(manager.biometricCleanupPending, isTrue);
    expect(await manager.biometricUnlockEnabled(), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showStudioCredentialSettings(context, manager: manager),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final retry = find.byKey(
      const ValueKey('studio-credential-touchid-cleanup'),
    );
    expect(retry, findsOneWidget);
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(manager.biometricCleanupPending, isTrue);
    expect(find.textContaining('Synthetic protected'), findsNothing);
    harness.keychain.rejectDelete = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(manager.biometricCleanupPending, isFalse);
    expect(harness.keychain.secret == null, isTrue);
    expect(retry, findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('unexpected manager failure still opens the password fallback', (
    tester,
  ) async {
    final first = await harness.createSelectedVault();
    addTearDown(first.dispose);
    await first.enableBiometricUnlock();
    final manager = _ThrowingBiometricManager(harness);
    addTearDown(manager.dispose);
    StudioVaultUnlockOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  outcome = await unlockStudioCredentialVault(
                    context,
                    manager: manager,
                    strings: _strings,
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(StudioVaultUnlockDialog), findsOneWidget);
    expect(find.textContaining('Synthetic private'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-vault-password')),
      _password,
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-vault-unlock')));
    await tester.pumpAndSettle();
    expect(outcome, StudioVaultUnlockOutcome.unlocked);
  });

  testWidgets('a failed biometric retry restores Cancel and password unlock', (
    tester,
  ) async {
    final first = await harness.createSelectedVault();
    addTearDown(first.dispose);
    final manager = _ThrowingBiometricManager(harness);
    addTearDown(manager.dispose);
    StudioVaultUnlockOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  outcome = await showDialog<StudioVaultUnlockOutcome>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => StudioVaultUnlockDialog(
                      manager: manager,
                      strings: _strings,
                      retryTouchId: true,
                    ),
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-vault-touchid-retry')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<PopScope<StudioVaultUnlockOutcome>>(
            find.byType(PopScope<StudioVaultUnlockOutcome>),
          )
          .canPop,
      isTrue,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('Synthetic private'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-vault-password')),
      _password,
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-vault-unlock')));
    await tester.pumpAndSettle();
    expect(outcome, StudioVaultUnlockOutcome.unlocked);
  });
}
