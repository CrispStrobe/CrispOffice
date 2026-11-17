import 'package:quds_office_engine/quds_office_engine.dart';

import 'backend.dart';
import 'bundle.dart';
import 'source_text.dart';
import 'tokenizer.dart';

/// Explicit request-local reuse of identical deterministic model predictions.
///
/// Only selected raw tags are retained, never logits, guarded edits or complete
/// segment results. Reaching either cache limit simply stops retaining new
/// entries; it does not reject text or change the decoding policy.
final class GectorInferenceReuseOptions {
  GectorInferenceReuseOptions({
    this.maximumCachedInputs = 32,
    this.maximumCachedTokens = 2048,
  }) {
    if (maximumCachedInputs < 1 ||
        maximumCachedInputs > 128 ||
        maximumCachedTokens < 2 ||
        maximumCachedTokens > 4096) {
      throw ArgumentError('Invalid bounded GECToR inference-reuse options.');
    }
  }

  final int maximumCachedInputs;
  final int maximumCachedTokens;
}

/// Opt-in planning limits for complete, sentence-aware source slices.
///
/// [targetTokens] is a preferred size, including CLS/SEP. A sentence with no
/// admitted internal boundary may exceed it, up to the decoder's hard limit.
/// [maximumTotalTokens] counts the initial encoding of every planned slice,
/// including its own special tokens. Iterative decoding needs a separate work
/// limit because corrections can change the token count on subsequent passes.
final class GectorSegmentationOptions {
  GectorSegmentationOptions({
    this.targetTokens = 64,
    this.maximumSegments = 32,
    this.maximumTotalTokens = 4096,
    this.inferenceReuse,
  }) {
    if (targetTokens < 2 ||
        targetTokens > 512 ||
        maximumSegments < 1 ||
        maximumSegments > 128 ||
        maximumTotalTokens < 2 ||
        maximumTotalTokens > 32768) {
      throw ArgumentError('Invalid bounded GECToR segmentation options.');
    }
  }

  final int targetTokens;
  final int maximumSegments;
  final int maximumTotalTokens;

  /// Null preserves independent forwards, including stateful backend behavior.
  /// Enabling reuse requires [GectorDeterministicBackend] and guarded decoding.
  final GectorInferenceReuseOptions? inferenceReuse;
}

/// An exact slice of the original source, with original UTF-16 coordinates.
///
/// Whitespace and closing punctuation belong to the preceding sentence. The
/// planner never trims or normalizes [text], including the final source tail.
final class GectorTextSegment {
  const GectorTextSegment._({
    required this.start,
    required this.text,
    required this.initialTokenCount,
  });

  final int start;
  final String text;
  final int initialTokenCount;
  int get end => start + text.length;
}

/// Plans a complete bounded partition before any model inference starts.
///
/// This is a conservative punctuation heuristic, not a German sentence parser.
/// Ambiguous boundaries stay in the same slice. An unsplittable slice above the
/// hard token limit fails explicitly; there is no word or character fallback.
/// The ordinary short-input path retains the entire original source unchanged.
final class GectorSegmenter {
  GectorSegmenter({
    required this.configuration,
    required this.tokenizer,
    required this.options,
    this.maximumTokens = 512,
    this.maximumTextCodeUnits = 32768,
  }) {
    if (maximumTokens < 2 ||
        maximumTokens > 512 ||
        options.targetTokens > maximumTokens ||
        maximumTextCodeUnits < 1 ||
        maximumTextCodeUnits > 32768) {
      throw ArgumentError('Invalid bounded GECToR segmenter limits.');
    }
  }

  final GectorConfiguration configuration;
  final GectorTokenizer tokenizer;
  final GectorSegmentationOptions options;
  final int maximumTokens;
  final int maximumTextCodeUnits;

