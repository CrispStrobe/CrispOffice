import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

ZoteroCitation _citation([String id = 'mixed']) => ZoteroCitation(
  citationId: id,
  plainCitation: 'Book 12',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'type': 'book', 'title': 'Book'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
      locator: '12',
      label: 'page',
    ),
  ],
);

List<WmlInline> _packet({String? code, bool locked = false}) => [
  WmlFieldBoundary(
    kind: WmlFieldBoundaryKind.begin,
    sourceXml: locked
        ? '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
              'w:fldCharType="begin" w:fldLock="1"/>'
        : null,
  ),
  WmlFieldBoundary(
    kind: WmlFieldBoundaryKind.instruction,
    text: code ?? _citation().fieldInstruction,
  ),
  WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
  WmlRun(text: 'Book', properties: WmlRunProps(italic: true)),
  WmlRun(text: ' 12'),
  WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
];

WmlDocument _document() {
  final document = WmlDocument.empty();
  document.paragraphs.single.inlines
    ..clear()
    ..addAll([
      WmlRun(text: 'Before ', commentIds: [42]),
      ..._packet(),
      WmlRun(text: ' after', properties: WmlRunProps(bold: true)),
    ]);
  return document;
}

void _expectIntact(WmlDocument document) {
  final field = WordZotero.fields(document).single;
  expect(field.cachedText, 'Book 12');
  expect(field.citation!.items.single.locator, '12');
  expect(field.canEdit, isTrue);
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  final runs = field.paragraph.inlines.whereType<WmlRun>();
  expect(runs.singleWhere((r) => r.text == 'Book').properties.italic, isTrue);
  expect(runs.singleWhere((r) => r.text == ' 12').properties.italic, isFalse);
}

