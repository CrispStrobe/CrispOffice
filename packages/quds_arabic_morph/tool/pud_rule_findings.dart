// Arabic rule findings over a corpus with the real analyzer, one JSON line
// per finding (sentence index, rule id, range, message), to compare backends,
// bundles or reading modes finding by finding:
//   dart run tool/pud_rule_findings.dart <library> <bundle dir> <corpus.txt>
//       [--model <context model bundle dir>] [--reading all|contextual]
//       [--margin <minimum lead of the best reading, default 0.9>]
// The corpus has one sentence per line; the bundle's manifest variant
// selects the pinned bundle (proofing-bin or the earlier noprob). A local
// context model bundle is pinned by its own manifest (developer use, before
// or after publication); --reading defaults to contextual.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// A bundle pinned by the local manifest at [dir] (developer use only).
MorphBundleDownload localBundle(String dir, MorphBundleDownload like) {
  final manifestBytes = File('$dir/manifest.json').readAsBytesSync();
  final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map;
  final main = (manifest['model'] ?? manifest['db']) as String;
  MorphArtifact artifact(Map<Object?, Object?> f) => MorphArtifact(
    f['path'] as String,
    f['sha256'] as String,
    f['size'] as int,
  );
  final files = [
    for (final f in manifest['files'] as List)
      artifact(f as Map<Object?, Object?>),
  ];
  return MorphBundleDownload(
    id: like.id,
    displayName: like.displayName,
    repository: like.repository,
    revision: like.revision,
    directory: like.directory,
    license: like.license,
    licenseUrl: like.licenseUrl,
    attribution: like.attribution,
    sourceUrl: like.sourceUrl,
    manifest: MorphArtifact(
      'manifest.json',
      sha256.convert(manifestBytes).toString(),
      manifestBytes.length,
    ),
    database: files.firstWhere((f) => f.file == main),
    notices: [
      for (final f in files)
        if (f.file != main) f,
    ],
  );
}

Future<void> main(List<String> arguments) async {
  final args = List.of(arguments);
  String? option(String name) {
    final i = args.indexOf(name);
    if (i < 0 || i + 1 >= args.length) return null;
    final value = args[i + 1];
    args.removeRange(i, i + 2);
    return value;
  }

  final modelDir = option('--model');
  final margin = double.parse(
    option('--margin') ?? arabicContextMinMargin.toString(),
  );
  final reading = option('--reading') == 'all'
      ? ArabicGrammarReading.allAnalyses
      : ArabicGrammarReading.contextual;
  if (args.length != 3) {
    stderr.writeln(
      'usage: pud_rule_findings.dart <library> <bundle> <corpus> '
      '[--model <dir>] [--reading all|contextual]',
    );
    exit(64);
  }
  final [library, bundle, corpus] = args;
  final variant =
      (jsonDecode(File('$bundle/manifest.json').readAsStringSync())
          as Map)['variant'];
  final morphology = CamelArabicMorphology(
    database: MorphDatabaseFiles(
      variant == 'noprob' ? camelMorphMsaNoprob : camelMorphMsaProofingBin,
      manifestPath: '$bundle/manifest.json',
    ),
    disambiguator: modelDir == null
        ? null
        : MorphDatabaseFiles(
            localBundle(modelDir, camelMorphMsaDisambig),
            manifestPath: '$modelDir/manifest.json',
          ),
    nativeLibraryPath: library,
  );
  await morphology.load();
  if (!morphology.isAvailable) throw StateError('${morphology.failure}');
  if (modelDir != null && !morphology.canDisambiguate) {
    throw StateError('${morphology.disambiguatorFailure}');
  }
  final provider = ArabicWritingRulesProvider(
    morphology: morphology,
    grammarReading: reading,
    contextMinMargin: margin,
  );
  final lines = File(corpus).readAsLinesSync();
  var count = 0;
  final watch = Stopwatch()..start();
  for (var i = 0; i < lines.length; i++) {
    final result = await provider.check(
      OfficeProofingRequest(
        documentId: 'corpus',
        blockId: 'line-$i',
        revision: 1,
        text: lines[i],
        language: 'ar',
      ),
    );
    for (final f in result.findings) {
      count++;
      stdout.writeln(
        jsonEncode({
          'line': i,
          'rule': f.ruleId,
          'start': f.start,
          'end': f.end,
          'text': lines[i].substring(f.start, f.end),
          'message': f.message,
          'replacements': f.replacements,
        }),
      );
    }
  }
  stderr.writeln(
    jsonEncode({
      'sentences': lines.length,
      'findings': count,
      'reading': reading.name,
      'margin': margin,
      'model': modelDir != null,
      'seconds': watch.elapsedMilliseconds / 1000,
    }),
  );
  await provider.dispose();
  await morphology.dispose();
}