  List<GectorTextSegment> plan(String text) {
    if (text.length > maximumTextCodeUnits) {
      throw GectorCapacityException(
        'GECToR text exceeds $maximumTextCodeUnits UTF-16 units.',
      );
    }
    // Validate the complete source first, including surrogates beyond an early
    // token-limit failure. The same source view drives the unsplit fast path.
    final source = GectorSourceText(text, configuration);
    final segments = <GectorTextSegment>[];
    var totalTokens = 0;

    void add(int start, int end, int tokenCount) {
      if (segments.length >= options.maximumSegments) {
        throw GectorCapacityException(
          'GECToR input exceeds ${options.maximumSegments} complete segments; '
          'no text was truncated.',
        );
      }
      totalTokens += tokenCount;
      if (totalTokens > options.maximumTotalTokens) {
        throw GectorCapacityException(
          'GECToR segmented input exceeds ${options.maximumTotalTokens} '
          'initial wordpieces; no text was truncated.',
        );
      }
      segments.add(
        GectorTextSegment._(
          start: start,
          text: text.substring(start, end),
          initialTokenCount: tokenCount,
        ),
      );
    }

    int? shortTokens;
    try {
      shortTokens = tokenizer
          .encode(
            source.words(source.plain),
            maximumTokens: options.targetTokens,
          )
          .tokenCount;
    } on GectorCapacityException {
      // Only the preferred token size triggers planning. Invalid source or
      // tokenizer input must not be hidden by a segmentation fallback.
    }
    if (shortTokens != null) {
      add(0, text.length, shortTokens);
      return List<GectorTextSegment>.unmodifiable(segments);
    }

    var start = 0;
    var pendingEnd = 0;
    var pendingTokens = 0;
    for (final end in _sentenceEnds(source)) {
      int? combinedTokens;
      try {
        combinedTokens = _tokenCount(
          text.substring(start, end),
          options.targetTokens,
        );
      } on GectorCapacityException {
        // Flush the preceding complete sentence group, then admit the next
        // sentence intact only if it fits the hard model limit.
      }
      if (combinedTokens != null) {
        pendingEnd = end;
        pendingTokens = combinedTokens;
        continue;
      }
      if (pendingEnd > start) {
        add(start, pendingEnd, pendingTokens);
        start = pendingEnd;
      }
      final tokens = _tokenCount(text.substring(start, end), maximumTokens);
      if (tokens > options.targetTokens) {
        add(start, end, tokens);
        start = end;
        pendingEnd = end;
        pendingTokens = 0;
      } else {
        pendingEnd = end;
        pendingTokens = tokens;
      }
    }
    if (pendingEnd > start) add(start, pendingEnd, pendingTokens);
    return List<GectorTextSegment>.unmodifiable(segments);
  }

  int _tokenCount(String text, int limit) {
    final source = GectorSourceText(text, configuration);
    return tokenizer
        .encode(source.words(source.plain), maximumTokens: limit)
        .tokenCount;
  }

  Iterable<int> _sentenceEnds(GectorSourceText source) sync* {
    final text = source.original;
    final boundaries = source.graphemeBoundaries;
    final protected = OfficeProofingTextRanges(text).ranges;
    final closingStack = <String>[];
    var protectedIndex = 0;
    for (var i = 0; i < text.length; i++) {
      while (protectedIndex < protected.length &&
          protected[protectedIndex].end <= i) {
        protectedIndex++;
      }
      if (protectedIndex < protected.length &&
          protected[protectedIndex].start <= i) {
        // Punctuation and unbalanced delimiters inside links/code do not make
        // sentence boundaries or change the surrounding prose's delimiter state.
        i = protected[protectedIndex].end - 1;
        continue;
      }
      final char = text[i];
      if (!_terminators.contains(char)) {
        _trackDelimiter(text, i, closingStack);
        continue;
      }
      if (i > 0 && _terminators.contains(text[i - 1])) continue;
      var punctuationEnd = i + 1;
      while (punctuationEnd < text.length &&
          _terminators.contains(text[punctuationEnd])) {
        punctuationEnd++;
      }
      final punctuation = text.substring(i, punctuationEnd);
      if (punctuation.contains('.') && punctuation != '.') continue;
      if (punctuation == '.' && !_periodCanEnd(text, i)) continue;

      var closingEnd = punctuationEnd;
      // Inspect the existing stack by depth instead of copying it for every
      // terminator. Deep unmatched delimiters followed by many short sentences
      // must not turn bounded source planning into quadratic allocation/work.
      var remainingDepth = closingStack.length;
      var mismatched = false;
      while (closingEnd < text.length &&
          _closingDelimiters.contains(text[closingEnd])) {
        if (remainingDepth == 0 ||
            closingStack[remainingDepth - 1] != text[closingEnd]) {
          mismatched = true;
          break;
        }
        remainingDepth--;
        closingEnd++;
      }
      if (mismatched || remainingDepth != 0) continue;
      var gapEnd = closingEnd;
      while (gapEnd < text.length && _whitespace.hasMatch(text[gapEnd])) {
        gapEnd++;
      }
      if (gapEnd == closingEnd ||
          gapEnd == text.length ||
          !boundaries.contains(gapEnd) ||
          !_plausibleStart(text, gapEnd)) {
        continue;
      }
      yield gapEnd;
    }
    // Always retain the complete final tail, including whitespace and an
    // unfinished sentence. There are no empty interior slices or omitted gaps.
    yield text.length;
  }