void main() {
  test('native insertion retains mixed citation formatting as one field', () {
    final document = WmlDocument.empty(text: 'Before  after');
    final paragraph = document.paragraphs.single;
    final rich = ZoteroFormattedText.fromHtml('<i>Book</i> 12');
    WordZotero.insertNativeCitation(
      paragraph,
      instruction: _citation().fieldInstruction,
      text: rich.plainText,
      formattedText: rich,
      index: 7,
    );
    expect(paragraph.text, 'Before Book 12 after');
    _expectIntact(document);
  });

  test(
    'native replacement upgrades a simple field without losing neighbors',
    () {
      final document = WmlDocument.empty(text: 'Before  after');
      final paragraph = document.paragraphs.single;
      WordZotero.insertCitation(paragraph, _citation(), index: 7);
      final before = paragraph.inlines.first;
      final after = paragraph.inlines.last;
      final rich = ZoteroFormattedText.fromHtml('<i>Book</i> 12');
      WordZotero.replaceNativeResult(
        WordZotero.fields(document).single,
        instruction: _citation().fieldInstruction,
        text: rich.plainText,
        formattedText: rich,
      );
      expect(identical(paragraph.inlines.first, before), isTrue);
      expect(identical(paragraph.inlines.last, after), isTrue);
      _expectIntact(document);
    },
  );

  test('a caret inside a mixed citation moves after the complete packet', () {
    final document = _document();
    final paragraph = document.paragraphs.single;
    expect(WmlRunEdit.normalizeRange(paragraph, 9, 9), (start: 14, end: 14));
    WmlRunEdit.replaceRange(paragraph, 9, 9, '!');
    expect(paragraph.text, 'Before Book 12! after');
    _expectIntact(document);
  });

  for (final replacement in ['', 'Replacement']) {
    test(
      'partial mixed citation replacement removes its entire packet: "$replacement"',
      () {
        final document = _document();
        final paragraph = document.paragraphs.single;
        final before = paragraph.inlines.first;
        final after = paragraph.inlines.last;
        WmlRunEdit.replaceRange(paragraph, 9, 11, replacement);
        expect(paragraph.text, 'Before $replacement after');
        expect(WordZotero.fields(document), isEmpty);
        expect(paragraph.inlines.whereType<WmlFieldBoundary>(), isEmpty);
        expect(identical(paragraph.inlines.first, before), isTrue);
        expect(identical(paragraph.inlines.last, after), isTrue);
        expect((before as WmlRun).commentIds, [42]);
        expect((after as WmlRun).properties.bold, isTrue);
      },
    );
  }

  for (final position in [7, 9, 14]) {
    test(
      'paste at citation position $position keeps the field packet intact',
      () {
        final document = _document();
        final paragraph = document.paragraphs.single;
        WmlRunEdit.insertRuns(paragraph, position, [
          WmlRun(
            text: 'PASTE',
            properties: WmlRunProps(underline: WmlUnderline.single),
          ),
        ]);
        expect(
          paragraph.text,
          position == 7
              ? 'Before PASTEBook 12 after'
              : 'Before Book 12PASTE after',
        );
        _expectIntact(document);
        final field = WordZotero.fields(document).single;
        expect(field.cachedText, isNot(contains('PASTE')));
      },
    );
  }

  for (final position in [7, 14]) {
    test(
      'paragraph split at citation edge $position keeps every marker together',
      () {
        final document = _document();
        final paragraph = document.paragraphs.single;
        final tail = WmlRunEdit.splitParagraphInlines(paragraph, position);
        document.sections.single.blocks.add(WmlParagraph(inlines: tail));
        expect(
          document.paragraphs.map((p) => p.text).toList(),
          position == 7
              ? ['Before ', 'Book 12 after']
              : ['Before Book 12', ' after'],
        );
        _expectIntact(document);
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        _expectIntact(reopened);
      },
    );
  }

  test('paragraph split within a mixed citation refuses before mutation', () {
    final document = _document();
    final paragraph = document.paragraphs.single;
    final before = List<WmlInline>.of(paragraph.inlines);
    expect(
      () => WmlRunEdit.splitParagraphInlines(paragraph, 9),
      throwsArgumentError,
    );
    expect(paragraph.inlines, orderedEquals(before));
    _expectIntact(document);
  });

  test('formatting a partial citation selects all result runs without splitting it', () {
    final document = _document();
    final paragraph = document.paragraphs.single;
    WmlRunEdit.applyRange(
      paragraph,
      9,
      10,
      (p) => p.underline = WmlUnderline.single,
    );
    _expectIntact(document);
    final result = paragraph.inlines.whereType<WmlRun>().where(
      (r) => r.text == 'Book' || r.text == ' 12',
    );
    expect(
      result.every((r) => r.properties.underline == WmlUnderline.single),
      isTrue,
    );
    expect(
      (paragraph.inlines.first as WmlRun).properties.underline,
      WmlUnderline.none,
    );
  });

  for (final kind in ['locked', 'malformed', 'unbalanced', 'nested']) {
    test(
      '$kind Zotero packets refuse generic interior editing without mutation',
      () {
        final document = WmlDocument.empty();
        final paragraph = document.paragraphs.single;
        final packet = _packet(
          locked: kind == 'locked',
          code: kind == 'malformed'
              ? ' ADDIN ZOTERO_ITEM CSL_CITATION {broken} '
              : null,
        );
        if (kind == 'unbalanced') packet.removeLast();
        if (kind == 'nested') {
          packet.insertAll(3, [
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
            WmlFieldBoundary(
              kind: WmlFieldBoundaryKind.instruction,
              text: ' PAGE ',
            ),
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
            WmlRun(text: '1'),
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          ]);
        }
        paragraph.inlines
          ..clear()
          ..addAll([
            WmlRun(text: 'Before '),
            ...packet,
            WmlRun(text: ' after'),
          ]);
        final before = List<WmlInline>.of(paragraph.inlines);
        final text = paragraph.text;
        expect(
          () => WmlRunEdit.replaceRange(paragraph, 8, 9, 'X'),
          throwsUnsupportedError,
        );
        expect(paragraph.inlines, orderedEquals(before));
        expect(paragraph.text, text);
      },
    );
  }

  for (final isolate in [false, true]) {
    test(
      'mixed citation styles survive repeated ${isolate ? "isolate" : "direct"} DOCX saves',
      () async {
        var document = _document();
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = isolate
              ? await OfficeIsolateSave.word(document)
              : WordSerializer().writeBytes(document);
          document = WordDeserializer().readBytes(bytes);
          _expectIntact(document);
          final paragraph = document.paragraphs.single;
          WmlRunEdit.insertRuns(paragraph, 9, [WmlRun(text: '!')]);
          _expectIntact(document);
        }
      },
    );
  }
}
