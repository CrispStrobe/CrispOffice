import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'backend.dart';
import 'tokenizer.dart';

/// Open one exact bundle basename. Model bytes are hashed as a stream.
typedef GectorAssetReader = Stream<List<int>> Function(String name);

final class GectorAssetPin {
  const GectorAssetPin(this.bytes, this.sha256);
  final int bytes;
  final String sha256;
}

/// Parsed inference/decoding metadata. Production providers receive it only
/// through [GectorVerifiedBundle.load], which authenticates the source files.
final class GectorConfiguration {
  GectorConfiguration._({
    required this.labels,
    required this.keepIndex,
    required this.incorrectIndex,
    required this.stripTerminators,
    required this.gluedArticles,
    required this.verbForms,
  });

  factory GectorConfiguration.fromSources({
    required String config,
    required String languageRules,
    required String verbForms,
    int expectedLabelCount = 5000,
  }) {
    final cfg = _map(jsonDecode(config));
    final labelMap = _map(cfg['id2label']);
    final detection = _map(cfg['d_id2label']);
    if (cfg['language'] != 'de' ||
        cfg['tokenizer'] != 'wordpiece' ||
        cfg['start_token'] != r'$START' ||
        labelMap.length != expectedLabelCount ||
        detection.length != 2 ||
        detection['0'] != r'$CORRECT' ||
        detection['1'] != r'$INCORRECT') {
      throw const FormatException('Unsupported GECToR model metadata.');
    }
    final labels = <String>[];
    for (var index = 0; index < labelMap.length; index++) {
      final value = labelMap['$index'];
      if (value is! String || value.isEmpty || labels.contains(value)) {
        throw const FormatException('Missing or duplicate GECToR label.');
      }
      labels.add(value);
    }
    final keepIndex = labels.indexOf(r'$KEEP');
    if (keepIndex < 0 || cfg['keep_label'] != r'$KEEP') {
      throw const FormatException('Missing GECToR KEEP label.');
    }
    final rules = _map(jsonDecode(languageRules));
    if (rules['language'] != 'de' ||
        rules['version'] != 1 ||
        rules['stripTrailingTerminator'] is! bool) {
      throw const FormatException('Unsupported GECToR language rules.');
    }
    final rawStrip = rules['stripTerminators'] ?? '.!?';
    if (rawStrip is! String) {
      throw const FormatException('Invalid terminators.');
    }
    final Object? rawGlued = rules['elision'] == null
        ? rules['nonElidingArticles']
        : _map(rules['elision'])['nonElidingArticles'];
    if (rawGlued != null && rawGlued is! List<Object?>) {
      throw const FormatException('Invalid glued-article rules.');
    }
    final glued = <String>{};
    if (rawGlued is List<Object?>) {
      for (final value in rawGlued) {
        if (value is! String || value.isEmpty) {
          throw const FormatException('Invalid glued article.');
        }
        glued.add(value.toLowerCase());
      }
    }
    final verbs = <String, String>{};
    for (final raw in const LineSplitter().convert(verbForms)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final colon = line.indexOf(':');
      final separator = line.indexOf('_');
      if (colon < 0 ||
          separator < 1 ||
          separator >= colon - 1 ||
          line.indexOf(':', colon + 1) >= 0) {
        throw const FormatException('Malformed GECToR verb-form vocabulary.');
      }
      final key =
          '${line.substring(0, separator)}_${line.substring(colon + 1)}';
      final target = line.substring(separator + 1, colon);
      // The upstream vocabulary can repeat a mapping. Conflicting entries fail.
      if (verbs.containsKey(key) && verbs[key] != target) {
        throw const FormatException('Ambiguous GECToR verb-form vocabulary.');
      }
      verbs[key] = target;
    }
    return GectorConfiguration._(
      labels: List<String>.unmodifiable(labels),
      keepIndex: keepIndex,
      incorrectIndex: 1,
      stripTerminators: rules['stripTrailingTerminator'] == true
          ? rawStrip
          : '',
      gluedArticles: Set<String>.unmodifiable(glued),
      verbForms: Map<String, String>.unmodifiable(verbs),
    );
  }

  final List<String> labels;
  final int keepIndex;
  final int incorrectIndex;
  final String stripTerminators;
  final Set<String> gluedArticles;
  final Map<String, String> verbForms;
}

/// Authenticated metadata and model identity. No model weights are retained here.
/// Loading precedes provider construction and service deadlines.
final class GectorVerifiedBundle {
  GectorVerifiedBundle._(
    this.artifact,
    this.configuration,
    this.tokenizer,
    this.guardsJson,
    this.assetDigests,
  );