  static bool _periodCanEnd(String text, int at) {
    final previous = _previousWord(text, at);
    if (previous.isEmpty ||
        _endsInNumber.hasMatch(previous) ||
        _singleLetter.hasMatch(previous) ||
        _shortAllCaps.hasMatch(previous) ||
        _abbreviations.contains(previous.toLowerCase())) {
      return false;
    }
    return true;
  }

  static String _previousWord(String text, int end) {
    var start = end;
    while (start > 0) {
      final before = _scalarStartBefore(text, start);
      if (!_wordCharacter.hasMatch(text.substring(before, start))) break;
      start = before;
    }
    return text.substring(start, end);
  }

  static bool _plausibleStart(String text, int at) {
    while (at < text.length &&
        (_openingDelimiters.containsKey(text[at]) ||
            _whitespace.hasMatch(text[at]))) {
      at++;
    }
    if (at == text.length) return false;
    final end = _scalarEndAfter(text, at);
    return _sentenceInitial.hasMatch(text.substring(at, end));
  }

  static void _trackDelimiter(String text, int at, List<String> closingStack) {
    final char = text[at];
    if ((char == "'" || char == '’') &&
        _wordBefore(text, at) &&
        _wordAfter(text, at + 1)) {
      return;
    }
    if (closingStack.isNotEmpty && closingStack.last == char) {
      closingStack.removeLast();
      return;
    }
    // A trailing genitive apostrophe is not an opening quotation mark.
    if (char == "'" && _wordBefore(text, at)) return;
    final closing = _openingDelimiters[char];
    if (closing != null) closingStack.add(closing);
  }

  static bool _wordBefore(String text, int at) =>
      at > 0 &&
      _wordCharacter.hasMatch(text.substring(_scalarStartBefore(text, at), at));

  static bool _wordAfter(String text, int at) =>
      at < text.length &&
      _wordCharacter.hasMatch(text.substring(at, _scalarEndAfter(text, at)));

  static int _scalarStartBefore(String text, int end) {
    final unit = text.codeUnitAt(end - 1);
    return unit >= 0xdc00 && unit <= 0xdfff ? end - 2 : end - 1;
  }

  static int _scalarEndAfter(String text, int start) {
    final unit = text.codeUnitAt(start);
    return unit >= 0xd800 && unit <= 0xdbff ? start + 2 : start + 1;
  }

  static const _terminators = '.!?';
  static const _closingDelimiters = ')]}“”‘’»›"\'';
  static const _openingDelimiters = <String, String>{
    '(': ')',
    '[': ']',
    '{': '}',
    '„': '“',
    '“': '”',
    '«': '»',
    '‹': '›',
    '‚': '‘',
    '‘': '’',
    '"': '"',
    "'": "'",
  };
  static final _whitespace = RegExp(
    r'^[\s\u0085\u001c-\u001f]$',
    unicode: true,
  );
  static final _wordCharacter = RegExp(r'^[\p{L}\p{M}\p{N}]$', unicode: true);
  static final _singleLetter = RegExp(r'^\p{L}\p{M}*$', unicode: true);
  static final _shortAllCaps = RegExp(r'^[\p{Lu}\p{Lt}]{2,5}$', unicode: true);
  static final _endsInNumber = RegExp(r'\p{N}$', unicode: true);
  static final _sentenceInitial = RegExp(
    r'^[\p{Lu}\p{Lt}\p{N}]$',
    unicode: true,
  );
  static const _abbreviations = <String>{
    'abb',
    'abs',
    'abschn',
    'abt',
    'aufl',
    'bspw',
    'bzw',
    'ca',
    'dipl',
    'dr',
    'etc',
    'evtl',
    'exkl',
    'fr',
    'geb',
    'gest',
    'ggf',
    'hr',
    'hrn',
    'inkl',
    'ing',
    'jg',
    'jh',
    'kap',
    'max',
    'min',
    'mr',
    'mrs',
    'nr',
    'prof',
    'sog',
    'str',
    'tel',
    'usw',
    'vgl',
    'zzgl',
  };
}
