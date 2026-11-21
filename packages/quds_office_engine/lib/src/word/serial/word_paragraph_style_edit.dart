part of 'word_deserializer.dart';

/// A style assignment owns one native pStyle value, never its inherited
/// formatting or the document's style definitions.
final class _ParagraphStyleEdit {
  _ParagraphStyleEdit(this.reader, this.document);
  final WordDeserializer reader;
  final WmlDocument document;
  static const _w = OfficeNamespaces.w;
  static const _builtins = <int, String>{
    -1: 'normal',
    -2: 'heading 1',
    -3: 'heading 2',
    -4: 'heading 3',
    -5: 'heading 4',
    -6: 'heading 5',
    -7: 'heading 6',
    -8: 'heading 7',
    -9: 'heading 8',
    -10: 'heading 9',
    -35: 'caption',
    -63: 'title',
    -75: 'subtitle',
  };

  Never _refuse(String reason) =>
      throw UnsupportedError('Paragraph style assignment $reason.');

  static bool _word(XmlElement node, String name) =>
      node.localName == name && node.namespaceUri == _w;

  static String? _attribute(XmlElement node, String name) =>
      node.getAttribute(name, namespaceUri: _w);

  static bool _safeText(String value) => value.runes.every(
    (rune) =>
        rune >= 0x20 && rune <= 0xd7ff ||
        rune >= 0xe000 && rune <= 0xfffd ||
        rune >= 0x10000 && rune <= 0x10ffff,
  );

  String _requiredValue(XmlElement element, String attribute) {
    final matches = element.attributes.where(
      (item) => item.namespaceUri == _w && item.localName == attribute,
    );
    if (matches.length != 1 ||
        matches.single.value.isEmpty ||
        !_safeText(matches.single.value)) {
      _refuse('requires one nonempty native $attribute');
    }
    return matches.single.value;
  }

  XmlElement? _child(XmlElement element, String name) {
    final children = element.childElements
        .where((child) => _word(child, name))
        .toList();
    if (children.length > 1) _refuse('refuses duplicate native $name elements');
    return children.singleOrNull;
  }

  bool _enabled(XmlElement element, String attribute) {
    final value = _attribute(element, attribute);
    if (value == null || const {'0', 'false', 'off'}.contains(value)) {
      return false;
    }
    if (const {'1', 'true', 'on'}.contains(value)) return true;
    _refuse('requires a recognized native $attribute value');
  }

  PackageRelationship _relationship(
    RelationshipCollection relationships,
    String type,
  ) {
    final matches = relationships.byType(type).toList();
    final ids = <String>{};
    if (relationships.items.any((item) => !ids.add(item.id)) ||
        matches.length != 1 ||
        matches.single.targetMode != RelationshipTargetMode.internal) {
      _refuse('requires one unambiguous internal $type relationship');
    }
    final target = matches.single.target;
    if (target.isEmpty || RegExp(r'[%?#:\s\\]').hasMatch(target)) {
      _refuse('refuses ambiguous relationship target syntax');
    }
    return matches.single;
  }

  void _attributes(XmlElement node) {
    final seen = <String>{};
    for (final attribute in node.attributes) {
      if (attribute.namespaceUri == _w && !seen.add(attribute.localName)) {
        _refuse('refuses duplicate native ${attribute.localName} attributes');
      }
    }
  }

