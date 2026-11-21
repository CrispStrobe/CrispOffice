import 'dart:convert';
import 'dart:typed_data';

import '../../odf/odf_text.dart';
import '../../odf/odf_zotero.dart';
import '../../opc/office_package_parts.dart';
import '../../opc/zip/zip_reader.dart';
import '../../xml/xml_node.dart';
import '../model/wml_document.dart';
import '../model/word_lists.dart';
import '../model/word_notes.dart';
import '../model/word_zotero.dart';
import '../model/word_zotero_data.dart';
import '../properties/wml_properties.dart';
import 'odt_reader_styles.dart';

const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _xml = 'http://www.w3.org/XML/1998/namespace';

/// Converts a bounded native ODT into an editable Word document.
///
/// This is an explicit conversion boundary, not a lossless ODF round trip.
/// Supported paragraphs, styles, hyperlinks, simple lists, unmerged tables and
/// authored notes keep their native structure. Canonical Zotero fields use the
/// inventory's exact paragraph identities and UTF-16 positions. Unsupported
/// content or ambiguous fields refuse the whole import before publication.
/// Save the result as DOCX to retain active Word/Zotero fields. Ordinary ODT
/// export retains its separate cached-result contract.
abstract final class OdtDocumentReader {
  static Future<WmlDocument> readBytes(
    Uint8List bytes, {
    OdfZoteroLimits limits = const OdfZoteroLimits(),
  }) async {
    limits.validate();
    if (bytes.length > limits.maxArchiveBytes) {
      throw const OdfZoteroLimitException('archive bytes');
    }
    // Bind inventory and rich parsing to the same immutable input across awaits.
    final source = Uint8List.fromList(bytes);
    final inventory = await OdfZotero.inspect(source, limits: limits);
    if (inventory.issues.isNotEmpty) {
      throw UnsupportedError(inventory.issues.first.message);
    }
    for (final field in inventory.fields) {
      // The inventory conservatively guards a whole paragraph containing a
      // note anchor. This richer reader may qualify its supported content, but
      // never repairs ambiguous endpoints, stories, owners or field metadata.
      final needsRichQualification =
          field.isValid &&
          field.issues.every(
            (issue) => issue.code == OdfZoteroIssueCode.unsupportedContent,
          );
      if (!field.isImportCandidate && !needsRichQualification) {
        throw FormatException(
          'The native Zotero field cannot be imported: '
          '${field.issues.map((issue) => issue.code.name).join(', ')}.',
        );
      }
    }
    final preferences = inventory.preferences;
    if (!preferences.isValid || preferences.issues.isNotEmpty) {
      throw const FormatException('Invalid native ODT Zotero preferences.');
    }
    if (preferences.rawData?.isNotEmpty == true &&
        !preferences.usesReferenceMarks) {
      throw const FormatException(
        'Native ODT import requires ReferenceMark Zotero preferences.',
      );
    }
    final zip = ZipReader.fromBytes(
      source,
      maxEntries: limits.maxZipEntries,
      rejectDuplicateNames: true,
    );
    // These exact parts have already passed cumulative XML/element/depth and
    // duplicate-attribute validation in the inventory, using the same bytes.
    final parts = OfficePackageParts(
      (name) => zip.contains(name)
          ? utf8.decode(zip.read(name, maxBytes: limits.maxPartBytes))
          : null,
      maxXmlDepth: limits.maxXmlDepth,
    );
    final content = (await parts.xml('content.xml'))!.root!;
    final styles = (await parts.xml('styles.xml'))?.root;
    final metadata = (await parts.xml('meta.xml'))?.root;
    final reader = _OdtReader(content, styles, inventory, limits);
    final document = reader.read();
    reader.readMetadata(metadata);
    // Only a fully reconstructed document may adopt foreign storage settings.
    document.zoteroDocumentData = WordZoteroDocumentData.fromOdt(
      preferences.rawData ?? '',
    );
    document.sourceByteLength = source.length;
    return document;
  }

