@TestOn('vm')
library;

import 'dart:io';

import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_arabic_morph/src/morph_transport_native.dart' as native;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Real-backend tests: QUDS_ARABIC_MORPH_TEST_LIBRARY is the built
/// libquds_arabic_morph and QUDS_ARABIC_MORPH_TEST_BUNDLE the directory with
/// the verified proofing-bin bundle (manifest.json, NOTICE, LICENSE,
/// database).
final _library = Platform.environment['QUDS_ARABIC_MORPH_TEST_LIBRARY'];
final _bundle = Platform.environment['QUDS_ARABIC_MORPH_TEST_BUNDLE'];
final Object _skip = _library == null || _bundle == null
    ? 'Set QUDS_ARABIC_MORPH_TEST_LIBRARY and QUDS_ARABIC_MORPH_TEST_BUNDLE.'
    : false;

/// QUDS_ARABIC_MORPH_TEST_MODEL: the directory with the verified context
/// model bundle (camelMorphMsaDisambig).
final _model = Platform.environment['QUDS_ARABIC_MORPH_TEST_MODEL'];
final Object _skipModel = _library == null || _bundle == null || _model == null
    ? 'Set QUDS_ARABIC_MORPH_TEST_LIBRARY, _BUNDLE and _MODEL.'
    : false;

MorphDatabaseFiles _files(String directory) => MorphDatabaseFiles(
  camelMorphMsaProofingBin,
  manifestPath: '$directory/manifest.json',
);

Directory _copyBundle() {
  final copy = Directory.systemTemp.createTempSync('arabic-morph-bundle-');
  for (final artifact in camelMorphMsaProofingBin.files) {
    File('$_bundle/${artifact.file}').copySync('${copy.path}/${artifact.file}');
  }
  return copy;
}

/// Counts this bundle's mappings, excluding other analyzers in the process.
/// The pinned POSIX backend owns one mapping through the model destructor.
int _databaseMappings(Directory bundle) {
  final path = File(
    '${bundle.path}/${camelMorphMsaProofingBin.database.file}',
  ).resolveSymbolicLinksSync();
  final mapping = RegExp(r'^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(.*)$');
  return File('/proc/self/maps')
      .readAsLinesSync()
      .where((line) => mapping.firstMatch(line)?.group(1) == path)
      .length;
}

