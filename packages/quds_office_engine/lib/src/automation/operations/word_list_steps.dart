import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_property_io.dart';

/// Toggle one paragraph's bullet/number kind, using the deterministic Quds
/// single-level defaults when the existing kind differs. Native definitions,
/// rather than display labels or presumed numbering IDs, determine the kind.
void applyDefaultWordList(
  WmlDocument document,
  WmlParagraph paragraph, {
  required bool numbered,
}) {
  final edit = _ListEdit(document, paragraph);
  final numbering = _NumberingSource(document);
  final current = numbering.kind(paragraph.properties);
  if (current == numbered) {
    edit.clear();
    return;
  }
  final prepared = numbering.defaultDefinition(numbered);
  final properties = edit.prepareDefault(prepared.id, numbered);
  // All source and argument checks above finish before either package or
  // paragraph mutation. The prepared XML is detached from the native package.
  prepared.publish();
  paragraph.properties = properties;
}

/// Remove paragraph numbering, with an explicit guard for unsupported LISTNUM
/// field removal. Ordinary field content is never rewritten by a list edit.
void removeWordNumbers(
  WmlDocument document,
  WmlParagraph paragraph, {
  required String numberType,
}) {
  if (numberType != 'paragraph' && numberType != 'all') {
    throw ArgumentError('numberType must be paragraph or all');
  }
  final edit = _ListEdit(document, paragraph, allNumbers: numberType == 'all');
  if (numberType == 'all') _checkListNumFields(document, paragraph);
  edit.clear();
}

const _w = OfficeNamespaces.w;
const _numberNames = {'numPr', 'numId', 'ilvl'};

bool _word(XmlElement node, String name) =>
    node.localName == name && node.namespaceUri == _w;

Iterable<XmlElement> _children(XmlElement node, String name) =>
    node.childElements.where((child) => _word(child, name));

XmlElement? _one(XmlElement node, String name) {
  final matches = _children(node, name).toList(growable: false);
  if (matches.length > 1) {
    throw UnsupportedError('Ambiguous duplicate native $name in list source.');
  }
  return matches.firstOrNull;
}

String? _value(XmlElement node, String name) {
  final attrs = node.attributes
      .where((attr) => attr.localName == name && attr.namespaceUri == _w)
      .toList(growable: false);
  if (attrs.length > 1) {
    throw UnsupportedError('Ambiguous duplicate native $name attribute.');
  }
  for (final attr in node.attributes) {
    if (attr.localName == name &&
        attr.prefix == 'w' &&
        attr.namespaceUri != _w) {
      throw UnsupportedError('Misbound native list attribute namespace.');
    }
  }
  return attrs.firstOrNull?.value;
}

int _integer(String? value, String field, {int min = 0, int max = 2147483647}) {
  final parsed = value != null && RegExp(r'^[0-9]+$').hasMatch(value)
      ? int.tryParse(value)
      : null;
  if (parsed == null || parsed < min || parsed > max) {
    throw UnsupportedError('Native $field must be an integer in $min..$max.');
  }
  return parsed;
}

XmlElement _element(String name) =>
    XmlElement(localName: name, prefix: 'w', namespaceUri: _w)
      ..setAttribute('w', _w, prefix: 'xmlns');

void _set(XmlElement node, String name, String value) {
  // A native attribute gets its own bound prefix; foreign same-name metadata
  // and its namespace declarations remain untouched.
  var prefix = 'w';
  var suffix = 1;
  final bindings = <String, String>{};
  for (XmlElement? parent = node; parent != null; parent = parent.parent) {
    for (final attr in parent.attributes) {
      if (attr.prefix == 'xmlns') {
        bindings.putIfAbsent(attr.localName, () => attr.value);
      }
    }
  }
  while (bindings[prefix] != null && bindings[prefix] != _w) {
    prefix = 'w${suffix++}';
  }
  node.setAttribute(prefix, _w, prefix: 'xmlns');
  node.attributes.removeWhere(
    (a) => a.localName == name && a.namespaceUri == _w,
  );
  node.attributes.add(
    XmlAttribute(
      localName: name,
      value: value,
      prefix: prefix,
      namespaceUri: _w,
    ),
  );
}

XmlElement _ensure(XmlElement parent, String name) {
  final found = _one(parent, name);
  if (found != null) return found;
  final child = _element(name);
  parent.addChild(child);
  return child;
}

XmlElement _properties(WmlParagraph paragraph) {
  final original = paragraph.properties.sourcePropertiesXml;
  if (original != null && original.isNotEmpty) {
    _checkProperties(_parseProperties(original));
  }
  final source = WordSerializer().paragraphPropertiesXml(paragraph.properties);
  return _parseProperties(source);
}