  /// Byte-based dispatch for the Word loader, independent of a file extension.
  /// Malformed ZIP packages continue to the normal loader's error handling.
  static bool isOdt(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
      return false;
    }
    final ZipReader zip;
    try {
      zip = ZipReader.fromBytes(bytes);
    } on ZipException {
      return false;
    }
    if (!zip.contains('mimetype') &&
        zip.contains('content.xml') &&
        !zip.contains('[Content_Types].xml')) {
      // Route damaged ODF-looking input through the strict native reader,
      // rather than repairing it into an empty DOCX model.
      return true;
    }
    return zip.contains('mimetype') &&
        utf8.decode(zip.read('mimetype', maxBytes: 128)) ==
            'application/vnd.oasis.opendocument.text';
  }
}

final class _OdtReader {
  _OdtReader(this.content, XmlElement? styleRoot, this.inventory, this.limits)
    : styles = OdtReaderStyles(content, styles: styleRoot),
      textBudget = OdfTextBudget(limits.maxTextBytes) {
    _index(content, '/0');
  }

  final XmlElement content;
  final OdfZoteroInventory inventory;
  final OdfZoteroLimits limits;
  final OdtReaderStyles styles;
  final OdfTextBudget textBudget;
  final document = WmlDocument(sections: []);
  final paths = Map<XmlElement, String>.identity();
  final paragraphs = <String, WmlParagraph>{};
  final _bibliographySections = <String>{};
  final _nativeMarks = <String>{};
  final _noteIds = <String>{};
  var _tableCount = 0;
  var _cellCount = 0;
  var _listCount = 0;

  void _index(XmlElement element, String path) {
    paths[element] = path;
    var index = 0;
    for (final child in element.childElements) {
      _index(child, '$path/${index++}');
    }
  }

  WmlDocument read() {
    for (final field in inventory.fields) {
      if (field.storage == OdfZoteroStorage.section) {
        _bibliographySections.add(field.name);
      } else {
        _nativeMarks.add(field.name);
      }
    }
    _attributes(content, {
      odfOfficeNamespace: {'version'},
    });
    for (final child in content.childElements) {
      if (child.namespaceUri != odfOfficeNamespace ||
          !{
            'font-face-decls',
            'automatic-styles',
            'body',
          }.contains(child.localName)) {
        _unsupported(child);
      }
    }
    final body = content
        .childrenNamed('body', namespaceUri: odfOfficeNamespace)
        .single;
    _attributes(body, {});
    final text = body
        .childrenNamed('text', namespaceUri: odfOfficeNamespace)
        .single;
    if (body.childElements.length != 1) _unsupported(body);
    _attributes(text, {});
    final section = WmlSection();
    document.sections.add(section);
    section.blocks.addAll(_blocks(text));
    styles.applyPageLayout(section);
    _attachFields();
    final actual = WordZotero.fields(document);
    if (actual.length != inventory.fields.length) {
      throw const FormatException(
        'Native ODT field reconstruction is incomplete.',
      );
    }
    final expected = <String, List<String>>{};
    for (final field in inventory.fields) {
      expected
          .putIfAbsent(' ADDIN ZOTERO_${field.logicalCode} ', () => [])
          .add(field.cachedText);
    }
    for (final field in actual) {
      final values = expected[field.instruction];
      if (values == null || !values.remove(field.cachedText)) {
        throw const FormatException(
          'Native ODT field content changed during import.',
        );
      }
      if (!field.isValid ||
          field.locked ||
          field.nested ||
          field.opaqueMetadata ||
          (field.kind == ZoteroFieldKind.citation && !field.canEdit)) {
        throw const FormatException(
          'Native ODT field has unsupported editable ownership.',
        );
      }
    }
    return document;
  }