  /// Check source packets before they pass through the effective parser.
  /// Foreign metadata is retained but cannot hide a native style reference.
  void _properties(XmlElement root, {bool style = false}) {
    if (!_word(root, 'pPr') && !_word(root, 'rPr')) {
      _refuse('requires native direct property roots');
    }
    final direct = <String>{};
    for (final child in root.childElements) {
      if (child.namespaceUri == _w && !direct.add(child.localName)) {
        _refuse('refuses duplicate native ${child.localName} properties');
      }
    }
    const paragraphProperties = {
      'pStyle',
      'jc',
      'spacing',
      'ind',
      'keepNext',
      'keepLines',
      'pageBreakBefore',
      'numPr',
      'pBdr',
      'framePr',
      'tabs',
      'outlineLvl',
      'suppressAutoHyphens',
      'bidi',
      'rPr',
    };
    const runProperties = {
      'rStyle',
      'lang',
      'rtl',
      'cs',
      'noProof',
      'b',
      'bCs',
      'i',
      'iCs',
      'strike',
      'dstrike',
      'smallCaps',
      'caps',
      'color',
      'highlight',
      'kern',
      'sz',
      'szCs',
      'u',
      'vertAlign',
      'rFonts',
      'emboss',
      'imprint',
      'outline',
      'shadow',
      'vanish',
    };
    const attributeNames = {
      'val',
      'themeColor',
      'themeShade',
      'themeTint',
      'ascii',
      'hAnsi',
      'cs',
      'eastAsia',
      'asciiTheme',
      'hAnsiTheme',
      'cstheme',
      'eastAsiaTheme',
      'before',
      'after',
      'line',
      'lineRule',
      'left',
      'right',
      'start',
      'end',
      'firstLine',
      'hanging',
      'pos',
      'leader',
      'type',
      'fill',
      'color',
      'sz',
      'space',
      'dropCap',
      'lines',
    };
    void visit(XmlElement node) {
      _attributes(node);
      if (node.namespaceUri == _w) {
        _propertyValues(node);
        if (style && node.localName == 'pStyle') {
          _refuse(
            'refuses paragraph-style references inside style definitions',
          );
        }
      }
      if (!identical(node, root)) {
        final property = node.localName;
        final expected = <String>{
          if (paragraphProperties.contains(property)) 'pPr',
          if (runProperties.contains(property)) 'rPr',
          if (property == 'shd') ...['pPr', 'rPr'],
          if (const {'numId', 'ilvl'}.contains(property)) 'numPr',
          if (property == 'tab') 'tabs',
          if (const {
            'top',
            'left',
            'bottom',
            'right',
            'between',
            'bar',
            'start',
            'end',
          }.contains(property))
            'pBdr',
        };
        // pStyle's projection and reader explicitly ignore namespace
        // lookalikes. Other native parsers still accept some local names;
        // refuse those inputs instead of returning a value that changes on
        // save/reopen. Benign extension attributes/children remain opaque.
        final foreignStyle =
            property == 'pStyle' &&
            node.namespaceUri != _w &&
            identical(node.parent, root);
        if (expected.isNotEmpty &&
            !foreignStyle &&
            (node.namespaceUri != _w ||
                node.parent?.namespaceUri != _w ||
                !expected.contains(node.parent?.localName))) {
          _refuse('refuses foreign or nested formatting-property lookalikes');
        }
        if (node.namespaceUri == _w && expected.isNotEmpty) {
          for (final attribute in node.attributes) {
            if (attribute.namespaceUri != _w &&
                attribute.prefix != 'xmlns' &&
                attribute.qualifiedName != 'xmlns' &&
                attributeNames.contains(attribute.localName) &&
                !(property == 'pStyle' && attribute.localName == 'val')) {
              _refuse('refuses ambiguous foreign formatting attributes');
            }
          }
        }
      }
      if (node.namespaceUri == _w &&
          const {'sectPr', 'pPrChange', 'rPrChange'}.contains(node.localName)) {
        return;
      }
      if (node.namespaceUri == OfficeNamespaces.mc &&
              node.localName == 'AlternateContent' ||
          (node
                  .getAttribute(
                    'ProcessContent',
                    namespaceUri: OfficeNamespaces.mc,
                  )
                  ?.trim()
                  .isNotEmpty ??
              false)) {
        _refuse('refuses alternative or ProcessContent property markup');
      }
      if (_word(node, 'pStyle') || _word(node, 'rStyle')) {
        final owner = node.parent;
        if (!identical(owner, root) ||
            _word(node, 'pStyle') != _word(root, 'pPr')) {
          _refuse('refuses nested native style references');
        }
        _requiredValue(node, 'val');
      }
      for (final child in node.childElements) {
        visit(child);
      }
    }

    visit(root);
  }

