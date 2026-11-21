import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_citing.dart';
import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

const _doc = 'quds-native-placeholders';
const _codeA = 'ITEM CSL_CITATION {"citationID":"first"}';
const _codeB = 'ITEM CSL_CITATION {"citationID":"second"}';

ZoteroHttpResponse _command(String name, List<Object?> arguments) =>
    ZoteroHttpResponse(
      statusCode: 200,
      body: jsonEncode(<String, Object?>{
        'command': name,
        'arguments': arguments,
      }),
    );

Map<String, Object?> _field(String id, String code) => <String, Object?>{
  'id': id,
  'code': code,
  'text': '(Citation)',
  'noteIndex': 1,
};

TypeMatcher<ZoteroCitingException> _invalid() => isA<ZoteroCitingException>()
    .having(
      (error) => error.kind,
      'kind',
      ZoteroCitingErrorKind.invalidResponse,
    )
    .having(
      (error) => error.desktopMayNeedRestart,
      'desktopMayNeedRestart',
      isFalse,
    );

void main() {
  // Both the original Quds source pin 992853536935dce3249a4ecf61d0d129883f85c4
  // and Zotero ebdf94eda5257292967ebe39ea06a9a5ed31d15c contain the same
  // httpIntegrationClient.js blob: 611911bbfce0a7656eab8e4a322588863976aa34.
  // Its actual callback is [documentId, codes, placeholderIDs, noteType].
  test('native placeholder codes and IDs retain their request order', () async {
    final args = <Object?>[
      _doc,
      <String>[_codeB, _codeA],
      <String>['B456', 'A123'],
      1,
    ];
    final fields = <Object?>[_field('f-b', _codeB), _field('f-a', _codeA)];
    final replies = <ZoteroHttpResponse>[
      _command('Document.insertText', <Object?>[
        _doc,
        '<p>A <a href="https://www.zotero.org/?A123">(A)</a> '
            'B <a href="https://www.zotero.org/?B456">(B)</a></p>',
      ]),
      _command('Document.convertPlaceholdersToFields', args),
      _command('Field.setText', <Object?>[_doc, 'f-a', '<i>First</i>', true]),
      _command('Field.setText', <Object?>[_doc, 'f-b', '<i>Second</i>', true]),
      _command('Document.complete', <Object?>[_doc]),
    ];
    var requests = 0;
    final handled = <String>[];
    await ZoteroCitingClient(
      transport: (request) async {
        if (requests == 0) {
          expect(jsonDecode(request.body!), <String, Object?>{
            'command': 'addNote',
            'docId': _doc,
          });
        }
        if (requests == 2) expect(jsonDecode(request.body!), fields);
        return replies[requests++];
      },
    ).execute(
      command: ZoteroCitingCommand.addNote,
      documentId: _doc,
      handler: (name, arguments) {
        handled.add(name);
        if (name == 'Document.convertPlaceholdersToFields') {
          expect(arguments, args);
          return fields;
        }
        return null;
      },
    );
    expect(requests, replies.length);
    expect(handled, <String>[
      'Document.insertText',
      'Document.convertPlaceholdersToFields',
      'Field.setText',
      'Field.setText',
      'Document.complete',
    ]);
  });

  test('legacy Quds IDs, note type, Http callback remains accepted', () async {
    var requests = 0;
    final args = <Object?>[
      _doc,
      <String>['A123'],
      0,
      'Http',
    ];
    final result = <Object?>[_field('legacy', 'TEMP')];
    await ZoteroCitingClient(
      transport: (request) async {
        if (++requests == 1) {
          return _command('Document.convertPlaceholdersToFields', args);
        }
        expect(jsonDecode(request.body!), result);
        return _command('Document.complete', <Object?>[_doc]);
      },
    ).execute(
      command: ZoteroCitingCommand.addNote,
      documentId: _doc,
      handler: (name, arguments) {
        if (name == 'Document.convertPlaceholdersToFields') {
          expect(arguments, args);
          return result;
        }
        return null;
      },
    );
    expect(requests, 2);
  });

  for (final args in <List<Object?>>[
    [
      _doc,
      <String>[_codeA],
      <String>['A123', 'B456'],
      0,
    ],
    [
      _doc,
      <String>[_codeA, _codeB],
      <String>['A123'],
      0,
    ],
    [
      _doc,
      <Object?>[42],
      <String>['A123'],
      0,
    ],
    [
      _doc,
      <String>[_codeA, _codeB],
      <String>['A123', 'A123'],
      0,
    ],
    [
      _doc,
      <String>[_codeA],
      <String>['bad-id'],
      0,
    ],
    [
      _doc,
      <String>[_codeA],
      <String>[''],
      0,
    ],
    [
      _doc,
      <String>[_codeA],
      <String>['A123'],
      -1,
    ],
    [
      _doc,
      <String>[_codeA],
      <String>['A123'],
      3,
    ],
    [
      _doc,
      <String>[_codeA],
      <String>['A123'],
      'Http',
    ],
    [
      _doc,
      <String>[_codeA],
      <String>['A123'],
      0,
      'Http',
    ],
    [
      _doc,
      _codeA,
      <String>['A123'],
      0,
    ],
  ]) {
    test('malformed native placeholder callback is rejected: $args', () async {
      var requests = 0;
      var handled = false;
      await expectLater(
        ZoteroCitingClient(
          transport: (request) async {
            if (++requests == 1) {
              return _command('Document.convertPlaceholdersToFields', args);
            }
            expect(jsonDecode(request.body!), containsPair('error', 'Alert'));
            return _command('Document.complete', <Object?>[_doc]);
          },
        ).execute(
          command: ZoteroCitingCommand.addNote,
          documentId: _doc,
          handler: (_, _) {
            handled = true;
            return null;
          },
        ),
        throwsA(_invalid()),
      );
      expect(handled, isFalse);
      expect(requests, 2);
    });
  }

  for (final result in <Object?>[
    null,
    <Object?>[],
    <Object?>[_field('a', _codeA)],
    <Object?>[_field('a', _codeA), _field('a', _codeB)],
  ]) {
    test(
      'native placeholder response must match IDs without duplicates: $result',
      () async {
        var requests = 0;
        await expectLater(
          ZoteroCitingClient(
            transport: (request) async {
              if (++requests == 1) {
                return _command(
                  'Document.convertPlaceholdersToFields',
                  <Object?>[
                    _doc,
                    <String>[_codeA, _codeB],
                    <String>['A123', 'B456'],
                    0,
                  ],
                );
              }
              expect(jsonDecode(request.body!), containsPair('error', 'Alert'));
              return _command('Document.complete', <Object?>[_doc]);
            },
          ).execute(
            command: ZoteroCitingCommand.addNote,
            documentId: _doc,
            handler: (_, _) => result,
          ),
          throwsA(_invalid()),
        );
        expect(requests, 2);
      },
    );
  }

  test(
    'native placeholder fields cannot reuse a known document identity',
    () async {
      var requests = 0;
      final replies = <ZoteroHttpResponse>[
        _command('Document.getFields', <Object?>[_doc, 'Http']),
        _command('Document.convertPlaceholdersToFields', <Object?>[
          _doc,
          <String>[_codeA],
          <String>['A123'],
          0,
        ]),
        _command('Document.complete', <Object?>[_doc]),
      ];
      await expectLater(
        ZoteroCitingClient(
          transport: (request) async {
            if (requests == 2) {
              expect(jsonDecode(request.body!), containsPair('error', 'Alert'));
            }
            return replies[requests++];
          },
        ).execute(
          command: ZoteroCitingCommand.addNote,
          documentId: _doc,
          handler: (_, _) => <Object?>[_field('existing', _codeA)],
        ),
        throwsA(_invalid()),
      );
      expect(requests, replies.length);
    },
  );
}
