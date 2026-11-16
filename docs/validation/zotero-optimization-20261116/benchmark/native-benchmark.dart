import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const documentId = 'native-benchmark';

ZoteroCitation citation(String id) => ZoteroCitation(
  citationId: id,
  plainCitation: 'Citation $id',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': id, 'type': 'book', 'title': 'Source'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

WmlDocument fixture(int groups) {
  final blocks = <WmlBlock>[];
  final document = WmlDocument(sections: [WmlSection(blocks: blocks)]);
  for (var i = 0; i < groups; i++) {
    final body = WmlParagraph();
    blocks.add(body);
    WordZotero.insertCitation(body, citation('body-$i'));
    for (final endnote in [false, true]) {
      final bucket = endnote ? document.endnotes : document.footnotes;
      final noteParagraph = WmlParagraph();
      WordZotero.insertCitation(noteParagraph, citation('${endnote ? 'end' : 'foot'}-$i'));
      final id = groups - i;
      bucket.insert(0, WmlNote(id: id, endnote: endnote, paragraphs: [noteParagraph]));
      body.inlines.add(WmlRun(text: '$id', noteRefId: id, noteRefEndnote: endnote));
    }
  }
  return document;
}

Object? call(WordZoteroCitingSession session, String command, [List<Object?> args = const []]) =>
    session.handle(command, [documentId, ...args]);

Map<String, Object> measure(int groups, int repeats) {
  final document = fixture(groups);
  final init = <int>[];
  final snapshots = <int>[];
  final guards = <int>[];
  final selections = <int>[];
  final checksums = <String>{};
  for (var repeat = 0; repeat < repeats; repeat++) {
    final timer = Stopwatch()..start();
    final session = WordZoteroCitingSession(document: document, documentId: documentId);
    init.add(timer.elapsedMicroseconds);
    timer.reset();
    final fields = call(session, 'Document.getFields', ['Http']) as List;
    snapshots.add(timer.elapsedMicroseconds);
    checksums.add(sha256.convert(utf8.encode(jsonEncode(fields))).toString());
    timer.reset();
    session.assertUnchanged();
    guards.add(timer.elapsedMicroseconds);
    timer.reset();
    for (var pass = 0; pass < 5; pass++) {
      for (final field in fields) {
        call(session, 'Field.select', [(field as Map)['id']]);
      }
    }
    selections.add(timer.elapsedMicroseconds);
    timer.stop();
  }
  return {
    'field_count': groups * 3,
    'note_count': groups * 2,
    'initialization_us': init,
    'get_fields_us': snapshots,
    'assert_unchanged_us': guards,
    'select_fields_five_passes_us': selections,
    'wire_snapshot_sha256': checksums.toList(),
  };
}

void main(List<String> args) {
  measure(80, 3);
  print(jsonEncode({
    'label': args.single,
    'runtime': Platform.version,
    'method': 'JIT warmup: 80 groups x 3; each measurement uses 3 fields and 2 notes per group, 5 repetitions; microseconds, no performance assertions',
    'results': [for (final groups in [100, 400, 800]) measure(groups, 5)],
  }));
}
