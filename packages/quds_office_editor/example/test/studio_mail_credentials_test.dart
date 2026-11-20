import 'dart:async';
import 'dart:convert';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_presets.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_draft_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _saved = StudioMailCredentials(
  email: 'old@example.test',
  password: 'saved-password',
  imapHost: 'imap.example.test',
  smtpHost: 'smtp.example.test',
  manual: true,
  startTls: false,
);

final class _Storage extends Fake implements FlutterSecureStorage {
  final records = <String, String>{};
  String? get raw => records['crispoffice.mail.account.v1'];
  set raw(String? value) {
    if (value == null) {
      records.remove('crispoffice.mail.account.v1');
    } else {
      records['crispoffice.mail.account.v1'] = value;
    }
  }

  bool readFails = false;
  bool writeFails = false;
  bool deleteFails = false;
  Completer<void>? writeGate;
  final calls = <String>[];
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('read');
    if (readFails) throw StateError('private-keychain-error');
    return records[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('write');
    if (writeGate != null) await writeGate!.future;
    if (writeFails) throw StateError('private-keychain-error');
    records[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('delete');
    if (deleteFails) throw StateError('private-keychain-error');
    records.remove(key);
  }
}

final class _Store extends Fake implements StudioMailCredentialStore {
  StudioMailCredentials? initial;
  Completer<StudioMailCredentials?>? loadGate;
  Completer<bool>? saveGate;
  Completer<bool>? clearGate;
  bool savesSucceed = true;
  bool clearsSucceed = true;
  final saved = <StudioMailCredentials>[];
  int clears = 0;
  @override
  Future<StudioMailCredentials?> load() async =>
      loadGate == null ? initial : await loadGate!.future;
  @override
  Future<bool> save(StudioMailCredentials value) async {
    saved.add(value);
    return saveGate == null ? savesSucceed : await saveGate!.future;
  }

  @override
  Future<bool> clear() async {
    clears++;
    return clearGate == null ? clearsSucceed : await clearGate!.future;
  }
}

final class _Loader extends Fake implements StudioMailMessageLoader {
  int disposes = 0;
  @override
  void dispose() => disposes++;
  @override
  void cancel() {}
}

final class _Client extends Fake implements mail.MailClient {
  final inbox = mail.Mailbox(
    encodedName: 'INBOX',
    encodedPath: 'INBOX',
    flags: [mail.MailboxFlag.inbox],
    pathSeparator: '/',
    uidValidity: 7,
    uidNext: 1,
  );
  Object? failure;
  Completer<void>? connectGate;
  int connects = 0;
  int disconnects = 0;
  @override
  mail.Mailbox get selectedMailbox => inbox;
  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 20)}) async {
    connects++;
    if (connectGate != null) await connectGate!.future;
    if (failure case final error?) throw error;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async => [inbox];
  @override
  Future<List<mail.MimeMessage>> fetchMessages({
    mail.Mailbox? mailbox,
    int count = 20,
    int page = 1,
    mail.FetchPreference fetchPreference =
        mail.FetchPreference.fullWhenWithinSize,
  }) async => [];
}

Finder _input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Finder _key(String value) => find.byKey(ValueKey(value));
Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _show(
  WidgetTester tester,
  _Store store, {
  mail.MailClient Function(mail.MailAccount)? client,
  StudioMailMessageLoader? loader,
  Future<mail.ClientConfig?> Function(String)? discovery,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        draftStoreFactory: MemoryStudioMailDrafts().open,
        strings: _strings,
        credentialStore: store,
        clientFactory: client ?? (_) => _Client(),
        accountDiscovery: discovery,
        messageLoaderFactory: (_) => loader ?? _Loader(),
      ),
    ),
  );
  await _pump(tester);
}

Future<void> _preset(WidgetTester tester, String name) async {
  await tester.ensureVisible(_key('studio-mail-provider-preset'));
  await tester.tap(_key('studio-mail-provider-preset'));
  await _pump(tester);
  await tester.tap(find.text(name).last);
  await _pump(tester);
}

