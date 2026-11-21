import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'labels.dart';
import 'presentation.dart';

enum MailReaderMode { full, preview }

/// Decoded-message operations shared by compact and full reader hosts.
///
/// Only rendering state is mutable. Source and attachment snapshots retain their
/// original ownership. This controller has no account, database or network port.
final class MailReaderController extends ChangeNotifier {
  MailReaderController({
    required MailParseResult result,
    this.mode = MailReaderMode.full,
    MailReadBudget? budget,
    bool preferHtml = true,
    this.labels = const MailReaderLabels(),
  }) : budget =
           budget ??
           (mode == MailReaderMode.preview
               ? const MailReadBudget.preview()
               : const MailReadBudget()),
       _result = result,
       _preferHtml = preferHtml {
    _presentation = buildMailPresentation(
      result,
      budget: this.budget,
      preferHtml: preferHtml,
      labels: labels,
    );
  }

  factory MailReaderController.fromBytes(
    Uint8List bytes, {
    required MailCodec codec,
    MailReaderMode mode = MailReaderMode.full,
    MailReadBudget? budget,
    bool preferHtml = true,
    MailReaderLabels labels = const MailReaderLabels(),
  }) {
    final limits =
        budget ??
        (mode == MailReaderMode.preview
            ? const MailReadBudget.preview()
            : const MailReadBudget());
    limits.validate();
    return MailReaderController(
      result: codec.parse(bytes, budget: limits),
      mode: mode,
      budget: limits,
      preferHtml: preferHtml,
      labels: labels,
    );
  }

  final MailReaderMode mode;
  final MailReadBudget budget;

  /// Header labels and formatting of the decoded text and the view.
  final MailReaderLabels labels;
  MailParseResult _result;
  late MailReaderPresentation _presentation;
  bool _preferHtml;
  bool _disposed = false;
  int _revision = 0;
  TextSelection _selection = const TextSelection.collapsed(offset: 0);
  List<TextRange> _matches = const [];
  String _query = '';
  bool _caseSensitive = false;
  bool _moreMatches = false;
  int _activeMatch = -1;
  final Map<String, MailInlineImage> _externalImages = {};

  MailParseResult get result => _result;
  MailReaderPresentation get presentation => _presentation;
  String get decodedText => _presentation.text;
  TextSelection get selection => _selection;
  List<TextRange> get searchMatches => _matches;
  String get searchQuery => _query;
  bool get searchHasMore => _moreMatches;
  int get activeSearchMatch => _activeMatch;
  bool get preferHtml => _preferHtml;
  bool get isDisposed => _disposed;
  int get revision => _revision;
  String get selectedText => _selection.textInside(decodedText);

  /// Replace the entire saved-message identity and invalidate pending UI actions.
  void replaceResult(MailParseResult value) {
    if (_disposed) return;
    _result = value;
    _externalImages.clear();
    _revision++;
    _presentation = buildMailPresentation(
      value,
      budget: budget,
      preferHtml: _preferHtml,
      labels: labels,
    );
    _selection = const TextSelection.collapsed(offset: 0);
    _runSearch();
    notifyListeners();
  }

  void setPreferHtml(bool value) {
    if (_disposed || _preferHtml == value) return;
    _preferHtml = value;
    _revision++;
    _presentation = buildMailPresentation(
      _result,
      budget: budget,
      preferHtml: value,
      labels: labels,
      externalImages: _externalImages.values,
    );
    _selection = const TextSelection.collapsed(offset: 0);
    _runSearch();
    notifyListeners();
  }

