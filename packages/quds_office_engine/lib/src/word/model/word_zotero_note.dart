import 'dart:convert';

import '../../xml/xml_reader.dart';
import '../../zotero/zotero_formatted_text.dart';
import '../properties/wml_properties.dart';
import 'wml_document.dart';

/// A bounded, inert note fragment with citation placeholders kept separate.
/// Unsupported structure and formatting are refused before document edits.
final class WordZoteroNoteText {
  WordZoteroNoteText._(this.paragraphs, this.placeholders);

  final List<WmlParagraph> paragraphs;
  final Map<String, WordZoteroNotePlaceholder> placeholders;
  String get plainText => paragraphs.map((p) => p.text).join('\n');

  factory WordZoteroNoteText.fromHtml(
    String html, {
    WmlRunProps? baseProperties,
  }) {
    final checked = ZoteroFormattedText.fromHtml(html);
    if (checked.unsupportedFormatting.isNotEmpty) {
      throw UnsupportedError(
        'This Zotero note contains unsupported formatting or embedded content. The document was kept unchanged.',
      );
    }
    if (html.contains('<![CDATA[')) {
      throw UnsupportedError('CDATA in Zotero note content is not supported.');
    }
    final reader = XmlPullReader('<quds-note>${_normalize(html)}</quds-note>');
    final canonical = StringBuffer();
    final stack = <_NoteElement>[];
    final links = <_NoteLink>[];
    var activeLink = false;
    var elements = 0;
    const escape = HtmlEscape(HtmlEscapeMode.element);
    const attributeEscape = HtmlEscape(HtmlEscapeMode.attribute);
    try {
      while (reader.next()) {
        switch (reader.eventType) {
          case XmlEventType.startElement:
            if (++elements > 50000 || stack.length > 64) {
              throw const FormatException('The Zotero note is too complex.');
            }
            final tag = reader.qualifiedName.toLowerCase();
            if (!_tags.contains(tag)) {
              throw UnsupportedError(
                'This Zotero note contains unsupported $tag content. The document was kept unchanged.',
              );
            }
            final attributes = <String, String>{};
            if (reader.attributeCount > 64) throw _malformed();
            for (var i = 0; i < reader.attributeCount; i++) {
              final name = reader.attributeQualifiedName(i).toLowerCase();
              if (attributes.containsKey(name)) throw _malformed();
              final value = reader.attributeValue(i);
              _checkMarkers(value);
              if (name != 'style' &&
                  name != 'class' &&
                  !(name == 'href' && tag == 'a') &&
                  !(const <String>{
                        'data-schema-version',
                        'data-citation-items',
                      }.contains(name) &&
                      tag == 'div') &&
                  !(name == 'data-annotation' && tag == 'span')) {
                throw UnsupportedError(
                  'This Zotero note contains unsupported $name attributes. The document was kept unchanged.',
                );
              }
              if (name == 'class' &&
                  value
                      .split(RegExp(r'\s+'))
                      .any((name) => name.startsWith('csl-'))) {
                throw UnsupportedError(
                  'This Zotero note uses unsupported class-based formatting.',
                );
              }
              attributes[name] = value;
            }
            final outputTag = tag == 'a' ? 'span' : tag;
            canonical.write('<$outputTag');
            final style = attributes['style'];
            if (style != null) {
              canonical.write(' style="${attributeEscape.convert(style)}"');
            }
            canonical.write('>');
            int? linkIndex;
            if (tag == 'a') {
              if (activeLink) throw _malformed();
              final href = attributes['href'];
              if (href == null) throw _malformed();
              final link = _NoteLink(href);
              linkIndex = links.length;
              links.add(link);
              if (links.length > 10000) {
                throw const FormatException(
                  'The Zotero note has too many links.',
                );
              }
              activeLink = true;
              canonical.write('\uE000${linkIndex * 2}\uE001');
            }
            // Preserve authored empty paragraphs through the shared renderer.
            if (tag == 'p') canonical.write('\uE002');
            if (_headings.contains(tag)) {
              canonical.write('\uE000$tag\uE001');
            }
            stack.add(_NoteElement(outputTag, tag, linkIndex));
          case XmlEventType.endElement:
            if (stack.isEmpty) throw _malformed();
            final element = stack.removeLast();
            if (element.linkIndex != null) {
              canonical.write('\uE000${element.linkIndex! * 2 + 1}\uE001');
              activeLink = false;
            }
            if (element.tag == 'p' ||
                (element.tag == 'div' && !element.hasText)) {
              canonical.write('\uE002');
            }
            if (_headings.contains(element.tag)) {
              canonical.write('\uE000/h\uE001');
            }
            canonical.write('</${element.outputTag}>');
            if (stack.isNotEmpty &&
                (element.hasText ||
                    element.tag == 'p' ||
                    element.tag == 'div')) {
              stack.last.hasText = true;
            }
          case XmlEventType.characters:
            _checkMarkers(reader.text);
            canonical.write(escape.convert(reader.text));
            if (stack.isNotEmpty && reader.text.trim().isNotEmpty) {
              stack.last.hasText = true;
            }
          case XmlEventType.comment:
          case XmlEventType.none:
          case XmlEventType.endDocument:
            break;
          case XmlEventType.cdata:
          case XmlEventType.xmlDeclaration:
          case XmlEventType.processingInstruction:
          case XmlEventType.dtd:
            throw _malformed();
        }
      }
    } on XmlParseException {
      throw _malformed();
    }
    if (stack.isNotEmpty || activeLink) throw _malformed();
    final formatted = ZoteroFormattedText.fromHtml(canonical.toString());
    if (formatted.unsupportedFormatting.isNotEmpty) throw _malformed();
    final paragraphs = <WmlParagraph>[];
    final placeholders = <String, WordZoteroNotePlaceholder>{};
    _NoteLink? current;
    var currentStart = 0;
    var currentParagraph = 0;
    final marker = RegExp('\uE000([0-9]+|h[1-6]|/h)\uE001|\uE002');
    for (final sourceRuns in formatted.toParagraphRuns(
      baseProperties: baseProperties,
    )) {
      final paragraph = WmlParagraph();
      var offset = 0;
      for (final run in sourceRuns) {
        void append(String value) {
          if (value.isEmpty) return;
          paragraph.inlines.add(
            WmlRun(
              text: value,
              properties: run.properties.copy(),
              hyperlink: current?.placeholderId == null && current != null
                  ? WmlHyperlink(url: current.href)
                  : null,
            ),
          );
          offset += value.length;
        }

        var start = 0;
        for (final match in marker.allMatches(run.text)) {
          append(run.text.substring(start, match.start));
          final number = match[1];
          if (number != null && number.startsWith('h')) {
            if (offset != 0 || paragraph.properties.headingLevel != null) {
              throw _malformed();
            }
            final level = int.parse(number.substring(1));
            paragraph.properties
              ..headingLevel = level
              ..styleId = 'Heading$level';
          } else if (number == '/h') {
            if (paragraph.properties.headingLevel == null) throw _malformed();
          } else if (number != null) {
            final index = int.parse(number);
            final link = links[index ~/ 2];
            if (index.isEven) {
              if (current != null) throw _malformed();
              current = link;
              currentStart = offset;
              currentParagraph = paragraphs.length;
            } else {
              if (!identical(current, link) ||
                  currentParagraph != paragraphs.length ||
                  currentStart == offset) {
                throw const FormatException(
                  'A Zotero note link is empty or crosses a paragraph boundary.',
                );
              }
              final id = link.placeholderId;
              if (id != null) {
                if (placeholders.containsKey(id)) {
                  throw const FormatException(
                    'The Zotero note repeats a citation placeholder.',
                  );
                }
                placeholders[id] = WordZoteroNotePlaceholder(
                  id,
                  paragraphs.length,
                  currentStart,
                  offset,
                );
              }
              current = null;
            }
          }
          start = match.end;
        }
        append(run.text.substring(start));
      }
      if (current != null) {
        throw const FormatException('A Zotero note link crosses paragraphs.');
      }
      paragraphs.add(paragraph);
      if (paragraphs.length > 10000) {
        throw const FormatException('The Zotero note has too many paragraphs.');
      }
    }
    if (paragraphs.every((p) => p.text.trim().isEmpty)) {
      throw const FormatException('The selected Zotero note contains no text.');
    }
    return WordZoteroNoteText._(paragraphs, placeholders);
  }

