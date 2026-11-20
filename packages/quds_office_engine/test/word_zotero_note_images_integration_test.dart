import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _docId = 'zotero-image-integration';
const _first = '<a href="https://www.zotero.org/?FIRST1">(old first)</a>';
const _second = '<a href="https://www.zotero.org/?SECOND2">(old second)</a>';

Uint8List _picture({bool jpeg = false}) {
  final raster = img.Image(width: 8, height: 4, numChannels: 3);
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      raster.setPixelRgb(x, y, x * 30, y * 60, 120);
    }
  }
  return Uint8List.fromList(
    jpeg ? img.encodeJpg(raster, quality: 95) : img.encodePng(raster),
  );
}

String _image(Uint8List bytes, {bool jpeg = false, String extra = ''}) =>
    '<img src="data:image/${jpeg ? 'jpeg' : 'png'};base64,${base64Encode(bytes)}" '
    'width="96" height="48" alt="Diagram &amp; detail" title="Research image" $extra>';

String _preferences(int noteType) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'image-note-session',
  'zoteroVersion': '10.0',
  'style': {'styleID': 'http://www.zotero.org/styles/apa', 'locale': 'en-US'},
  'prefs': {'fieldType': 'Http', 'noteType': noteType},
});

ZoteroCitation _citation(
  String id,
  String text, {
  int noteIndex = 0,
}) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  noteIndex: noteIndex,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
      uris: [
        'http://zotero.org/users/42/items/${id == 'first' ? 'ABCD1234' : 'EFGH5678'}',
      ],
      locator: id == 'first' ? '4' : '9',
      label: 'page',
    ),
  ],
);

WordZoteroCitingSession _session(WmlDocument document, {int offset = 6}) =>
    WordZoteroCitingSession(
      document: document,
      documentId: _docId,
      insertionParagraph: document.paragraphs.first,
      insertionOffset: offset,
    );

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_docId, ...args]);

List<Map<String, Object?>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object?>>();

void _setCitation(
  WordZoteroCitingSession session,
  Map<String, Object?> field,
  String id,
  String text,
) {
  _call(session, 'Field.setCode', [
    field['id'],
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, text, noteIndex: field['noteIndex']! as int).toJson())}',
  ]);
  _call(session, 'Field.setText', [field['id'], '<i>$text</i>', true]);
}

void _start(WordZoteroCitingSession session, String html, int noteType) {
  _call(session, 'Document.setDocumentData', [_preferences(noteType)]);
  final temporary =
      _call(session, 'Document.insertField', ['Http', noteType])!
          as Map<String, Object?>;
  _call(session, 'Field.delete', [temporary['id']]);
  _call(session, 'Document.insertText', [html]);
}

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

List<OfficeVisual> _images(WmlDocument document) => [
  for (final picture in document.visuals) picture.visual,
];