  void _propertyValues(XmlElement node) {
    final value = _attribute(node, 'val');
    const onOff = {'0', '1', 'true', 'false', 'on', 'off'};
    if (const {
          'b',
          'i',
          'bCs',
          'iCs',
          'caps',
          'smallCaps',
          'strike',
          'noProof',
          'rtl',
          'cs',
          'bidi',
          'keepLines',
          'keepNext',
          'pageBreakBefore',
          'suppressAutoHyphens',
        }.contains(node.localName) &&
        value != null &&
        !onOff.contains(value)) {
      _refuse('requires a recognized native ${node.localName} boolean');
    }
    if (const {'sz', 'szCs', 'kern', 'outlineLvl'}.contains(node.localName)) {
      final number = value == null ? null : int.tryParse(value);
      if (number == null ||
          number < 0 ||
          number > 2147483647 ||
          node.localName == 'outlineLvl' && number > 9) {
        _refuse('requires a valid native ${node.localName} value');
      }
    }
    if (node.localName == 'spacing' || node.localName == 'ind') {
      for (final attribute in node.attributes.where(
        (item) => item.namespaceUri == _w,
      )) {
        if (attribute.localName == 'lineRule') {
          if (!const {'auto', 'exact', 'atLeast'}.contains(attribute.value)) {
            _refuse('requires a recognized native line-spacing rule');
          }
        } else if (attribute.localName.endsWith('Autospacing')) {
          if (!onOff.contains(attribute.value)) {
            _refuse('requires a recognized native automatic-spacing boolean');
          }
        } else {
          final number = int.tryParse(attribute.value);
          if (number == null || number < -2147483648 || number > 2147483647) {
            _refuse('requires valid native paragraph measurements');
          }
        }
      }
    }
    if (node.localName == 'numPr') {
      for (final name in ['numId', 'ilvl']) {
        final child = _child(node, name);
        if (child == null) continue;
        final number = int.tryParse(_requiredValue(child, 'val'));
        if (number == null ||
            number < 0 ||
            number > (name == 'ilvl' ? 8 : 2147483647)) {
          _refuse('requires a valid native numbering $name');
        }
      }
    }
  }

  void _numberingStyleLinks(
    OpcPackage package,
    RelationshipCollection relationships,
    String? previousStyle,
    String nextStyle,
  ) {
    if (previousStyle == nextStyle) return;
    final references = relationships
        .byType(RelationshipTypes.numbering)
        .toList();
    if (references.length > 1 ||
        references.any(
          (reference) =>
              reference.targetMode != RelationshipTargetMode.internal ||
              reference.target.isEmpty ||
              RegExp(r'[%?#:\s\\]').hasMatch(reference.target),
        )) {
      _refuse('requires unambiguous native numbering relationships');
    }
    final part = package.getPart(
      references.isEmpty
          ? '/word/numbering.xml'
          : relationships.resolve(references.single),
    );
    if (part == null) return;
    final root = XmlDocument.parse(part.readText()).root;
    if (root == null || !_word(root, 'numbering')) {
      _refuse('requires native numbering XML');
    }
    void visit(XmlElement node) {
      if (node.namespaceUri != _w) return;
      if (const {
        'pStyle',
        'styleLink',
        'numStyleLink',
      }.contains(node.localName)) {
        final style = _requiredValue(node, 'val');
        if (style == previousStyle || style == nextStyle) {
          _refuse('does not change style-linked numbering');
        }
      }
      for (final child in node.childElements) {
        visit(child);
      }
    }

    visit(root);
  }

