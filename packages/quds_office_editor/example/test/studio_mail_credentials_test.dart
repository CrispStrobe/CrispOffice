import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';

const _credentials = StudioMailCredentials(
  email: 'reader@example.invalid',
  password: 'fixture-only-password',
  imapHost: 'imap.example.invalid',
  smtpHost: 'smtp.example.invalid',
  manual: true,
  startTls: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StudioMailCredentialStore store;
  late Map<String, String> records;
  late List<String> calls;
  Future<void> Function()? beforeWrite;
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

  setUp(() {
    store = StudioMailCredentialStore();
    records = {};
    calls = [];
    beforeWrite = null;
    failRead = failWrite = failDelete = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      final args = (call.arguments as Map).cast<String, Object?>();
      final key = args['key']! as String;
      switch (call.method) {
        case 'read':
          if (failRead) {
            throw PlatformException(code: 'locked', message: 'private read');
          }
          return records[key];
        case 'write':
          await beforeWrite?.call();
          if (failWrite) {
            throw PlatformException(code: 'locked', message: 'private write');
          }
          records[key] = args['value']! as String;
          return null;
        case 'delete':
          if (failDelete) {
            throw PlatformException(code: 'locked', message: 'private delete');
          }
          records.remove(key);
          return null;
        default:
          throw StateError('Unexpected keychain operation: ${call.method}');
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'the platform record round-trips credentials and TLS settings',
    () async {
      expect(await store.load(), isNull);
      expect(await store.save(_credentials), isTrue);
      expect(records, hasLength(1));
      expect((await store.load())!.toJson(), _credentials.toJson());
      expect(await store.clear(), isTrue);
      expect(records, isEmpty);
      expect(await store.load(), isNull);
    },
  );

  test('malformed or unreadable platform records are unavailable', () async {
    await store.save(_credentials);
    final key = records.keys.single;
    for (final raw in [
      '{',
      '[]',
      jsonEncode({..._credentials.toJson(), 'password': 42}),
    ]) {
      records[key] = raw;
      expect(await store.load(), isNull);
    }
    failRead = true;
    expect(await store.load(), isNull);
  });

  test(
    'failed writes and deletions report failure and preserve the record',
    () async {
      expect(await store.save(_credentials), isTrue);
      final original = Map<String, String>.of(records);
      failWrite = true;
      expect(await store.save(_credentials), isFalse);
      expect(records, original);
      failDelete = true;
      expect(await store.clear(), isFalse);
      expect(records, original);
      failDelete = false;
      expect(await store.clear(), isTrue);
      expect(records, isEmpty);
    },
  );

  test(
    'a later delete waits for a pending write and cannot be undone by it',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      beforeWrite = () {
        started.complete();
        return release.future;
      };
      final writing = store.save(_credentials);
      final deleting = store.clear();
      await started.future;
      expect(calls, ['write']);
      release.complete();
      expect(await writing, isTrue);
      expect(await deleting, isTrue);
      expect(calls, ['write', 'delete']);
      expect(records, isEmpty);
      expect(await store.load(), isNull);
    },
  );

  test(
    'a failed operation does not prevent the next queued operation',
    () async {
      failWrite = true;
      final writing = store.save(_credentials);
      final deleting = store.clear();
      expect(await writing, isFalse);
      expect(await deleting, isTrue);
      expect(calls, ['write', 'delete']);
      failWrite = false;
      expect(await store.save(_credentials), isTrue);
      expect((await store.load())!.email, _credentials.email);
    },
  );
}