  static Future<GectorVerifiedBundle> load({
    required GectorAssetReader read,
    required GectorModelArtifact artifact,
  }) async {
    final texts = <String, String>{};
    final digests = <String, String>{};
    for (final entry in gectorBundleAssetPins.entries) {
      final collected = BytesBuilder(copy: false);
      await _verify(read, entry.key, entry.value, collect: collected);
      texts[entry.key] = utf8.decode(
        collected.takeBytes(),
        allowMalformed: false,
      );
      digests[entry.key] = entry.value.sha256;
    }
    await _verify(
      read,
      artifact.file,
      GectorAssetPin(artifact.bytes, artifact.sha256),
    );
    digests[artifact.file] = artifact.sha256;
    final configuration = GectorConfiguration.fromSources(
      config: texts['config.json']!,
      languageRules: texts['language-rules.json']!,
      verbForms: texts['verb-form-vocab.txt']!,
    );
    final tokenizer = GectorTokenizer.fromJson(texts['tokenizer.json']!);
    if (tokenizer.vocabulary.length != 31102) {
      throw const FormatException('Unexpected frozen GECToR vocabulary size.');
    }
    final vocabRows = const LineSplitter().convert(texts['vocab.txt']!);
    if (vocabRows.length != 31102) {
      throw const FormatException('Incomplete frozen GECToR vocabulary.');
    }
    for (var i = 0; i < vocabRows.length; i++) {
      if (tokenizer.vocabulary[vocabRows[i]] != i) {
        throw const FormatException(
          'GECToR tokenizer and vocabulary disagree.',
        );
      }
    }
    return GectorVerifiedBundle._(
      artifact,
      configuration,
      tokenizer,
      texts['gector-guards.json']!,
      Map<String, String>.unmodifiable(digests),
    );
  }

  final GectorModelArtifact artifact;
  final GectorConfiguration configuration;
  final GectorTokenizer tokenizer;
  final String guardsJson;
  final Map<String, String> assetDigests;

  static Future<void> _verify(
    GectorAssetReader read,
    String name,
    GectorAssetPin pin, {
    BytesBuilder? collect,
  }) async {
    var length = 0;
    Stream<List<int>> checked() async* {
      await for (final chunk in read(name)) {
        length += chunk.length;
        if (length > pin.bytes) {
          throw FormatException('Oversized GECToR asset: $name');
        }
        collect?.add(chunk);
        yield chunk;
      }
    }

    final actual = await sha256.bind(checked()).single;
    if (length != pin.bytes || actual.toString() != pin.sha256) {
      throw FormatException(
        'GECToR asset failed size/SHA-256 verification: $name',
      );
    }
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a GECToR JSON object.');
  }
  return value;
}

/// Immutable source bundle pins; model.onnx is replaced by the explicitly
/// pinned runtime artifact, whose source identity must remain this revision.
const Map<String, GectorAssetPin> gectorBundleAssetPins =
    <String, GectorAssetPin>{
      'LICENSE': GectorAssetPin(
        11358,
        'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30',
      ),
      'NOTICE': GectorAssetPin(
        444,
        '52b20b1d66a7eeb6765f1829f08daddca2c36cd2e6c995439a4860e8b71e29e3',
      ),
      'README.md': GectorAssetPin(
        13590,
        'e2e5120e6c25299f962120463936427056fd9b468c714a1bf785f555edabf00f',
      ),
      'quickstart.py': GectorAssetPin(
        12746,
        'f5ce68cc466b5891fc3f13280dc9db3a55bf9016505c2b2d84eb1d2cb07c2b40',
      ),
      'gector-meta.json': GectorAssetPin(
        930,
        'acb7edf298f6ac4ba8b83c628ad512404eadb6c43120c1878d4f3356ebd8b5a5',
      ),
      'config.json': GectorAssetPin(
        176821,
        'c870008059c0f354e1ebc30c816ae5f55fa14a77ffa7da5271310ccf5e24e170',
      ),
      'gector-guards.json': GectorAssetPin(
        6088,
        '57c4824e541d323e9cff4c543bd80cfd93c333d3be64cce83297bf5b8a44627a',
      ),
      'language-rules.json': GectorAssetPin(
        1155,
        '901b350a9c751fc95d51eb5ee3ba7b7f0d11b61c6cc17e67bce2996e17bc5815',
      ),
      'tokenizer_config.json': GectorAssetPin(
        370,
        '4e5738ad97f034b944ce8b7b8c3165f7a6333b524b7b77044f7e9e9b963f4dea',
      ),
      'tokenizer.json': GectorAssetPin(
        729060,
        '45253db94c657c7b89880de2c8872e10cd0561577e9393e1f5f4df27b0165087',
      ),
      'vocab.txt': GectorAssetPin(
        239836,
        'bf186f7fb9cb667d811c08b45ce64d1e8e262277bb053f05d1aef3e9f13039a3',
      ),
      'verb-form-vocab.txt': GectorAssetPin(
        121758,
        '7582e7c2f480d7e49ac18677195cfff4ad1d0c350b0448f1271aacf290205b68',
      ),
    };