  XmlElement _fragment(String? xml, String name) {
    if (xml == null || xml.isEmpty) {
      return XmlElement(localName: name, prefix: 'w', namespaceUri: _w)
        ..setAttribute('w', _w, prefix: 'xmlns');
    }
    final context = XmlDocument.parse(
      '<w:styleContext xmlns:w="$_w">$xml</w:styleContext>',
    ).root!;
    final roots = context.childElements.toList();
    if (roots.length != 1 || !_word(roots.single, name)) {
      _refuse('requires one native $name source packet');
    }
    final root = roots.single;
    _properties(root);
    return root;
  }

  void _packageAlternatives(OpcPackage package) {
    void visit(XmlElement node, bool alternative) {
      // Import retains one direct pPr/rPr packet. Refuse duplicate original
      // packets before a style save can silently discard an earlier one.
      if (_word(node, 'p')) _child(node, 'pPr');
      if (_word(node, 'r')) _child(node, 'rPr');
      final inside =
          alternative ||
          node.namespaceUri == OfficeNamespaces.mc &&
              node.localName == 'AlternateContent';
      if (inside &&
          node.namespaceUri == _w &&
          const {
            'style',
            'pPr',
            'rPr',
            'pStyle',
            'rStyle',
          }.contains(node.localName)) {
        _refuse('refuses style-bearing markup-compatibility alternatives');
      }
      if (node
              .getAttribute('ProcessContent', namespaceUri: OfficeNamespaces.mc)
              ?.trim()
              .isNotEmpty ??
          false) {
        _refuse('refuses ProcessContent source markup');
      }
      for (final child in node.childElements) {
        visit(child, inside);
      }
    }

    for (final part in package.parts) {
      if (!part.contentType.endsWith('+xml') ||
          (!part.contentType.contains('wordprocessingml') &&
              !part.contentType.contains('vnd.ms-word'))) {
        continue;
      }
      final source = package.getPart(part.uri)!.readText();
      final root = XmlDocument.parse(source).root;
      if (root != null) visit(root, false);
    }
  }

