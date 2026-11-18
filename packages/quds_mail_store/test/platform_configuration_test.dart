import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/src/errors.dart';
import 'package:quds_mail_store/src/platform_configuration.dart';
import 'package:test/test.dart';

void main() {
  test(
    'database identity separates hosts, profiles and browser namespaces',
    () {
      final a = MailProfileId('bc', hostId: 'a');
      final b = MailProfileId('c', hostId: 'ab');
      expect(mailStoreNamespace(a), hasLength(64));
      expect(mailStoreNamespace(a), matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(mailStoreNamespace(a), isNot(mailStoreNamespace(b)));
      expect(
        mailStoreNamespace(a, namespace: 'office'),
        isNot(mailStoreNamespace(a, namespace: 'cloud')),
      );
      expect(
        mailStoreNamespace(a),
        isNot(mailStoreNamespace(MailProfileId('another', hostId: 'a'))),
      );
    },
  );

  test('browser namespaces are explicit and bounded', () {
    final profile = MailProfileId('profile', hostId: 'office');
    for (final namespace in ['', 'x' * 257]) {
      expect(
        () => mailStoreNamespace(profile, namespace: namespace),
        throwsA(
          isA<MailStoreStorageException>().having(
            (e) => e.code,
            'code',
            MailProblemCode.invalidInput,
          ),
        ),
      );
    }
  });

  test('relative and absolute same-origin assets resolve explicitly', () {
    final base = Uri.parse('https://mail.example.test/app/index.html');
    expect(
      mailStoreAssetUri(Uri.parse('sqlite3.wasm'), baseUri: base),
      Uri.parse('https://mail.example.test/app/sqlite3.wasm'),
    );
    expect(
      mailStoreAssetUri(
        Uri.parse('https://mail.example.test:443/assets/worker.js'),
        baseUri: base,
      ),
      Uri.parse('https://mail.example.test/assets/worker.js'),
    );
  });

  test('assets reject remote origins, credentials, fragments and non-HTTP', () {
    final base = Uri.parse('https://mail.example.test/app/');
    for (final value in [
      'https://cdn.example.test/sqlite3.wasm',
      'http://mail.example.test/sqlite3.wasm',
      'https://mail.example.test:444/sqlite3.wasm',
      'https://secret@mail.example.test/sqlite3.wasm',
      'data:application/wasm;base64,AA==',
      'file:///sqlite3.wasm',
      '/sqlite3.wasm#fragment',
      '/assets/',
    ]) {
      expect(
        () => mailStoreAssetUri(Uri.parse(value), baseUri: base),
        throwsA(isA<MailStoreStorageException>()),
        reason: 'Rejected asset must never trigger a fetch.',
      );
    }
    expect(
      () => mailStoreAssetUri(
        Uri.parse('sqlite3.wasm'),
        baseUri: Uri.parse('file:///app/index.html'),
      ),
      throwsA(isA<MailStoreStorageException>()),
    );
  });
}