  List<WmlBlock> _blocks(
    XmlElement owner, {
    bool inNote = false,
    int tableDepth = 0,
    int listDepth = 0,
    String? inheritedListStyle,
  }) {
    final result = <WmlBlock>[];
    for (final node in owner.children) {
      if (node is XmlText || node is XmlCdata) {
        final value = node is XmlText ? node.text : (node as XmlCdata).text;
        if (value.trim().isNotEmpty) _unsupported(owner);
        continue;
      }
      if (node is! XmlElement) continue;
      if (isOdfParagraph(node)) {
        result.add(_paragraph(node, inNote: inNote));
      } else if (_is(node, odfTableNamespace, 'table')) {
        result.add(_table(node, inNote: inNote, depth: tableDepth + 1));
      } else if (_is(node, odfTextNamespace, 'list')) {
        result.addAll(
          _list(
            node,
            inNote: inNote,
            tableDepth: tableDepth,
            depth: listDepth,
            inheritedStyle: inheritedListStyle,
          ),
        );
      } else if (_is(node, odfTextNamespace, 'section')) {
        _attributes(node, {
          odfTextNamespace: {'name'},
        });
        final name = _attr(node, 'name', odfTextNamespace);
        if (!_bibliographySections.contains(name)) _unsupported(node);
        result.addAll(_blocks(node, inNote: inNote, tableDepth: tableDepth));
      } else if (_is(node, odfTextNamespace, 'sequence-decls')) {
        // Inert declarations generated by LibreOffice do not author content.
        // A later sequence field is rejected by the inline parser.
        for (final declaration in node.childElements) {
          if (!_is(declaration, odfTextNamespace, 'sequence-decl') ||
              declaration.childElements.isNotEmpty) {
            _unsupported(declaration);
          }
        }
      } else {
        _unsupported(node);
      }
    }
    return result;
  }

  WmlParagraph _paragraph(XmlElement element, {required bool inNote}) {
    if (paragraphs.length >= limits.maxParagraphs) {
      throw const OdfZoteroLimitException('paragraphs');
    }
    _attributes(element, {
      odfTextNamespace: {'style-name', 'outline-level'},
      _xml: {'id'},
    });
    final styleName = _attr(element, 'style-name', odfTextNamespace);
    final properties = styles.paragraphProperties(styleName);
    if (element.localName == 'h') {
      final level = int.tryParse(
        _attr(element, 'outline-level', odfTextNamespace) ?? '1',
      );
      if (level == null || level < 1 || level > 9) _unsupported(element);
      properties.headingLevel = level;
    }
    final runProperties = styles.paragraphRunProperties(styleName);
    properties.importedParagraphMark = runProperties.copy();
    final paragraph = WmlParagraph(properties: properties);
    paragraphs[paths[element]!] = paragraph;
    final buffer = _RichText(paragraph, textBudget);
    _inlines(element, buffer, runProperties, null, inNote: inNote);
    buffer.finish();
    return paragraph;
  }

  void _inlines(
    XmlElement parent,
    _RichText buffer,
    WmlRunProps properties,
    WmlHyperlink? hyperlink, {
    required bool inNote,
  }) {
    for (final node in parent.children) {
      if (node is XmlText || node is XmlCdata) {
        buffer.literal(
          node is XmlText ? node.text : (node as XmlCdata).text,
          properties,
          hyperlink,
        );
        continue;
      }
      if (node is! XmlElement) continue;
      if (node.namespaceUri != odfTextNamespace) _unsupported(node);
      switch (node.localName) {
        case 'span':
          _attributes(node, {
            odfTextNamespace: {'style-name'},
          });
          final resolved = styles.runProperties(
            _attr(node, 'style-name', odfTextNamespace),
            inherited: properties,
          );
          _inlines(node, buffer, resolved, hyperlink, inNote: inNote);
        case 'a':
          if (hyperlink != null) _unsupported(node);
          _attributes(node, {
            _xlink: {'href', 'type'},
            odfTextNamespace: {'style-name', 'visited-style-name'},
          });
          final target = _attr(node, 'href', _xlink);
          final type = _attr(node, 'type', _xlink);
          if (target == null ||
              target.isEmpty ||
              (type != null && type != 'simple')) {
            _unsupported(node);
          }
          final link = target.startsWith('#')
              ? WmlHyperlink(anchor: target.substring(1))
              : WmlHyperlink(url: target);
          final resolved = styles.runProperties(
            _attr(node, 'style-name', odfTextNamespace),
            inherited: properties,
          );
          _inlines(node, buffer, resolved, link, inNote: inNote);
        case 's':
          _attributes(node, {
            odfTextNamespace: {'c'},
          });
          _empty(node);
          final count = int.tryParse(_attr(node, 'c', odfTextNamespace) ?? '1');
          if (count == null || count < 0 || count > textBudget.remaining) {
            throw const OdfZoteroLimitException('decoded text');
          }
          buffer.spaces(count, properties, hyperlink);
        case 'tab':
        case 'line-break':
          _attributes(node, {});
          _empty(node);
          buffer.explicit(
            node.localName == 'tab' ? '\t' : '\n',
            properties,
            hyperlink,
          );
        case 'soft-page-break':
          _attributes(node, {});
          _empty(node);
        case 'reference-mark-start':
        case 'reference-mark-end':
          _attributes(node, {
            odfTextNamespace: {'name'},
          });
          _empty(node);
          if (!_nativeMarks.contains(_attr(node, 'name', odfTextNamespace))) {
            _unsupported(node);
          }
        case 'note':
          if (inNote || hyperlink != null) _unsupported(node);
          buffer.inline(_note(node, properties));
        default:
          _unsupported(node);
      }
    }
  }