XmlElement _parseProperties(String source) {
  final wrapper = XmlDocument.parse(
    '<w:context xmlns:w="$_w">$source</w:context>',
  ).root!;
  final children = wrapper.childElements.toList(growable: false);
  if (children.length != 1 || !_word(children.single, 'pPr')) {
    throw UnsupportedError(
      'List edits require unambiguous native paragraph properties.',
    );
  }
  return children.single..setAttribute('w', _w, prefix: 'xmlns');
}

void _checkProperties(XmlElement properties) {
  void check(XmlElement node) {
    if (_numberNames.contains(node.localName) && node.namespaceUri != _w) {
      throw UnsupportedError(
        'List edits cannot resolve foreign or misbound numbering properties.',
      );
    }
    if (_word(node, 'pPr')) {
      final number = _one(node, 'numPr');
      if (number != null) {
        final id = _one(number, 'numId');
        if (id == null) {
          throw UnsupportedError(
            'Partial native numPr without numId is outside the list-edit contract.',
          );
        }
        _integer(_value(id, 'val'), 'numId');
        final level = _one(number, 'ilvl');
        if (level != null) _integer(_value(level, 'val'), 'ilvl', max: 8);
        if (_one(number, 'numberingChange') != null ||
            _one(number, 'ins') != null) {
          throw UnsupportedError(
            'Resolve tracked numbering changes before list edits.',
          );
        }
      }
    }
    for (final child in node.childElements) {
      check(child);
    }
  }

  check(properties);
}

void _checkPackageSources(WmlDocument document, {required bool allNumbers}) {
  for (final part in document.package?.parts ?? <PackagePart>[]) {
    if (!part.contentType.endsWith('+xml') ||
        (!part.contentType.contains('wordprocessingml') &&
            !part.contentType.contains('vnd.ms-word'))) {
      continue;
    }
    final text = part.readText();
    final isStyles = part.contentType == OfficeContentTypes.wordStyles;
    if (!isStyles && !text.contains('AlternateContent')) continue;
    final root = XmlDocument.parse(text).root;
    if (root == null) throw UnsupportedError('Missing native XML root.');
    if (isStyles) _checkProperties(root);
    void check(XmlElement node, bool alternative) {
      final inside =
          alternative ||
          (node.localName == 'AlternateContent' &&
              node.namespaceUri == OfficeNamespaces.mc);
      if (inside &&
          node.namespaceUri == _w &&
          (_numberNames.contains(node.localName) ||
              (allNumbers &&
                  {
                    'fldSimple',
                    'instrText',
                    'fldChar',
                  }.contains(node.localName)))) {
        throw UnsupportedError(
          'List edits do not resolve numbering or field-bearing markup-compatibility alternatives.',
        );
      }
      for (final child in node.childElements) {
        check(child, inside);
      }
    }

    check(root, false);
  }
}

class _ListEdit {
  _ListEdit(this.document, this.paragraph, {bool allNumbers = false})
    : direct = _properties(paragraph) {
    _checkPackageSources(document, allNumbers: allNumbers);
    _checkProperties(direct);
    _one(direct, 'ind');
    if (paragraph.properties.numId != null) {
      _integer('${paragraph.properties.numId}', 'effective numId');
      _integer('${paragraph.properties.ilvl}', 'effective ilvl', max: 8);
    }
  }

  final WmlDocument document;
  final WmlParagraph paragraph;
  final XmlElement direct;

  void clear() {
    final props = paragraph.properties.copy()
      ..numId = null
      ..numberingSuppressed = true
      ..ilvl = 0
      ..listLabel = null
      ..listRestart = null;
    _writeNumber(0);
    _publish(props);
  }

  WmlParagraphProps prepareDefault(int id, bool numbered) {
    final props = paragraph.properties.copy()
      ..numId = id
      ..numberingSuppressed = false
      ..ilvl = 0
      ..listLabel = numbered ? '1. ' : '• '
      ..listRestart = null;
    _writeNumber(id);
    final indent = _ensure(direct, 'ind');
    // The deterministic single-level default owns left/first-line/hanging.
    // Preserve the right indent and all foreign attributes/children.
    for (final name in {
      'left',
      'start',
      'leftChars',
      'startChars',
      'firstLine',
      'firstLineChars',
      'hanging',
      'hangingChars',
    }) {
      indent.attributes.removeWhere(
        (a) => a.namespaceUri == _w && a.localName == name,
      );
    }
    _set(indent, 'left', '360');
    _set(indent, 'hanging', '180');
    _set(indent, 'firstLine', '0');
    props
      ..indent = WmlIndent(left: 18, right: props.indent.right, hanging: 9)
      ..explicitIndent = true;
    _finish(props);
    return props;
  }

