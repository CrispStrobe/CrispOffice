// English/French end-to-end smoke through the app's own code paths.
//
// Installs into a NEW empty root, from the immutable Hub revisions in the
// compiled-in catalog: either the platform's v2 runtime capsule plus each
// language bundle (`--runtime`), or only the bundles with an explicitly
// supplied library (`--library <dir named by its SHA-256>/<file>`). Then
// starts the real isolate worker per language and analyzes sample texts.
//
//   dart run tool/language_worker_smoke.dart --root <new-dir> --report <json> \
//       (--runtime | --library <path> --library-sha256 <hex>)
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_install.dart';

const _samples = {
  SpacyLanguage.english: (
    'en-US',
    'Apple is looking at buying a U.K. startup for \$1 billion. '
        'Tim Cook visited London on Monday.',
  ),
  SpacyLanguage.french: (
    'fr-FR',
    'Emmanuel Macron a rencontré les dirigeants de Renault à Paris. '
        'Les négociations reprendront lundi.',
  ),
};

Future<void> main(List<String> arguments) async {
  String? option(String name) {
    final index = arguments.indexOf(name);
    return index < 0 || index + 1 >= arguments.length
        ? null
        : arguments[index + 1];
  }

  final rootPath = option('--root');
  final reportPath = option('--report');
  final runtimeMode = arguments.contains('--runtime');
  final libraryPath = option('--library');
  final librarySha = option('--library-sha256');
  final platformId = option('--platform');
  if (rootPath == null ||
      reportPath == null ||
      (!runtimeMode && (libraryPath == null || librarySha == null))) {
    stderr.writeln(
      'usage: --root <new-dir> --report <json> (--runtime --platform <id> | '
      '--library <path> --library-sha256 <hex>)',
    );
    exitCode = 64;
    return;
  }
  final root = Directory(rootPath);
  if (root.existsSync()) {
    stderr.writeln('The root must not exist (fresh empty cache required).');
    exitCode = 65;
    return;
  }
  final report = <String, Object?>{
    'schema': 'quds.spacy.language_worker_smoke.v1',
    'passed': false,
    'mode': runtimeMode ? 'published-runtime-capsule' : 'explicit-library',
    'host': '${Platform.operatingSystem} ${Platform.version.split(' ').first}',
    'grammar_used': false,
  };
  final installer = SpacyPackageInstaller(root: root);
  try {
    final languages = <Object?>[];
    for (final MapEntry(key: language, value: sample) in _samples.entries) {
      final download = spacyLanguageDownload(language)!;
      final started = Stopwatch()..start();
      final String bundleDirectory;
      final String library;
      final String digest;
      Map<String, Object?>? runtimeInfo;
      if (runtimeMode) {
        final platform = SpacyPlatform.values.firstWhere(
          (p) => p.id == platformId,
        );
        final runtime = spacyRuntimePackage(platform)!;
        final installation = await installer.installLanguage(download, runtime);
        bundleDirectory = installation.bundleDirectory;
        library = installation.libraryPath!;
        digest = installation.librarySha256!;
        runtimeInfo = {
          'url': runtime.url.toString(),
          'archive_sha256': runtime.archiveSha256,
          'library_sha256': runtime.librarySha256,
        };
      } else {
        bundleDirectory = await installer.installLanguageBundle(download);
        library = libraryPath!;
        digest = librarySha!;
        final actual = sha256
            .convert(File(library).readAsBytesSync())
            .toString();
        if (actual != digest) throw StateError('Library digest differs.');
      }
      final installSeconds = started.elapsedMilliseconds / 1000;
      final transport = await startSpacyWorker(
        bundle: download.bundle,
        backendFactory: SpacyNativeBackendFactory(
          bundleDirectory: bundleDirectory,
          libraryPath: library,
          librarySha256: digest,
        ),
      );
      try {
        final (locale, text) = sample;
        final result = await transport.analyze(
          LinguisticAnalysisRequest(
            text: text,
            documentId: 'smoke',
            blockId: language.code,
            revision: 1,
            locale: locale,
            startOffset: 0,
            generation: 0,
            configurationId: 'language-smoke',
          ),
        );
        final wrongLocale = await transport.analyze(
          LinguisticAnalysisRequest(
            text: 'Katze',
            documentId: 'smoke',
            blockId: '${language.code}-de',
            revision: 1,
            locale: 'de-DE',
            startOffset: 0,
            generation: 0,
            configurationId: 'language-smoke',
          ),
        );
        languages.add({
          'language': language.code,
          'bundle_revision': download.revision,
          'bundle_repository': download.repository,
          'runtime': ?runtimeInfo,
          'install_seconds': installSeconds,
          'closed_tree_reverified': await installer.hasLanguageBundle(download),
          'status': result.status.name,
          'identity': result.identity?.toJson(),
          'tokens': [
            for (final token in result.tokens)
              '${token.text}/${token.pos}/${token.tag}/${token.lemma}/'
                  '${token.dependency}->${token.head}'
                  '${token.morphology.isEmpty ? '' : '/${token.morphology}'}',
          ],
          'sentences': result.sentences.length,
          'entities': [
            for (final entity in result.entities)
              '${entity.text} (${entity.label})',
          ],
          'german_request_refused': wrongLocale.status.name,
        });
        if (!result.isSuccess ||
            result.tokens.isEmpty ||
            wrongLocale.status != LinguisticAnalysisStatus.unsupported) {
          throw StateError('${language.code} smoke failed: ${result.status}');
        }
      } finally {
        await transport.dispose();
      }
    }
    report['languages'] = languages;
    report['passed'] = true;
  } on Object catch (error) {
    report['failure'] = '${error.runtimeType}: $error';
    exitCode = 1;
  }
  File(reportPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode({'passed': report['passed']}));
}