  WmlRun _note(XmlElement element, WmlRunProps properties) {
    _attributes(element, {
      odfTextNamespace: {'id', 'note-class'},
    });
    final sourceId = _attr(element, 'id', odfTextNamespace);
    if (sourceId != null && !_noteIds.add(sourceId)) {
      throw const FormatException('Duplicate ODT note identity.');
    }
    final kind = _attr(element, 'note-class', odfTextNamespace) ?? 'footnote';
    if (kind != 'footnote' && kind != 'endnote') _unsupported(element);
    final children = element.childElements.toList();
    if (children.length != 2 ||
        !_is(children[0], odfTextNamespace, 'note-citation') ||
        !_is(children[1], odfTextNamespace, 'note-body')) {
      _unsupported(element);
    }
    _attributes(children[0], {});
    _attributes(children[1], {});
    if (children[0].childElements.isNotEmpty) _unsupported(children[0]);
    final notes = kind == 'endnote' ? document.endnotes : document.footnotes;
    if (notes.length >= 10000) throw const OdfZoteroLimitException('notes');
    final id = notes.length + 1;
    final label = children[0].text.trim();
    if (label.isNotEmpty && label != '$id') {
      throw UnsupportedError('Custom ODT note numbering is not supported.');
    }
    final blocks = _blocks(children[1], inNote: true);
    if (blocks.isEmpty || blocks.first is! WmlParagraph) {
      _unsupported(children[1]);
    }
    final first = blocks.first as WmlParagraph;
    first.inlines.insert(
      0,
      WmlNoteMarker(
        endnote: kind == 'endnote',
        properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
      ),
    );
    notes.add(
      WmlNote(
        id: id,
        endnote: kind == 'endnote',
        addReference: false,
        addReferenceSpace: false,
        blocks: blocks,
      ),
    );
    return WmlRun(
      properties: properties.copy()..vertAlign = WmlVertAlign.superscript,
      noteRefId: id,
      noteRefEndnote: kind == 'endnote',
    );
  }

