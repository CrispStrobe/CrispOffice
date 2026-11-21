import 'dart:convert';

import 'package:flutter/foundation.dart';
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

const _password = 'correct horse battery staple';
const _strings = StudioStrings(StudioLanguage.en);

/// Stand-in for macos/Runner/BiometricVaultKeychain.swift: one item, an
/// availability answer and the outcome of the next Touch ID sheet.
class _NativeKeychain {
  String availability = 'available';
  String? item;
  // What the system sheet does on the next read: success (if an item
  // exists), cancelled, failed.
  String sheet = 'success';
  final calls = <MethodCall>[];

  int count(String method) => calls.where((c) => c.method == method).length;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'isAvailable':
        return availability;
      case 'store':
        item = (call.arguments as Map)['secret'] as String;
        return null;
      case 'read':
        if (item == null) return {'status': 'notFound'};
        if (sheet != 'success') return {'status': sheet};
        return {'status': 'success', 'secret': item};
      case 'delete':
        item = null;
        return null;
    }
    throw MissingPluginException(call.method);
  }

  /// A fingerprint was added: .biometryCurrentSet makes the item unreadable.
  void changeEnrolledFingers() => item = null;
}

class _Harness {
  _Harness() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelBiometricSecretStore.defaultChannel,
          native.handle,
        );
  }

  final native = _NativeKeychain();
  // Persists across manager instances, like credential-vault.json.
  InMemoryWebStorageBackend vaultFile = InMemoryWebStorageBackend();

  /// A fresh manager models a new app process (vault locked).
  StudioCredentialStorage manager() => StudioCredentialStorage(
    vaultFactory: () async => WebEncryptedStorage(
      vaultFile,
      cryptoProvider: const PointycastleCryptoProvider(),
      newVaultIterations: 1000,
    ),
  );

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelBiometricSecretStore.defaultChannel,
          null,
        );
  }
}

Future<bool> _flag() async =>
    (await SharedPreferences.getInstance()).getBool(
      StudioCredentialStorage.biometricPreferenceKey,
    ) ??
    false;