void main() {
  group('real library with the context model', () {
    late CamelArabicMorphology morphology;
    setUpAll(() async {
      morphology = CamelArabicMorphology(
        database: _files(_bundle!),
        disambiguator: MorphDatabaseFiles(
          camelMorphMsaDisambig,
          manifestPath: '$_model/manifest.json',
        ),
        nativeLibraryPath: _library,
      );
      await morphology.load();
    });
    tearDownAll(() => morphology.dispose());

    test('loads the pinned model and ranks readings in context', () async {
      expect(morphology.canDisambiguate, isTrue);
      expect(
        morphology.disambiguatorInfo!['model_format'],
        'crispembed-camel-morph-disambig-v1',
      );
      final sentences = [
        for (final s in arabicContextSentences(
          'قرأت ثلاثة كتب في المكتبة. كان الطلاب مجتهدين!',
        ))
          [for (final t in s) t.text],
      ];
      expect(sentences, hasLength(2));
      final readings = await morphology.disambiguate(sentences);
      expect(readings.map((s) => s.length), [6, 4]);
      // كتب after a numeral is the plural of كتاب, في the preposition,
      // كان the verb.
      expect(readings[0][2].best.map((a) => a['lex']).toSet(), {'كِتَاب'});
      expect(readings[0][3].best.first['pos'], 'prep');
      expect(readings[1][0].best.first['pos'], 'verb');
      for (final s in readings) {
        for (final r in s) {
          final best = r.bestScore;
          expect(best, inInclusiveRange(0, 1.0001));
          if (r.analyses.isNotEmpty) expect(r.margin, lessThanOrEqualTo(best));
        }
      }
      expect(readings[0][5].analyses.single['pos'], 'punc');
    });

    test('a tampered model leaves analysis working without ranking', () async {
      final copy = Directory.systemTemp.createTempSync('arabic-morph-model-');
      addTearDown(() => copy.deleteSync(recursive: true));
      for (final a in camelMorphMsaDisambig.files) {
        File('$_model/${a.file}').copySync('${copy.path}/${a.file}');
      }
      final model = File('${copy.path}/${camelMorphMsaDisambig.database.file}');
      final bytes = model.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0x5a;
      model.writeAsBytesSync(bytes);
      final other = CamelArabicMorphology(
        database: _files(_bundle!),
        disambiguator: MorphDatabaseFiles(
          camelMorphMsaDisambig,
          manifestPath: '${copy.path}/manifest.json',
        ),
        nativeLibraryPath: _library,
      );
      addTearDown(other.dispose);
      await other.load();
      expect(other.isAvailable, isTrue);
      expect(other.canDisambiguate, isFalse);
      expect(other.disambiguatorFailure.toString(), contains('SHA-256'));
      expect(
        await other.disambiguate([
          ['كتب'],
        ]),
        isEmpty,
      );
    });
  }, skip: _skipModel);

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

  group('real library and proofing-bin database', () {
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

    test('maps the pinned proofing-bin variant', () {
      expect(morphology.isAvailable, isTrue);
      final info = morphology.info!;
      expect(info['variant'], 'proofing-bin');
      expect(info['db_format'], 'binary');
      expect(info['storage'], 'mapped');
      expect(info['db_sha256'], camelMorphMsaProofingBin.database.sha256);
      expect(info['manifest_sha256'], camelMorphMsaProofingBin.manifest.sha256);
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
      // Only the proofing profile is stored and returned.
      final first = result['كتبوا']!.first;
      expect(
        first.keys,
        containsAll(['diac', 'lex', 'root', 'pos', 'per', 'gen', 'num']),
      );
      for (final dropped in ['gloss', 'bw', 'caphi', 'pos_lex_logprob']) {
        expect(first[dropped], isNull);
      }
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

    test('normal disposal releases the mapped database', () async {
      final copy = _copyBundle();
      final other = CamelArabicMorphology(
        database: _files(copy.path),
        nativeLibraryPath: _library,
      );
      try {
        expect(_databaseMappings(copy), 0);
        await other.load();
        expect(other.failure, isNull);
        expect(other.isAvailable, isTrue);
        expect(other.info!['storage'], 'mapped');
        expect(_databaseMappings(copy), 1);
        expect((await other.analyzeWords(['كتبوا']))['كتبوا'], isNotEmpty);

        await other.dispose().timeout(const Duration(seconds: 5));
        expect(other.isAvailable, isFalse);
        expect(_databaseMappings(copy), 0);
        await other.dispose().timeout(const Duration(seconds: 5));
        expect(_databaseMappings(copy), 0);
        expect(await other.analyzeWords(['كتبوا']), {'كتبوا': isEmpty});
      } finally {
        await other.dispose();
        copy.deleteSync(recursive: true);
      }
    }, testOn: 'linux');

    test('disposal while the worker starts settles opening', () async {
      final copy = _copyBundle();
      final transport = native.createArabicMorphTransport(
        nativeLibraryPath: _library,
      );
      try {
        expect(_databaseMappings(copy), 0);
        final opening = expectLater(
          transport.open(_files(copy.path)),
          throwsA(isA<ArabicMorphUnavailableException>()),
        );
        await transport.dispose().timeout(const Duration(seconds: 5));
        await opening;
        expect(_databaseMappings(copy), 0);
        await expectLater(
          transport.open(_files(copy.path)),
          throwsA(isA<ArabicMorphUnavailableException>()),
        );
      } finally {
        await transport.dispose();
        copy.deleteSync(recursive: true);
      }
    }, testOn: 'linux');

    test('disposal settles pending analysis and releases its model', () async {
      final copy = _copyBundle();
      final transport = native.createArabicMorphTransport(
        nativeLibraryPath: _library,
      );
      try {
        expect(_databaseMappings(copy), 0);
        final info = await transport.open(_files(copy.path));
        expect(info['storage'], 'mapped');
        expect(_databaseMappings(copy), 1);
        final pending = expectLater(
          transport.analyze(['كتبوا', 'والمدرسة']),
          throwsA(isA<ArabicMorphUnavailableException>()),
        );
        // Let _send enqueue the request. A worker response is an event and
        // cannot run before this microtask continuation disposes the worker.
        await Future<void>.value();
        await Future.wait([
          transport.dispose(),
          transport.dispose(),
          pending,
        ]).timeout(const Duration(seconds: 5));
        expect(_databaseMappings(copy), 0);
        await expectLater(
          transport.analyze(['كتبوا']),
          throwsA(isA<ArabicMorphUnavailableException>()),
        );
      } finally {
        await transport.dispose();
        copy.deleteSync(recursive: true);
      }
    }, testOn: 'linux');
  }, skip: _skip);

  test('earlier bundles are removed, the current one is kept', () async {
    final root = Directory.systemTemp.createTempSync('arabic-morph-stale-');
    try {
      final parent = Directory('${root.path}/arabic_morph')..createSync();
      final current = camelMorphMsaProofingBin;
      final old = camelMorphMsaNoprob;
      for (final name in [
        '${current.revision}-${current.id}',
        '${old.revision}-${old.id}',
        '.removing-x-1',
        '.staging-abc',
      ]) {
        Directory('${parent.path}/$name').createSync();
        File('${parent.path}/$name/file').writeAsStringSync('x');
      }
      File('${parent.path}/unrelated.txt').writeAsStringSync('x');
      final removed = await MorphInstaller(root).removeOtherBundles(current);
      expect(
        removed,
        unorderedEquals(['${old.revision}-${old.id}', '.removing-x-1']),
      );
      expect(
        parent.listSync().map(
          (e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
        ),
        unorderedEquals([
          '${current.revision}-${current.id}',
          '.staging-abc',
          'unrelated.txt',
        ]),
      );
      expect(
        await MorphInstaller(
          Directory('${root.path}/none'),
        ).removeOtherBundles(current),
        isEmpty,
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  group('installer', () {
    late Directory root;
    late HttpServer server;
    final served = <String, List<int>>{};
    var requests = 0;
    setUp(() async {
      root = Directory.systemTemp.createTempSync('arabic-morph-install-');
      requests = 0;
      for (final artifact in camelMorphMsaProofingBin.files) {
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
          camelMorphMsaProofingBin,
          onProgress: (received, total) => progress.add(received),
        );
        expect(progress.last, camelMorphMsaProofingBin.totalBytes);
        expect(requests, camelMorphMsaProofingBin.files.length);
        final morphology = CamelArabicMorphology(
          database: files,
          nativeLibraryPath: _library,
        );
        await morphology.load();
        expect(morphology.isAvailable, isTrue);
        await morphology.dispose();
        // Reuse: no second download.
        await installer().install(camelMorphMsaProofingBin);
        expect(requests, camelMorphMsaProofingBin.files.length);
        expect(
          await installer().installed(camelMorphMsaProofingBin),
          isNotNull,
        );
        // Tampering after installation is detected, never used.
        File(files.manifestPath).parent
            .listSync()
            .whereType<File>()
            .first
            .writeAsStringSync('x', mode: FileMode.append);
        await expectLater(
          installer().installed(camelMorphMsaProofingBin),
          throwsA(isA<MorphInstallException>()),
        );
        await installer().remove(camelMorphMsaProofingBin);
        expect(await installer().installed(camelMorphMsaProofingBin), isNull);
        expect(Directory('${root.path}/arabic_morph').listSync(), isEmpty);
      },
    );

    test('a changed download is rejected and nothing is installed', () async {
      final db = camelMorphMsaProofingBin.database.file;
      served[db] = [...served[db]!]..[1000] ^= 1;
      await expectLater(
        installer().install(camelMorphMsaProofingBin),
        throwsA(isA<MorphInstallException>()),
      );
      expect(await installer().installed(camelMorphMsaProofingBin), isNull);
      expect(Directory('${root.path}/arabic_morph').listSync(), isEmpty);
    });

    test('a longer download is rejected while streaming', () async {
      served['NOTICE'] = [...served['NOTICE']!, 0x0a];
      await expectLater(
        installer().install(camelMorphMsaProofingBin),
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
      final files = await installer().install(camelMorphMsaProofingBin);
      File(
        '${File(files.manifestPath).parent.path}/extra',
      ).writeAsStringSync('');
      await expectLater(
        installer().installed(camelMorphMsaProofingBin),
        throwsA(isA<MorphInstallException>()),
      );
    });

    test('cancellation stops the download and installs nothing', () async {
      final cancellation = MorphInstallCancellation();
      await expectLater(
        installer().install(
          camelMorphMsaProofingBin,
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
      expect(await installer().installed(camelMorphMsaProofingBin), isNull);
      expect(Directory('${root.path}/arabic_morph').listSync(), isEmpty);
    });
  }, skip: _skip);
}
