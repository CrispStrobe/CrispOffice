import 'package:quds_office_engine/quds_office_engine.dart';

/// Text presented to Harper, with a reversible range map to the Word source.
///
/// A discretionary soft hyphen is a layout instruction, not part of an English
/// word. It is omitted from the checker input only. Source ranges continue to
/// include controls inside a finding, and document text is never rewritten by
/// this projection. Other punctuation, joiners and line breaks remain literal.
final class HarperSourceText {
  HarperSourceText(String source) : _sourceLength = source.length {
    final buffer = StringBuffer();
    var offset = 0;
    for (final rune in source.runes) {
      final end = offset + (rune > 0xffff ? 2 : 1);
      if (rune != 0x00ad) {
        buffer.writeCharCode(rune);
        _starts.add(offset);
        _ends.add(end);
      }
      offset = end;
    }
    text = buffer.toString();
    _sourceBoundaries.addAll(
      GraphemeClusters.segment(source).map((cluster) => cluster.end),
    );
    var scalar = 0;
    for (final cluster in GraphemeClusters.segment(text)) {
      scalar += cluster.text.runes.length;
      _checkBoundaries.add(scalar);
    }
  }

  late final String text;
  final int _sourceLength;
  final List<int> _starts = <int>[];
  final List<int> _ends = <int>[];
  final Set<int> _sourceBoundaries = <int>{0};
  final Set<int> _checkBoundaries = <int>{0};

  int get scalarLength => _starts.length;

  /// Maps a checked Unicode-scalar interval to source UTF-16 in constant time.
  /// Invalid backend offsets throw. A valid interval that would split a
  /// grapheme in either representation is omitted, as in German proofing.
  ///
  /// At an insertion point adjacent to omitted controls, insert immediately
  /// before the next visible scalar (or at source end). A nonempty interval
  /// owns only the controls between its first and last retained scalars.
  ({int start, int end})? sourceRange(int start, int end) {
    if (start < 0 || end < start || end > scalarLength) {
      throw RangeError('Invalid Harper scalar range: $start..$end');
    }
    if (!_checkBoundaries.contains(start) || !_checkBoundaries.contains(end)) {
      return null;
    }
    final sourceStart = start == scalarLength ? _sourceLength : _starts[start];
    final sourceEnd = start == end ? sourceStart : _ends[end - 1];
    if (!_sourceBoundaries.contains(sourceStart) ||
        !_sourceBoundaries.contains(sourceEnd)) {
      return null;
    }
    return (start: sourceStart, end: sourceEnd);
  }
}