  WmlTable _table(
    XmlElement element, {
    required bool inNote,
    required int depth,
  }) {
    if (depth > 8 || ++_tableCount > 64) {
      throw const OdfZoteroLimitException('tables');
    }
    _attributes(element, {
      odfTableNamespace: {'name', 'style-name'},
    });
    final table = WmlTable(
      properties: WmlTableProps(borders: false, cellMargin: 0),
    );
    final tableStyle = _attr(element, 'style-name', odfTableNamespace);
    for (final style in styles.styleChain('table', tableStyle)) {
      for (final props in style.childElements) {
        if (!_is(props, _style, 'table-properties')) _unsupported(props);
        _attributes(props, {
          odfTableNamespace: {'align'},
          _fo: {'margin-left', 'margin-right'},
          _style: {'width'},
        });
        final align = _attr(props, 'align', odfTableNamespace);
        table.properties.alignment = switch (align) {
          null || 'left' || 'margins' => WmlJustification.left,
          'center' => WmlJustification.center,
          'right' => WmlJustification.right,
          _ => throw UnsupportedError('Unsupported ODT table alignment.'),
        };
        for (final name in ['margin-left', 'margin-right']) {
          final margin = _attr(props, name, _fo);
          if (margin != null && _length(margin) != 0) _unsupported(props);
        }
      }
    }
    var columnsSeen = false;
    var rowsSeen = false;
    for (final child in element.childElements) {
      if (_is(child, odfTableNamespace, 'table-column') && !rowsSeen) {
        columnsSeen = true;
        _attributes(child, {
          odfTableNamespace: {'style-name', 'number-columns-repeated'},
        });
        _empty(child);
        final count = int.tryParse(
          _attr(child, 'number-columns-repeated', odfTableNamespace) ?? '1',
        );
        if (count == null || count < 1 || table.grid.length + count > 32) {
          throw const OdfZoteroLimitException('table columns');
        }
        var width = 120.0;
        for (final style in styles.styleChain(
          'table-column',
          _attr(child, 'style-name', odfTableNamespace),
        )) {
          for (final props in style.childElements) {
            if (!_is(props, _style, 'table-column-properties')) {
              _unsupported(props);
            }
            _attributes(props, {
              _style: {'column-width'},
            });
            final value = _attr(props, 'column-width', _style);
            if (value != null) width = _length(value);
          }
        }
        if (width <= 0 || width > 4000) _unsupported(child);
        table.grid.addAll(List<double>.filled(count, width));
      } else if (_is(child, odfTableNamespace, 'table-row')) {
        rowsSeen = true;
        if (table.rows.length >= 256) {
          throw const OdfZoteroLimitException('table rows');
        }
        _attributes(child, {
          odfTableNamespace: {'style-name'},
        });
        final row = WmlTableRow();
        for (final style in styles.styleChain(
          'table-row',
          _attr(child, 'style-name', odfTableNamespace),
        )) {
          for (final props in style.childElements) {
            if (!_is(props, _style, 'table-row-properties')) {
              _unsupported(props);
            }
            _attributes(props, {
              _style: {'min-row-height'},
              _fo: {'keep-together'},
            });
            final height = _attr(props, 'min-row-height', _style);
            if (height != null) row.height = _length(height);
            final keep = _attr(props, 'keep-together', _fo);
            if (keep != null && keep != 'auto' && keep != 'always') {
              _unsupported(props);
            }
            row.cantSplit = keep == 'always';
          }
        }
        for (final sourceCell in child.childElements) {
          if (!_is(sourceCell, odfTableNamespace, 'table-cell')) {
            _unsupported(sourceCell);
          }
          if (++_cellCount > 4096 || row.cells.length >= 32) {
            throw const OdfZoteroLimitException('table cells');
          }
          _attributes(sourceCell, {
            odfTableNamespace: {'style-name'},
            odfOfficeNamespace: {'value-type'},
          });
          final valueType = _attr(sourceCell, 'value-type', odfOfficeNamespace);
          if (valueType != null && valueType != 'string') {
            _unsupported(sourceCell);
          }
          final cell = WmlTableCell(
            blocks: _blocks(sourceCell, inNote: inNote, tableDepth: depth),
          );
          for (final style in styles.styleChain(
            'table-cell',
            _attr(sourceCell, 'style-name', odfTableNamespace),
          )) {
            for (final props in style.childElements) {
              if (!_is(props, _style, 'table-cell-properties')) {
                _unsupported(props);
              }
              _attributes(props, {
                _fo: {'background-color'},
              });
              final fill = _attr(props, 'background-color', _fo);
              if (fill != null && fill != 'transparent') {
                if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(fill)) {
                  _unsupported(props);
                }
                cell.fillColor = fill.substring(1).toUpperCase();
              }
            }
          }
          if (cell.blocks.isEmpty || cell.blocks.last is! WmlParagraph) {
            if (paragraphs.length + _cellCount > limits.maxParagraphs) {
              throw const OdfZoteroLimitException('native paragraphs');
            }
            cell.blocks.add(WmlParagraph());
          }
          row.cells.add(cell);
        }
        if (row.cells.isEmpty) _unsupported(child);
        if (!columnsSeen && table.rows.isEmpty) {
          table.grid.addAll(List<double>.filled(row.cells.length, 120));
        }
        if (row.cells.length != table.grid.length) {
          _unsupported(child);
        }
        for (var i = 0; i < row.cells.length; i++) {
          row.cells[i].width = table.grid[i];
        }
        table.rows.add(row);
      } else {
        _unsupported(child);
      }
    }
    if (table.rows.isEmpty ||
        table.grid.fold<double>(0, (sum, width) => sum + width) > 4000) {
      _unsupported(element);
    }
    return table;
  }

  List<WmlBlock> _list(
    XmlElement element, {
    required bool inNote,
    required int tableDepth,
    required int depth,
    String? inheritedStyle,
  }) {
    if (depth >= 9 || ++_listCount > 1000) {
      throw const OdfZoteroLimitException('lists');
    }
    _attributes(element, {
      odfTextNamespace: {'style-name'},
      _xml: {'id'},
    });
    final name =
        _attr(element, 'style-name', odfTextNamespace) ?? inheritedStyle;
    final definition = styles.listStyle(name);
    if (definition == null) _unsupported(element);
    final levels = definition.childElements
        .where(
          (node) =>
              node.namespaceUri == odfTextNamespace &&
              _attr(node, 'level', odfTextNamespace) == '${depth + 1}',
        )
        .toList();
    if (levels.length != 1) _unsupported(definition);
    final level = levels.single;
    final numbered = level.localName == 'list-level-style-number';
    if (!numbered && level.localName != 'list-level-style-bullet') {
      _unsupported(level);
    }
    _attributes(level, {
      odfTextNamespace: {'level', 'start-value', 'bullet-char'},
      _style: {'num-format', 'num-prefix', 'num-suffix'},
    });
    final start = int.tryParse(
      _attr(level, 'start-value', odfTextNamespace) ?? '1',
    );
    if (start == null || start < 1 || start > 1000000) _unsupported(level);
    if (numbered &&
        (_attr(level, 'num-format', _style) != '1' ||
            (_attr(level, 'num-prefix', _style) ?? '').isNotEmpty ||
            (_attr(level, 'num-suffix', _style) ?? '.') != '.')) {
      _unsupported(level);
    }
    final bullet = switch (depth) {
      0 => '•',
      1 => '◦',
      _ => '▪',
    };
    if (!numbered && _attr(level, 'bullet-char', odfTextNamespace) != bullet) {
      _unsupported(level);
    }
    var left = 18.0 * (depth + 1);
    var hanging = 9.0;
    for (final props in level.childElements) {
      if (!_is(props, _style, 'list-level-properties')) _unsupported(props);
      _attributes(props, {
        odfTextNamespace: {'space-before', 'min-label-width'},
      });
      final before = _attr(props, 'space-before', odfTextNamespace);
      final width = _attr(props, 'min-label-width', odfTextNamespace);
      if (before != null) left = _length(before);
      if (width != null) hanging = _length(width);
      if (before != null) left += hanging;
    }
    final id = WordLists.numberingId(
      document,
      numbered: numbered,
      independent: true,
      outline: false,
    );
    final result = <WmlBlock>[];
    var index = 0;
    for (final item in element.childElements) {
      if (!_is(item, odfTextNamespace, 'list-item')) _unsupported(item);
      _attributes(item, {
        odfTextNamespace: {'start-value'},
      });
      final restartRaw = _attr(item, 'start-value', odfTextNamespace);
      final restart = restartRaw == null ? null : int.tryParse(restartRaw);
      if (restartRaw != null &&
          (restart == null || restart < 1 || restart > 1000000)) {
        _unsupported(item);
      }
      final blocks = _blocks(
        item,
        inNote: inNote,
        tableDepth: tableDepth,
        listDepth: depth + 1,
        inheritedListStyle: name,
      );
      if (blocks.isEmpty || blocks.first is! WmlParagraph) _unsupported(item);
      var first = true;
      for (final block in blocks) {
        if (block is WmlParagraph && block.properties.numId == null) {
          block.properties
            ..numId = first ? id : null
            ..numberingSuppressed = !first
            ..ilvl = depth
            ..listLabel = first
                ? (numbered ? '${restart ?? start + index}. ' : '$bullet ')
                : null
            ..listRestart = first && numbered
                ? (restart ?? (index == 0 ? start : null))
                : null
            ..indent = WmlIndent(left: left, hanging: first ? hanging : 0)
            ..explicitIndent = true;
          first = false;
        }
      }
      result.addAll(blocks);
      index = restart == null ? index + 1 : restart - start + 1;
    }
    if (result.isEmpty) _unsupported(element);
    return result;
  }

  void _attachFields() {
    final events = <String, List<_FieldEvent>>{};
    var identity = 0;
    for (final field in inventory.fields) {
      if (field.ranges.isEmpty) {
        throw const FormatException('Empty native Zotero field ownership.');
      }
      for (final range in field.ranges) {
        final paragraph = paragraphs[range.location.paragraphPath];
        if (range.location.part != 'content.xml' ||
            paragraph == null ||
            range.start < 0 ||
            range.end > paragraph.text.length ||
            paragraph.text.substring(range.start, range.end) != range.text) {
          throw const FormatException(
            'Native ODT field offsets do not match rich content.',
          );
        }
        var offset = 0;
        for (final inline in paragraph.inlines.whereType<WmlRun>()) {
          if (inline.noteRefId != null &&
              offset >= range.start &&
              offset < range.end) {
            throw const FormatException(
              'A native Zotero field contains a note anchor.',
            );
          }
          offset += inline.text.length;
        }
      }
      final first = field.ranges.first;
      final last = field.ranges.last;
      final instruction = ' ADDIN ZOTERO_${field.logicalCode} ';
      events
          .putIfAbsent(first.location.paragraphPath!, () => [])
          .add(_FieldEvent(first.start, true, instruction, identity));
      events
          .putIfAbsent(last.location.paragraphPath!, () => [])
          .add(_FieldEvent(last.end, false, instruction, identity));
      identity++;
    }
    for (final entry in events.entries) {
      final paragraph = paragraphs[entry.key]!;
      final sorted = entry.value
        ..sort((a, b) {
          final order = a.offset.compareTo(b.offset);
          if (order != 0) return order;
          if (a.identity == b.identity) return a.start ? -1 : 1;
          return a.start == b.start
              ? a.identity.compareTo(b.identity)
              : (a.start ? 1 : -1);
        });
      final result = <WmlInline>[];
      var index = 0;
      var offset = 0;
      void emit(int at) {
        while (index < sorted.length && sorted[index].offset == at) {
          final event = sorted[index++];
          if (event.start) {
            result.addAll([
              WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
              WmlFieldBoundary(
                kind: WmlFieldBoundaryKind.instruction,
                text: event.instruction,
              ),
              WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
            ]);
          } else {
            result.add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.end));
          }
        }
      }

      for (final inline in paragraph.inlines) {
        // The automatic note number belongs to the note story, before any
        // citation beginning at its first visible text position.
        if (inline is WmlNoteMarker) {
          result.add(inline);
          continue;
        }
        emit(offset);
        if (inline is! WmlRun || inline.text.isEmpty) {
          result.add(inline);
          continue;
        }
        var start = 0;
        while (index < sorted.length &&
            sorted[index].offset < offset + inline.text.length) {
          final cut = sorted[index].offset - offset;
          if (cut < start) {
            throw const FormatException('Reversed native field offset.');
          }
          if (cut > start) result.add(_slice(inline, start, cut));
          emit(offset + cut);
          start = cut;
        }
        if (start < inline.text.length) {
          result.add(_slice(inline, start, inline.text.length));
        }
        offset += inline.text.length;
      }
      emit(offset);
      if (index != sorted.length) {
        throw const FormatException('Unresolved native field endpoint.');
      }
      paragraph.inlines = result;
    }
  }

  void readMetadata(XmlElement? root) {
    if (root == null) return;
    const dc = 'http://purl.org/dc/elements/1.1/';
    final owner = root
        .childrenNamed('meta', namespaceUri: odfOfficeNamespace)
        .single;
    final seen = <String>{};
    for (final child in owner.childElements) {
      if (child.namespaceUri != dc &&
          child.namespaceUri != odfMetadataNamespace) {
        continue;
      }
      final key = '${child.namespaceUri}:${child.localName}';
      if (child.localName == 'user-defined') continue;
      if (!seen.add(key) || child.childElements.isNotEmpty) continue;
      final value = child.text;
      if (child.namespaceUri == dc) {
        switch (child.localName) {
          case 'title':
            document.properties.title = value;
          case 'subject':
            document.properties.subject = value;
          case 'description':
            document.properties.description = value;
          case 'creator':
            document.properties.lastModifiedBy = value;
          case 'date':
            document.properties.modifiedIso = value;
        }
      } else {
        switch (child.localName) {
          case 'initial-creator':
            document.properties.creator = value;
          case 'creation-date':
            document.properties.createdIso = value;
          case 'keyword':
            document.properties.keywords = value;
        }
      }
    }
  }
}

