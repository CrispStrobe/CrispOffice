@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Native/web parity of the context model on a fixed panel.
///
/// QUDS_ARABIC_MORPH_TEST_LIBRARY, _BUNDLE and _MODEL select the native
/// library and the verified database and context model bundles (as in
/// arabic_morph_native_test.dart). QUDS_ARABIC_MORPH_WEB_PARITY is the JSON
/// that `node tool/disambig_parity.mjs` wrote from the shipped Wasm worker
/// for test/fixtures/disambig_parity_panel.json. That buffer is decoded with
/// the decoder the web transport uses and must equal the native readings:
/// the same analyses in the same order, bit-identical scores and the same
/// ranks, hence the same lemma and POS choice for every token. When
/// test/fixtures/disambig_parity_expected.json exists, both paths must also
/// make exactly its recorded choices. QUDS_ARABIC_MORPH_PARITY_REPORT, when
/// set, receives the choices (the source of that expected file).
final _env = Platform.environment;
final _library = _env['QUDS_ARABIC_MORPH_TEST_LIBRARY'];
final _bundle = _env['QUDS_ARABIC_MORPH_TEST_BUNDLE'];
final _model = _env['QUDS_ARABIC_MORPH_TEST_MODEL'];
final _web = _env['QUDS_ARABIC_MORPH_WEB_PARITY'];
final Object _skip =
    _library == null || _bundle == null || _model == null || _web == null
    ? 'Set QUDS_ARABIC_MORPH_TEST_LIBRARY, _BUNDLE, _MODEL and '
          'QUDS_ARABIC_MORPH_WEB_PARITY.'
    : false;

const _panelPath = 'test/fixtures/disambig_parity_panel.json';
const _expectedPath = 'test/fixtures/disambig_parity_expected.json';

/// Camel Morph POS tag -> Universal Dependencies UPOS (camel_tools tag set).
/// Derived from the chosen `pos`, so equal POS choices give equal UPOS.
String upos(String? pos) => switch (pos) {
  null => 'X',
  'noun' || 'noun_quant' => 'NOUN',
  'noun_prop' => 'PROPN',
  'noun_num' || 'adj_num' || 'digit' => 'NUM',
  'adj' || 'adj_comp' => 'ADJ',
  'adv' || 'adv_interrog' || 'adv_rel' => 'ADV',
  'pron' || 'pron_dem' || 'pron_exclam' || 'pron_interrog' || 'pron_rel' =>
    'PRON',
  'verb' => 'VERB',
  'verb_pseudo' => 'AUX',
  'prep' => 'ADP',
  'conj' => 'CCONJ',
  'conj_sub' => 'SCONJ',
  'interj' => 'INTJ',
  'punc' => 'PUNCT',
  'part_det' => 'DET',
  final p when p.startsWith('part') => 'PART',
  _ => 'X',
};

/// The best reading's choice for one token (`-` when it has no analyses).
Map<String, String> choice(String word, ArabicContextReading reading) {
  final best = reading.analyses.isEmpty ? null : reading.best.first;
  return {
    'word': word,
    'lex': best?['lex'] ?? '-',
    'pos': best?['pos'] ?? '-',
    'upos': best == null ? '-' : upos(best['pos']),
  };
}

void main() {
  test('the Wasm worker ranks the panel exactly like the native library', () async {
    final panel =
        (jsonDecode(File(_panelPath).readAsStringSync())
                as Map<String, Object?>)['sentences']!
            as List;
    final sentences = [
      for (final s in panel) [for (final w in s as List) w as String],
    ];
    final words = [for (final s in sentences) ...s];

    final web = jsonDecode(File(_web!).readAsStringSync()) as Map;
    expect(web['words'], words.length);
    expect(web['sentence_lengths'], [for (final s in sentences) s.length]);
    expect(web['model_format'], 'crispembed-camel-morph-disambig-v1');
    final webReadings = CompactAnalysisDecoder(
      (web['keys'] as List).cast<String>(),
    ).decodeReadings(
      Uint8List.fromList(base64Decode(web['buffer_base64'] as String)),
      words.length,
    );

    final morphology = CamelArabicMorphology(
      database: MorphDatabaseFiles(
        camelMorphMsaProofingBin,
        manifestPath: '$_bundle/manifest.json',
      ),
      disambiguator: MorphDatabaseFiles(
        camelMorphMsaDisambig,
        manifestPath: '$_model/manifest.json',
      ),
      nativeLibraryPath: _library,
    );
    addTearDown(morphology.dispose);
    await morphology.load();
    expect(morphology.canDisambiguate, isTrue);
    final nativeReadings = [
      for (final s in await morphology.disambiguate(sentences)) ...s,
    ];
    expect(nativeReadings, hasLength(words.length));

    var analyses = 0;
    final choices = <Map<String, String>>[];
    for (var i = 0; i < words.length; i++) {
      final n = nativeReadings[i];
      final w = webReadings[i];
      final where = 'token $i (${words[i]})';
      expect(w.analyses.length, n.analyses.length, reason: where);
      for (var a = 0; a < n.analyses.length; a++) {
        expect(
          Map<String, String>.of(w.analyses[a]),
          Map<String, String>.of(n.analyses[a]),
          reason: '$where analysis $a',
        );
      }
      // Scores travel as float32 in both buffers: compare exactly.
      expect(w.scores, n.scores, reason: '$where scores');
      expect(w.ranks, n.ranks, reason: '$where ranks');
      final native = choice(words[i], n);
      expect(choice(words[i], w), native, reason: where);
      choices.add(native);
      analyses += n.analyses.length;
    }
    // The panel exercises ambiguity, not only unambiguous tokens.
    expect(analyses, greaterThan(words.length * 2));

    final report = {
      'panel': _panelPath,
      'model': '${camelMorphMsaDisambig.repository}@'
          '${camelMorphMsaDisambig.revision}/${camelMorphMsaDisambig.directory}',
      'tokens': words.length,
      'analyses': analyses,
      'web_buffer_sha256': web['buffer_sha256'],
      'choices': choices,
    };
    final out = _env['QUDS_ARABIC_MORPH_PARITY_REPORT'];
    if (out != null) {
      File(out).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
    final expected = File(_expectedPath);
    if (expected.existsSync()) {
      final golden =
          (jsonDecode(expected.readAsStringSync()) as Map)['choices'] as List;
      expect(
        choices,
        [for (final c in golden) Map<String, String>.from(c as Map)],
        reason: 'both paths must keep the recorded panel choices',
      );
    }
  }, skip: _skip);
}
