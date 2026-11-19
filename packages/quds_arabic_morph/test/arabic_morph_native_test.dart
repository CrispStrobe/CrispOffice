@TestOn('vm')
library;

import 'dart:io';

import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Real-backend tests: QUDS_ARABIC_MORPH_TEST_LIBRARY is the built
/// libquds_arabic_morph and QUDS_ARABIC_MORPH_TEST_BUNDLE the directory with
/// the verified noprob bundle (manifest.json, NOTICE, LICENSE, database).
final _library = Platform.environment['QUDS_ARABIC_MORPH_TEST_LIBRARY'];
final _bundle = Platform.environment['QUDS_ARABIC_MORPH_TEST_BUNDLE'];
final Object _skip = _library == null || _bundle == null
    ? 'Set QUDS_ARABIC_MORPH_TEST_LIBRARY and QUDS_ARABIC_MORPH_TEST_BUNDLE.'
    : false;

MorphDatabaseFiles _files(String directory) => MorphDatabaseFiles(
  camelMorphMsaNoprob,
  manifestPath: '$directory/manifest.json',
);

Directory _copyBundle() {
  final copy = Directory.systemTemp.createTempSync('arabic-morph-bundle-');
  for (final artifact in camelMorphMsaNoprob.files) {
    File('$_bundle/${artifact.file}').copySync('${copy.path}/${artifact.file}');
  }
  return copy;
}

