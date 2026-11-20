import 'dart:convert';

import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _documentId = 'research-target';
const _one = '<a href="https://www.zotero.org/?FIRST1">(old one)</a>';
const _two = '<a href="https://www.zotero.org/?SECOND2">(old two)</a>';

WordZoteroCitingSession _session(
  WmlDocument document,
  WmlParagraph paragraph, {
  int start = 0,
  int? end,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _documentId,
  insertionParagraph: paragraph,
  insertionOffset: start,
  insertionEndOffset: end,
);

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_documentId, ...args]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

List<Map<String, Object>> _convert(
  WordZoteroCitingSession session,
  List<String> ids, {
  int type = 0,
}) =>
    (_call(session, 'Document.convertPlaceholdersToFields', [
              ids,
              type,
              'Http',
            ])!
            as List<Object?>)
        .cast<Map<String, Object>>();

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

void _set(
  WordZoteroCitingSession session,
  Map<String, Object> field,
  String id,
  String html,
) {
  _call(session, 'Field.setCode', [
    field['id'],
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, html).toJson())}',
  ]);
  _call(session, 'Field.setText', [field['id'], html, true]);
}

void _start(WordZoteroCitingSession session, String html, {int type = 0}) {
  final temp =
      _call(session, 'Document.insertField', ['Http', type])!
          as Map<String, Object>;
  _call(session, 'Field.delete', [temp['id']]);
  _call(session, 'Document.insertText', [html]);
}

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

