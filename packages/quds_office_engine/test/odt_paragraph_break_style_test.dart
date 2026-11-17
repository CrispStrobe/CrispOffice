import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

typedef _Style = ({String name, XmlElement style, XmlElement properties});

List<_Style> _styles(List<WmlSection> sections) {
  final content = XmlDocument.parse(
    OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(WmlDocument(sections: sections)),
    ).getPart('/content.xml')!.readText(),
  ).root!;
  final automatic = content.firstChild(
    'automatic-styles',
    namespaceUri: _officeNs,
  )!;
  final paragraphs = content
      .firstChild('body', namespaceUri: _officeNs)!
      .firstChild('text', namespaceUri: _officeNs)!
      .childrenNamed('p', namespaceUri: _textNs);
  return [
    for (final paragraph in paragraphs)
      _resolve(
        automatic,
        paragraph.getAttribute('style-name', namespaceUri: _textNs)!,
      ),
  ];
}

_Style _resolve(XmlElement automatic, String name) {
  final style = automatic
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (element) =>
            element.getAttribute('name', namespaceUri: _styleNs) == name,
      );
  return (
    name: name,
    style: style,
    properties: style.firstChild(
      'paragraph-properties',
      namespaceUri: _styleNs,
    )!,
  );
}

WmlParagraph _paragraph(WmlParagraphProps properties) => WmlParagraph(
  properties: properties,
  inlines: [WmlRun(text: 'Preserved paragraph')],
);

List<_Style> _paragraphStyles(List<WmlParagraphProps> properties) => _styles([
  WmlSection(blocks: [for (final props in properties) _paragraph(props)]),
]);

String? _property(_Style style, String name) =>
    style.properties.getAttribute(name, namespaceUri: _foNs);

void main() {
  for (final enabledFirst in [false, true]) {
    test(
      'column breaks stay paragraph-specific with enabledFirst=$enabledFirst',
      () {
        final flags = [enabledFirst, !enabledFirst, enabledFirst];
        final properties = [
          for (final flag in flags) WmlParagraphProps(columnBreakBefore: flag),
        ];
        final styles = _paragraphStyles(properties);
        expect(
          styles.map((style) => _property(style, 'break-before')),
          flags.map((enabled) => enabled ? 'column' : null),
        );
        expect(
          styles.map((style) => _property(style, 'keep-together')),
          everyElement(isNull),
        );
        expect(styles[0].name, styles[2].name);
        expect(styles[0].name, isNot(styles[1].name));
        expect(properties.map((props) => props.columnBreakBefore), flags);
      },
    );

    test(
      'keep-together stays paragraph-specific with enabledFirst=$enabledFirst',
      () {
        final flags = [enabledFirst, !enabledFirst, enabledFirst];
        final properties = [
          for (final flag in flags) WmlParagraphProps(keepTogether: flag),
        ];
        final styles = _paragraphStyles(properties);
        expect(
          styles.map((style) => _property(style, 'keep-together')),
          flags.map((enabled) => enabled ? 'always' : null),
        );
        expect(
          styles.map((style) => _property(style, 'break-before')),
          everyElement(isNull),
        );
        expect(styles[0].name, styles[2].name);
        expect(styles[0].name, isNot(styles[1].name));
        expect(properties.map((props) => props.keepTogether), flags);
      },
    );
  }

  test(
    'column breaks and keep-together remain independent in every combination',
    () {
      const states = [
        (false, false),
        (true, false),
        (false, true),
        (true, true),
      ];
      final properties = [
        for (final (column, keep) in states)
          WmlParagraphProps(columnBreakBefore: column, keepTogether: keep),
      ];
      final styles = _paragraphStyles(properties);
      expect(styles.map((style) => style.name).toSet(), hasLength(4));
      for (var index = 0; index < states.length; index++) {
        final (column, keep) = states[index];
        expect(
          _property(styles[index], 'break-before'),
          column ? 'column' : null,
        );
        expect(
          _property(styles[index], 'keep-together'),
          keep ? 'always' : null,
        );
      }
      expect(
        properties.map(
          (props) => (props.columnBreakBefore, props.keepTogether),
        ),
        states,
      );
    },
  );

  test('an explicit page break takes priority over a column break', () {
    final properties = [
      WmlParagraphProps(columnBreakBefore: true, keepTogether: true),
      WmlParagraphProps(
        pageBreakBefore: true,
        columnBreakBefore: true,
        keepTogether: true,
      ),
      WmlParagraphProps(pageBreakBefore: true, keepTogether: true),
      WmlParagraphProps(keepTogether: true),
    ];
    final styles = _paragraphStyles(properties);
    expect(styles.map((style) => _property(style, 'break-before')), [
      'column',
      'page',
      'page',
      null,
    ]);
    expect(
      styles.map((style) => _property(style, 'keep-together')),
      everyElement('always'),
    );
    expect(properties.map((props) => props.pageBreakBefore), [
      false,
      true,
      true,
      false,
    ]);
    expect(properties.map((props) => props.columnBreakBefore), [
      true,
      true,
      false,
      false,
    ]);
  });

  for (final kind in [
    WmlSectionBreakKind.nextPage,
    WmlSectionBreakKind.continuous,
  ]) {
    test('section $kind preserves keep-together and the effective break', () {
      final props = WmlParagraphProps(
        columnBreakBefore: true,
        keepTogether: true,
      );
      final styles = _styles([
        WmlSection(blocks: [_paragraph(WmlParagraphProps())]),
        WmlSection(breakKind: kind, blocks: [_paragraph(props)]),
      ]);
      expect(styles, hasLength(2));
      expect(_property(styles.first, 'keep-together'), isNull);
      expect(_property(styles.last, 'keep-together'), 'always');
      expect(
        _property(styles.last, 'break-before'),
        kind == WmlSectionBreakKind.nextPage ? 'page' : 'column',
      );
      expect(
        styles.last.style.getAttribute(
          'master-page-name',
          namespaceUri: _styleNs,
        ),
        kind == WmlSectionBreakKind.nextPage ? 'mp1' : null,
      );
      expect(props.columnBreakBefore, isTrue);
      expect(props.keepTogether, isTrue);
    });
  }
}
