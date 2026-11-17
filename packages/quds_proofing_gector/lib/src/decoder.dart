// Adapted from Proofbird quickstart.py, Apache-2.0. See NOTICE and third_party/.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'backend.dart';
import 'bundle.dart';
import 'guards.dart';
import 'source_text.dart';
import 'tokenizer.dart';
import 'unicode_case.dart';

final class GectorDecodeOptions {
  GectorDecodeOptions({
    this.maximumPasses = 5,
    this.maximumTokens = 512,
    this.maximumTextCodeUnits = 32768,
    this.keepConfidence = 0.0,
    this.minimumErrorProbability = 0.0,
  }) {
    if (maximumPasses < 1 ||
        maximumPasses > 5 ||
        maximumTokens < 2 ||
        maximumTokens > 512 ||
        maximumTextCodeUnits < 1 ||
        maximumTextCodeUnits > 32768 ||
        !keepConfidence.isFinite ||
        keepConfidence < 0 ||
        keepConfidence > 1 ||
        !minimumErrorProbability.isFinite ||
        minimumErrorProbability < 0 ||
        minimumErrorProbability > 1) {
      throw ArgumentError('Invalid bounded GECToR decoding options.');
    }
  }
  final int maximumPasses;
  final int maximumTokens;
  final int maximumTextCodeUnits;
  final double keepConfidence;
  final double minimumErrorProbability;
}

final class GectorTag {
  const GectorTag(this.label, this.probability, this.incorrectProbability);
  final String label;
  final double probability;
  final double incorrectProbability;
}

final class GectorPass {
  GectorPass({
    required Iterable<String> words,
    required this.input,
    required Iterable<GectorTag> tags,
    required Iterable<String> editedWords,
    required this.inferenceMicroseconds,
  }) : words = List<String>.unmodifiable(words),
       tags = List<GectorTag>.unmodifiable(tags),
       editedWords = List<String>.unmodifiable(editedWords);
  final List<String> words;
  final GectorPreparedInput input;
  final List<GectorTag> tags;
  final List<String> editedWords;
  final int inferenceMicroseconds;
}

enum GectorStopReason { stable, cycle, passLimit }

final class GectorDecodedText {
  GectorDecodedText({
    required this.original,
    required this.corrected,
    required Iterable<GectorEdit> edits,
    required Iterable<GectorPass> passes,
    required this.stopReason,
    required this.guarded,
  }) : edits = List<GectorEdit>.unmodifiable(edits),
       passes = List<GectorPass>.unmodifiable(passes);
  final String original;
  final String corrected;
  final List<GectorEdit> edits;
  final List<GectorPass> passes;
  final GectorStopReason stopReason;
  final bool guarded;
  bool get complete => stopReason == GectorStopReason.stable;
}

/// Backend-neutral iterative decoder. Reference mode is explicit and intended
/// for parity tooling only; the Office provider always creates guarded mode.
final class GectorDecoder {
  GectorDecoder.guarded({
    required this.configuration,
    required this.tokenizer,
    required this.backend,
    required GectorGermanGuards this.guards,
    GectorDecodeOptions? options,
  }) : options = options ?? GectorDecodeOptions();

  GectorDecoder.reference({
    required this.configuration,
    required this.tokenizer,
    required this.backend,
    GectorDecodeOptions? options,
  }) : guards = null,
       options = options ?? GectorDecodeOptions();

  final GectorConfiguration configuration;
  final GectorTokenizer tokenizer;
  final GectorBackend backend;
  final GectorGermanGuards? guards;
  final GectorDecodeOptions options;

  Future<GectorDecodedText> correct(
    String text, {
    Set<String> personalWords = const <String>{},
    bool Function()? isCancelled,
  }) async {
    if (text.length > options.maximumTextCodeUnits) {
      throw GectorCapacityException(
        'GECToR text exceeds ${options.maximumTextCodeUnits} UTF-16 units.',
      );
    }
    void cancellationPoint() {
      if (isCancelled?.call() ?? false) throw const GectorCancelledException();
    }

    cancellationPoint();
    final source = GectorSourceText(text, configuration);
    var words = source.words(source.plain);
    final passes = <GectorPass>[];
    final seen = <String>{jsonEncode(words)};
    var reason = GectorStopReason.passLimit;
    guards?.beginRequest();
    if (words.isEmpty) {
      return GectorDecodedText(
        original: text,
        corrected: text,
        edits: const [],
        passes: const [],
        stopReason: GectorStopReason.stable,
        guarded: guards != null,
      );
    }
    for (var pass = 0; pass < options.maximumPasses; pass++) {
      // Allow the isolate to process cancellation between synchronous native
      // forwards; no UI-isolate work or per-request model construction occurs.
      await Future<void>.delayed(Duration.zero);
      cancellationPoint();
      final input = tokenizer.encode(
        words,
        maximumTokens: options.maximumTokens,
      );
      final timer = Stopwatch()..start();
      final logits = await backend.forward(input);
      timer.stop();
      cancellationPoint();
      logits.validate(input, configuration.labels.length);
      final tags = selectTags(input, logits);
      if (tags.length != words.length + 1) {
        throw const FormatException('GECToR word/tag alignment is incomplete.');
      }
      final edited = <String>[];
      for (var i = 0; i < tags.length; i++) {
        cancellationPoint();
        final word = i == 0 ? r'$START' : words[i - 1];
        var replacement = edit(word, tags[i].label);
        if (guards case final policy?) {
          replacement = await policy.apply(
            words: words,
            index: i - 1,
            label: tags[i].label,
            replacement: replacement,
            personalWords: personalWords,
          );
        }
        edited.add(replacement);
      }
      if (guards != null) _retainOneDuplicate(words, edited);
      final intermediate = edited
          .where((value) => value.isNotEmpty)
          .join(' ')
          .replaceAll(r' $MERGE_HYPHEN ', '-')
          .replaceAll(r' $MERGE_SPACE ', '');
      final tokens = GectorSourceText.splitWhitespace(
        intermediate,
      ).where((token) => token != r'$START');
      final newWords = <String>[
        for (final token in GectorSourceText.rejoin(tokens))
          ...source.words(token),
      ];
      passes.add(
        GectorPass(
          words: words,
          input: input,
          tags: tags,
          editedWords: newWords,
          inferenceMicroseconds: timer.elapsedMicroseconds,
        ),
      );
      if (_equalWords(newWords, words)) {
        reason = GectorStopReason.stable;
        break;
      }
      words = newWords;
      if (!seen.add(jsonEncode(words))) {
        reason = GectorStopReason.cycle;
        break;
      }
    }
    cancellationPoint();
    final edits = source.suggestions(words);
    return GectorDecodedText(
      original: text,
      corrected: source.apply(edits),
      edits: edits,
      passes: passes,
      stopReason: reason,
      guarded: guards != null,
    );
  }

