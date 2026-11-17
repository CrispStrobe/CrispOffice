import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _item(String text, {int level = 0, String? label, int id = 1}) =>
    WmlParagraph(
      properties: WmlParagraphProps(numId: id, ilvl: level, listLabel: label),
      inlines: [WmlRun(text: text)],
    );

XmlElement _body(List<WmlBlock> blocks) {
  final package = OpcPackage.openBytes(
    OdtDocumentWriter.writeBytes(
      WmlDocument(sections: [WmlSection(blocks: blocks)]),
    ),
  );
  return XmlDocument.parse(
    package.getPart('/content.xml')!.readText(),
  ).root!.firstChild('body')!.firstChild('text')!;
}

String _text(XmlNode node) => switch (node) {
  XmlText() => node.text,
  XmlElement() => node.children.map(_text).join(),
  _ => '',
};

List<(String, int)> _itemDepths(XmlElement body) {
  final result = <(String, int)>[];
  void visit(XmlElement element, int depth) {
    final next = depth + (element.localName == 'list' ? 1 : 0);
    if (element.localName == 'list-item') {
      final paragraph = element.firstChild('p') ?? element.firstChild('h');
      if (paragraph != null) result.add((_text(paragraph), depth));
    }
    for (final child in element.childElements) {
      visit(child, next);
    }
  }

  visit(body, 0);
  return result;
}

void main() {
  group('ODT authored list levels', () {
    for (final (levels, expected) in <(List<int>, List<int>)>[
      ([0, 3, 3, 0], [1, 2, 2, 1]),
      ([2, 2, 2], [1, 1, 1]),
      ([2, 5, 5, 3, 3, 0], [1, 2, 2, 2, 2, 1]),
      ([0, 1, 2, 3, 2, 1, 0], [1, 2, 3, 4, 3, 2, 1]),
      ([8, 8, 0, 8, 8], [1, 1, 1, 2, 2]),
      ([-9, 999, 999, -1], [1, 2, 2, 1]),
    ]) {
      test('normalizes $levels without inventing ancestors', () {
        final items = <WmlParagraph>[
          for (var i = 0; i < levels.length; i++)
            _item('Item $i', level: levels[i]),
        ];
        final body = _body(items);
        expect(_itemDepths(body), [
          for (var i = 0; i < expected.length; i++) ('Item $i', expected[i]),
        ]);
        expect(items.map((item) => item.properties.ilvl), levels);
        expect(items.map((item) => item.text), [
          for (var i = 0; i < levels.length; i++) 'Item $i',
        ]);
      });
    }

    test('mixed bullets and numbers use their own list styles', () {
      final body = _body([
        _item('Numbered parent', label: '1. '),
        _item('Bullet child', level: 2, label: '• '),
        _item('Number child', level: 2, label: '1. '),
        _item('Bullet parent', label: '• '),
      ]);
      final roots = body.childrenNamed('list').toList();
      expect(roots, hasLength(2));
      expect(roots.map((list) => list.getAttribute('style-name')), [
        'L2',
        'L1',
      ]);
      final parent = roots.first.firstChild('list-item')!;
      final children = parent.childrenNamed('list').toList();
      expect(children.map((list) => list.getAttribute('style-name')), [
        'L1',
        'L2',
      ]);
      expect(_itemDepths(body), [
        ('Numbered parent', 1),
        ('Bullet child', 2),
        ('Number child', 2),
        ('Bullet parent', 1),
      ]);
    });

    test('adjacent mixed siblings stay at one output depth', () {
      final body = _body([
        _item('Bullet one', level: 3, label: '• '),
        _item('Number one', level: 3, label: '1. '),
        _item('Number two', level: 3, label: '2. '),
        _item('Bullet two', level: 3, label: '▪ '),
      ]);
      expect(body.childrenNamed('list'), hasLength(3));
      expect(_itemDepths(body), [
        ('Bullet one', 1),
        ('Number one', 1),
        ('Number two', 1),
        ('Bullet two', 1),
      ]);
    });

    test('a changed numbering identity starts a separate list', () {
      final body = _body([
        _item('Parent', id: 7),
        _item('Other', id: 8, level: 3),
        _item('Other sibling', id: 8, level: 3),
      ]);
      expect(body.childrenNamed('list'), hasLength(2));
      expect(_itemDepths(body), [
        ('Parent', 1),
        ('Other', 1),
        ('Other sibling', 1),
      ]);
    });

    test('suppressed numbering interrupts and stays ordinary text', () {
      final suppressed = _item('Ordinary', level: 2)
        ..properties.numberingSuppressed = true;
      final body = _body([
        _item('Before', level: 2),
        suppressed,
        _item('After', level: 2),
      ]);
      expect(body.childElements.map((node) => node.localName), [
        'list',
        'p',
        'list',
      ]);
      expect(_text(body.childrenNamed('p').single), 'Ordinary');
      expect(_itemDepths(body), [('Before', 1), ('After', 1)]);
    });

    test('paragraph and run formatting remains on a skipped-level child', () {
      final child = _item('Styled', level: 4)
        ..properties.rightToLeft = true
        ..properties.lineSpacingRule = WmlLineSpacingRule.exact
        ..properties.lineSpacing = 18;
      (child.inlines.single as WmlRun).properties.bold = true;
      final body = _body([_item('Parent'), child]);
      final paragraph = body
          .firstChild('list')!
          .firstChild('list-item')!
          .firstChild('list')!
          .firstChild('list-item')!
          .firstChild('p')!;
      expect(paragraph.getAttribute('style-name'), isNotEmpty);
      expect(
        paragraph.firstChild('span')!.getAttribute('style-name'),
        isNotEmpty,
      );
      expect(_text(paragraph), 'Styled');
      expect(child.properties.ilvl, 4);
      expect(child.properties.rightToLeft, isTrue);
      expect((child.inlines.single as WmlRun).properties.bold, isTrue);
    });

    test('deep malformed levels cannot create unbounded recursion', () {
      final items = <WmlParagraph>[
        for (var i = 0; i < 1000; i++) _item('Item $i', level: i),
      ];
      final depths = _itemDepths(_body(items));
      expect(depths, hasLength(items.length));
      expect(
        depths.map((entry) => entry.$2).reduce((a, b) => a > b ? a : b),
        9,
      );
      expect(depths.last, ('Item 999', 9));
    });
  });
}
