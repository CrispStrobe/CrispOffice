// On-device gate for the optional native proofing backends packaged in the
// Studio app (iOS frameworks, Android jniLibs, desktop libraries). Each case
// loads the real library through the same Studio host code the app uses,
// downloads its pinned data into the app's private sandbox directory and
// checks a known result. Run on a simulator/emulator:
//
//   flutter test integration_test/mobile_native_proofing_test.dart -d <device>
//
// A line `QUDS_NATIVE_GATE {json}` records what each backend did.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_studio/studio_arabic_morph_host_native.dart';
import 'package:quds_office_studio/studio_hunspell_host_native.dart';
import 'package:quds_office_studio/studio_language_id_host_native.dart';
import 'package:quds_office_studio/studio_data_root.dart';
import 'package:quds_office_studio/studio_native_paths.dart';
import 'package:quds_proofing_harper/quds_proofing_harper.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_install.dart';
import 'package:quds_office_studio/studio_spacy_host_native.dart';

import 'spacy_development_cases.g.dart';

OfficeProofingRequest _request(String text, String language) =>
    OfficeProofingRequest(
      documentId: 'gate',
      blockId: 'b',
      revision: 1,
      text: text,
      language: language,
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{
    'os': Platform.operatingSystem,
    'abi': Abi.current().toString(),
  };
  setUpAll(initializeStudioDataRoot);
  tearDownAll(() {
    // ignore: avoid_print
    print('QUDS_NATIVE_GATE ${jsonEncode(report)}');
  });

  test('private data directory is inside the app sandbox and writable', () {
    final root = Directory(studioPrivateDataDirectory());
    report['data_directory'] = root.path;
    if (Platform.isIOS) {
      expect(root.path, contains('/Library/Application Support/'));
      // Same container as the synchronous fallback (temporary directory).
      expect(root.path, startsWith(Directory.systemTemp.absolute.parent.path));
    } else if (Platform.isAndroid) {
      expect(
        root.path,
        matches(RegExp(r'^/data/(user/\d+|data)/[^/]+/files/')),
      );
      expect(
        root.path.endsWith('/files/quds_office_studio'),
        isTrue,
        reason: 'derived ${androidFilesDirectory()}',
      );
    }
    root.createSync(recursive: true);
    final probe = File('${root.path}/.write-probe')..writeAsStringSync('ok');
    expect(probe.readAsStringSync(), 'ok');
    probe.deleteSync();
  });

  test('Hunspell loads and AyaSpell flags known misspellings', () async {
    final host = NativeStudioHunspellHost(
      root: Directory(studioHunspellDataDirectory()),
      libraryPath: studioHunspellLibraryPath(),
    );
    report['hunspell_library'] = studioHunspellLibraryPath() ?? '(default)';
    await host.refresh();
    if (!host.status(ayaspellArabic).installed) {
      await host.install(ayaspellArabic);
    }
    expect(host.status(ayaspellArabic).installed, isTrue);
    final provider = host.createProviders(OfficeProofingVocabulary()).single;
    addTearDown(provider.dispose);
    const text = 'ذهبت البنت الى المدرسه وقالت هاذا جميل';
    final result = await provider.check(_request(text, 'ar'));
    expect(result.status, OfficeProofingStatus.success, reason: result.message);
    final byWord = {for (final f in result.findings) f.originalText: f};
    expect(byWord.keys.toSet(), {'الى', 'المدرسه', 'هاذا'});
    expect(byWord['الى']!.replacements.first, 'إلى');
    report['hunspell'] = {
      for (final e in byWord.entries)
        e.key: e.value.replacements.take(3).toList(),
    };
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('Arabic morphology analyzes كتبوا', () async {
    final host = NativeStudioArabicMorphHost(
      root: Directory(studioHunspellDataDirectory()),
      libraryPath: studioArabicMorphLibraryPath(),
    );
    addTearDown(host.dispose);
    await host.refresh();
    if (!host.status.installed) await host.install();
    expect(host.status.loaded, isTrue, reason: host.status.problem);
    final result = await host.morphology.analyzeWords(['كتبوا']);
    expect(
      result['كتبوا'],
      contains(
        predicate<ArabicAnalysis>(
          (a) => a['lex'] == 'كَتَب' && a['pos'] == 'verb' && a['num'] == 'p',
        ),
      ),
    );
    report['arabic_morph'] = {
      'analyses': result['كتبوا']!.length,
      'first_lex': result['كتبوا']!.first['lex'],
    };
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('CLD3 detects German and Arabic', () async {
    final host = createLanguageIdHost();
    addTearDown(host.dispose);
    await host.load();
    expect(host.problem, isNull);
    expect(host.detector, isNotNull);
    final data = await rootBundle.load(Cld3Model.assetKey);
    final identifier = Cld3LanguageIdentifier(
      model: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      nativeLibraryPath: studioLanguageIdLibraryPath(),
    );
    addTearDown(identifier.dispose);
    await identifier.load();
    expect(identifier.failure, isNull);
    final results = await identifier.detectBatch([
      'Das ist ein ganz normaler deutscher Satz über das Wetter.',
      'هذا نص عربي قصير',
    ]);
    expect([for (final r in results) r.first.language], ['de', 'ar']);
    report['language_id'] = [
      for (final r in results) '${r.first.language}:${r.first.confidence}',
    ];
  });

  test('Harper flags "an test"', () async {
    final provider = HarperProofingProvider();
    addTearDown(provider.dispose);
    final result = await provider.check(_request('This is an test.', 'en-US'));
    expect(result.status, OfficeProofingStatus.success, reason: result.message);
    final article = result.findings.firstWhere(
      (finding) => finding.ruleId == 'harper.AnA',
    );
    expect(article.originalText, 'an');
    expect(article.replacements, contains('a'));
    report['harper'] = '${article.ruleId}:${article.replacements}';
  });

  // spaCy: the library the app ships (iOS framework / Android jniLibs; on
  // desktop the macOS bundle), the pinned German model downloaded into the
  // sandbox, then the frozen 16-case development panel compared field by
  // field exactly as tool/replay_development.dart does.
  test('spaCy German analysis matches the development panel', () async {
    final bundled = Platform.isIOS || Platform.isAndroid
        ? detectMobileBundledSpacyLibrary()
        : detectBundledSpacyLibrary(Platform.environment);
    expect(bundled, isNotNull, reason: 'crispembed-spacy is not packaged');
    final qualification = spacyQualificationForHostBundled(
      librarySha256: bundled!.sha256,
      codeSha256: bundled.codeSha256,
    );
    final installer = SpacyPackageInstaller(
      root: Directory(studioSpacyDataDirectory()),
    );
    final installation =
        await installer.installedBundle() ?? await installer.installBundle();
    final backend = await SpacyNativeBackendFactory(
      bundleDirectory: installation.bundleDirectory,
      libraryPath: bundled.path,
      librarySha256: bundled.sha256,
      hostBundled: true,
    ).open(const SpacyBundle.germanF32());
    addTearDown(backend.dispose);
    final panel = jsonDecode(spacyDevelopmentPanelJson) as Map<String, dynamic>;
    final differences = <String>[];
    var tokens = 0, sentences = 0, fields = 0;
    final watch = Stopwatch()..start();
    for (final item in (panel['cases'] as List).cast<Map<String, dynamic>>()) {
      final id = item['id'] as String;
      final request = LinguisticAnalysisRequest(
        text: item['text'] as String,
        documentId: 'development',
        blockId: id,
        revision: 7,
        startOffset: 37,
        generation: 11,
        configurationId: 'development-ffi-v1',
      );
      final result = await backend.analyze(request);
      expect(result.isSuccess, isTrue, reason: '$id: ${result.message}');
      final actual = result.toJson();
      for (final category in ['tokens', 'sentences']) {
        final actualRows = actual[category] as List;
        final expectedRows = item[category] as List;
        if (actualRows.length != expectedRows.length) {
          differences.add('$id.$category.count');
          continue;
        }
        for (var i = 0; i < actualRows.length; i++) {
          final row = actualRows[i] as Map<String, Object?>;
          final original = expectedRows[i] as Map<String, dynamic>;
          for (final field in row.keys) {
            fields++;
            if (!original.containsKey(field) || original[field] != row[field]) {
              differences.add('$id.$category[$i].$field');
            }
          }
        }
      }
      tokens += result.tokens.length;
      sentences += result.sentences.length;
    }
    report['spacy'] = {
      'library': bundled.path.split('/').last,
      'library_sha256': bundled.sha256,
      'code_sha256': bundled.codeSha256,
      'identity': backend.identity.toJson(),
      'recorded_qualification': qualification?.analysis,
      'grammar_qualified': qualification?.grammarQualified ?? false,
      'manifest_sha256': panel['manifest_sha256'],
      'cases': (panel['cases'] as List).length,
      'tokens': tokens,
      'sentences': sentences,
      'compared_fields': fields,
      'differences': differences,
      'analysis_microseconds': watch.elapsedMicroseconds,
    };
    expect(differences, isEmpty);
    expect([tokens, sentences], [113, 22]);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
