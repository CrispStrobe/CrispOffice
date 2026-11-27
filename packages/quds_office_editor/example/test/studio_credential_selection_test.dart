import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/credentials/secure_storage_macos_keychain.dart';
import 'package:quds_office_studio/credentials/secure_storage_service.dart';
import 'package:quds_office_studio/studio_credential_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _PersistentMemoryStorage extends InMemorySecureStorage {
  @override
  bool get isPersistent => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'slow system initialization cannot become the session backend',
    () async {
      final started = Completer<void>();
      final pending = Completer<SecureStorage>();
      final persistent = _PersistentMemoryStorage();
      final manager = StudioCredentialStorage(
        systemStorageFactory: () {
          started.complete();
          return pending.future;
        },
      );
      final originalRequest = manager.storage;
      await started.future;
      await manager.select(StudioCredentialMode.session);
      final session = await manager.storage;

      pending.complete(persistent);
      expect(await originalRequest, same(persistent));
      expect(persistent.isPersistent, isTrue);
      expect(session.isPersistent, isFalse);
      expect(await manager.storage, same(session));
      await (await manager.storage).write('session-secret', 'private');
      expect(await session.read('session-secret'), 'private');
      expect(await persistent.read('session-secret'), isNull);
    },
  );
  test(
    'old initialization cannot replace a newer instance of the same store',
    () async {
      final started = [Completer<void>(), Completer<void>()];
      final pending = [Completer<SecureStorage>(), Completer<SecureStorage>()];
      final original = _PersistentMemoryStorage();
      final current = _PersistentMemoryStorage();
      var attempts = 0;
      final manager = StudioCredentialStorage(
        systemStorageFactory: () {
          final index = attempts++;
          started[index].complete();
          return pending[index].future;
        },
      );
      final originalRequest = manager.storage;
      await started[0].future;
      await manager.select(StudioCredentialMode.session);
      final session = await manager.storage;
      await manager.select(StudioCredentialMode.system);
      final currentRequest = manager.storage;
      await started[1].future;
      pending[1].complete(current);
      expect(await currentRequest, same(current));
      pending[0].complete(original);
      expect(await originalRequest, same(original));

      expect(await manager.storage, same(current));
      await (await manager.storage).write('current-secret', 'private');
      expect(await current.read('current-secret'), 'private');
      expect(await original.read('current-secret'), isNull);
      expect(await session.read('current-secret'), isNull);
      expect(attempts, 2);
    },
  );
  test(
    'session selection persists only its mode, never account secrets',
    () async {
      final manager = StudioCredentialStorage();
      await manager.select(StudioCredentialMode.session);
      final store = await manager.storage;
      await store.write('synthetic-secret', 'private');
      expect(store.isPersistent, isFalse);
      final raw = (await SharedPreferences.getInstance()).getString(
        StudioCredentialStorage.preferenceKey,
      )!;
      final value = jsonDecode(raw) as Map<String, Object?>;
      expect(value['mode'], 'session');
      expect(raw, isNot(contains('private')));
      final restarted = StudioCredentialStorage();
      await restarted.loadSelection();
      expect(restarted.mode, StudioCredentialMode.session);
      expect(await (await restarted.storage).read('synthetic-secret'), isNull);
    },
  );
  test(
    'failed custom keychain selection preserves the original store and never redirects a write',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <String>[];
      const channel = MethodChannel(
        MacOsCustomKeychainStorage.methodChannelName,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (c) async {
        calls.add(c.method);
        throw PlatformException(code: 'custom_keychain_access_denied');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final manager = StudioCredentialStorage();
      await manager.select(StudioCredentialMode.session);
      final original = await manager.storage;
      await expectLater(
        manager.select(
          StudioCredentialMode.customKeychain,
          path: '/tmp/synthetic.keychain-db',
        ),
        Platform.isMacOS
            ? throwsA(
                isA<PlatformException>().having(
                  (error) => error.code,
                  'native denial',
                  'custom_keychain_access_denied',
                ),
              )
            : throwsA(
                isA<ArgumentError>().having(
                  (error) => error.message,
                  'host admission',
                  'Choose a macOS keychain file.',
                ),
              ),
      );
      expect(manager.mode, StudioCredentialMode.session);
      expect(await manager.storage, same(original));
      // The manager uses dart:io admission. A Flutter target override does
      // not turn a Linux/Windows test process into a macOS host.
      expect(calls, Platform.isMacOS ? ['initialize'] : isEmpty);
    },
  );
  test(
    'custom keychain adapter retains native access-denial without fallback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const path = '/tmp/synthetic.keychain-db';
      const channel = MethodChannel(
        MacOsCustomKeychainStorage.methodChannelName,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        expect(call.arguments, {'path': path});
        throw PlatformException(code: 'custom_keychain_access_denied');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final store = MacOsCustomKeychainStorage(path: path);
      await expectLater(
        store.initialize(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'native denial',
            'custom_keychain_access_denied',
          ),
        ),
      );
      expect(
        () => store.write('synthetic-key', 'synthetic-value'),
        throwsStateError,
      );
      expect(calls, ['initialize']);
    },
  );
  test('missing entitlement never opens the default file keychain', () async {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final optionsSeen = <String?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final options = arguments['options'] as Map<Object?, Object?>;
      optionsSeen.add(options['useDataProtectionKeyChain'] as String?);
      throw PlatformException(code: 'Unexpected security result: -34018');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
      StudioCredentialStorage().storage,
      throwsA(isA<PlatformException>()),
    );
    expect(optionsSeen, isNotEmpty);
    expect(optionsSeen, everyElement('true'));
  }, skip: !Platform.isMacOS);

  test(
    'platform probe selects host options and verifies read-back before deletion',
    () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? saved;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (c) async {
        final args = c.arguments as Map<Object?, Object?>;
        final options = args['options'] as Map<Object?, Object?>;
        // The plugin chooses options using dart:io Platform, independently
        // of Flutter's visual platform override used by the custom-store test.
        if (Platform.isMacOS) {
          expect(options['useDataProtectionKeyChain'], 'true');
        } else {
          expect(options.containsKey('useDataProtectionKeyChain'), isFalse);
        }
        calls.add(c.method);
        switch (c.method) {
          case 'write':
            saved = args['value'] as String;
            return null;
          case 'read':
            return saved;
          case 'delete':
            saved = null;
            return null;
        }
        throw StateError('Unexpected operation');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await PlatformSecureStorage().verifyAvailable();
      expect(calls, ['write', 'read', 'delete']);
      expect(saved, isNull);
    },
  );
}
