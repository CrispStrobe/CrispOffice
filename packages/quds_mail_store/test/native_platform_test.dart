@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:test/test.dart';

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

MailProblemCode _code<T>(MailResult<T> result) {
  expect(result, isA<MailFailure<T>>());
  return (result as MailFailure<T>).problem.code;
}

void main() {
  late Directory directory;
  final profile = MailProfileId('profile', hostId: 'office');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quds-mail-native-');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('native committed accounts survive close and reopen', () async {
    final first = _value(
      await openNativeMailStore(appDirectory: directory, profile: profile),
    );
    final account = MailAccountId('account', profile: profile);
    _value(
      await first.createAccount(
        MailStoreAccount(
          id: account,
          provider: MailProviderKind.imap,
          displayName: 'A saved account',
          credentialReference: 'vault-reference-only',
        ),
      ),
    );
    await first.close();
    final second = _value(
      await openNativeMailStore(appDirectory: directory, profile: profile),
    );
    try {
      final accounts = _value(await second.listAccounts());
      expect(accounts.single.id, account);
      expect(accounts.single.displayName, 'A saved account');
      expect(accounts.single.credentialReference, 'vault-reference-only');
    } finally {
      await second.close();
    }
  });

  test(
    'a second live owner conflicts; a closed owner releases its lease',
    () async {
      final first = _value(
        await openNativeMailStore(appDirectory: directory, profile: profile),
      );
      expect(
        _code(
          await openNativeMailStore(appDirectory: directory, profile: profile),
        ),
        MailProblemCode.conflict,
      );
      await first.close();
      await first.close();
      final reopened = _value(
        await openNativeMailStore(appDirectory: directory, profile: profile),
      );
      await reopened.close();
    },
  );

  test(
    'same profile names in different hosts use separate containers',
    () async {
      final a = _value(
        await openNativeMailStore(appDirectory: directory, profile: profile),
      );
      final other = MailProfileId(profile.value, hostId: 'crispcloud');
      final b = _value(
        await openNativeMailStore(appDirectory: directory, profile: other),
      );
      try {
        _value(
          await a.createAccount(
            MailStoreAccount(
              id: MailAccountId('same-id', profile: profile),
              provider: MailProviderKind.local,
              displayName: 'Office only',
            ),
          ),
        );
        expect(_value(await b.listAccounts()), isEmpty);
        final databases = await directory
            .list(recursive: true)
            .where((entry) => p.basename(entry.path) == 'mail.sqlite3')
            .toList();
        expect(databases, hasLength(2));
      } finally {
        await a.close();
        await b.close();
      }
    },
  );

  test(
    'migration failure releases ownership and rolls back before reopening',
    () async {
      final failed = await openNativeMailStore(
        appDirectory: directory,
        profile: profile,
        faultInjector: (checkpoint) {
          if (checkpoint == MailStoreCheckpoint.migrationCreated) {
            throw const MailStoreStorageException(
              MailProblemCode.quotaExceeded,
            );
          }
        },
      );
      expect(_code(failed), MailProblemCode.quotaExceeded);
      final reopened = _value(
        await openNativeMailStore(appDirectory: directory, profile: profile),
      );
      expect(_value(await reopened.listAccounts()), isEmpty);
      await reopened.close();
    },
  );

  test(
    'a relative container is rejected without choosing a global directory',
    () async {
      expect(
        _code(
          await openNativeMailStore(
            appDirectory: Directory('relative-container'),
            profile: profile,
          ),
        ),
        MailProblemCode.invalidInput,
      );
      expect(Directory('relative-container').existsSync(), isFalse);
    },
  );

  test('an unavailable app container returns a typed failure', () async {
    final blocked = File(p.join(directory.path, 'file-instead-of-directory'));
    await blocked.writeAsString('fixture');
    expect(
      _code(
        await openNativeMailStore(
          appDirectory: Directory(blocked.path),
          profile: profile,
        ),
      ),
      MailProblemCode.unavailable,
    );
  });

  test(
    'process termination releases ownership and preserves committed data',
    () async {
      final library = await Isolate.resolvePackageUri(
        Uri.parse('package:quds_mail_store/quds_mail_store_native.dart'),
      );
      final package = File.fromUri(library!).parent.parent;
      final dart = p.join(p.dirname(Platform.resolvedExecutable), 'dart');
      final process = await Process.start(dart, [
        'run',
        p.join(package.path, 'tool/native_crash_fixture.dart'),
        directory.path,
      ], workingDirectory: package.path);
      final errors = process.stderr.transform(utf8.decoder).join();
      try {
        final ready = await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .firstWhere((line) => line == 'READY')
            .timeout(const Duration(seconds: 45));
        expect(ready, 'READY');
        expect(
          _code(
            await openNativeMailStore(
              appDirectory: directory,
              profile: profile,
            ),
          ),
          MailProblemCode.conflict,
        );
        expect(process.kill(ProcessSignal.sigkill), isTrue);
        await process.exitCode.timeout(const Duration(seconds: 10));
        final reopened = _value(
          await openNativeMailStore(appDirectory: directory, profile: profile),
        );
        try {
          expect(
            _value(await reopened.listAccounts()).single.displayName,
            'Crash checkpoint',
          );
        } finally {
          await reopened.close();
        }
      } finally {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        await errors;
      }
    },
    timeout: const Timeout(Duration(seconds: 75)),
  );
}