  /// Admits images loaded by an explicit host action for the current message.
  /// Only URLs exposed by the inert projection are accepted. Pixel dimensions
  /// are checked from the bytes, and the cumulative reader limits still apply.
  /// [expectedResult] prevents a late host completion attaching to a replacement.
  /// Returns the number of newly admitted images. An unsupported image keeps
  /// its placeholder; a batch admitting nothing leaves view state unchanged.
  int addImages(
    Iterable<MailInlineImage> extra, {
    MailParseResult? expectedResult,
  }) {
    if (_disposed ||
        _presentation.rejected ||
        expectedResult != null && !identical(expectedResult, _result)) {
      return 0;
    }
    final candidates = Map<String, MailInlineImage>.of(_externalImages);
    for (final image in extra.take(8)) {
      final path = image.attachment.partPath;
      if (!path.startsWith('remote:')) continue;
      final uri = Uri.tryParse(path.substring(7));
      if (uri == null || !_presentation.remoteImageUrls.contains(uri)) continue;
      if (candidates.length >= 8 && !candidates.containsKey(path)) continue;
      candidates[path] = image;
    }
    if (candidates.length == _externalImages.length &&
        candidates.entries.every(
          (entry) => identical(entry.value, _externalImages[entry.key]),
        )) {
      return 0;
    }
    final rebuilt = buildMailPresentation(
      _result,
      budget: budget,
      preferHtml: _preferHtml,
      labels: labels,
      externalImages: candidates.values,
    );
    if (rebuilt.rejected) return 0;
    final admitted = {
      for (final image in rebuilt.images)
        if (image.attachment.partPath.startsWith('remote:'))
          image.attachment.partPath: image,
    };
    final count = admitted.keys
        .where((path) => !_externalImages.containsKey(path))
        .length;
    if (count == 0) return 0;
    _presentation = rebuilt;
    _externalImages
      ..clear()
      ..addAll(admitted);
    _selection = const TextSelection.collapsed(offset: 0);
    _runSearch();
    _revision++;
    notifyListeners();
    return count;
  }

  /// Offsets use UTF-16 like Flutter. Selection snaps to grapheme boundaries.
  void select(TextSelection value) {
    if (_disposed) return;
    final start = value.start.clamp(0, decodedText.length);
    final end = value.end.clamp(0, decodedText.length);
    var offset = 0, snappedStart = 0, snappedEnd = 0;
    for (final grapheme in decodedText.characters) {
      final next = offset + grapheme.length;
      if (offset <= start) snappedStart = offset;
      if (next <= end) snappedEnd = next;
      if (offset < end && next > end) snappedEnd = next;
      offset = next;
      if (offset > end) break;
    }
    if (start == decodedText.length) snappedStart = start;
    if (value.isCollapsed) snappedEnd = snappedStart;
    final selection = TextSelection(
      baseOffset: value.baseOffset <= value.extentOffset
          ? snappedStart
          : snappedEnd,
      extentOffset: value.baseOffset <= value.extentOffset
          ? snappedEnd
          : snappedStart,
    );
    if (selection == _selection) return;
    _selection = selection;
    notifyListeners();
  }

  void selectAll() =>
      select(TextSelection(baseOffset: 0, extentOffset: decodedText.length));

  void selectWordAt(int offset) {
    if (_disposed || decodedText.isEmpty) return;
    final bounded = offset.clamp(0, decodedText.length - 1);
    var start = bounded, end = bounded;
    bool whitespace(int i) => RegExp(r'\s').hasMatch(decodedText[i]);
    while (start > 0 && !whitespace(start - 1)) {
      start--;
    }
    while (end < decodedText.length && !whitespace(end)) {
      end++;
    }
    select(TextSelection(baseOffset: start, extentOffset: end));
  }

  /// Searches the exact displayed decoded projection; raw MIME is unchanged.
  /// Up to 1,000 matches are retained. [searchHasMore] reports the explicit cap.
  void search(String query, {bool caseSensitive = false}) {
    if (_disposed) return;
    if (query.length > 2048) {
      throw ArgumentError('Search text exceeds 2048 code units.');
    }
    _query = query;
    _caseSensitive = caseSensitive;
    _runSearch();
    notifyListeners();
  }

  void _runSearch() {
    _activeMatch = -1;
    _moreMatches = false;
    if (_query.isEmpty) {
      _matches = const [];
      return;
    }
    final expression = RegExp(
      RegExp.escape(_query),
      caseSensitive: _caseSensitive,
      unicode: true,
    );
    final matches = <TextRange>[];
    for (final match in expression.allMatches(decodedText)) {
      if (matches.length == 1000) {
        _moreMatches = true;
        break;
      }
      matches.add(TextRange(start: match.start, end: match.end));
    }
    _matches = List.unmodifiable(matches);
  }

  TextRange? nextSearchMatch({bool backwards = false}) {
    if (_disposed || _matches.isEmpty) return null;
    _activeMatch = backwards
        ? (_activeMatch <= 0 ? _matches.length - 1 : _activeMatch - 1)
        : (_activeMatch + 1) % _matches.length;
    final range = _matches[_activeMatch];
    select(TextSelection(baseOffset: range.start, extentOffset: range.end));
    // select may be unchanged, but the current result indicator still changes.
    notifyListeners();
    return range;
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
