import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('embeddedItems resolves an alias bridge after both snapshots', () {
    const local = 'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
    const account = 'http://zotero.org/users/42/items/ABCD1234';
    final sources = <ZoteroCitationItem>[
      for (final (index, uris) in <List<String>>[
        [local],
        [account],
        [local, account],
      ].indexed)
        ZoteroCitationItem.fromJson({
          'id': index,
          'uris': uris,
          'itemData': {
            'id': index,
            'type': 'book',
            'title': 'Snapshot $index',
            'unknownData': {'retained': index},
          },
          'locator': '8-10',
          'prefix': 'see',
          'suffix': 'and following',
        }),
    ];
    final paragraphs = <WmlParagraph>[];
    for (final (index, source) in sources.indexed) {
      final paragraph = WmlParagraph();
      WordZotero.insertCitation(
        paragraph,
        ZoteroCitation(
          citationId: 'control-$index',
          plainCitation: '(Source $index)',
          items: [source],
        ),
      );
      paragraphs.add(paragraph);
    }
    final document = WmlDocument(
      sections: [WmlSection(blocks: paragraphs)],
    );
    final before = WordZotero.fields(document)
        .map((field) => field.instruction)
        .toList();
    // This public entry point existed before the optimization; an old-code
    // failure is behavioral, never an unavailable-helper compilation failure.
    final result = WordZotero.embeddedItems(document);
    expect(result, hasLength(1));
    expect(jsonEncode(result.single), jsonEncode(sources.first.itemData));
    expect(
      WordZotero.fields(document).map((field) => field.instruction),
      before,
    );
  });
}