final class _RichText {
  _RichText(this.paragraph, this.budget);
  final WmlParagraph paragraph;
  final OdfTextBudget budget;
  bool _started = false;
  WmlRunProps? _pending;
  WmlHyperlink? _pendingLink;

  void literal(String value, WmlRunProps props, WmlHyperlink? link) {
    var index = 0;
    while (index < value.length) {
      if (_whitespace(value.codeUnitAt(index))) {
        _pending ??= props;
        _pendingLink = link;
        index++;
      } else {
        final start = index;
        while (index < value.length && !_whitespace(value.codeUnitAt(index))) {
          index++;
        }
        _flush();
        _append(value.substring(start, index), props, link);
        _started = true;
      }
    }
  }

  void explicit(String value, WmlRunProps props, WmlHyperlink? link) {
    _flush();
    _append(value, props, link);
    _started = true;
  }

  void spaces(int count, WmlRunProps props, WmlHyperlink? link) {
    _flush();
    budget.consume(count);
    if (count > 0) {
      paragraph.inlines.add(
        WmlRun(text: ' ' * count, properties: props.copy(), hyperlink: link),
      );
    }
    _started = true;
  }

  void inline(WmlInline value) => paragraph.inlines.add(value);
  void _flush() {
    if (_pending != null && _started) _append(' ', _pending!, _pendingLink);
    _pending = null;
    _pendingLink = null;
  }