/// Creates a vault holding one credential and turns Touch ID on.
Future<StudioCredentialStorage> _enrolled(_Harness h) async {
  final first = h.manager();
  await first.unlockVault(_password, create: true);
  await first.select(StudioCredentialMode.encryptedVault);
  await (await first.storage).write('mail', 'secret-mail-password');
  await first.enableBiometricUnlock();
  return first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness h;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    h = _Harness();
  });
  tearDown(() => h.dispose());

  group('vault key', () {
    WebEncryptedStorage vault(InMemoryWebStorageBackend backend) =>
        WebEncryptedStorage(
          backend,
          cryptoProvider: const PointycastleCryptoProvider(),
          newVaultIterations: 1000,
        );

    test('exported key reopens the vault; other keys are rejected', () async {
      final backend = InMemoryWebStorageBackend();
      final first = vault(backend);
      expect(await first.exportUnlockKey(), isNull);
      await first.initialize(_password, expectedExisting: false);
      await first.write('k', 'v');
      final key = (await first.exportUnlockKey())!;
      expect(key, hasLength(32));

      final second = vault(backend);
      await second.initializeWithKey(key);
      expect(await second.read('k'), 'v');

      final wrong = vault(backend);
      await expectLater(
        wrong.initializeWithKey(Uint8List(32)),
        throwsA(isA<CredentialVaultKeyRejected>()),
      );
      expect(wrong.isInitialized, isFalse);
      await expectLater(
        wrong.initializeWithKey(Uint8List(16)),
        throwsA(isA<CredentialVaultKeyRejected>()),
      );
    });

    test('a missing vault is not reported as a rejected key', () async {
      await expectLater(
        vault(InMemoryWebStorageBackend()).initializeWithKey(Uint8List(32)),
        throwsA(isNot(isA<CredentialVaultKeyRejected>())),
      );
    });
  });

  group('manager', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    });
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test(
      'opt-in after a password unlock stores the derived key, not the password',
      () async {
        await _enrolled(h);
        expect(await _flag(), isTrue);
        final payload = jsonDecode(h.native.item!) as Map<String, Object?>;
        expect(payload['v'], 1);
        expect(base64.decode(payload['key'] as String), hasLength(32));
        expect(h.native.item, isNot(contains(_password)));

        // Next start: Touch ID alone opens the vault.
        final next = h.manager();
        await next.loadSelection();
        expect(
          await next.unlockVaultWithBiometrics(reason: 'unlock your accounts'),
          StudioVaultBiometricUnlock.unlocked,
        );
        final read = h.native.calls.lastWhere((c) => c.method == 'read');
        expect((read.arguments as Map)['reason'], 'unlock your accounts');
        expect(await (await next.storage).read('mail'), 'secret-mail-password');
      },
    );

    test('enabling requires an unlocked vault and usable biometry', () async {
      final manager = h.manager();
      await expectLater(manager.enableBiometricUnlock(), throwsStateError);
      await manager.unlockVault(_password, create: true);
      await manager.select(StudioCredentialMode.encryptedVault);
      h.native.availability = 'keychainUnavailable';
      await expectLater(manager.enableBiometricUnlock(), throwsStateError);
      expect(h.native.count('store'), 0);
      expect(await _flag(), isFalse);
    });

    test(
      'cancel and failure leave the vault locked and keep the key',
      () async {
        await _enrolled(h);
        final next = h.manager();
        await next.loadSelection();
        h.native.sheet = 'cancelled';
        expect(
          await next.unlockVaultWithBiometrics(reason: 'r'),
          StudioVaultBiometricUnlock.cancelled,
        );
        h.native.sheet = 'failed';
        expect(
          await next.unlockVaultWithBiometrics(reason: 'r'),
          StudioVaultBiometricUnlock.failed,
        );
        expect(next.vaultUnlocked, isFalse);
        expect(() => next.storage, throwsStateError);
        expect(h.native.item, isNotNull);
        expect(await _flag(), isTrue);
        // The master password still works.
        await next.unlockVault(_password, create: false);
        expect(await (await next.storage).read('mail'), 'secret-mail-password');
      },
    );

    test('biometry unavailable does not show the sheet', () async {
      await _enrolled(h);
      h.native.availability = 'lockedOut';
      final next = h.manager();
      expect(
        await next.unlockVaultWithBiometrics(reason: 'r'),
        StudioVaultBiometricUnlock.unavailable,
      );
      expect(h.native.count('read'), 0);
      expect(await _flag(), isTrue);
    });

    test('not enabled never touches the keychain item', () async {
      final manager = h.manager();
      await manager.unlockVault(_password, create: true);
      expect(
        await h.manager().unlockVaultWithBiometrics(reason: 'r'),
        StudioVaultBiometricUnlock.notEnabled,
      );
      expect(h.native.count('read'), 0);
    });

    test(
      'a fingerprint change invalidates the item and suggests re-enrolment',
      () async {
        await _enrolled(h);
        h.native.changeEnrolledFingers();
        final next = h.manager();
        expect(
          await next.unlockVaultWithBiometrics(reason: 'r'),
          StudioVaultBiometricUnlock.invalidated,
        );
        expect(next.biometricReenrolmentSuggested, isTrue);
        expect(await _flag(), isFalse);
        expect(h.native.count('delete'), greaterThan(0));

        // Re-enrolment after the password unlock.
        await next.unlockVault(_password, create: false);
        await next.enableBiometricUnlock();
        expect(next.biometricReenrolmentSuggested, isFalse);
        expect(
          await h.manager().unlockVaultWithBiometrics(reason: 'r'),
          StudioVaultBiometricUnlock.unlocked,
        );
      },
    );

    test('a key that no longer opens the vault is deleted', () async {
      await _enrolled(h);
      // The vault file is replaced by one with another password (outside
      // this app's flows); the stored key cannot verify it.
      h.vaultFile = InMemoryWebStorageBackend();
      final keep = h.native.item;
      await h.manager().unlockVault('another password', create: true);
      h.native.item = keep; // as if the creation could not clean it up
      await (await SharedPreferences.getInstance()).setBool(
        StudioCredentialStorage.biometricPreferenceKey,
        true,
      );
      final next = h.manager();
      expect(
        await next.unlockVaultWithBiometrics(reason: 'r'),
        StudioVaultBiometricUnlock.invalidated,
      );
      expect(h.native.item, isNull);
      expect(await _flag(), isFalse);
      expect(next.vaultUnlocked, isFalse);
    });

    test('creating a new vault (reset) removes the old item', () async {
      await _enrolled(h);
      h.vaultFile = InMemoryWebStorageBackend();
      await h.manager().unlockVault('new password', create: true);
      expect(h.native.item, isNull);
      expect(await _flag(), isFalse);
    });

    test('changing the storage mode removes the item', () async {
      final manager = await _enrolled(h);
      await manager.select(StudioCredentialMode.session);
      expect(h.native.item, isNull);
      expect(await _flag(), isFalse);
    });

    test('a removal that failed during a mode change is retried', () async {
      final manager = await _enrolled(h);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannelBiometricSecretStore.defaultChannel,
            (call) async {
              if (call.method == 'delete') {
                throw PlatformException(code: 'biometric_vault_delete_failed');
              }
              return h.native.handle(call);
            },
          );
      await manager.select(StudioCredentialMode.session);
      expect(
        await _flag(),
        isFalse,
        reason: 'disabled before removal is retried',
      );
      expect(manager.biometricCleanupPending, isTrue);
      h.dispose();
      h = _Harness()..native.item = 'stale';
      final restarted = h.manager();
      await restarted.loadSelection();
      await pumpEventQueue();
      expect(h.native.count('delete'), 1);
      expect(h.native.item, isNull);
      expect(await _flag(), isFalse);
    });

    test('disabling deletes the item', () async {
      final manager = await _enrolled(h);
      await manager.disableBiometricUnlock();
      expect(h.native.item, isNull);
      expect(await _flag(), isFalse);
    });

    test('availability maps the native answer', () async {
      for (final value in BiometricUnlockAvailability.values) {
        if (value == BiometricUnlockAvailability.unsupportedPlatform) continue;
        h.native.availability = value.name;
        expect(await h.manager().biometricAvailability(), value);
      }
      h.native.availability = 'something new';
      expect(
        await h.manager().biometricAvailability(),
        BiometricUnlockAvailability.error,
      );
    });
  });

  test('other platforms report unsupported and never call native', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final manager = h.manager();
    expect(
      await manager.biometricAvailability(),
      BiometricUnlockAvailability.unsupportedPlatform,
    );
    expect(h.native.calls, isEmpty);
  });

  group('unlock flow', () {
    final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);
    late StudioCredentialStorage manager;
    StudioVaultUnlockOutcome? outcome;

    Future<void> open(WidgetTester tester) async {
      outcome = null;
      await manager.loadSelection();
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
    }

    Future<void> enterPassword(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const ValueKey('studio-mail-vault-password')),
        _password,
      );
      await tester.tap(find.byKey(const ValueKey('studio-mail-vault-unlock')));
      await tester.pumpAndSettle();
    }

    testWidgets('Touch ID first: success skips the password dialog', (
      tester,
    ) async {
      await _enrolled(h);
      manager = h.manager();
      await open(tester);
      expect(outcome, StudioVaultUnlockOutcome.unlocked);
      expect(find.byType(StudioVaultUnlockDialog), findsNothing);
      expect(manager.vaultUnlocked, isTrue);
    }, variant: macOS);

    testWidgets('cancel falls back to the password; Touch ID can be retried', (
      tester,
    ) async {
      await _enrolled(h);
      manager = h.manager();
      h.native.sheet = 'cancelled';
      await open(tester);
      expect(find.byType(StudioVaultUnlockDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('studio-vault-touchid-optin')),
        findsNothing,
      );
      h.native.sheet = 'success';
      await tester.tap(
        find.byKey(const ValueKey('studio-vault-touchid-retry')),
      );
      await tester.pumpAndSettle();
      expect(outcome, StudioVaultUnlockOutcome.unlocked);
      expect(h.native.count('read'), 2);
    }, variant: macOS);

    testWidgets('failure falls back to the master password', (tester) async {
      await _enrolled(h);
      manager = h.manager();
      h.native.sheet = 'failed';
      await open(tester);
      expect(
        find.text(
          'Touch ID did not unlock the vault. Enter the master '
          'password.',
        ),
        findsOneWidget,
      );
      await enterPassword(tester);
      expect(outcome, StudioVaultUnlockOutcome.unlocked);
      expect(manager.vaultUnlocked, isTrue);
    }, variant: macOS);

    testWidgets('opt-in is offered after a password unlock', (tester) async {
      final selected = h.manager();
      await selected.unlockVault(_password, create: true);
      await selected.select(StudioCredentialMode.encryptedVault);
      manager = h.manager();
      await open(tester);
      expect(h.native.count('read'), 0);
      await tester.tap(
        find.byKey(const ValueKey('studio-vault-touchid-optin')),
      );
      await tester.pump();
      await enterPassword(tester);
      expect(outcome, StudioVaultUnlockOutcome.unlocked);
      expect(h.native.item, isNotNull);
      expect(await _flag(), isTrue);
    }, variant: macOS);

    testWidgets('declining the opt-in stores nothing', (tester) async {
      final selected = h.manager();
      await selected.unlockVault(_password, create: true);
      await selected.select(StudioCredentialMode.encryptedVault);
      manager = h.manager();
      await open(tester);
      await enterPassword(tester);
      expect(outcome, StudioVaultUnlockOutcome.unlocked);
      expect(h.native.count('store'), 0);
    }, variant: macOS);

    testWidgets('invalidation re-offers Touch ID with an explanation', (
      tester,
    ) async {
      await _enrolled(h);
      h.native.changeEnrolledFingers();
      manager = h.manager();
      await open(tester);
      expect(
        find.byKey(const ValueKey('studio-vault-touchid-notice')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('studio-vault-touchid-optin')),
      );
      await tester.pump();
      await enterPassword(tester);
      expect(outcome, StudioVaultUnlockOutcome.unlocked);
      expect(h.native.item, isNotNull);
      expect(await _flag(), isTrue);
    }, variant: macOS);

    testWidgets('no opt-in without the protected keychain', (tester) async {
      final selected = h.manager();
      await selected.unlockVault(_password, create: true);
      await selected.select(StudioCredentialMode.encryptedVault);
      h.native.availability = 'keychainUnavailable';
      manager = h.manager();
      await open(tester);
      expect(
        find.byKey(const ValueKey('studio-vault-touchid-optin')),
        findsNothing,
      );
      await enterPassword(tester);
      expect(outcome, StudioVaultUnlockOutcome.unlocked);
    }, variant: macOS);
  });

  group('credential settings', () {
    late StudioCredentialStorage manager;

    Future<void> open(WidgetTester tester) async {
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
      await tester.tap(
        find.byType(DropdownButtonFormField<StudioCredentialMode>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encrypted credential vault').last);
      await tester.pumpAndSettle();
    }

    final toggle = find.byKey(
      const ValueKey('studio-credential-touchid-toggle'),
    );

    testWidgets('toggle turns Touch ID on with the password unlock', (
      tester,
    ) async {
      await h.manager().unlockVault(_password, create: true);
      manager = h.manager();
      await open(tester);
      await tester.tap(toggle);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, _password);
      await tester.tap(find.text('Use this store'));
      await tester.pumpAndSettle();
      expect(manager.mode, StudioCredentialMode.encryptedVault);
      expect(h.native.item, isNotNull);
      expect(await _flag(), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Touch ID button unlocks; toggle off deletes the item', (
      tester,
    ) async {
      await _enrolled(h);
      manager = h.manager();
      await open(tester);
      final button = find.byKey(
        const ValueKey('studio-credential-touchid-unlock'),
      );
      expect(button, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(h.native.item, isNull);
      expect(button, findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Touch ID button opens the vault without a password', (
      tester,
    ) async {
      await _enrolled(h);
      manager = h.manager();
      await open(tester);
      await tester.tap(
        find.byKey(const ValueKey('studio-credential-touchid-unlock')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(manager.mode, StudioCredentialMode.encryptedVault);
      expect(
        await (await manager.storage).read('mail'),
        'secret-mail-password',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('unsigned builds explain and disable the toggle', (
      tester,
    ) async {
      h.native.availability = 'keychainUnavailable';
      await h.manager().unlockVault(_password, create: true);
      manager = h.manager();
      await open(tester);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      expect(
        find.textContaining('not signed for the protected keychain'),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('hidden where biometric unlock is unsupported', (tester) async {
      await h.manager().unlockVault(_password, create: true);
      manager = h.manager();
      await open(tester);
      expect(toggle, findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