void main() {
  test('a missing native library leaves the analyzer unavailable', () async {
    final morphology = CamelArabicMorphology(
      database: _files('/missing'),
      nativeLibraryPath: '/missing/libquds_arabic_morph',
    );
    expect(morphology.isAvailable, isFalse);
    final result = await morphology
        .analyzeWords(['كتبوا', 'كتبوا'])
        .timeout(const Duration(seconds: 5));
    expect(result, {'كتبوا': isEmpty});
    expect(morphology.isAvailable, isFalse);
    expect(morphology.failure, isA<ArabicMorphUnavailableException>());
    await morphology.dispose();
  });

  group('real library and noprob database', () {
    late CamelArabicMorphology morphology;
    setUpAll(() async {
      morphology = CamelArabicMorphology(
        database: _files(_bundle!),
        nativeLibraryPath: _library,
      );
      await morphology.load();
      expect(morphology.failure, isNull);
    });
    tearDownAll(() => morphology.dispose());

    test('loads the pinned noprob variant', () {
      expect(morphology.isAvailable, isTrue);
      final info = morphology.info!;
      expect(info['variant'], 'noprob');
      expect(info['db_sha256'], camelMorphMsaNoprob.database.sha256);
      expect(info['manifest_sha256'], camelMorphMsaNoprob.manifest.sha256);
      expect(info['backoff'], 'NONE');
    });

    test('known analyses: كتبوا and والمدرسة', () async {
      final result = await morphology.analyzeWords(['كتبوا', 'والمدرسة']);
      expect(
        result['كتبوا'],
        contains(
          predicate<ArabicAnalysis>(
            (a) => a['lex'] == 'كَتَب' && a['pos'] == 'verb' && a['num'] == 'p',
          ),
        ),
      );
      expect(
        result['والمدرسة'],
        contains(
          predicate<ArabicAnalysis>(
            (a) =>
                a['pos'] == 'noun' &&
                a['prc2'] == 'wa_conj' &&
                a['prc0'] == 'Al_det' &&
                a['lex'] == 'مَدْرَسَة',
          ),
        ),
      );
      // noprob carries the -99.0 placeholder for every probability field.
      final first = result['كتبوا']!.first;
      expect(first['pos_lex_logprob'], '-99.0');
      expect(first.keys, containsAll(['diac', 'lex', 'bw', 'pos', 'gloss']));
    });

    test('harakat and tatweel are normalized by the analyzer', () async {
      final result = await morphology.analyzeWords([
        'كَتَبُوا',
        'كتـــبوا',
        'كتبوا',
      ]);
      bool plainVerb(ArabicAnalysis a) =>
          a['lex'] == 'كَتَب' && a['pos'] == 'verb' && a['num'] == 'p';
      expect(result['كتـــبوا']!.where(plainVerb), isNotEmpty);
      expect(result['كَتَبُوا']!.where(plainVerb), isNotEmpty);
      // Diacritized input restricts analyses to compatible ones.
      expect(
        result['كَتَبُوا']!.length,
        lessThanOrEqualTo(result['كتبوا']!.length),
      );
    });

    test(
      'every requested word is a key; unknown and invalid words are empty',
      () async {
        final long = 'ب' * 3000; // 6,000 UTF-8 bytes: over the ABI limit
        final result = await morphology.analyzeWords([
          'xyzzyq',
          '',
          long,
          'كتبوا',
          'xyzzyq',
        ]);
        expect(result.keys, unorderedEquals(['xyzzyq', '', long, 'كتبوا']));
        expect(result[long], isEmpty);
        expect(result['كتبوا'], isNotEmpty);
      },
    );

    test('results are cached per session and stay read-only', () async {
      morphology.clearCache();
      final first = await morphology.analyzeWords(['المدرسة', 'ذهب']);
      expect(morphology.cachedWords, 2);
      final second = await morphology.analyzeWords(['ذهب', 'المدرسة']);
      expect(identical(first['ذهب'], second['ذهب']), isTrue);
      expect(() => second['ذهب']!.first['pos'] = 'x', throwsUnsupportedError);
      expect(() => second['ذهب']!.clear(), throwsUnsupportedError);
    });

    test('a tampered bundle file is rejected before parsing', () async {
      final copy = _copyBundle();
      try {
        File(
          '${copy.path}/NOTICE',
        ).writeAsStringSync('x', mode: FileMode.append);
        final tampered = CamelArabicMorphology(
          database: _files(copy.path),
          nativeLibraryPath: _library,
        );
        await tampered.load();
        expect(tampered.isAvailable, isFalse);
        expect('${tampered.failure}', contains('could not be opened'));
        expect(await tampered.analyzeWords(['كتبوا']), {'كتبوا': isEmpty});
        await tampered.dispose();
      } finally {
        copy.deleteSync(recursive: true);
      }
    });

    test('a disposed analyzer is unavailable', () async {
      final other = CamelArabicMorphology(
        database: _files(_bundle!),
        nativeLibraryPath: _library,
      );
      await other.load();
      expect(other.isAvailable, isTrue);
      await other.dispose();
      expect(other.isAvailable, isFalse);
    });
  }, skip: _skip);

  group('installer', () {
    late Directory root;
    late HttpServer server;
    final served = <String, List<int>>{};
    var requests = 0;
    setUp(() async {
      root = Directory.systemTemp.createTempSync('arabic-morph-install-');
      requests = 0;
      for (final artifact in camelMorphMsaNoprob.files) {
        served[artifact.file] = File(
          '$_bundle/${artifact.file}',
        ).readAsBytesSync();
      }
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        requests++;
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

    MorphInstaller installer() => MorphInstaller(
      root,
      resolveUrl: (bundle, artifact) =>
          Uri.http('127.0.0.1:${server.port}', '/${artifact.file}'),
    );

    test(
      'installs, verifies, opens, reuses and removes the pinned bundle',
      () async {
        final progress = <int>[];
        final files = await installer().install(
          camelMorphMsaNoprob,
          onProgress: (received, total) => progress.add(received),
        );
        expect(progress.last, camelMorphMsaNoprob.totalBytes);
        expect(requests, camelMorphMsaNoprob.files.length);
        final morphology = CamelArabicMorphology(
          database: files,
          nativeLibraryPath: _library,
        );
        await morphology.load();
        expect(morphology.isAvailable, isTrue);
        await morphology.dispose();
        // Reuse: no second download.
        await installer().install(camelMorphMsaNoprob);
        expect(requests, camelMorphMsaNoprob.files.length);
        expect(await installer().installed(camelMorphMsaNoprob), isNotNull);
        // Tampering after installation is detected, never used.
        File(files.manifestPath).parent
            .listSync()
            .whereType<File>()
            .first
            .writeAsStringSync('x', mode: FileMode.append);
        await expectLater(
          installer().installed(camelMorphMsaNoprob),
          throwsA(isA<MorphInstallException>()),
        );
        await installer().remove(camelMorphMsaNoprob);
        expect(await installer().installed(camelMorphMsaNoprob), isNull);
        expect(Directory('${root.path}/arabic_morph').listSync(), isEmpty);
      },
    );

    test('a changed download is rejected and nothing is installed', () async {
      final db = camelMorphMsaNoprob.database.file;
      served[db] = [...served[db]!]..[1000] ^= 1;
      await expectLater(
        installer().install(camelMorphMsaNoprob),
        throwsA(isA<MorphInstallException>()),
      );
      expect(await installer().installed(camelMorphMsaNoprob), isNull);
      expect(Directory('${root.path}/arabic_morph').listSync(), isEmpty);
    });

    test('a longer download is rejected while streaming', () async {
      served['NOTICE'] = [...served['NOTICE']!, 0x0a];
      await expectLater(
        installer().install(camelMorphMsaNoprob),
        throwsA(
          isA<MorphInstallException>().having(
            (e) => e.message,
            'message',
            contains('larger than pinned'),
          ),
        ),
      );
      expect(Directory('${root.path}/arabic_morph').listSync(), isEmpty);
    });

    test('an extra file in the installed tree is not trusted', () async {
      final files = await installer().install(camelMorphMsaNoprob);
      File(
        '${File(files.manifestPath).parent.path}/extra',
      ).writeAsStringSync('');
      await expectLater(
        installer().installed(camelMorphMsaNoprob),
        throwsA(isA<MorphInstallException>()),
      );
    });

    test('cancellation stops the download and installs nothing', () async {
      final cancellation = MorphInstallCancellation();
      await expectLater(
        installer().install(
          camelMorphMsaNoprob,
          cancellation: cancellation,
          onProgress: (received, total) {
            if (received > 1 << 20) cancellation.cancel();
          },
        ),
        throwsA(
          isA<MorphInstallException>().having(
            (e) => e.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );
      expect(await installer().installed(camelMorphMsaNoprob), isNull);
      expect(Directory('${root.path}/arabic_morph').listSync(), isEmpty);
    });
  }, skip: _skip);

  test(
    'live download from the pinned Hugging Face revision',
    () async {
      final root = Directory.systemTemp.createTempSync('arabic-morph-live-');
      try {
        final files = await MorphInstaller(root).install(camelMorphMsaNoprob);
        expect(
          File(
            '${File(files.manifestPath).parent.path}/'
            '${camelMorphMsaNoprob.database.file}',
          ).lengthSync(),
          camelMorphMsaNoprob.database.bytes,
        );
        if (_library != null) {
          final morphology = CamelArabicMorphology(
            database: files,
            nativeLibraryPath: _library,
          );
          final result = await morphology.analyzeWords(['كتبوا']);
          expect(result['كتبوا'], isNotEmpty);
          await morphology.dispose();
        }
      } finally {
        root.deleteSync(recursive: true);
      }
    },
    skip: Platform.environment['QUDS_ARABIC_MORPH_LIVE_DOWNLOAD'] == '1'
        ? false
        : 'Set QUDS_ARABIC_MORPH_LIVE_DOWNLOAD=1 to download from Hugging Face.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