  void apply(WmlParagraph target, {String? name, int? builtin}) {
    if ((name == null) == (builtin == null)) {
      throw ArgumentError('Provide exactly one style name or builtin.');
    }
    if (name != null && (name.trim().isEmpty || !_safeText(name))) {
      throw ArgumentError('Style name must be nonempty XML-safe text.');
    }
    if (builtin != null && !_builtins.containsKey(builtin)) {
      throw ArgumentError('Unsupported Word built-in paragraph style.');
    }
    final package = document.package;
    if (package == null) _refuse('requires existing native styles');
    final office = _relationship(
      package.packageRelationships,
      RelationshipTypes.officeDocument,
    );
    final documentUri = package.packageRelationships.resolve(office);
    final documentPart = package.getPart(documentUri);
    final documentRoot = documentPart == null
        ? null
        : XmlDocument.parse(documentPart.readText()).root;
    if (documentRoot == null || !_word(documentRoot, 'document')) {
      _refuse('requires its native document part');
    }
    final relationships = package.relationshipsFor(documentUri);
    final stylesRel = _relationship(relationships, RelationshipTypes.styles);
    final stylesPart = package.getPart(relationships.resolve(stylesRel));
    if (stylesPart == null ||
        stylesPart.contentType != OfficeContentTypes.wordStyles) {
      _refuse('requires an existing native styles part');
    }
    final root = XmlDocument.parse(stylesPart.readText()).root;
    if (root == null || !_word(root, 'styles')) {
      _refuse('requires a native styles root');
    }
    _packageAlternatives(package);
    // Native source remains authoritative for this bounded operation. A host
    // may have replaced/removed a model style since import; save would then
    // rewrite its definition after this edit resolved the old native cascade.
    final modeledIds = <String>{};
    if (document.styles.any(
          (style) =>
              !modeledIds.add(style.id) ||
              !identical(style, document.importedStyles[style.id]),
        ) ||
        document.importedStyles.keys.any((id) => !modeledIds.contains(id))) {
      _refuse('requires synchronized native and modeled style definitions');
    }
    final styles = <String, XmlElement>{};
    final names = <String, String>{};
    String? defaultParagraph;
    final defaults = _child(root, 'docDefaults');
    if (defaults != null) {
      for (final name in ['pPr', 'rPr']) {
        final wrapper = _child(defaults, '${name}Default');
        final properties = wrapper == null ? null : _child(wrapper, name);
        if (properties != null) _properties(properties, style: true);
      }
    }
    for (final style in root.childElements.where(
      (node) => _word(node, 'style'),
    )) {
      _attributes(style);
      final id = _requiredValue(style, 'styleId');
      if (styles.containsKey(id)) _refuse('refuses duplicate native style IDs');
      final type = _attribute(style, 'type') ?? 'paragraph';
      if (!const {
        'paragraph',
        'character',
        'table',
        'numbering',
      }.contains(type)) {
        _refuse('requires recognized native style types');
      }
      final primary = _child(style, 'name');
      if (primary != null) {
        final value = _requiredValue(primary, 'val').toLowerCase();
        if (names.containsKey(value)) {
          _refuse('refuses ambiguous case-insensitive primary style names');
        }
        names[value] = id;
      }
      _enabled(style, 'customStyle');
      if (_enabled(style, 'default') && type == 'paragraph') {
        if (defaultParagraph != null) {
          _refuse('refuses multiple default styles');
        }
        defaultParagraph = id;
      }
      _child(style, 'basedOn');
      for (final properties in ['pPr', 'rPr']) {
        final packet = _child(style, properties);
        if (packet != null) _properties(packet, style: true);
      }
      for (final region in style.childElements.where(
        (node) => _word(node, 'tblStylePr'),
      )) {
        for (final properties in ['pPr', 'rPr']) {
          final packet = _child(region, properties);
          if (packet != null) _properties(packet, style: true);
        }
      }
      styles[id] = style;
    }
    final resolved = <String>{};
    void chain(String id, Set<String> visiting) {
      if (resolved.contains(id)) return;
      if (!visiting.add(id)) _refuse('refuses cyclic basedOn chains');
      final style = styles[id];
      if (style == null) _refuse('requires resolved native style references');
      final parent = _child(style, 'basedOn');
      if (parent != null) {
        final parentId = _requiredValue(parent, 'val');
        final parentStyle = styles[parentId];
        if (parentStyle == null ||
            (_attribute(parentStyle, 'type') ?? 'paragraph') !=
                (_attribute(style, 'type') ?? 'paragraph')) {
          _refuse('requires a resolved basedOn chain of matching style types');
        }
        chain(parentId, visiting);
      }
      visiting.remove(id);
      resolved.add(id);
    }

    for (final id in styles.keys) {
      chain(id, {});
    }
    final id = names[(name ?? _builtins[builtin]!).toLowerCase()];
    if (id == null) throw ArgumentError('Unknown native paragraph style.');
    final selected = styles[id]!;
    if ((_attribute(selected, 'type') ?? 'paragraph') != 'paragraph') {
      throw ArgumentError('Style must be a native paragraph style.');
    }
    if (builtin != null && _enabled(selected, 'customStyle')) {
      _refuse('cannot select a custom style through a built-in constant');
    }
    final cascade = _StyleCascade(reader, document, nativeOnly: true).._load();
    List<XmlElement>? tableLayers;
    var occurrences = 0;
    final all = <WmlParagraph>[];
    final blocksSeen = Set<WmlBlock>.identity();
    void locate(
      Iterable<WmlBlock> blocks, [
      List<XmlElement> inherited = const [],
    ]) {
      for (final block in blocks) {
        if (!blocksSeen.add(block)) {
          throw StateError(
            'Paragraph style assignment requires uniquely owned, acyclic blocks.',
          );
        }
        if (block is WmlParagraph) all.add(block);
        if (identical(block, target)) {
          tableLayers = inherited;
          occurrences++;
        }
        if (block is WmlTable) {
          final tableStyle = block.properties.styleId;
          if (tableStyle != null &&
              (styles[tableStyle] == null ||
                  _attribute(styles[tableStyle]!, 'type') != 'table')) {
            _refuse('requires resolved native table style context');
          }
          for (var row = 0; row < block.rows.length; row++) {
            final layers = cascade._tableCellLayers(block, row);
            for (final cell in block.rows[row].cells) {
              locate(cell.blocks, layers);
            }
          }
        } else if (block is WmlToc) {
          final generated = [
            block.titleParagraph,
            ...block.itemParagraphs,
            for (final source
                in block.sourcePresentation?.paragraphs ??
                    <WmlTocSourceParagraph>[])
              source.paragraph,
          ];
          if (generated.any((paragraph) => identical(paragraph, target))) {
            _refuse('does not edit generated table-of-contents paragraphs');
          }
          // Generated/live cache runs are owners too: publishing a body run
          // must not accidentally rewrite an aliased TOC title or result.
          locate(generated, inherited);
        } else {
          for (final children in WordTree.childLists(block)) {
            locate(children, inherited);
          }
        }
      }
    }

    for (final section in document.sections) {
      locate(section.blocks);
      for (final story in [
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ]) {
        locate(story);
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      locate(note.blocks);
    }
    for (final comment in document.comments) {
      locate(comment.paragraphs);
    }
    if (occurrences != 1) _refuse('requires one current paragraph owner');
    Iterable<Object> mutable(WmlParagraph paragraph) sync* {
      yield paragraph;
      yield paragraph.inlines;
      yield paragraph.properties;
      yield paragraph.properties.tabs;
      if (paragraph.properties.importedValues case final map?) yield map;
      if (paragraph.properties.importedParagraphMark case final mark?) {
        yield mark;
      }
      for (final inline in paragraph.inlines) {
        yield inline;
        if (inline is WmlRun) {
          yield inline.properties;
          if (inline.properties.importedValues case final map?) yield map;
        } else if (inline is WmlNoteMarker) {
          yield inline.properties;
        }
      }
    }

    final selectedObjects = Set<Object>.identity()..addAll(mutable(target));
    final seen = Set<Object>.identity();
    for (final paragraph in all) {
      for (final value in mutable(paragraph)) {
        if (selectedObjects.contains(value) && !seen.add(value)) {
          _refuse(
            'refuses shared mutable paragraph, inline or property models',
          );
        }
      }
    }
    // Cycle/ownership checks above must precede generic field traversal.
    if (WordFieldSpans.unbalanced(document).isNotEmpty) {
      _refuse('cannot preserve unbalanced modeled field boundaries');
    }
    final before = target.properties;
    if (before.numId != null ||
        before.listLabel != null ||
        before.listRestart != null) {
      _refuse('does not restyle actively numbered paragraphs');
    }
    final nativeBefore = _fragment(before.sourcePropertiesXml, 'pPr');
    final imported = before.importedValues;
    final pendingStyle =
        imported == null || imported['pStyle'] != '${before.styleId}';
    final beforeReference = _child(nativeBefore, 'pStyle');
    final oldStyle = pendingStyle
        ? before.styleId
        : beforeReference == null
        ? defaultParagraph
        : _requiredValue(beforeReference, 'val');
    if (oldStyle != null &&
        (styles[oldStyle] == null ||
            (_attribute(styles[oldStyle]!, 'type') ?? 'paragraph') !=
                'paragraph')) {
      _refuse('requires a resolved existing paragraph style');
    }
    final prepared = WmlClone.paragraph(target);
    // This setter replaces the pending pStyle value itself. Keep its original
    // sparse packet while flushing other pending edits, so the general value
    // serializer cannot discard extension metadata on the old reference.
    prepared.properties.importedValues?['pStyle'] =
        '${prepared.properties.styleId}';
    final serializer = WordSerializer();
    final direct = _fragment(
      serializer.paragraphPropertiesXml(prepared.properties),
      'pPr',
    );
    for (final run in prepared.inlines.whereType<WmlRun>()) {
      final style = run.properties.styleId;
      if (style != null &&
          (styles[style] == null ||
              _attribute(styles[style]!, 'type') != 'character')) {
        _refuse('requires resolved native character style references');
      }
      _fragment(run.properties.sourcePropertiesXml, 'rPr');
      run.properties.sourcePropertiesXml = XmlDocument(
        root: _fragment(serializer.runPropertiesXml(run.properties), 'rPr'),
      ).toXmlString(declaration: false);
      run.properties.importedValues = WordPropertyIo.runValues(run.properties);
    }
    var reference = _child(direct, 'pStyle');
    if (reference == null) {
      reference = XmlElement(localName: 'pStyle', prefix: 'w', namespaceUri: _w)
        ..setAttribute('w', _w, prefix: 'xmlns');
      direct.addChild(reference);
    }
    reference.attributes.removeWhere(
      (item) => item.localName == 'val' && item.namespaceUri == _w,
    );
    var prefix = reference.prefix;
    if (prefix.isEmpty || reference.namespaceUri != _w) prefix = 'w';
    reference.setAttribute(prefix, _w, prefix: 'xmlns');
    reference.attributes.add(
      XmlAttribute(
        localName: 'val',
        value: id,
        prefix: prefix,
        namespaceUri: _w,
      ),
    );
    WordPropertyIo.orderChildren(direct);
    prepared.properties
      ..styleId = id
      ..sourcePropertiesXml = XmlDocument(
        root: direct,
      ).toXmlString(declaration: false);
    prepared.properties.importedValues = WordPropertyIo.paragraphValues(
      prepared.properties,
    );
    cascade.paragraph(prepared, tableLayers!);
    final after = prepared.properties;
    if (after.numId != null ||
        after.numberingSuppressed != before.numberingSuppressed ||
        after.ilvl != before.ilvl) {
      _refuse('does not change effective paragraph numbering');
    }
    _numberingStyleLinks(package, relationships, oldStyle, id);
    // Some legacy effective-property readers are permissive about namespace
    // aliases. This operation must never publish a value that changes when the
    // ordinary import cascade next resolves the same sparse source. Compare a
    // second detached projection rather than broadening unrelated readers.
    final reopenedProjection = WmlClone.paragraph(prepared);
    final ordinary = _StyleCascade(reader, document).._load();
    ordinary.paragraph(reopenedProjection, tableLayers!);
    bool same(Map<String, String> left, Map<String, String> right) =>
        left.length == right.length &&
        left.entries.every((entry) => right[entry.key] == entry.value);
    bool sameRun(WmlRunProps? left, WmlRunProps? right) =>
        left == null && right == null ||
        left != null &&
            right != null &&
            left.complexScript == right.complexScript &&
            same(
              WordPropertyIo.runValues(left),
              WordPropertyIo.runValues(right),
            );
    final preparedRuns = prepared.inlines.whereType<WmlRun>().toList();
    final ordinaryRuns = reopenedProjection.inlines
        .whereType<WmlRun>()
        .toList();
    if (!same(
          WordPropertyIo.paragraphValues(prepared.properties),
          WordPropertyIo.paragraphValues(reopenedProjection.properties),
        ) ||
        !sameRun(
          prepared.properties.importedParagraphMark,
          reopenedProjection.properties.importedParagraphMark,
        ) ||
        preparedRuns.length != ordinaryRuns.length ||
        preparedRuns.indexed.any(
          (entry) =>
              !sameRun(entry.$2.properties, ordinaryRuns[entry.$1].properties),
        )) {
      _refuse(
        'requires effective property namespaces stable across native reopens',
      );
    }
    final liveRuns = target.inlines.whereType<WmlRun>().toList(growable: false);
    // No further validation or fallible work follows. Preserve the identities
    // used by caller selections, bookmarks, fields and revision ownership.
    for (final (index, run) in liveRuns.indexed) {
      run.properties = preparedRuns[index].properties;
    }
    target.properties = prepared.properties;
  }
}
