import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

XmlElement _capture(String source, String localName) {
  final reader = XmlPullReader(source);
  while (reader.next()) {
    if (reader.eventType == XmlEventType.startElement &&
        reader.localName == localName) {
      return XmlDocument.readElement(reader);
    }
  }
  throw StateError('Missing capture target $localName');
}

XmlElement _roundTrip(XmlElement element) => XmlDocument.parse(
  XmlDocument(root: element).toXmlString(declaration: false),
).root!;

String? _declaration(XmlElement element, String prefix) {
  final name = prefix.isEmpty ? 'xmlns' : 'xmlns:$prefix';
  for (final attribute in element.attributes) {
    if (attribute.qualifiedName == name) return attribute.value;
  }
  return null;
}

void main() {
  test(
    'namespace snapshots are immutable and independent of reader movement',
    () {
      final reader = XmlPullReader(
        '<root xmlns="urn:default" xmlns:p="urn:outer">'
        '<plain xmlns="" xmlns:p="urn:inner"><p:item/></plain>'
        '<p:after/></root>',
      )..next();
      final outer = reader.inScopeNamespaces;
      expect(outer, {'': 'urn:default', 'p': 'urn:outer'});
      expect(() => outer['p'] = 'changed', throwsUnsupportedError);
      reader.next();
      final inner = reader.inScopeNamespaces;
      expect(inner, {'': '', 'p': 'urn:inner'});
      while (reader.next()) {
        if (reader.eventType == XmlEventType.startElement &&
            reader.localName == 'after') {
          expect(reader.inScopeNamespaces, outer);
          break;
        }
      }
      expect(inner, {'': '', 'p': 'urn:inner'});
      expect(outer, {'': 'urn:default', 'p': 'urn:outer'});
    },
  );

  for (final declaredHere in [false, true]) {
    test(
      'captured w:w survives ${declaredHere ? 'local' : 'inherited'} xmlns:w',
      () {
        final reader = XmlPullReader(
          '<w:root xmlns:w="${OfficeNamespaces.w}">'
          '<w:tcW ${declaredHere ? 'xmlns:w="${OfficeNamespaces.w}" ' : ''}'
          'w:w="1465" w:type="dxa"/></w:root>',
        );
        while (reader.next() && reader.localName != 'tcW') {}
        final captured = XmlDocument.readElement(reader);
        expect(
          captured.getAttribute('w', namespaceUri: OfficeNamespaces.w),
          '1465',
        );
        expect(
          captured.attributes.where((a) => a.qualifiedName == 'xmlns:w'),
          hasLength(1),
        );
        final serialized = XmlDocument(root: captured).toXmlString();
        final restored = XmlDocument.parse(serialized).root!;
        expect(restored.namespaceUri, OfficeNamespaces.w);
        expect(
          restored.getAttribute('w', namespaceUri: OfficeNamespaces.w),
          '1465',
        );
        expect(
          restored.getAttribute('type', namespaceUri: OfficeNamespaces.w),
          'dxa',
        );
      },
    );
  }

  test(
    'namespace declaration does not replace an unqualified same-name attribute',
    () {
      final reader = XmlPullReader('<a:shape xmlns:a="urn:shape" a="payload"/>')
        ..next();
      final captured = XmlDocument.readElement(reader);
      expect(
        captured.attributes.singleWhere((a) => a.qualifiedName == 'a').value,
        'payload',
      );
      expect(
        captured.attributes.where((a) => a.qualifiedName == 'xmlns:a'),
        hasLength(1),
      );
      final restored = XmlDocument.parse(
        XmlDocument(root: captured).toXmlString(),
      ).root!;
      expect(
        restored.attributes.singleWhere((a) => a.qualifiedName == 'a').value,
        'payload',
      );
    },
  );

  test('a descendant shadow cannot change a captured Word section binding', () {
    final captured = _capture(
      '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>'
          '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
          '<c:cols xmlns:c="${OfficeNamespaces.w}" xmlns:w="urn:extension" '
          'c:num="2" c:space="240" c:sep="0" '
          'w:num="foreign-count" w:space="foreign-gap" w:sep="foreign-separator">'
          '<w:columnMetadata w:token="preserve"/>'
          '</c:cols></w:sectPr></w:body></w:document>',
      'sectPr',
    );
    var section = captured;
    for (var cycle = 0; cycle < 3; cycle++) {
      section = _roundTrip(section);
      expect(section.namespaceUri, OfficeNamespaces.w);
      expect(_declaration(section, 'w'), OfficeNamespaces.w);
      final page = section.firstChild(
        'pgSz',
        namespaceUri: OfficeNamespaces.w,
      )!;
      expect(page.getAttribute('w', namespaceUri: OfficeNamespaces.w), '12240');
      final columns = section.firstChild(
        'cols',
        namespaceUri: OfficeNamespaces.w,
      )!;
      expect(_declaration(columns, 'w'), 'urn:extension');
      expect(
        columns.getAttribute('num', namespaceUri: OfficeNamespaces.w),
        '2',
      );
      expect(
        columns.getAttribute('num', namespaceUri: 'urn:extension'),
        'foreign-count',
      );
      expect(
        columns.getAttribute('space', namespaceUri: 'urn:extension'),
        'foreign-gap',
      );
      expect(
        columns.getAttribute('sep', namespaceUri: 'urn:extension'),
        'foreign-separator',
      );
      expect(
        columns
            .firstChild('columnMetadata', namespaceUri: 'urn:extension')!
            .getAttribute('token', namespaceUri: 'urn:extension'),
        'preserve',
      );
    }
  });

  test(
    'nested rebinding retains each element, attribute, and sibling scope',
    () {
      var fragment = _capture(
        '<root xmlns:p="urn:outer"><p:fragment p:id="outer">'
            '<p:branch xmlns:p="urn:inner" p:id="inner">'
            '<p:leaf xmlns:p="urn:deep" p:id="deep"/>'
            '<p:afterLeaf p:id="inner-again"/></p:branch>'
            '<p:afterBranch p:id="outer-again"/>'
            '</p:fragment></root>',
        'fragment',
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        fragment = _roundTrip(fragment);
        expect(fragment.namespaceUri, 'urn:outer');
        expect(fragment.getAttribute('id', namespaceUri: 'urn:outer'), 'outer');
        final branch = fragment.firstChild(
          'branch',
          namespaceUri: 'urn:inner',
        )!;
        expect(branch.getAttribute('id', namespaceUri: 'urn:inner'), 'inner');
        expect(
          branch
              .firstChild('leaf', namespaceUri: 'urn:deep')!
              .getAttribute('id', namespaceUri: 'urn:deep'),
          'deep',
        );
        expect(
          branch
              .firstChild('afterLeaf', namespaceUri: 'urn:inner')!
              .getAttribute('id', namespaceUri: 'urn:inner'),
          'inner-again',
        );
        expect(
          fragment
              .firstChild('afterBranch', namespaceUri: 'urn:outer')!
              .getAttribute('id', namespaceUri: 'urn:outer'),
          'outer-again',
        );
      }
    },
  );

  test('capture inherits prefixes used only by descendant names', () {
    final fragment = _roundTrip(
      _capture(
        '<root xmlns:r="urn:root" xmlns:p="urn:payload" xmlns:a="urn:attribute">'
            '<r:fragment><p:item a:id="17"/><p:item a:id="18"/></r:fragment>'
            '</root>',
        'fragment',
      ),
    );
    expect(fragment.namespaceUri, 'urn:root');
    expect(
      fragment.childrenNamed('item', namespaceUri: 'urn:payload'),
      hasLength(2),
    );
    expect(
      fragment.childElements.map(
        (item) => item.getAttribute('id', namespaceUri: 'urn:attribute'),
      ),
      ['17', '18'],
    );
  });

  test(
    'default namespaces, local unbinding, and unqualified attributes survive',
    () {
      var fragment = _capture(
        '<root xmlns="urn:outer"><fragment id="root">'
            '<item id="outer"/><plain xmlns="" id="plain"><child id="empty"/>'
            '<nested xmlns="urn:inner"><item id="inner"/></nested>'
            '<afterNested id="empty-again"/></plain>'
            '<afterPlain id="outer-again"/></fragment></root>',
        'fragment',
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        fragment = _roundTrip(fragment);
        expect(fragment.namespaceUri, 'urn:outer');
        expect(fragment.getAttribute('id', namespaceUri: ''), 'root');
        expect(
          fragment
              .firstChild('item', namespaceUri: 'urn:outer')!
              .getAttribute('id', namespaceUri: ''),
          'outer',
        );
        final plain = fragment.firstChild('plain', namespaceUri: '')!;
        expect(_declaration(plain, ''), '');
        expect(
          plain
              .firstChild('child', namespaceUri: '')!
              .getAttribute('id', namespaceUri: ''),
          'empty',
        );
        expect(
          plain
              .firstChild('nested', namespaceUri: 'urn:inner')!
              .firstChild('item', namespaceUri: 'urn:inner')!
              .getAttribute('id', namespaceUri: ''),
          'inner',
        );
        expect(
          plain
              .firstChild('afterNested', namespaceUri: '')!
              .getAttribute('id', namespaceUri: ''),
          'empty-again',
        );
        expect(
          fragment
              .firstChild('afterPlain', namespaceUri: 'urn:outer')!
              .getAttribute('id', namespaceUri: ''),
          'outer-again',
        );
      }
    },
  );

  test('captured default unbinding remains explicit when embedded elsewhere', () {
    final fragment = _capture(
      '<root xmlns="urn:outer"><plain xmlns=""><fragment><child/></fragment></plain></root>',
      'fragment',
    );
    final serialized = XmlDocument(
      root: fragment,
    ).toXmlString(declaration: false);
    final embedded = XmlDocument.parse(
      '<host xmlns="urn:host">$serialized</host>',
    ).root!;
    final restored = embedded.firstChild('fragment', namespaceUri: '')!;
    expect(restored.firstChild('child', namespaceUri: ''), isNotNull);
  });

  test(
    'QName-only and compatibility prefixes are retained in detached fragments',
    () {
      final fragment = _capture(
        '<root xmlns:w="${OfficeNamespaces.w}" xmlns:mc="${OfficeNamespaces.mc}" '
            'xmlns:xsi="${OfficeNamespaces.xsi}" xmlns:ext="urn:extension" '
            'xmlns:t="urn:type"><w:fragment mc:Ignorable="ext" xsi:type="t:Container">'
            '<mc:AlternateContent><mc:Choice Requires="ext"><w:p/></mc:Choice>'
            '<mc:Fallback><w:p/></mc:Fallback></mc:AlternateContent>'
            '<w:p xmlns:ext="urn:local-extension" mc:Ignorable="ext"/>'
            '</w:fragment></root>',
        'fragment',
      );
      final reader = XmlPullReader(XmlDocument(root: fragment).toXmlString());
      var choices = 0;
      var localPrefixes = 0;
      while (reader.next()) {
        if (reader.eventType != XmlEventType.startElement) continue;
        if (reader.localName == 'fragment') {
          expect(reader.lookupNamespace('ext'), 'urn:extension');
          expect(reader.lookupNamespace('t'), 'urn:type');
          expect(
            reader.getAttribute('type', namespaceUri: OfficeNamespaces.xsi),
            't:Container',
          );
          expect(
            reader.getAttribute('Ignorable', namespaceUri: OfficeNamespaces.mc),
            'ext',
          );
        }
        if (reader.localName == 'Choice') {
          choices++;
          expect(
            reader.lookupNamespace(reader.getAttribute('Requires')!),
            'urn:extension',
          );
        }
        if (reader.localName == 'p' &&
            reader.getAttribute(
                  'Ignorable',
                  namespaceUri: OfficeNamespaces.mc,
                ) !=
                null) {
          localPrefixes++;
          expect(reader.lookupNamespace('ext'), 'urn:local-extension');
        }
      }
      expect(choices, 1);
      expect(localPrefixes, 1);
    },
  );
}
