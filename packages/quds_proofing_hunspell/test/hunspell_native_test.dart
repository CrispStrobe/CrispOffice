@TestOn('vm')
library;

import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/installer_io.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:test/test.dart';

OfficeProofingRequest _request(String text) => OfficeProofingRequest(
  documentId: 'd',
  blockId: 'b',
  revision: 1,
  text: text,
  language: 'ar',
);

void main() {
  test(
    'missing native library is unavailable without isolate errors',
    () async {
      final provider = HunspellProofingProvider(
        bundle: ayaspellArabic,
        dictionary: const HunspellDictionaryFiles(affPath: 'a', dicPath: 'd'),
        nativeLibraryPath: '/missing/quds_hunspell_library',
      );
      final result = await provider.check(_request('الى'));
      expect(result.status, OfficeProofingStatus.unavailable);
      final repeated = await provider
          .check(result.request)
          .timeout(const Duration(seconds: 2));
      expect(repeated.status, OfficeProofingStatus.unavailable);
      await provider.dispose();
    },
  );

  final library = Platform.environment['QUDS_HUNSPELL_TEST_LIBRARY'];
  final dictionary = Platform.environment['QUDS_HUNSPELL_TEST_DICTIONARY'];
  final skip = library == null || dictionary == null
      ? 'Set QUDS_HUNSPELL_TEST_LIBRARY and QUDS_HUNSPELL_TEST_DICTIONARY '
            '(directory holding the verified AyaSpell bundle).'
      : false;

  group('real library and AyaSpell', () {
    late HunspellProofingProvider provider;
    setUp(() {
      provider = HunspellProofingProvider(
        bundle: ayaspellArabic,
        dictionary: HunspellDictionaryFiles(
          affPath: '$dictionary/ar.aff',
          dicPath: '$dictionary/ar.dic',
        ),
        nativeLibraryPath: library,
      );
    });
    tearDown(() => provider.dispose());

    test('known corrections come first', () async {
      const text = 'ذهبت البنت الى المدرسه وقالت هاذا جميل';
      final result = await provider.check(_request(text));
      expect(result.status, OfficeProofingStatus.success);
      final byWord = {for (final f in result.findings) f.originalText: f};
      expect(byWord.keys.toSet(), {'الى', 'المدرسه', 'هاذا'});
      expect(byWord['الى']!.replacements.first, 'إلى');
      expect(byWord['المدرسه']!.replacements.first, 'المدرسة');
      expect(byWord['هاذا']!.replacements, contains('هذا'));
      for (final finding in result.findings) {
        expect(
          text.substring(finding.start, finding.end),
          finding.originalText,
        );
      }
    });

    test(
      'harakat and tatweel are ignored by the dictionary, offsets kept',
      () async {
        const text = 'كَتَبَ الطالـــبُ الدرسَ في المدرسةِ';
        final result = await provider.check(_request(text));
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty);
        final wrong = await provider.check(_request('ذهبَ الَى'));
        expect(wrong.findings.single.originalText, 'الَى');
        expect(wrong.findings.single.start, 5);
      },
    );

    test('personal vocabulary suppresses a name', () async {
      final vocabulary = OfficeProofingVocabulary()
        ..addWord('ترامب', language: 'ar');
      final named = HunspellProofingProvider(
        bundle: ayaspellArabic,
        dictionary: HunspellDictionaryFiles(
          affPath: '$dictionary/ar.aff',
          dicPath: '$dictionary/ar.dic',
        ),
        nativeLibraryPath: library,
        vocabulary: vocabulary,
      );
      final before = await provider.check(_request('قال ترامب'));
      expect(before.findings.single.originalText, 'ترامب');
      final after = await named.check(_request('قال ترامب'));
      expect(after.findings, isEmpty);
      await named.dispose();
    });

    test('a non-UTF-8 or missing dictionary is unavailable', () async {
      final missing = HunspellProofingProvider(
        bundle: ayaspellArabic,
        dictionary: const HunspellDictionaryFiles(
          affPath: '/missing/ar.aff',
          dicPath: '/missing/ar.dic',
        ),
        nativeLibraryPath: library,
      );
      final result = await missing.check(_request('الى'));
      expect(result.status, OfficeProofingStatus.unavailable);
      await missing.dispose();
    });
  }, skip: skip);

  group('installer', () {
    late Directory root;
    late HttpServer server;
    final served = <String, List<int>>{};
    setUp(() async {
      root = Directory.systemTemp.createTempSync('hunspell-install-');
      for (final artifact in ayaspellArabic.files) {
        served[artifact.file] = File(
          '$dictionary/${artifact.file}',
        ).readAsBytesSync();
      }
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        final name = request.uri.pathSegments.last;
        final body = served[name];
        request.response.statusCode = body == null ? 404 : 200;
        if (body != null) request.response.add(body);
        request.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      root.deleteSync(recursive: true);
    });

    HunspellInstaller installer() => HunspellInstaller(
      root,
      resolveUrl: (bundle, artifact) =>
          Uri.http('127.0.0.1:${server.port}', '/${artifact.file}'),
    );

    test('installs, verifies, reuses and removes the pinned bundle', () async {
      final progress = <int>[];
      final files = await installer().install(
        ayaspellArabic,
        onProgress: (received, total) => progress.add(received),
      );
      expect(File(files.affPath).existsSync(), isTrue);
      expect(progress.last, ayaspellArabic.totalBytes);
      expect(await installer().installed(ayaspellArabic), isNotNull);
      // Tampering after installation is detected, never used.
      File(files.dicPath).writeAsStringSync('x', mode: FileMode.append);
      await expectLater(
        installer().installed(ayaspellArabic),
        throwsA(isA<HunspellInstallException>()),
      );
      await installer().remove(ayaspellArabic);
      expect(await installer().installed(ayaspellArabic), isNull);
    });

    test('a changed download is rejected and nothing is installed', () async {
      served['ar.aff'] = [...served['ar.aff']!]..[100] ^= 1;
      await expectLater(
        installer().install(ayaspellArabic),
        throwsA(isA<HunspellInstallException>()),
      );
      expect(await installer().installed(ayaspellArabic), isNull);
      expect(Directory('${root.path}/hunspell').listSync(), isEmpty);
    });
  }, skip: skip);

  test(
    'live download from the pinned Hugging Face revision',
    () async {
      final root = Directory.systemTemp.createTempSync('hunspell-live-');
      try {
        final files = await HunspellInstaller(root).install(ayaspellArabic);
        expect(File(files.dicPath).lengthSync(), ayaspellArabic.dic.bytes);
      } finally {
        root.deleteSync(recursive: true);
      }
    },
    skip: Platform.environment['QUDS_HUNSPELL_LIVE_DOWNLOAD'] == '1'
        ? false
        : 'Set QUDS_HUNSPELL_LIVE_DOWNLOAD=1 to download from Hugging Face.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