  void _writeNumber(int id) {
    final num = _ensure(direct, 'numPr');
    _set(_ensure(num, 'ilvl'), 'val', '0');
    _set(_ensure(num, 'numId'), 'val', '$id');
    // Native children stay in schema order; opaque siblings retain order.
    final level = _one(num, 'ilvl')!;
    final number = _one(num, 'numId')!;
    final numberIndex = num.children.indexOf(number);
    if (num.children.indexOf(level) > numberIndex) {
      num.children.remove(level);
      num.children.insert(numberIndex, level);
    }
  }

  void _publish(WmlParagraphProps props) {
    _finish(props);
    paragraph.properties = props;
  }

  void _finish(WmlParagraphProps props) {
    WordPropertyIo.orderChildren(direct);
    props.sourcePropertiesXml = XmlDocument(
      root: direct,
    ).toXmlString(declaration: false);
    props.importedValues = WordPropertyIo.paragraphValues(props);
  }
}

class _NumberingSource {
  _NumberingSource(this.document) {
    package = document.package ?? OpcPackage.create(OpcPackageKind.word);
    final mainRels = package.packageRelationships
        .byType(RelationshipTypes.officeDocument)
        .toList();
    if (mainRels.length > 1) {
      throw UnsupportedError('Ambiguous main document relationship.');
    }
    final main = mainRels.isEmpty
        ? '/word/document.xml'
        : package.packageRelationships.resolve(mainRels.single);
    relationships = package.relationshipsFor(main);
    final refs = relationships.byType(RelationshipTypes.numbering).toList();
    if (refs.length > 1 ||
        refs.any((r) => r.targetMode == RelationshipTargetMode.external)) {
      throw UnsupportedError(
        'List edits need one internal numbering relationship.',
      );
    }
    hasRelationship = refs.isNotEmpty;
    uri = refs.isEmpty
        ? '/word/numbering.xml'
        : relationships.resolve(refs.single);
    final part = package.getPart(uri);
    if (hasRelationship && part == null) {
      throw UnsupportedError('Missing native numbering part.');
    }
    root = part == null
        ? _element('numbering')
        : XmlDocument.parse(part.readText()).root!;
    if (!_word(root, 'numbering')) {
      throw UnsupportedError('Invalid native numbering root.');
    }
    void check(XmlElement node) {
      if (node.prefix == 'w' && node.namespaceUri != _w) {
        throw UnsupportedError('Misbound native numbering namespace.');
      }
      if (node.namespaceUri == OfficeNamespaces.mc &&
          node.localName == 'AlternateContent') {
        throw UnsupportedError(
          'List edits do not resolve alternative numbering definitions.',
        );
      }
      for (final child in node.childElements) {
        check(child);
      }
    }

    check(root);
    for (final node in _children(root, 'abstractNum')) {
      final id = _integer(_value(node, 'abstractNumId'), 'abstractNumId');
      if (abstracts.containsKey(id)) {
        throw UnsupportedError('Duplicate abstract numbering identity.');
      }
      abstracts[id] = node;
    }
    for (final node in _children(root, 'num')) {
      final id = _integer(_value(node, 'numId'), 'numId', min: 1);
      if (instances.containsKey(id)) {
        throw UnsupportedError('Duplicate numbering identity.');
      }
      instances[id] = node;
    }
  }
  final WmlDocument document;
  late final OpcPackage package;
  late final RelationshipCollection relationships;
  late final bool hasRelationship;
  late final String uri;
  late final XmlElement root;
  final abstracts = <int, XmlElement>{};
  final instances = <int, XmlElement>{};

