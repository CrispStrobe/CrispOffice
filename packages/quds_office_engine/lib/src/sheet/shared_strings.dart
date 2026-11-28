import '../xml/namespaces.dart';
import '../xml/xml_node.dart';
import '../xml/xml_reader.dart';
import '../xml/xml_writer.dart';
import 'styles/sml_styles.dart';

/// Native text and run properties for one imported XLSX string.
class SmlRichString {
  SmlRichString._(this.text, this._source, this.runs);

  /// Visible string, excluding phonetic guides.
  final String text;
  final XmlElement _source;

  /// Inline styles in source order. Null properties inherit the cell font.
  final List<SmlRichStringRun> runs;

  /// Reads either a shared string item or an inline string.
  static ({String text, SmlRichString? rich}) read(XmlPullReader reader) {
    final node = XmlDocument.readElement(reader);
    final runs = <SmlRichStringRun>[];
    final text = StringBuffer();
    for (final child in node.childElements) {
      if (child.localName == 't') {
        text.write(child.text);
      } else if (child.localName == 'r') {
        final value = child.firstChild('t')?.text ?? '';
        text.write(value);
        runs.add(SmlRichStringRun._(value, child.firstChild('rPr')));
      }
    }
    final visible = text.toString();
    final hasAnnotations =
        node.firstChild('rPh') != null || node.firstChild('phoneticPr') != null;
    return (
      text: visible,
      rich: runs.isEmpty && !hasAnnotations
          ? null
          : SmlRichString._(visible, node, List.unmodifiable(runs)),
    );
  }

  void _writeSharedItem(XmlWriter writer) {
    // The shared and inline string elements have the same content model.
    final item = XmlElement(
      localName: 'si',
      namespaceUri: _source.namespaceUri,
      prefix: _source.prefix,
      attributes: _source.attributes,
      children: _source.children,
    );
    item.writeTo(writer);
  }
}

/// Native baseline position of an XLSX text run.
enum SmlRunVerticalPosition { baseline, superscript, subscript }

/// A font override for one segment of an XLSX cell.
class SmlRichStringRun {
  SmlRichStringRun._(this.text, XmlElement? properties)
    : family = properties?.firstChild('rFont')?.getAttribute('val'),
      size = _readSize(properties),
      bold = _readFlag(properties, 'b'),
      italic = _readFlag(properties, 'i'),
      underline = _readUnderline(properties),
      verticalPosition = switch (properties
          ?.firstChild('vertAlign')
          ?.getAttribute('val')) {
        'superscript' => SmlRunVerticalPosition.superscript,
        'subscript' => SmlRunVerticalPosition.subscript,
        _ => SmlRunVerticalPosition.baseline,
      },
      rgb = SmlStyleSheet.normalizeRgb(
        properties?.firstChild('color')?.getAttribute('rgb') ?? '',
      );

  final String text;
  final String? family;
  final double? size;
  final bool? bold;
  final bool? italic;
  final String underline;
  final SmlRunVerticalPosition verticalPosition;
  final String rgb;

  static double? _readSize(XmlElement? properties) {
    final value = double.tryParse(
      properties?.firstChild('sz')?.getAttribute('val') ?? '',
    );
    return value != null && value.isFinite && value > 0 && value <= 409
        ? value
        : null;
  }

  static bool? _readFlag(XmlElement? properties, String name) {
    final flag = properties?.firstChild(name);
    if (flag == null) return null;
    final value = flag.getAttribute('val')?.trim();
    return value != '0' && value != 'false';
  }

  static String _readUnderline(XmlElement? properties) {
    final underline = properties?.firstChild('u');
    return underline == null
        ? 'none'
        : underline.getAttribute('val') ?? 'single';
  }
}

/// Streaming shared-string table with write-side deduplication.
class SharedStringTable {
  /// SharedStringTable API.
  SharedStringTable({List<String>? strings})
    : _strings = strings ?? <String>[],
      _index = <String, int>{
        for (int i = 0; i < (strings?.length ?? 0); i++) strings![i]: i,
      };

  final List<String> _strings;
  final Map<String, int> _index;
  final _richAt = <int, SmlRichString>{};
  final _richIndex = <SmlRichString, int>{};

  /// Rich-text metadata associated with an imported index.
  SmlRichString? richAt(int index) => _richAt[index];

  /// values API.
  List<String> get values => List<String>.unmodifiable(_strings);

  /// length API.
  int get length => _strings.length;

  String operator [](int index) =>
      index >= 0 && index < _strings.length ? _strings[index] : '';

  /// Interns a plain string or preserves one native run sequence.
  int intern(String value, {SmlRichString? rich}) {
    final existing = rich == null ? _index[value] : _richIndex[rich];
    if (existing != null) return existing;
    return _append(value, rich);
  }

  int _append(String value, SmlRichString? rich) {
    final id = _strings.length;
    _strings.add(value);
    if (rich == null) {
      _index.putIfAbsent(value, () => id);
    } else {
      _richAt[id] = rich;
      _richIndex[rich] = id;
    }
    return id;
  }

  /// Reads the source indices without coalescing visually distinct strings.
  factory SharedStringTable.parse(String xml) {
    final table = SharedStringTable();
    final reader = XmlPullReader(xml);
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'si') {
        final item = SmlRichString.read(reader);
        table._append(item.text, item.rich);
      }
    }
    return table;
  }

  /// toXml API.
  String toXml() {
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('sst');
    w.writeAttribute('xmlns', OfficeNamespaces.x);
    w.writeAttribute('count', '${_strings.length}');
    w.writeAttribute('uniqueCount', '${_strings.length}');
    for (final (index, value) in _strings.indexed) {
      final rich = _richAt[index];
      if (rich != null) {
        rich._writeSharedItem(w);
        continue;
      }
      w.writeStartElement('si');
      w.writeStartElement('t');
      w.writeAttribute('xml:space', 'preserve');
      w.writeText(value);
      w.writeEndElement();
      w.writeEndElement();
    }
    w.writeEndElement();
    return w.toXml();
  }
}
