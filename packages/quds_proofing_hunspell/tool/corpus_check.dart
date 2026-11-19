// Corpus check for the native Hunspell provider:
//   dart run tool/corpus_check.dart <library> <dictionary dir> <corpus.txt> [cli-flagged.txt]
// Prints token/flag counts as JSON; with the Hunspell CLI's `-l` output for
// the same lines, also compares the flagged Arabic-script word multisets.
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

Future<void> main(List<String> args) async {
  final provider = HunspellProofingProvider(
    bundle: ayaspellArabic,
    dictionary: HunspellDictionaryFiles(
      affPath: '${args[1]}/ar.aff',
      dicPath: '${args[1]}/ar.dic',
    ),
    nativeLibraryPath: args[0],
    maxSuggestedWords: int.parse(Platform.environment["SUGGEST"] ?? "0"),
  );
  final lines = File(args[2]).readAsLinesSync();
  var tokens = 0;
  final flagged = <String, int>{};
  final watch = Stopwatch()..start();
  for (var i = 0; i < lines.length; i++) {
    tokens += hunspellWords(lines[i], script: arabicScriptLetter).length;
    final result = await provider.check(
      OfficeProofingRequest(
        documentId: 'pud',
        blockId: '$i',
        revision: 1,
        text: lines[i],
        language: 'ar',
      ),
    );
    if (result.status != OfficeProofingStatus.success) {
      stderr.writeln('line $i: ${result.status} ${result.message}');
      exit(1);
    }
    for (final finding in result.findings) {
      flagged.update(finding.originalText, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final total = flagged.values.fold(0, (a, b) => a + b);
  final report = <String, Object?>{
    'lines': lines.length,
    'arabic_words': tokens,
    'flagged': total,
    'rate': total / tokens,
    'seconds': watch.elapsedMilliseconds / 1000,
  };
  if (args.length > 3) {
    final cli = <String, int>{};
    for (final word in File(args[3]).readAsLinesSync()) {
      if (word.isEmpty || !arabicScriptLetter.hasMatch(word)) continue;
      cli.update(word, (n) => n + 1, ifAbsent: () => 1);
    }
    final keys = {...cli.keys, ...flagged.keys};
    final differences = [
      for (final key in keys)
        if ((cli[key] ?? 0) != (flagged[key] ?? 0))
          {'word': key, 'cli': cli[key] ?? 0, 'native': flagged[key] ?? 0},
    ];
    report['cli_flagged'] = cli.values.fold<int>(0, (a, b) => a + b);
    report['multiset_differences'] = differences.length;
    report['first_differences'] = differences.take(15).toList();
  }
  await provider.dispose();
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
