import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/credentials/secure_storage_file_io.dart';
import 'package:quds_office_studio/credentials/secure_storage_service.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';

StudioMailCredentials account(String email) => StudioMailCredentials(
  email: email,
  password: 'synthetic-test-password',
  imapHost: 'imap.example.test',
  smtpHost: 'smtp.example.test',
  manual: true,
  startTls: false,
);

class FailingStorage extends InMemorySecureStorage {
  bool fail = false;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('Unavailable selected store');
    await super.write(key, value);
  }
}

void main() {
  test(
    'independent accounts survive a new repository and forgetting one preserves the other',
    () async {
      final storage = InMemorySecureStorage();
      final repo = StudioMailCredentialStore(backend: () async => storage);
      final first = account('first@example.test'),
          second = account('second@example.test');
      expect(await repo.save(first), isTrue);
      expect(await repo.save(second), isTrue);
      final reopened = StudioMailCredentialStore(backend: () async => storage);
      expect(
        (await (reopened as StudioMailAccountCatalogStore).loadAccounts())
            .catalog!
            .accounts
            .map((c) => c.credentials.email),
        [first.email, second.email],
      );
      expect((await reopened.load())!.email, second.email);
      await (reopened as StudioMailAccountCatalogStore).selectAccount(
        first.accountId,
      );
      expect(await reopened.clear(), isTrue);
      expect(
        (await (reopened as StudioMailAccountCatalogStore).loadAccounts())
            .catalog!
            .accounts
            .single
            .credentials
            .email,
        second.email,
      );
      expect((await reopened.load())!.email, second.email);
    },
  );
  test(
    'a failed selected-store write preserves previously saved accounts',
    () async {
      final storage = FailingStorage();
      final repo = StudioMailCredentialStore(backend: () async => storage);
      expect(await repo.save(account('first@example.test')), isTrue);
      storage.fail = true;
      expect(await repo.save(account('second@example.test')), isFalse);
      expect(
        (await (repo as StudioMailAccountCatalogStore).loadAccounts())
            .catalog!
            .accounts
            .single
            .credentials
            .email,
        'first@example.test',
      );
    },
  );
  test(
    'encrypted vault persists two accounts, rejects a wrong password and never stores their plaintext',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'crispoffice-vault-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/vault.json');
      final vault = EncryptedFileStorage(file);
      await vault.initialize(
        'synthetic-master-password',
        expectedExisting: false,
      );
      final repo = StudioMailCredentialStore(backend: () async => vault);
      expect(await repo.save(account('first@example.test')), isTrue);
      expect(await repo.save(account('second@example.test')), isTrue);
      final ciphertext = await file.readAsBytes();
      expect(
        await file.readAsString(),
        isNot(contains('synthetic-test-password')),
      );
      expect(await file.readAsString(), isNot(contains('first@example.test')));
      final wrong = EncryptedFileStorage(file);
      await expectLater(
        wrong.initialize('wrong-password', expectedExisting: true),
        throwsA(anything),
      );
      expect(await file.readAsBytes(), ciphertext);
      final reopened = EncryptedFileStorage(file);
      await reopened.initialize(
        'synthetic-master-password',
        expectedExisting: true,
      );
      expect(
        (await (StudioMailCredentialStore(backend: () async => reopened)
                    as StudioMailAccountCatalogStore)
                .loadAccounts())
            .catalog!
            .accounts
            .length,
        2,
      );
      if (!Platform.isWindows) expect((await file.stat()).mode & 0x1ff, 0x180);
    },
  );
}