  void _append(String value, WmlRunProps props, WmlHyperlink? link) {
    budget.consume(utf8.encode(value).length);
    paragraph.inlines.add(
      WmlRun(text: value, properties: props.copy(), hyperlink: link),
    );
  }

  void finish() {
    _pending = null;
    _pendingLink = null;
  }
}

final class _FieldEvent {
  const _FieldEvent(this.offset, this.start, this.instruction, this.identity);
  final int offset;
  final bool start;
  final String instruction;
  final int identity;
}

WmlRun _slice(WmlRun run, int start, int end) => WmlRun(
  text: run.text.substring(start, end),
  properties: run.properties.copy(),
  hyperlink: run.hyperlink,
);

bool _is(XmlElement node, String namespace, String local) =>
    node.namespaceUri == namespace && node.localName == local;
String? _attr(XmlElement node, String name, String namespace) =>
    node.getAttribute(name, namespaceUri: namespace);
bool _whitespace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

Never _unsupported(XmlElement element) => throw UnsupportedError(
  'Native ODT import does not yet support ${element.qualifiedName} '
  'with these properties. The document was not opened.',
);

void _empty(XmlElement element) {
  if (element.childElements.isNotEmpty || element.text.trim().isNotEmpty) {
    _unsupported(element);
  }
}

void _attributes(XmlElement element, Map<String, Set<String>> allowed) {
  for (final attribute in element.attributes) {
    if (attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') {
      continue;
    }
    if (allowed[attribute.namespaceUri]?.contains(attribute.localName) !=
        true) {
      _unsupported(element);
    }
  }
}

double _length(String value) {
  final match = RegExp(
    r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))(pt|in|cm|mm|pc)$',
  ).firstMatch(value.trim());
  if (match == null) throw UnsupportedError('Unsupported ODT length: $value.');
  final number = double.parse(match.group(1)!);
  final factor = switch (match.group(2)) {
    'in' => 72.0,
    'cm' => 72 / 2.54,
    'mm' => 72 / 25.4,
    'pc' => 12.0,
    _ => 1.0,
  };
  final points = number * factor;
  if (!points.isFinite || points < 0 || points > 4000) {
    throw const FormatException('ODT length is out of bounds.');
  }
  return points;
}