  bool? kind(WmlParagraphProps props) {
    final id = props.numId;
    if (id == null || id == 0 || props.numberingSuppressed) return null;
    final instance = instances[id];
    if (instance == null) {
      throw UnsupportedError('Unresolved native numbering identity.');
    }
    final abstractRef = _one(instance, 'abstractNumId');
    final abstractId = _integer(
      abstractRef == null ? null : _value(abstractRef, 'val'),
      'abstractNumId',
    );
    final definition = abstracts[abstractId];
    if (definition == null) {
      throw UnsupportedError('Unresolved abstract numbering identity.');
    }
    if (_one(definition, 'numStyleLink') != null ||
        _one(definition, 'styleLink') != null) {
      throw UnsupportedError(
        'Linked numbering definitions are outside this list-edit contract.',
      );
    }
    final levels = <int, XmlElement>{};
    for (final level in _children(definition, 'lvl')) {
      final index = _integer(_value(level, 'ilvl'), 'ilvl', max: 8);
      if (levels.containsKey(index)) {
        throw UnsupportedError('Duplicate numbering level.');
      }
      levels[index] = level;
    }
    final overrides = <int, XmlElement>{};
    for (final override in _children(instance, 'lvlOverride')) {
      final index = _integer(_value(override, 'ilvl'), 'override ilvl', max: 8);
      if (overrides.containsKey(index)) {
        throw UnsupportedError('Duplicate numbering level override.');
      }
      overrides[index] = override;
    }
    var level = levels[props.ilvl];
    final override = overrides[props.ilvl];
    final replacement = override == null ? null : _one(override, 'lvl');
    if (replacement != null) {
      if (_integer(
            _value(replacement, 'ilvl'),
            'override level ilvl',
            max: 8,
          ) !=
          props.ilvl) {
        throw UnsupportedError('Mismatched native numbering level override.');
      }
      level = replacement;
    }
    if (level == null) {
      throw UnsupportedError('Unresolved native numbering level.');
    }
    if (_one(level, 'lvlPicBulletId') != null) {
      throw UnsupportedError(
        'Picture bullets are outside this list-edit contract.',
      );
    }
    final format = _one(level, 'numFmt');
    final value = format == null ? null : _value(format, 'val');
    if (value == 'bullet') return false;
    if (!const {
      'decimal',
      'decimalZero',
      'upperRoman',
      'lowerRoman',
      'upperLetter',
      'lowerLetter',
      'ordinal',
      'cardinalText',
      'ordinalText',
      'hex',
      'chicago',
    }.contains(value)) {
      throw UnsupportedError('Unsupported or missing native numbering format.');
    }
    final text = _one(level, 'lvlText');
    final label = text == null ? '' : _value(text, 'val') ?? '';
    if (RegExp(r'%[1-9]').allMatches(label).length != 1) {
      throw UnsupportedError(
        'Outline or unmodeled numbered labels are outside this list-edit contract.',
      );
    }
    return true;
  }

  _PreparedNumbering defaultDefinition(bool numbered) {
    final name = 'Quds-VBA-${numbered ? 'decimal' : 'bullet'}-single-v1';
    final used = <int>{
      ...abstracts.keys,
      ...instances.keys,
      for (final p in document.paragraphs)
        if (p.properties.numId case final int id) id,
      for (final style in document.styles)
        if (style.numId case final int id) id,
    };
    for (final entry in abstracts.entries) {
      final marker = _one(entry.value, 'name');
      if (marker == null || _value(marker, 'val') != name) continue;
      if (!_defaultShape(entry.value, numbered)) {
        throw UnsupportedError(
          'An imported list conflicts with the Quds default definition.',
        );
      }
      for (final instance in instances.entries) {
        final ref = _one(instance.value, 'abstractNumId');
        if (ref == null || _value(ref, 'val') != '${entry.key}') continue;
        if (_children(instance.value, 'lvlOverride').isNotEmpty) continue;
        return _PreparedNumbering(this, instance.key, changed: false);
      }
    }
    var id = 1;
    while (used.contains(id)) {
      id++;
    }
    if (id > 2147483647) {
      throw UnsupportedError('No native numbering identity available.');
    }
    final definition = XmlDocument.parse(
      '<w:abstractNum xmlns:w="$_w" w:abstractNumId="$id">'
      '<w:multiLevelType w:val="singleLevel"/><w:name w:val="$name"/>'
      '<w:lvl w:ilvl="0"><w:start w:val="1"/>'
      '<w:numFmt w:val="${numbered ? 'decimal' : 'bullet'}"/>'
      '<w:lvlText w:val="${numbered ? '%1.' : '•'}"/>'
      '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="360" w:hanging="180"/>'
      '</w:pPr></w:lvl></w:abstractNum>',
    ).root!;
    final instance = XmlDocument.parse(
      '<w:num xmlns:w="$_w" w:numId="$id"><w:abstractNumId w:val="$id"/></w:num>',
    ).root!;
    final beforeNum = root.children.indexWhere(
      (n) =>
          n is XmlElement && (_word(n, 'num') || _word(n, 'numIdMacAtCleanup')),
    );
    if (beforeNum < 0) {
      root.addChild(definition);
    } else {
      root.children.insert(beforeNum, definition..parent = root);
    }
    final cleanup = root.children.indexWhere(
      (n) => n is XmlElement && _word(n, 'numIdMacAtCleanup'),
    );
    if (cleanup < 0) {
      root.addChild(instance);
    } else {
      root.children.insert(cleanup, instance..parent = root);
    }
    return _PreparedNumbering(this, id, changed: true);
  }

