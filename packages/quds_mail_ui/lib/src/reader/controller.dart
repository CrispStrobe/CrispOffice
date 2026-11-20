import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

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
    );
  }

  factory MailReaderController.fromBytes(
    Uint8List bytes, {
    required MailCodec codec,
    MailReaderMode mode = MailReaderMode.full,
    MailReadBudget? budget,
    bool preferHtml = true,
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
    );
  }

  final MailReaderMode mode;
  final MailReadBudget budget;
  MailParseResult _result;
  late MailReaderPresentation _presentation;
  bool _preferHtml;
  bool _disposed = false;
  final List<MailInlineImage> _externalImages = [];
  int _revision = 0;
  TextSelection _selection = const TextSelection.collapsed(offset: 0);
  List<TextRange> _matches = const [];
  String _query = '';
  bool _caseSensitive = false;
  bool _moreMatches = false;
  int _activeMatch = -1;

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
    );
    _selection = const TextSelection.collapsed(offset: 0);
    _runSearch();
    notifyListeners();
  }

  void setPreferHtml(bool value) {
    if (_disposed || _preferHtml == value) return;
    _preferHtml = value;
    _revision++;
    _presentation = _withExternalImages();
    _selection = const TextSelection.collapsed(offset: 0);
    _runSearch();
    notifyListeners();
  }

  /// Appends admitted host-loaded images and returns the number added.
  ///
  /// Admission is incremental: an invalid or over-budget item does not discard
  /// earlier valid items. Nothing is fetched here; the host owns authorization.
  int addImages(Iterable<MailInlineImage> extra) {
    if (_disposed) return 0;
    final additions = extra.toList(growable: false);
    if (additions.isEmpty || _presentation.rejected) return 0;
    var pixels = _presentation.images.fold<int>(
      0,
      (total, image) => total + image.width * image.height,
    );
    var imageCount =
        (_result.message?.attachments.length ?? 0) + _externalImages.length;
    final known = {
      for (final image in [..._presentation.images, ..._externalImages])
        image.attachment.partPath,
    };
    final body = _result.message?.body;
    var decodedBytes =
        utf8.encode(body?.plainText ?? '').length +
        utf8.encode(body?.html ?? '').length;
    for (final attachment
        in _result.message?.attachments ?? <MailAttachment>[]) {
      decodedBytes += attachment.content.length;
    }
    for (final image in _externalImages) {
      decodedBytes += image.attachment.content.length;
    }
    var added = 0;
    for (final image in additions) {
      final dimensions = mailRasterDimensions(image.attachment);
      if (dimensions == null) continue;
      final count = dimensions.$1 * dimensions.$2;
      if (count > budget.maxImagePixels - pixels ||
          image.attachment.content.length > budget.maxAttachmentBytes ||
          image.attachment.content.length >
              budget.maxDecodedBytes - decodedBytes ||
          imageCount >= budget.maxAttachments ||
          !known.add(image.attachment.partPath)) {
        continue;
      }
      pixels += count;
      decodedBytes += image.attachment.content.length;
      imageCount++;
      _externalImages.add(
        MailInlineImage(
          attachment: image.attachment,
          width: dimensions.$1,
          height: dimensions.$2,
        ),
      );
      added++;
    }
    if (added == 0) return 0;
    _presentation = _withExternalImages();
    _revision++;
    _selection = const TextSelection.collapsed(offset: 0);
    _runSearch();
    notifyListeners();
    return added;
  }

  MailReaderPresentation _withExternalImages() {
    final base = buildMailPresentation(
      _result,
      budget: budget,
      preferHtml: _preferHtml,
    );
    if (base.rejected) return base;
    var pixels = base.images.fold<int>(
      0,
      (total, image) => total + image.width * image.height,
    );
    var count = _result.message?.attachments.length ?? 0;
    final admitted = <MailInlineImage>[];
    for (final image in _externalImages) {
      final imagePixels = image.width * image.height;
      if (imagePixels > budget.maxImagePixels - pixels ||
          count >= budget.maxAttachments) {
        continue;
      }
      pixels += imagePixels;
      count++;
      admitted.add(image);
    }
    if (admitted.isEmpty) return base;
    final loadedUris = <Uri>{
      for (final image in admitted)
        if (image.attachment.partPath.startsWith('remote:'))
          ?Uri.tryParse(image.attachment.partPath.substring(7)),
    };
    final rebuilt = buildMailPresentation(
      _result,
      budget: budget,
      preferHtml: _preferHtml,
      loadedRemoteImageUris: loadedUris,
    );
    if (rebuilt.rejected) return rebuilt;
    return MailReaderPresentation(
      text: rebuilt.text,
      bodyText: rebuilt.bodyText,
      runs: rebuilt.runs,
      images: <MailInlineImage>[...rebuilt.images, ...admitted],
      remoteImageUris: rebuilt.remoteImageUris,
      diagnostics: rebuilt.diagnostics,
      rejected: rebuilt.rejected,
      usedHtml: rebuilt.usedHtml,
      blockedResourceCount: rebuilt.blockedResourceCount,
    );
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