  static void _checkMarkers(String value) {
    if (value.contains(RegExp('[\uE000-\uE002]'))) throw _malformed();
  }

  static String _normalize(String html) => html
      .replaceAllMapped(RegExp(r'&([A-Za-z][A-Za-z0-9]*);'), (match) {
        final value = _entities[match[1]];
        if (value == null) throw _malformed();
        return '&#$value;';
      })
      .replaceAll(RegExp(r'<br\s*>', caseSensitive: false), '<br/>');
  static FormatException _malformed() => const FormatException(
    'Zotero returned a malformed or unsupported note. The document was kept unchanged.',
  );
  static const _headings = <String>{'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
  static const _tags = <String>{
    ..._headings,
    'quds-note',
    'html',
    'body',
    'div',
    'p',
    'span',
    'a',
    'br',
    'b',
    'strong',
    'i',
    'em',
    'u',
    's',
    'strike',
    'del',
    'sub',
    'sup',
  };
  static const _entities = <String, int>{
    'amp': 38,
    'lt': 60,
    'gt': 62,
    'quot': 34,
    'apos': 39,
    'nbsp': 160,
    'ensp': 8194,
    'emsp': 8195,
    'thinsp': 8201,
    'ndash': 8211,
    'mdash': 8212,
    'lsquo': 8216,
    'rsquo': 8217,
    'sbquo': 8218,
    'ldquo': 8220,
    'rdquo': 8221,
    'bdquo': 8222,
    'bull': 8226,
    'hellip': 8230,
    'laquo': 171,
    'raquo': 187,
    'copy': 169,
    'reg': 174,
    'trade': 8482,
    'deg': 176,
    'plusmn': 177,
    'times': 215,
    'divide': 247,
    'minus': 8722,
    'micro': 181,
    'middot': 183,
  };
}

final class WordZoteroNotePlaceholder {
  const WordZoteroNotePlaceholder(
    this.id,
    this.paragraphIndex,
    this.start,
    this.end,
  );
  final String id;
  final int paragraphIndex;
  final int start;
  final int end;
}

final class _NoteElement {
  _NoteElement(this.outputTag, this.tag, this.linkIndex);
  final String outputTag;
  final String tag;
  final int? linkIndex;
  bool hasText = false;
}

final class _NoteLink {
  _NoteLink(this.href) {
    const prefix = 'https://www.zotero.org/?';
    if (href.startsWith(prefix)) {
      final id = href.substring(prefix.length);
      if (!RegExp(r'^[A-Za-z0-9]{1,128}$').hasMatch(id)) {
        throw const FormatException('Invalid Zotero citation placeholder.');
      }
      placeholderId = id;
      return;
    }
    final uri = Uri.tryParse(href);
    if (href.length > 8192 ||
        href.trim() != href ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(href) ||
        uri == null ||
        !const <String>{
          'http',
          'https',
          'mailto',
          'zotero',
        }.contains(uri.scheme) ||
        (uri.scheme != 'mailto' && uri.host.isEmpty) ||
        uri.userInfo.isNotEmpty) {
      throw UnsupportedError(
        'This Zotero note has an unsupported link target.',
      );
    }
  }
  final String href;
  String? placeholderId;
}
