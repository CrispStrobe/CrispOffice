import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/studio_credential_storage.dart';
import '../lib/credentials/secure_storage_macos_keychain.dart';
import '../lib/credentials/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
      expect(jsonDecode(raw)['mode'], 'session');
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
        throwsA(isA<PlatformException>()),
      );
      expect(manager.mode, StudioCredentialMode.session);
      expect(await manager.storage, same(original));
      expect(calls, ['initialize']);
    },
  );
  test(
    'local macOS platform probe uses the file keychain and verifies read-back before deletion',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? saved;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (c) async {
        final args = (c.arguments as Map);
        expect((args['options'] as Map)['useDataProtectionKeyChain'], 'false');
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
      await PlatformSecureStorage(
        useDataProtectionKeyChain: false,
      ).verifyAvailable();
      expect(calls, ['write', 'read', 'delete']);
      expect(saved, isNull);
    },
  );
}