  List<GectorTag> selectTags(GectorPreparedInput input, GectorLogits logits) {
    final result = <GectorTag>[];
    for (final row in input.firstSubwordIndices) {
      final labelOffset = row * logits.labelCount;
      final scores = _softmax(logits.labels, labelOffset, logits.labelCount);
      scores[configuration.keepIndex] += options.keepConfidence;
      var best = 0;
      for (var i = 1; i < scores.length; i++) {
        if (scores[i] > scores[best]) best = i;
      }
      final detection = _softmax(logits.detection, row * 2, 2);
      final label = scores[best] >= options.minimumErrorProbability
          ? configuration.labels[best]
          : r'$KEEP';
      result.add(
        GectorTag(label, scores[best], detection[configuration.incorrectIndex]),
      );
    }
    if (result.every(
      (tag) => tag.incorrectProbability < options.minimumErrorProbability,
    )) {
      return <GectorTag>[
        for (final tag in result)
          GectorTag(r'$KEEP', tag.probability, tag.incorrectProbability),
      ];
    }
    return result;
  }

  String edit(String word, String label) {
    if (label.startsWith(r'$APPEND_')) return '$word ${label.substring(8)}';
    if (word == r'$START' || label == r'$KEEP') return word;
    if (label.startsWith(r'$REPLACE_')) return label.substring(9);
    if (label == r'$DELETE') return '';
    if (label.startsWith(r'$TRANSFORM_SUF_')) {
      final values = label.substring(15);
      final split = values.indexOf('_');
      if (split < 0) {
        throw const FormatException('Invalid GECToR suffix label.');
      }
      final old = values.substring(0, split);
      final next = values.substring(split + 1);
      return word.endsWith(old)
          ? word.substring(0, word.length - old.length) + next
          : word;
    }
    if (label.startsWith(r'$TRANSFORM_VERB_')) {
      return configuration.verbForms['${word}_${label.substring(16)}'] ?? word;
    }
    return switch (label) {
      r'$TRANSFORM_CASE_CAPITAL' => gectorCapital(word),
      r'$TRANSFORM_CASE_LOWER' => gectorLower(word),
      r'$TRANSFORM_CASE_UPPER' => gectorUpper(word),
      r'$TRANSFORM_AGREEMENT_PLURAL' => '${word}s',
      r'$TRANSFORM_AGREEMENT_SINGULAR' =>
        word.isEmpty
            ? ''
            : String.fromCharCodes(word.runes.take(word.runes.length - 1)),
      r'$TRANSFORM_SPLIT_HYPHEN' => word.replaceAll('-', ' '),
      r'$MERGE_HYPHEN' || r'$MERGE_SPACE' => '$word $label',
      '@@UNKNOWN@@' => word,
      _ => throw FormatException('Unsupported GECToR edit label: $label'),
    };
  }

  static List<double> _softmax(List<double> values, int offset, int count) {
    var maximum = double.negativeInfinity;
    for (var i = 0; i < count; i++) {
      maximum = math.max(maximum, values[offset + i]);
    }
    final result = List<double>.filled(count, 0);
    var total = 0.0;
    for (var i = 0; i < count; i++) {
      total += result[i] = math.exp(values[offset + i] - maximum);
    }
    for (var i = 0; i < count; i++) {
      result[i] /= total;
    }
    return result;
  }

  static bool _equalWords(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static void _retainOneDuplicate(List<String> words, List<String> edited) {
    for (var start = 0; start < words.length;) {
      var end = start + 1;
      while (end < words.length &&
          gectorLower(words[end]) == gectorLower(words[start])) {
        end++;
      }
      if (end - start > 1 &&
          edited.sublist(start + 1, end + 1).every((word) => word.isEmpty)) {
        edited[start + 1] = words[start];
      }
      start = end;
    }
  }
}