  bool _defaultShape(XmlElement definition, bool numbered) {
    final type = _one(definition, 'multiLevelType');
    final levels = _children(definition, 'lvl').toList();
    if (type == null ||
        _value(type, 'val') != 'singleLevel' ||
        levels.length != 1) {
      return false;
    }
    final level = levels.single;
    if (_value(level, 'ilvl') != '0') return false;
    for (final (key, expected) in <(String, String)>[
      ('start', '1'),
      ('numFmt', numbered ? 'decimal' : 'bullet'),
      ('lvlText', numbered ? '%1.' : '•'),
      ('lvlJc', 'left'),
    ]) {
      final node = _one(level, key);
      if (node == null || _value(node, 'val') != expected) return false;
    }
    final pp = _one(level, 'pPr');
    final indent = pp == null ? null : _one(pp, 'ind');
    return indent != null &&
        _value(indent, 'left') == '360' &&
        _value(indent, 'hanging') == '180' &&
        _one(level, 'lvlPicBulletId') == null &&
        _one(definition, 'numStyleLink') == null &&
        _one(definition, 'styleLink') == null;
  }
}

class _PreparedNumbering {
  _PreparedNumbering(this.source, this.id, {required this.changed});
  final _NumberingSource source;
  final int id;
  final bool changed;
  void publish() {
    if (!changed) return;
    final xml = XmlDocument(root: source.root).toXmlString();
    final part = source.package.getPart(source.uri);
    if (part == null) {
      source.package.createPart(
        source.uri,
        OfficeContentTypes.wordNumbering,
        utf8.encode(xml),
      );
    } else {
      part.writeText(xml);
    }
    if (!source.hasRelationship) {
      source.relationships.add(
        type: RelationshipTypes.numbering,
        target: source.uri,
      );
    }
    source.document.package = source.package;
  }
}

bool _listNum(String? instruction) =>
    instruction != null &&
    RegExp(r'^\s*LISTNUM(?:\s|$)', caseSensitive: false).hasMatch(instruction);

class _FieldScan {
  _FieldScan(this.touches);
  bool touches;
  final instruction = StringBuffer();
}

void _checkListNumFields(WmlDocument document, WmlParagraph target) {
  final open = <_FieldScan>[];
  void check(_FieldScan field) {
    if (field.touches && _listNum(field.instruction.toString())) {
      throw UnsupportedError(
        'RemoveNumbers all cannot remove LISTNUM fields; use paragraph to retain fields.',
      );
    }
  }

  for (final paragraph in document.paragraphs) {
    final selected = identical(paragraph, target);
    for (final field in open) {
      field.touches |= selected;
    }
    if (selected && _listNum(paragraph.properties.fieldInstruction)) {
      throw UnsupportedError(
        'RemoveNumbers all cannot remove a paragraph LISTNUM field.',
      );
    }
    for (final inline in paragraph.inlines) {
      if (inline is WmlFieldBoundary) {
        switch (inline.kind) {
          case WmlFieldBoundaryKind.begin:
            open.add(_FieldScan(selected));
          case WmlFieldBoundaryKind.instruction:
            if (open.isNotEmpty) {
              open.last.instruction.write(inline.text);
            } else if (selected) {
              throw UnsupportedError(
                'Unbalanced field instruction in selected paragraph.',
              );
            }
          case WmlFieldBoundaryKind.separate:
            if (open.isNotEmpty) check(open.last);
          case WmlFieldBoundaryKind.end:
            if (open.isNotEmpty) check(open.removeLast());
        }
      } else if (selected &&
          inline is WmlRun &&
          _listNum(inline.fieldInstruction)) {
        throw UnsupportedError(
          'RemoveNumbers all cannot remove an inline LISTNUM field.',
        );
      } else if (selected && inline is WmlOpaqueInline) {
        final raw = inline.content.xml;
        if (raw.contains('instrText') ||
            raw.contains('fldSimple') ||
            raw.contains('fldChar')) {
          throw UnsupportedError(
            'RemoveNumbers all cannot interpret opaque native field content.',
          );
        }
      }
    }
  }
  for (final field in open) {
    if (field.touches) {
      throw UnsupportedError(
        'Unbalanced field overlaps the selected paragraph.',
      );
    }
  }
}