void main() {
  for (final endnote in [false, true]) {
    final label = endnote ? 'endnote' : 'footnote';
    final type = endnote ? 2 : 1;

    for (final requested in [0, type]) {
      test(
        '$label research content inherits its story for request $requested',
        () {
          final document = WmlDocument.empty(text: 'Body');
          final note = WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: endnote,
            text: 'Before target after',
          );
          final paragraph = note.paragraphs.single;
          WordZotero.insertCitation(
            paragraph,
            _citation('before', '(B)'),
            index: 0,
          );
          WordZotero.insertCitation(
            paragraph,
            _citation('after', '(A)'),
            index: paragraph.text.length,
          );
          final start = paragraph.text.indexOf('target');
          final original = paragraph.text;
          final session = _session(
            document,
            paragraph,
            start: start,
            end: start + 6,
          );
          expect(session.canInsertNoteText, isTrue);
          final originalFields = _fields(session);
          _start(
            session,
            '<p>First <b>$_one</b></p><p>Second $_two</p>',
            type: requested,
          );
          final inserted = _convert(session, [
            'SECOND2',
            'FIRST1',
          ], type: requested);
          expect(inserted.map((field) => field['noteIndex']), [1, 1]);
          _set(session, inserted[0], 'two', '(Two)');
          _set(session, inserted[1], 'one', '<i>(One)</i>');
          _set(session, originalFields.first, 'before', '(Before expanded)');
          _set(session, originalFields.last, 'after', '(After expanded)');
          expect(_fields(session).map((field) => field['id']), [
            originalFields.first['id'],
            inserted[1]['id'],
            inserted[0]['id'],
            originalFields.last['id'],
          ]);
          expect(
            paragraph.text,
            original,
            reason: 'The entire result stays staged.',
          );
          _finish(session);
          expect(note.paragraphs.map((p) => p.text), [
            '(Before expanded)Before First (One)',
            'Second (Two) after(After expanded)',
          ]);
          expect(session.caretAfter!.paragraph, same(note.paragraphs.last));
          expect(session.caretAfter!.offset, 'Second (Two)'.length);
          expect(document.footnotes.length + document.endnotes.length, 1);
          expect(
            note.allParagraphs
                .expand((p) => p.inlines.whereType<WmlRun>())
                .any((run) => run.noteRefId != null),
            isFalse,
          );
          final reopened = _reopen(document);
          final restored =
              (endnote ? reopened.endnotes : reopened.footnotes).single;
          expect(
            WordNotes.editableText(restored),
            WordNotes.editableText(note),
          );
          expect(
            WordZotero.fields(reopened)
                .map((field) => field.citation!.citationId),
            ['before', 'one', 'two', 'after'],
          );
          final next = _session(reopened, restored.paragraphs.first);
          expect(_fields(next).map((field) => field['noteIndex']), [
            1,
            1,
            1,
            1,
          ]);
        },
      );
    }

    test(
      '$label headings lists and images retain the leading reference marker',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Trailing prose',
        );
        final paragraph = note.paragraphs.single;
        paragraph.inlines.insert(
          0,
          WmlNoteMarker(endnote: endnote, properties: WmlRunProps(bold: true)),
        );
        final png = image.encodePng(
          image.Image(width: 2, height: 2, numChannels: 4),
        );
        final session = _session(document, paragraph);
        _start(
          session,
          '<h2>Research</h2><ol start="3"><li><p>First $_one</p>'
          '<p><img src="data:image/png;base64,${base64Encode(png)}" '
          'width="24" alt="Note image"/></p><ul><li>Nested $_two</li></ul>'
          '</li></ol>',
          type: type,
        );
        final inserted = _convert(session, ['SECOND2', 'FIRST1'], type: type);
        _set(session, inserted[0], 'two', '(Two)');
        _set(session, inserted[1], 'one', '(One)');
        _finish(session);
        for (final result in [document, _reopen(document)]) {
          final current = (endnote ? result.endnotes : result.footnotes).single;
          expect(current.paragraphs.first.text, 'Research');
          expect(current.paragraphs.first.properties.headingLevel, 2);
          final markers = current.allParagraphs
              .expand((p) => p.inlines.whereType<WmlNoteMarker>())
              .toList();
          expect(markers, hasLength(1));
          expect(current.paragraphs.first.inlines.first, same(markers.single));
          expect(markers.single.endnote, endnote);
          expect(markers.single.properties.bold, isTrue);
          expect(current.paragraphs.last.text, 'Trailing prose');
          expect(current.paragraphs[1].properties.numId, isNotNull);
          expect(current.paragraphs[1].properties.listLabel, '3. ');
          expect(current.paragraphs[2].properties.numberingSuppressed, isTrue);
          final pictures = current.allParagraphs
              .expand((p) => p.inlines.whereType<WmlRun>())
              .where((run) => run.inlineVisual != null)
              .toList();
          expect(pictures, hasLength(1));
          expect(
            WordZotero.fields(result)
                .map((field) => field.citation!.citationId),
            ['one', 'two'],
          );
          expect(result.footnotes.length + result.endnotes.length, 1);
        }
        expect(session.caretAfter!.paragraph.text, 'Nested (Two)');
        expect(session.caretAfter!.offset, 'Nested (Two)'.length);
      },
    );

    test(
      '$label visible start keeps reference separator on the inserted heading',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: ' Trailing prose',
        );
        final paragraph = note.paragraphs.single;
        paragraph.inlines.insert(
          0,
          WmlNoteMarker(
            endnote: endnote,
            properties: WmlRunProps(bold: true),
          ),
        );
        expect(WordNotes.editableText(note), 'Trailing prose');
        final session = _session(document, paragraph, start: 1);
        _start(session, '<h2>Research</h2><p>Details</p>', type: type);
        _finish(session);
        for (final result in [document, _reopen(document)]) {
          final current = (endnote ? result.endnotes : result.footnotes).single;
          expect(current.paragraphs.map((p) => p.text), [
            ' Research',
            'Details',
            'Trailing prose',
          ]);
          expect(
            WordNotes.editableText(current),
            'Research\nDetails\nTrailing prose',
          );
          expect(current.paragraphs.first.inlines.first, isA<WmlNoteMarker>());
          expect(current.paragraphs.first.properties.headingLevel, 2);
        }
      },
    );

    test(
      '$label rejects incompatible placeholder placement before changes',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Keep',
        );
        final session = _session(document, note.paragraphs.single);
        _start(session, '<p>$_one</p>', type: type);
        expect(
          () => _convert(session, ['FIRST1'], type: endnote ? 1 : 2),
          throwsUnsupportedError,
        );
        expect(
          () => _call(session, 'Document.complete'),
          throwsFormatException,
        );
        expect(note.text, 'Keep');
        expect(WordZotero.fields(document), isEmpty);
        expect(document.footnotes.length + document.endnotes.length, 1);
      },
    );

    test(
      '$label keeps destination note when an original sole citation is deleted',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
        );
        final paragraph = note.paragraphs.single;
        WordZotero.insertCitation(paragraph, _citation('old', '(Old)'));
        final session = _session(
          document,
          paragraph,
          start: paragraph.text.length,
        );
        final original = _fields(session).single;
        _start(session, '<p> New authored content</p>', type: type);
        _call(session, 'Field.delete', [original['id']]);
        _finish(session);
        expect(
          (endnote ? document.endnotes : document.footnotes).single,
          same(note),
        );
        expect(note.text, 'New authored content');
        expect(WordZotero.fields(document), isEmpty);
        expect(session.caretAfter!.offset, note.paragraphs.single.text.length);
      },
    );

    test(
      '$label refuses conversion of the destination after research text is staged',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
        );
        final paragraph = note.paragraphs.single;
        WordZotero.insertCitation(paragraph, _citation('old', '(Old)'));
        final session = _session(
          document,
          paragraph,
          start: paragraph.text.length,
        );
        final field = _fields(session).single;
        _start(session, '<p> New content</p>', type: type);
        expect(
          () => _call(session, 'Document.convert', [
            [field['id']],
            'Http',
            [0],
          ]),
          throwsUnsupportedError,
        );
        expect(note.text, '(Old)');
      },
    );
  }

  test('body selection replaces only ordinary selected text and adjusts earlier fields', () {
    final document = WmlDocument.empty(text: 'Before target after');
    final paragraph = document.paragraphs.single;
    WordZotero.insertCitation(paragraph, _citation('before', '(B)'), index: 0);
    WordZotero.insertCitation(
      paragraph,
      _citation('after', '(A)'),
      index: paragraph.text.length,
    );
    final start = paragraph.text.indexOf('target');
    final session = _session(document, paragraph, start: start, end: start + 6);
    final originals = _fields(session);
    _start(session, '<p>First $_one</p><p>Second</p>');
    final inserted = _convert(session, ['FIRST1']).single;
    _set(session, inserted, 'one', '(One)');
    _set(session, originals.first, 'before', '(Expanded before)');
    _set(session, originals.last, 'after', '(Expanded after)');
    _finish(session);
    expect(document.paragraphs.map((p) => p.text), [
      '(Expanded before)Before First (One)',
      'Second after(Expanded after)',
    ]);
    expect(session.caretAfter!.offset, 'Second'.length);
    expect(
      WordZotero.fields(_reopen(document))
          .map((field) => field.citation!.citationId),
      ['before', 'one', 'after'],
    );
  });

  test(
    'selection containing a field or note reference is refused as a whole',
    () {
      final document = WmlDocument.empty(text: 'Before after');
      final paragraph = document.paragraphs.single;
      WordZotero.insertCitation(paragraph, _citation('old', '(Old)'), index: 7);
      final citationTarget = _session(
        document,
        paragraph,
        start: 0,
        end: paragraph.text.length,
      );
      expect(citationTarget.canInsertNoteText, isFalse);
      expect(
        () => _call(citationTarget, 'Document.insertText', ['<p>New</p>']),
        throwsUnsupportedError,
      );
      final noteDocument = WmlDocument.empty(text: 'Body');
      final body = noteDocument.paragraphs.single;
      WordNotes.insert(noteDocument, body, endnote: false, text: 'Keep note');
      final noteTarget = _session(
        noteDocument,
        body,
        start: 0,
        end: body.text.length,
      );
      expect(noteTarget.canInsertNoteText, isFalse);
      expect(noteDocument.footnotes.single.text, 'Keep note');
      expect(WordZotero.fields(document).single.citation!.citationId, 'old');
    },
  );

  test(
    'selection crossing a structural marker or commented text is refused',
    () {
      final document = WmlDocument.empty(text: 'Before');
      final paragraph = document.paragraphs.single;
      paragraph.inlines.addAll([
        WmlBookmarkBoundary(id: '1', isStart: true, name: 'keep'),
        WmlRun(text: ' after'),
        WmlBookmarkBoundary(id: '1', isStart: false),
      ]);
      expect(
        _session(document, paragraph, start: 1, end: 10).canInsertNoteText,
        isFalse,
      );
      final commented = WmlDocument.empty(text: 'Commented');
      commented.paragraphs.single.inlines
          .whereType<WmlRun>()
          .single
          .commentIds
          .add(1);
      expect(
        _session(
          commented,
          commented.paragraphs.single,
          end: 3,
        ).canInsertNoteText,
        isFalse,
      );
    },
  );

  test(
    'selection bounds and surrogate boundaries are validated without edits',
    () {
      final document = WmlDocument.empty(text: 'A😀B');
      final paragraph = document.paragraphs.single;
      for (final range in [(3, 2), (-1, 2), (0, 5)]) {
        expect(
          () => _session(document, paragraph, start: range.$1, end: range.$2),
          throwsArgumentError,
        );
      }
      expect(
        _session(document, paragraph, start: 2).canInsertNoteText,
        isFalse,
      );
      expect(
        _session(document, paragraph, start: 1, end: 2).canInsertNoteText,
        isFalse,
      );
      expect(
        _session(document, paragraph, start: 1, end: 3).canInsertNoteText,
        isTrue,
      );
      expect(paragraph.text, 'A😀B');
    },
  );

  test(
    'research text cannot extend a paragraph-owned field at its end boundary',
    () {
      final document = WmlDocument.empty(text: 'Result');
      final paragraph = document.paragraphs.single;
      paragraph.properties.fieldInstruction =
          _citation('old', 'Result').fieldInstruction;
      final session = _session(
        document,
        paragraph,
        start: paragraph.text.length,
      );
      expect(session.canInsertNoteText, isFalse);
      expect(
        () => _call(session, 'Document.insertText', ['<p>New</p>']),
        throwsUnsupportedError,
      );
      expect(paragraph.text, 'Result');
    },
  );

  test('changed selection content or deleted note refuses completed research content', () {
    for (final remove in [false, true]) {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
        text: 'Replace',
      );
      final paragraph = note.paragraphs.single;
      final session = _session(document, paragraph, end: paragraph.text.length);
      _start(session, '<p>Research</p>');
      _call(session, 'Document.complete');
      if (remove) {
        WordNotes.delete(document, note.id, endnote: false);
      } else {
        paragraph.inlines.add(WmlRun(text: ' changed'));
      }
      expect(session.apply, throwsStateError);
      if (!remove) expect(note.text, 'Replace changed');
      expect(WordZotero.fields(document), isEmpty);
    }
  });
}
