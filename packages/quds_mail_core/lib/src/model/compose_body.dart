/// Alignment supported by the bounded Mail authoring format.
enum MailComposeAlignment { left, center, right, justify }

/// An immutable authored text span. No HTML or resource-loading attributes are
/// accepted. Paragraph construction normalizes CRLF/CR across span boundaries.
final class MailComposeRun {
  factory MailComposeRun({
    required String text,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strike = false,
    String? link,
  }) {
    _textBytes(text, limit: MailComposeBody.maxPlainTextBytes);
    if (link != null && !isSupportedLink(link)) _invalid();
    return MailComposeRun._(text, bold, italic, underline, strike, link);
  }

  const MailComposeRun._(
    this.text,
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.link,
  );

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final String? link;

  static const maxLinkBytes = 2048;

  /// Only explicit web links and one simple mailto address are supported.
  /// Credential-bearing, relative, local, executable and resource URLs are
  /// refused. mailto query parameters cannot add hidden recipients or content.
  static bool isSupportedLink(String value) {
    try {
      _textBytes(value, limit: maxLinkBytes, multiline: false);
      if (value.isEmpty || value.contains(RegExp(r'[\s\\]'))) return false;
      for (var i = 0; i < value.length; i++) {
        if (value.codeUnitAt(i) != 0x25) continue;
        if (i + 2 >= value.length ||
            !RegExp(r'^[0-9a-fA-F]{2}$')
                .hasMatch(value.substring(i + 1, i + 3))) {
          return false;
        }
        i += 2;
      }
      final decoded = Uri.decodeComponent(value);
      _textBytes(decoded, limit: maxLinkBytes, multiline: false);
      if (decoded.contains('\\')) return false;
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasScheme || uri.userInfo.isNotEmpty)
        return false;
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return uri.hasAuthority && uri.host.isNotEmpty && uri.port <= 65535;
      }
      if (uri.scheme != 'mailto' ||
          uri.hasAuthority ||
          uri.hasQuery ||
          uri.hasFragment) {
        return false;
      }
      final address = Uri.decodeComponent(uri.path);
      return address.length <= 254 &&
          RegExp(
            r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$",
          ).hasMatch(address) &&
          !address.startsWith('.') &&
          !address.contains('..') &&
          !address.contains('.@');
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  bool get hasFormatting =>
      bold || italic || underline || strike || link != null;

  bool _sameFormat(MailComposeRun other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      strike == other.strike &&
      link == other.link;

  MailComposeRun _withText(String value) =>
      MailComposeRun._(value, bold, italic, underline, strike, link);

  @override
  String toString() => 'MailComposeRun(redacted)';
}

/// A flat paragraph with explicitly bounded inline formatting. Lists, tables,
/// images and imported HTML are outside this format's first version.
final class MailComposeParagraph {
  factory MailComposeParagraph({
    required Iterable<MailComposeRun> runs,
    MailComposeAlignment alignment = MailComposeAlignment.left,
    bool? rightToLeft,
  }) {
    final result = <MailComposeRun>[];
    MailComposeRun? current;
    var text = StringBuffer();
    var count = 0;
    var bytes = 0;
    var previousCr = false;
    for (final run in runs) {
      if (++count > MailComposeBody.maxRuns) _invalid();
      var value = run.text;
      if (previousCr && value.startsWith('\n')) value = value.substring(1);
      if (run.text.isNotEmpty) previousCr = run.text.endsWith('\r');
      value = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      bytes += _textBytes(
        value,
        limit: MailComposeBody.maxPlainTextBytes - bytes,
      );
      if (current == null || !current._sameFormat(run)) {
        if (current != null) result.add(current._withText(text.toString()));
        current = run;
        text = StringBuffer();
      }
      text.write(value);
    }
    if (current != null) result.add(current._withText(text.toString()));
    if (result.isEmpty) result.add(MailComposeRun(text: ''));
    return MailComposeParagraph._(
      List<MailComposeRun>.unmodifiable(result),
      alignment,
      rightToLeft,
    );
  }

  const MailComposeParagraph._(this.runs, this.alignment, this.rightToLeft);

  final List<MailComposeRun> runs;
  final MailComposeAlignment alignment;
  final bool? rightToLeft;

  bool get hasFormatting =>
      alignment != MailComposeAlignment.left ||
      rightToLeft != null ||
      runs.any((run) => run.hasFormatting);