Future<void> _connectPreset(
  WidgetTester tester, {
  String email = 'reader@yahoo.com',
  String preset = 'Yahoo Mail',
}) async {
  await _preset(tester, preset);
  await tester.enterText(_input(_strings.emailAddress), email);
  await tester.enterText(_input(_strings.mailAppPassword), 'new-app-password');
  final connect = find.widgetWithText(FilledButton, _strings.connect);
  await tester.ensureVisible(connect);
  await tester.tap(connect);
  await _pump(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _registerPlatformCredentialTests();
  test(
    'old keychain records remain readable and new preset settings round trip',
    () {
      final old = Map<String, Object?>.from(_saved.toJson())
        ..remove('preset')
        ..remove('primaryLogin')
        ..remove('icloudFullAddressLogin');
      expect(StudioMailCredentials.fromJson(old)!.email, _saved.email);
      const preset = StudioMailCredentials(
        email: 'alias@example.test',
        password: 'app-password',
        imapHost: 'imap.mail.me.com',
        smtpHost: 'smtp.mail.me.com',
        manual: false,
        startTls: false,
        preset: StudioMailImapPreset.icloud,
        primaryLogin: 'primary@icloud.com',
        icloudFullAddressLogin: true,
      );
      final copy = StudioMailCredentials.fromJson(preset.toJson())!;
      expect(copy.preset, StudioMailImapPreset.icloud);
      expect(copy.primaryLogin, 'primary@icloud.com');
      expect(copy.icloudFullAddressLogin, isTrue);
      expect(copy.toString(), isNot(contains('app-password')));
      expect(copy.toString(), isNot(contains('alias@')));
    },
  );

  test(
    'invalid persisted values cannot silently select security or provider settings',
    () {
      for (final replacement in <String, Object?>{
        'email': 'invalid',
        'password': 'private\r\n',
        'imapHost': 'https://unsafe host',
        'manual': 'true',
        'startTls': 1,
        'preset': 'unrecognized',
        'primaryLogin': 'invalid',
        'icloudFullAddressLogin': 'true',
      }.entries) {
        expect(
          StudioMailCredentials.fromJson({
            ..._saved.toJson(),
            replacement.key: replacement.value,
          }),
          isNull,
          reason: replacement.key,
        );
      }
    },
  );

  test(
    'platform keychain failures report failed save and clear without erasing prior values',
    () async {
      final storage = _Storage()..raw = jsonEncode(_saved.toJson());
      final store = StudioMailCredentialStore(storage: storage);
      storage.writeFails = true;
      expect(await store.save(_saved), isFalse);
      storage.deleteFails = true;
      expect(await store.clear(), isFalse);
      expect(storage.raw, jsonEncode(_saved.toJson()));
      storage.writeFails = storage.deleteFails = false;
      expect((await store.load())!.password, _saved.password);
      storage.readFails = true;
      expect(await store.load(), isNull);
    },
  );

  test('malformed or excessive keychain records fail closed', () async {
    final storage = _Storage();
    final store = StudioMailCredentialStore(storage: storage);
    for (final raw in [
      '{bad json',
      '[]',
      jsonEncode({'email': 'reader@example.test'}),
      'x' * (256 * 1024 + 1),
    ]) {
      storage.raw = raw;
      expect(await store.load(), isNull);
    }
  });

  test(
    'a later Forget waits for an older write across store instances',
    () async {
      final storage = _Storage()..writeGate = Completer<void>();
      final first = StudioMailCredentialStore(storage: storage);
      final second = StudioMailCredentialStore(storage: storage);
      final saving = first.save(_saved);
      await Future<void>.delayed(Duration.zero);
      final clearing = second.clear();
      await Future<void>.delayed(Duration.zero);
      expect(storage.calls, ['read', 'read', 'write']);
      storage.writeGate!.complete();
      expect(await saving, isTrue);
      expect(await clearing, isTrue);
      expect(storage.calls, [
        'read',
        'read',
        'write',
        'read', // Verify the written catalog before proceeding.
        'read',
        'delete',
        'write',
        'read', // Verify the cleared selected-account catalog.
      ]);
      expect(storage.raw, isNull);
      expect(storage.records.keys, ['crispoffice.mail.accounts.v2']);
      expect(await second.load(), isNull);
    },
  );

  test(
    'failed platform writes do not poison later keychain operations',
    () async {
      final storage = _Storage()..writeFails = true;
      final store = StudioMailCredentialStore(storage: storage);
      expect(await store.save(_saved), isFalse);
      storage.writeFails = false;
      expect(await store.save(_saved), isTrue);
      expect((await store.load())!.email, _saved.email);
      expect(await store.clear(), isTrue);
      expect(await store.load(), isNull);
    },
  );

  testWidgets(
    'late keychain load cannot replace newly typed account settings',
    (tester) async {
      final store = _Store()..loadGate = Completer<StudioMailCredentials?>();
      await _show(tester, store);
      await tester.enterText(_input(_strings.emailAddress), 'new@example.test');
      store.loadGate!.complete(_saved);
      await _pump(tester);
      expect(
        tester
            .widget<TextField>(_input(_strings.emailAddress))
            .controller!
            .text,
        'new@example.test',
      );
      expect(
        tester.widget<TextField>(_input(_strings.password)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets('late keychain load cannot undo a newly selected provider', (
    tester,
  ) async {
    final store = _Store()..loadGate = Completer<StudioMailCredentials?>();
    await _show(tester, store);
    await _preset(tester, 'Yahoo Mail');
    store.loadGate!.complete(_saved);
    await _pump(tester);
    expect(find.text('Yahoo Mail'), findsOneWidget);
    expect(_input(_strings.mailAppPassword), findsOneWidget);
    expect(
      tester.widget<TextField>(_input(_strings.emailAddress)).controller!.text,
      isEmpty,
    );
  });

  testWidgets(
    'remembered iCloud settings restore the visible preset and login mode',
    (tester) async {
      final store = _Store()
        ..initial = const StudioMailCredentials(
          email: 'alias@example.test',
          password: 'app-password',
          imapHost: 'imap.mail.me.com',
          smtpHost: 'smtp.mail.me.com',
          manual: false,
          startTls: false,
          preset: StudioMailImapPreset.icloud,
          primaryLogin: 'primary@icloud.com',
          icloudFullAddressLogin: true,
        );
      await _show(tester, store);
      expect(find.text('iCloud Mail'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(_key('studio-mail-icloud-full-login'))
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(_input(_strings.mailPrimaryLogin))
            .controller!
            .text,
        'primary@icloud.com',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keychain save failure retains the connected mailbox and reports fixed feedback',
    (tester) async {
      final store = _Store()..savesSucceed = false;
      await _show(tester, store);
      await _connectPreset(tester);
      expect(store.saved.single.preset, StudioMailImapPreset.yahoo);
      expect(find.byTooltip(_strings.disconnect), findsOneWidget);
      expect(find.text(_strings.mailKeychainSaveFailed), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final clearsSucceed in [true, false]) {
    testWidgets(
      'Remember opt-out clears the old account and reports ${clearsSucceed ? 'success' : 'failure'} accurately',
      (tester) async {
        final store = _Store()
          ..initial = _saved
          ..clearsSucceed = clearsSucceed;
        await _show(tester, store);
        await tester.ensureVisible(_key('studio-mail-remember'));
        await tester.tap(_key('studio-mail-remember'));
        await _pump(tester);
        expect(store.clears, 0);
        await _connectPreset(tester);
        expect(store.saved, isEmpty);
        expect(store.clears, 1);
        expect(find.byTooltip(_strings.disconnect), findsOneWidget);
        expect(
          find.text(_strings.mailKeychainClearFailed),
          clearsSucceed ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed Forget preserves filled credentials and remains retryable',
    (tester) async {
      final store = _Store()
        ..initial = _saved
        ..clearsSucceed = false;
      await _show(tester, store);
      await tester.ensureVisible(_key('studio-mail-forget'));
      await tester.tap(_key('studio-mail-forget'));
      await _pump(tester);
      expect(find.text(_strings.mailKeychainClearFailed), findsOneWidget);
      expect(
        tester.widget<TextField>(_input(_strings.password)).controller!.text,
        _saved.password,
      );
      store.clearsSucceed = true;
      await tester.tap(_key('studio-mail-forget'));
      await _pump(tester);
      expect(store.clears, 2);
      expect(find.text(_strings.mailKeychainClearFailed), findsNothing);
      expect(
        tester.widget<TextField>(_input(_strings.password)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets('late Forget failure cannot replace newer provider feedback', (
    tester,
  ) async {
    final store = _Store()
      ..initial = _saved
      ..clearGate = Completer<bool>();
    await _show(tester, store);
    await tester.ensureVisible(_key('studio-mail-forget'));
    await tester.tap(_key('studio-mail-forget'));
    await _pump(tester);
    await _preset(tester, 'Fastmail');
    store.clearGate!.complete(false);
    await _pump(tester);
    expect(find.text('Fastmail'), findsOneWidget);
    expect(find.text(_strings.mailKeychainClearFailed), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late Forget failure cannot overwrite a newer successful remembered session',
    (tester) async {
      final store = _Store()
        ..initial = _saved
        ..clearGate = Completer<bool>();
      await _show(tester, store);
      await tester.ensureVisible(_key('studio-mail-forget'));
      await tester.tap(_key('studio-mail-forget'));
      await _pump(tester);
      await _connectPreset(tester);
      store.clearGate!.complete(false);
      await _pump(tester);
      expect(store.saved.single.email, 'reader@yahoo.com');
      expect(find.text(_strings.mailKeychainClearFailed), findsNothing);
      expect(find.byTooltip(_strings.disconnect), findsOneWidget);
    },
  );

  testWidgets('late saved-account completion cannot undo a newer Forget', (
    tester,
  ) async {
    final store = _Store()..saveGate = Completer<bool>();
    await _show(tester, store);
    await _connectPreset(tester);
    await tester.tap(find.byTooltip(_strings.disconnect));
    await _pump(tester);
    await tester.ensureVisible(_key('studio-mail-forget'));
    await tester.tap(_key('studio-mail-forget'));
    await _pump(tester);
    store.saveGate!.complete(true);
    await _pump(tester);
    expect(store.clears, 1);
    expect(
      tester
          .widget<TextField>(_input(_strings.mailAppPassword))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing while saving cannot update the disposed dialog', (
    tester,
  ) async {
    final store = _Store()..saveGate = Completer<bool>();
    final client = _Client();
    final loader = _Loader();
    await _show(tester, store, client: (_) => client, loader: loader);
    await _connectPreset(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    store.saveGate!.complete(false);
    await _pump(tester);
    expect(client.disconnects, 1);
    expect(loader.disposes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'explicit manual STARTTLS is honored without automatic authentication retry',
    (tester) async {
      final store = _Store();
      final accounts = <mail.MailAccount>[];
      await _show(
        tester,
        store,
        client: (account) {
          accounts.add(account);
          return _Client()..failure = StateError('private-auth-error');
        },
      );
      await tester.enterText(
        _input(_strings.emailAddress),
        'reader@example.test',
      );
      await tester.enterText(_input(_strings.password), 'password');
      await tester.tap(find.text(_strings.manualServers));
      await _pump(tester);
      await tester.enterText(_input(_strings.imapHost), 'imap.example.test');
      await tester.enterText(_input(_strings.smtpHost), 'smtp.example.test');
      await tester.ensureVisible(_key('studio-mail-starttls'));
      await tester.tap(_key('studio-mail-starttls'));
      await _pump(tester);
      final connect = find.widgetWithText(FilledButton, _strings.connect);
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await _pump(tester);
      expect(accounts, hasLength(1));
      expect(accounts.single.incoming.serverConfig.port, 143);
      expect(accounts.single.outgoing.serverConfig.port, 587);
      expect(
        accounts.single.incoming.serverConfig.socketType,
        mail.SocketType.starttls,
      );
      expect(find.textContaining('private-auth-error'), findsNothing);
      expect(store.saved, isEmpty);
    },
  );

  for (final preset in StudioMailImapPreset.values) {
    testWidgets(
      '${preset.label} authentication failures never switch fixed transport settings',
      (tester) async {
        final accounts = <mail.MailAccount>[];
        await _show(
          tester,
          _Store(),
          client: (account) {
            accounts.add(account);
            return _Client()..failure = StateError('authentication rejected');
          },
        );
        await _connectPreset(
          tester,
          preset: preset.label,
          email: 'reader@example.test',
        );
        expect(accounts, hasLength(1));
        expect(accounts.single.incoming.serverConfig.port, 993);
        expect(accounts.single.outgoing.serverConfig.port, preset.smtpPort);
        expect(
          accounts.single.incoming.serverConfig.socketType,
          mail.SocketType.ssl,
        );
        expect(
          accounts.single.outgoing.serverConfig.socketType,
          preset.smtpSocketType,
        );
      },
    );
  }

  testWidgets(
    'closing an in-flight failed connection never creates a fallback client',
    (tester) async {
      final gate = Completer<void>();
      var clients = 0;
      final client = _Client()..connectGate = gate;
      await _show(
        tester,
        _Store(),
        client: (_) {
          clients++;
          return client;
        },
      );
      await _connectPreset(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      gate.completeError(StateError('late connection error'));
      await _pump(tester);
      expect(clients, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mailbox.org keeps its known verified STARTTLS route without discovery',
    (tester) async {
      final accounts = <mail.MailAccount>[];
      final store = _Store();
      var discoveries = 0;
      await _show(
        tester,
        store,
        client: (account) {
          accounts.add(account);
          return _Client();
        },
        discovery: (_) async {
          discoveries++;
          return null;
        },
      );
      await tester.enterText(
        _input(_strings.emailAddress),
        'reader@mailbox.org',
      );
      await tester.enterText(_input(_strings.password), 'password');
      final connect = find.widgetWithText(FilledButton, _strings.connect);
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await _pump(tester);
      expect(discoveries, 0);
      expect(
        accounts.single.incoming.serverConfig.hostname,
        'imap.mailbox.org',
      );
      expect(accounts.single.incoming.serverConfig.port, 143);
      expect(accounts.single.outgoing.serverConfig.port, 587);
      expect(store.saved.single.startTls, isTrue);
      expect(store.saved.single.manual, isTrue);
    },
  );
}

const _credentials = StudioMailCredentials(
  email: 'reader@example.invalid',
  password: 'fixture-only-password',
  imapHost: 'imap.example.invalid',
  smtpHost: 'smtp.example.invalid',
  manual: true,
  startTls: true,
);

void _registerPlatformCredentialTests() {
  group('platform keychain boundary', () {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
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
      store = StudioMailCredentialStore(storage: const FlutterSecureStorage());
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
              throw PlatformException(
                code: 'locked',
                message: 'private delete',
              );
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
        expect(records.keys, ['crispoffice.mail.accounts.v2']);
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
        failWrite = false;
        expect(await store.clear(), isTrue);
        expect(records.keys, ['crispoffice.mail.accounts.v2']);
        expect(await store.load(), isNull);
      },
    );

    test(
      'a later delete waits for a pending write and cannot be undone by it',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        beforeWrite = () {
          if (!started.isCompleted) started.complete();
          return release.future;
        };
        final writing = store.save(_credentials);
        final deleting = store.clear();
        await started.future;
        expect(calls, ['read', 'read', 'write']);
        release.complete();
        expect(await writing, isTrue);
        expect(await deleting, isTrue);
        expect(calls, [
          'read',
          'read',
          'write',
          'read',
          'read',
          'delete',
          'write',
          'read',
        ]);
        expect(records.keys, ['crispoffice.mail.accounts.v2']);
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
        expect(await deleting, isFalse);
        expect(calls, ['read', 'read', 'write', 'read', 'read', 'write']);
        failWrite = false;
        expect(await store.save(_credentials), isTrue);
        expect((await store.load())!.email, _credentials.email);
      },
    );
  });
}
