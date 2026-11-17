import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

Future<void> main() async {
  final GermanSpellingProvider provider = GermanSpellingProvider();
  final Stopwatch clock = Stopwatch()..start();
  await provider.warmUp();
  print('warmup ${clock.elapsedMilliseconds}ms');
  for (final String word in <String>[
    'interresant', 'Intresant', 'Komunikazion', 'Kommunkationn',
    'Xnternehme', 'Xnternehemen', 'Rechschreibugn', 'Rehtschreibugn',
    'Interressand', 'Strasenbahnn', 'Wissenscahflt', 'Scmetterlng',
    'QudsClodu', 'QudsClou', 'STRASENBAHNN', 'Huas', 'wunderbarr',
  ]) {
    provider.vocabulary.addWord('QudsCloud');
    clock.reset();
    final result = await provider.check(OfficeProofingRequest(
      documentId:'d',blockId:'p',revision:1,text:'hier $word',
    ));
    print('$word ${clock.elapsedMilliseconds}ms ${result.findings.map((f)=>'${f.originalText}: ${f.replacements}').toList()}');
  }
  await provider.dispose();
}