  @override
  String toString() => 'MailComposeParagraph(redacted)';
}

/// Canonical, inert rich Mail authoring data with matching plain/HTML outputs.
///
/// [fromHtml] accepts only this format's exact emitted grammar and canonical
/// spelling. It is not a general HTML importer or sanitizer. The fixed-depth
/// parser has no DOM, external entities, resource resolver or network access.
final class MailComposeBody {
  factory MailComposeBody({
    required Iterable<MailComposeParagraph> paragraphs,
  }) {
    final result = <MailComposeParagraph>[];
    final plain = StringBuffer();
    var bytes = 0;
    var runs = 0;
    for (final paragraph in paragraphs) {
      if (result.length == maxParagraphs) _invalid();
      if (result.isNotEmpty) {
        plain.write('\n');
        bytes++;
      }
      runs += paragraph.runs.length;
      if (runs > maxRuns || bytes > maxPlainTextBytes) _invalid();
      for (final run in paragraph.runs) {
        bytes += _textBytes(run.text, limit: maxPlainTextBytes - bytes);
        plain.write(run.text);
      }
      result.add(paragraph);
    }
    if (result.isEmpty) _invalid();
    final owned = List<MailComposeParagraph>.unmodifiable(result);
    return MailComposeBody._(owned, plain.toString(), _writeHtml(owned));
  }

  factory MailComposeBody.fromHtml(String html) {
    _textBytes(html, limit: maxHtmlBytes);
    final body = _ComposeHtmlReader(html).read();
    if (body.html != html) _invalid();
    return body;
  }

  const MailComposeBody._(this.paragraphs, this.plainText, this.html);

  static const maxPlainTextBytes = 1024 * 1024;
  static const maxHtmlBytes = 4 * 1024 * 1024;
  static const maxParagraphs = 4096;
  static const maxRuns = 16384;

  final List<MailComposeParagraph> paragraphs;
  final String plainText;
  final String html;

  bool get hasFormatting =>
      paragraphs.any((paragraph) => paragraph.hasFormatting);

  @override
  bool operator ==(Object other) =>
      other is MailComposeBody && html == other.html;

  @override
  int get hashCode => html.hashCode;

  @override
  String toString() => 'MailComposeBody(redacted)';
}

Never _invalid() => throw const FormatException('Invalid Mail composition.');

/// Counts UTF-8 without allocating an encoded copy, rejecting malformed UTF-16
/// and control characters before storage/encoding could silently replace them.
int _textBytes(String value, {required int limit, bool multiline = true}) {
  if (limit < 0 || value.length > limit) _invalid();
  var bytes = 0;
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (code < 0x20 || (code >= 0x7f && code <= 0x9f)) {
      if (!multiline || (code != 0x09 && code != 0x0a && code != 0x0d))
        _invalid();
    }
    if (code < 0x80) {
      bytes++;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xd800 && code <= 0xdbff) {
      if (++i >= value.length) _invalid();
      final low = value.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff) _invalid();
      bytes += 4;
    } else {
      if (code >= 0xdc00 && code <= 0xdfff) _invalid();
      bytes += 3;
    }
    if (bytes > limit) _invalid();
  }
  return bytes;
}

const _root = '<div data-crispoffice-mail="1">';
const _paragraphStart = '<p style="margin:0;white-space:pre-wrap;text-align:';

String _style(MailComposeRun run) => <String>[
  if (run.bold) 'font-weight:bold',
  if (run.italic) 'font-style:italic',
  if (run.underline || run.strike)
    'text-decoration:${[if (run.underline) 'underline', if (run.strike) 'line-through'].join(' ')}',
].join(';');

String _writeHtml(List<MailComposeParagraph> paragraphs) {
  final output = _ComposeHtmlWriter()..write(_root);
  for (final paragraph in paragraphs) {
    output.write('$_paragraphStart${paragraph.alignment.name}"');
    if (paragraph.rightToLeft case final rtl?) {
      output.write(' dir="${rtl ? 'rtl' : 'ltr'}"');
    }
    output.write('>');
    for (final run in paragraph.runs) {
      final style = _style(run);
      output.write(style.isEmpty ? '<span>' : '<span style="$style">');
      if (run.link case final link?) {
        output.write('<a href="');
        output.escaped(link);
        output.write('">');
      }
      output.escaped(run.text);
      if (run.link != null) output.write('</a>');
      output.write('</span>');
    }
    // Empty spans alone have no line box in HTML. This distinct paragraph-level
    // placeholder retains empty first/middle/trailing lines without inventing
    // a newline in the editable text or confusing it with a soft break.
    if (paragraph.runs.every((run) => run.text.isEmpty)) output.write('<br />');
    output.write('</p>');
  }
  output.write('</div>');
  return output.buffer.toString();
}

final class _ComposeHtmlWriter {
  final buffer = StringBuffer();
  var bytes = 0;

  void write(String value) {
    bytes += _textBytes(value, limit: MailComposeBody.maxHtmlBytes - bytes);
    buffer.write(value);
  }