void main() {
  for (final operation in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    test(
      '${operation.name} carries native images through the HTTP transaction',
      () async {
        final png = _picture();
        final document = WmlDocument.empty(text: 'BeforeAfter');
        final session = _session(document);
        final citation = _citation('first', '(Source, p. 4)');
        final commands = <(String, List<Object?>)>[
          ('Application.getActiveDocument', []),
          ('Document.setDocumentData', [_docId, _preferences(0)]),
          ('Document.insertField', [_docId, 'Http', 0]),
          ('Field.delete', [_docId, 'f0']),
          (
            'Document.insertText',
            [
              _docId,
              '<html><body><p>${_image(png, extra: 'class="ink" data-annotation="%7B%22pageLabel%22%3A%224%22%7D"')}'
                  '<br/>$_first Comment</p></body></html>',
            ],
          ),
          (
            'Document.convertPlaceholdersToFields',
            [
              _docId,
              ['FIRST1'],
              0,
              'Http',
            ],
          ),
          (
            'Field.setCode',
            [
              _docId,
              'f1',
              'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
            ],
          ),
          ('Field.setText', [_docId, 'f1', '<i>(Source, p. 4)</i>', true]),
          ('Document.complete', [_docId]),
        ];
        var requests = 0;
        await ZoteroCitingClient(
          transport: (request) async {
            expect(request.uri.host, 'localhost');
            expect(request.method, 'POST');
            if (requests == 0) {
              expect(jsonDecode(request.body!), {
                'command': operation.name,
                'docId': _docId,
              });
            }
            final command = commands[requests++];
            return ZoteroHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'command': command.$1,
                'arguments': command.$2,
              }),
            );
          },
        ).execute(
          command: operation,
          documentId: _docId,
          handler: session.handle,
        );
        expect(requests, commands.length);
        expect(document.paragraphs.single.text, 'BeforeAfter');
        expect(document.visuals, isEmpty);
        expect(WordZoteroDocumentData.read(document), isEmpty);
        session.apply();
        expect(
          document.paragraphs.single.text,
          'Before\uFFFC\n(Source, p. 4) CommentAfter',
        );
        expect(
          session.caretAfter!.offset,
          'Before\uFFFC\n(Source, p. 4) Comment'.length,
        );
        expect(_images(document).single.imageBytes, png);
        expect(_images(document).single.width, 72);
        expect(_images(document).single.height, 36);
        expect(
          _images(document).single.picture.altDescription,
          'Diagram & detail',
        );
        expect(_images(document).single.picture.altTitle, 'Research image');
        expect(
          WordZotero.fields(document).single.citation!.items.single.locator,
          '4',
        );
      },
    );
  }

  for (final noteType in [0, 1, 2]) {
    test(
      'images and type $noteType citations retain order through refresh and DOCX',
      () {
        final png = _picture();
        final jpeg = _picture(jpeg: true);
        var document = WmlDocument.empty(text: 'BeforeAfter');
        final session = _session(document);
        _start(
          session,
          '<p>First ${_image(png)} $_first</p>'
          '<p>Second ${_image(jpeg, jpeg: true)} $_second</p>',
          noteType,
        );
        final converted =
            (_call(session, 'Document.convertPlaceholdersToFields', [
                      ['SECOND2', 'FIRST1'],
                      noteType,
                      'Http',
                    ])!
                    as List<Object?>)
                .cast<Map<String, Object?>>();
        _setCitation(session, converted[0], 'second', '(Second, p. 9)');
        _setCitation(session, converted[1], 'first', '(First, p. 4)');
        expect(_fields(session).map((field) => field['text']), [
          '(First, p. 4)',
          '(Second, p. 9)',
        ]);
        expect(document.visuals, isEmpty);
        _finish(session);
        for (var cycle = 0; cycle < 3; cycle++) {
          final images = _images(document);
          expect(images, hasLength(2), reason: 'cycle $cycle');
          expect(images[0].imageBytes, png);
          expect(images[1].imageBytes, jpeg);
          expect(images.map((image) => (image.width, image.height)), [
            (72, 36),
            (72, 36),
          ]);
          final refresh = _session(document, offset: 0);
          final fields = _fields(refresh);
          expect(fields.map((field) => field['text']), [
            cycle == 0 ? '(First, p. 4)' : '(Updated first)',
            cycle == 0 ? '(Second, p. 9)' : '(Updated second)',
          ]);
          expect(
            fields.map((field) => field['noteIndex']),
            noteType == 0 ? [0, 0] : [1, 2],
          );
          _setCitation(refresh, fields[0], 'first', '(Updated first)');
          _setCitation(refresh, fields[1], 'second', '(Updated second)');
          _finish(refresh);
          final package = WordSerializer().write(document);
          final xml = package.getPart('/word/document.xml')!.readText();
          expect(RegExp(r'<w:drawing>').allMatches(xml), hasLength(2));
          expect(xml, isNot(contains('data:image/')));
          final relationships = package.relationshipsFor('/word/document.xml');
          final media = relationships.items
              .where((r) => r.type == RelationshipTypes.image)
              .toList();
          expect(media, hasLength(2));
          expect(
            media.map(
              (r) => package.getPart(relationships.resolve(r))!.readBytes(),
            ),
            [png, jpeg],
          );
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        expect(
          document.paragraphs.first.text,
          startsWith('BeforeFirst \uFFFC '),
        );
        expect(document.paragraphs.last.text, endsWith('After'));
        expect(
          WordZotero.fields(
            document,
          ).map((f) => f.citation!.citationId).toSet(),
          {'first', 'second'},
        );
        // Physical note IDs need not be allocated in reading order. Zotero's
        // document session, already checked on every cycle, owns that order.
        expect(
          _fields(_session(document, offset: 0)).map((field) => field['text']),
          ['(Updated first)', '(Updated second)'],
        );
      },
    );
  }

  test('image-only notes retain a native image after saving and reopening', () {
    final png = _picture();
    var document = WmlDocument.empty(text: '');
    final session = _session(document, offset: 0);
    _start(session, '<p>${_image(png)}</p>', 0);
    expect(session.hasInsertedNoteText, isTrue);
    expect(session.hasChanges, isTrue);
    _finish(session);
    expect(document.paragraphs.single.text, '\uFFFC');
    expect(session.caretAfter!.offset, 1);
    expect(WordZotero.fields(document), isEmpty);
    for (var cycle = 0; cycle < 3; cycle++) {
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(_images(document).single.imageBytes, png);
      expect(
        _images(document).single.picture.altDescription,
        'Diagram & detail',
      );
    }
  });

  test(
    'image hyperlinks and independent list numbering survive native export',
    () {
      final png = _picture();
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final session = _session(document);
      _start(
        session,
        '<ol start="3"><li>See <a href="https://example.org/figure?x=1&amp;y=2">'
        '${_image(png)}</a> now</li><li>Continue</li></ol>',
        0,
      );
      _finish(session);
      final imageRun = document.paragraphs
          .expand((p) => p.inlines.whereType<WmlRun>())
          .singleWhere((r) => r.inlineVisual != null);
      expect(imageRun.hyperlink!.url, 'https://example.org/figure?x=1&y=2');
      final imported = document.paragraphs.singleWhere(
        (p) => p.text.startsWith('See '),
      );
      expect(imported.properties.listRestart, 3);
      final saved = WordSerializer().write(document);
      final xml = saved.getPart('/word/document.xml')!.readText();
      expect(
        RegExp(
          r'<w:hyperlink\b[^>]*>.*?<w:drawing>.*?</w:hyperlink>',
          dotAll: true,
        ).hasMatch(xml),
        isTrue,
      );
      final reopened = WordDeserializer().read(saved);
      final linkedImage = reopened.paragraphs
          .expand((p) => p.inlines.whereType<WmlRun>())
          .singleWhere((r) => r.inlineVisual != null);
      expect(linkedImage.hyperlink!.url, 'https://example.org/figure?x=1&y=2');
      expect(linkedImage.inlineVisual!.visual.imageBytes, png);
      expect(reopened.paragraphs.first.text, 'Before');
      expect(reopened.paragraphs.last.text, 'After');
    },
  );

  test(
    'unconverted citation following a staged image cannot publish partial content',
    () {
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final session = _session(document);
      _start(session, '<p>${_image(_picture())} $_first</p>', 0);
      expect(() => _call(session, 'Document.complete'), throwsFormatException);
      expect(session.apply, throwsStateError);
      expect(document.paragraphs.single.text, 'BeforeAfter');
      expect(document.visuals, isEmpty);
      expect(WordZoteroDocumentData.read(document), isEmpty);
    },
  );
}
