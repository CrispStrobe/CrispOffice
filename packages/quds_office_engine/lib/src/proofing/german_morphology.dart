import 'dart:async';
import 'dart:convert';

import '../opc/zip/deflate_codec.dart';
import 'data/german_morphology_data.dart';
import 'german_spelling.dart' show normalizeGermanWord;

/// A noun analysis with all licensed alternatives for one gender and number.
///
/// Gender indexes are masculine, feminine, neuter, plural (0..3). Case indexes
/// are nominative, accusative, dative, genitive (0..3). These stable internal
/// indexes match the phrase analyzer without making its private enums public.
/// A reading is evidence, not a spelling guarantee or a sentence parse.
final class GermanNounReading {
  GermanNounReading._(this.lemma, this._stem, this._pattern);

  final String lemma;
  final String _stem;
  final _GermanNounPattern _pattern;
  List<Set<String>?>? _forms;

  int get gender => _pattern.gender;

  /// All valid recorded alternatives. The collection cannot be mutated by a
  /// caller, and is constructed only when this reading is actually inspected.
  Set<String> formsForCase(int caseIndex) {
    RangeError.checkValidIndex(caseIndex, _pattern.endings, 'caseIndex');
    final List<Set<String>?> forms = _forms ??= List<Set<String>?>.filled(
      4,
      null,
    );
    return forms[caseIndex] ??= Set<String>.unmodifiable(
      _pattern.endings[caseIndex].map((String ending) => '$_stem$ending'),
    );
  }
}

final class _GermanNounPattern {
  _GermanNounPattern(String encoded) {
    final List<String> fields = encoded.split('\t');
    if (fields.length != 5) {
      throw const FormatException('Invalid German noun pattern');
    }
    gender = int.parse(fields.first);
    if (gender < 0 || gender > 3) {
      throw const FormatException('Invalid German noun gender');
    }
    endings = <List<String>>[
      for (final String field in fields.skip(1))
        List<String>.unmodifiable(field.split('|')),
    ];
    allEndings = <String>{for (final List<String> values in endings) ...values};
  }

  late final int gender;
  late final List<List<String>> endings;
  late final Set<String> allEndings;
}

/// Offline German lexical morphology derived from Unicode Inflection.
///
/// The generated resource has separately pinned Unicode-3.0 provenance and
/// includes its full notice. Noun suggestions must pass [acceptsSpelling];
/// lexical evidence never adds words to [GermanSpellingProvider]'s dictionary.
/// Unknown words return no readings. Homographs retain every selected reading.
///
/// Initialization is shared by providers and yields between bounded chunks on
/// both Dart VM and JavaScript. No file, network, FFI or isolate is required.
final class GermanNounMorphology {
  GermanNounMorphology._();

  static final GermanNounMorphology shared = GermanNounMorphology._();

  Future<void>? _loading;
  bool _loaded = false;
  Map<String, List<GermanNounReading>> _forms =
      <String, List<GermanNounReading>>{};
  Set<String> _standardSpellings = <String>{};
  Set<String> _swissSpellings = <String>{};

  int get lemmaCount => germanMorphologyLemmaCount;
  int get readingCount => germanMorphologyReadingCount;
  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() {
    // A completed future can retain the zone of the initial caller (notably
    // a disposed Flutter test zone). Warm callers get their own completion.
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  static List<String> _decode(String chunk) => utf8
      .decode(RawDeflate.inflate(base64Decode(chunk), maxOutputBytes: 1048576))
      .split('\n');

  Future<void> _load() async {
    // Keep partial initialization private. Every concurrent caller awaits the
    // same future; no check observes half of the dictionary after a yield.
    final Map<String, List<GermanNounReading>> forms =
        <String, List<GermanNounReading>>{};
    final Set<String> standard = <String>{};
    final Set<String> swiss = <String>{};
    final List<_GermanNounPattern> patterns = germanMorphologyPatterns
        .map(_GermanNounPattern.new)
        .toList(growable: false);
    int count = 0;
    for (final String chunk in germanMorphologyNounChunks) {
      for (final String line in _decode(chunk)) {
        if (line.isEmpty) continue;
        final List<String> fields = line.split('\t');
        if (fields.length != 3) {
          throw const FormatException('Invalid German noun reading');
        }
        final _GermanNounPattern pattern = patterns[int.parse(fields[2])];
        final GermanNounReading reading = GermanNounReading._(
          fields[0],
          fields[1],
          pattern,
        );
        final Set<String> keys = <String>{};
        for (final String ending in pattern.allEndings) {
          final String key = '${fields[1]}$ending'.toLowerCase();
          keys.add(key);
          keys.add(key.replaceAll('ß', 'ss'));
        }
        for (final String key in keys) {
          forms.putIfAbsent(key, () => <GermanNounReading>[]).add(reading);
        }
        count++;
      }
      await Future<void>.delayed(Duration.zero);
    }
    if (count != germanMorphologyReadingCount) {
      throw const FormatException('Incomplete German noun resource');
    }
    for (final String chunk in germanMorphologySpellingChunks) {
      for (final String line in _decode(chunk)) {
        if (line.isEmpty) continue;
        final int separator = line.lastIndexOf('\t');
        if (separator <= 0) {
          throw const FormatException('Invalid German spelling guard');
        }
        final String form = line.substring(0, separator);
        switch (line.substring(separator + 1)) {
          case '1':
            standard.add(form);
          case '2':
            swiss.add(form);
          default:
            throw const FormatException('Invalid German spelling locale');
        }
      }
      await Future<void>.delayed(Duration.zero);
    }
    // Freeze only the shared lists. The map remains private and no method
    // mutates it after publication. Freeze in batches to retain UI scheduling.
    int frozen = 0;
    for (final String key in forms.keys) {
      forms[key] = List<GermanNounReading>.unmodifiable(forms[key]!);
      if (++frozen % 4096 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    _forms = forms;
    _standardSpellings = standard;
    _swissSpellings = swiss;
    _loaded = true;
  }

  List<GermanNounReading> lookup(String word) {
    if (!_loaded) throw StateError('Load German morphology before lookup');
    return _forms[normalizeGermanWord(word).toLowerCase()] ??
        const <GermanNounReading>[];
  }

  /// A finite intersection with the unchanged modern spelling vocabulary.
  /// Case remains significant. Swiss suggestions replace sharp-s with ss,
  /// matching the provider's later source-preserving presentation conversion.
  bool acceptsSpelling(String form, {bool swiss = false}) {
    if (!_loaded) throw StateError('Load German morphology before lookup');
    final String normalized = normalizeGermanWord(form);
    return swiss
        ? _swissSpellings.contains(
            normalized.replaceAll('ß', 'ss').replaceAll('ẞ', 'SS'),
          )
        : _standardSpellings.contains(normalized);
  }
}