  void escaped(String value) {
    var start = 0;
    for (var i = 0; i < value.length; i++) {
      final replacement = switch (value.codeUnitAt(i)) {
        0x26 => '&amp;',
        0x3c => '&lt;',
        0x3e => '&gt;',
        0x22 => '&quot;',
        0x27 => '&#39;',
        0x0a => '<br />',
        _ => null,
      };
      if (replacement == null) continue;
      write(value.substring(start, i));
      write(replacement);
      start = i + 1;
    }
    write(value.substring(start));
  }
}

/// Fixed grammar: root -> paragraph -> span -> optional link -> text/br.
final class _ComposeHtmlReader {
  _ComposeHtmlReader(this.source);
  final String source;
  var position = 0;
  var runCount = 0;
  var plainBytes = 0;

  bool take(String value) {
    if (!source.startsWith(value, position)) return false;
    position += value.length;
    return true;
  }

  void expect(String value) {
    if (!take(value)) _invalid();
  }

  String until(String delimiter, {required int maxLength}) {
    final end = source.indexOf(delimiter, position);
    if (end < position || end - position > maxLength) _invalid();
    final value = source.substring(position, end);
    position = end;
    return value;
  }

  MailComposeBody read() {
    expect(_root);
    final paragraphs = <MailComposeParagraph>[];
    while (!take('</div>')) {
      if (paragraphs.length == MailComposeBody.maxParagraphs) _invalid();
      if (paragraphs.isNotEmpty &&
          ++plainBytes > MailComposeBody.maxPlainTextBytes) {
        _invalid();
      }
      expect(_paragraphStart);
      final name = until('"', maxLength: 7);
      final alignment = switch (name) {
        'left' => MailComposeAlignment.left,
        'center' => MailComposeAlignment.center,
        'right' => MailComposeAlignment.right,
        'justify' => MailComposeAlignment.justify,
        _ => _invalid(),
      };
      expect('"');
      bool? direction;
      if (take(' dir="rtl"')) {
        direction = true;
      } else if (take(' dir="ltr"')) {
        direction = false;
      }
      expect('>');
      final runs = <MailComposeRun>[];
      while (!take('</p>')) {
        if (take('<br />')) {
          if (runs.isEmpty || runs.any((run) => run.text.isNotEmpty))
            _invalid();
          expect('</p>');
          break;
        }
        if (++runCount > MailComposeBody.maxRuns) _invalid();
        expect('<span');
        var style = '';
        if (take(' style="')) {
          style = until('"', maxLength: 90);
          expect('"');
        }
        expect('>');
        String? link;
        if (take('<a href="')) {
          link = _decode(
            until('"', maxLength: MailComposeRun.maxLinkBytes * 6),
          );
          expect('">');
        }
        final text = StringBuffer();
        final close = link == null ? '</span>' : '</a>';
        while (!take(close)) {
          if (take('<br />')) {
            if (++plainBytes > MailComposeBody.maxPlainTextBytes) _invalid();
            text.write('\n');
          } else {
            final raw = until('<', maxLength: MailComposeBody.maxHtmlBytes);
            if (raw.isEmpty) _invalid();
            final decoded = _decode(raw);
            plainBytes += _textBytes(
              decoded,
              limit: MailComposeBody.maxPlainTextBytes - plainBytes,
            );
            text.write(decoded);
          }
        }
        if (link != null) expect('</span>');
        final run = MailComposeRun(
          text: text.toString(),
          bold: style.contains('font-weight:bold'),
          italic: style.contains('font-style:italic'),
          underline: style.contains('underline'),
          strike: style.contains('line-through'),
          link: link,
        );
        if (_style(run) != style) _invalid();
        runs.add(run);
      }
      if (runs.isEmpty) _invalid();
      paragraphs.add(
        MailComposeParagraph(
          runs: runs,
          alignment: alignment,
          rightToLeft: direction,
        ),
      );
    }
    if (position != source.length) _invalid();
    return MailComposeBody(paragraphs: paragraphs);
  }
}

String _decode(String value) {
  final output = StringBuffer();
  var start = 0;
  while (true) {
    final amp = value.indexOf('&', start);
    if (amp == -1) {
      output.write(value.substring(start));
      return output.toString();
    }
    output.write(value.substring(start, amp));
    final end = value.indexOf(';', amp + 1);
    if (end < 0 || end - amp > 5) _invalid();
    output.write(switch (value.substring(amp, end + 1)) {
      '&amp;' => '&',
      '&lt;' => '<',
      '&gt;' => '>',
      '&quot;' => '"',
      '&#39;' => "'",
      _ => _invalid(),
    });
    start = end + 1;
  }
}
