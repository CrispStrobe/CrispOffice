import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late GectorConfiguration config;
  setUpAll(() async {
    config = (await TestBundle.load()).bundle.configuration;
  });

  test(
    'emoji offsets, curly quotes, untouched spacing and terminator tail are retained',
    () {
      final source = GectorSourceText('😊  Das ist mude.  \n', config);
      final edits = source.suggestions(<String>['😊', 'Das', 'ist', 'müde']);
      expect(edits, hasLength(1));
      expect(edits.single.start, 12);
      expect(edits.single.end, 16);
      expect(edits.single.original, 'mude');
      expect(source.apply(edits), '😊  Das ist müde.  \n');
      final apostrophe = GectorSourceText('Anna’s Haus.', config);
      expect(apostrophe.plain, "Anna's Haus");
      expect(
        apostrophe.apply(apostrophe.suggestions(<String>["Anna's", 'Haus'])),
        'Anna’s Haus.',
      );
    },
  );

  test('insertion and deletion keep neighboring source spacing', () {
    final source = GectorSourceText('Das  Haus.', config);
    expect(
      source.apply(source.suggestions(<String>['Das', 'neue', 'Haus'])),
      'Das  neue Haus.',
    );
    final duplicate = GectorSourceText('Das ist ist gut.', config);
    expect(
      duplicate.apply(duplicate.suggestions(<String>['Das', 'ist', 'gut'])),
      'Das ist gut.',
    );
    final comma = GectorSourceText('Hallo Welt!', config);
    // Frozen quickstart inserts before Welt without removing source spacing.
    expect(
      comma.apply(comma.suggestions(<String>['Hallo', ',', 'Welt'])),
      'Hallo , Welt!',
    );
  });

  test(
    'repeated-word diff keeps SequenceMatcher first-occurrence tie order',
    () {
      final source = GectorSourceText('a b a b.', config);
      final edits = source.suggestions(<String>['a', 'b']);
      expect(edits, hasLength(1));
      expect(edits.single.start, 3);
      expect(edits.single.end, 7);
      expect(source.apply(edits), 'a b.');
    },
  );

  test('grapheme boundaries expose unsafe decomposed-character edits', () {
    final source = GectorSourceText('Mu\u0308de 😊', config);
    expect(source.graphemeBoundaries, isNot(contains(2)));
    expect(source.graphemeBoundaries, containsAll(<int>[0, 1, 3, 4, 5, 6, 8]));
    final edits = source.suggestions(<String>['Müde', '😊']);
    expect(edits.single.start, 0);
    expect(edits.single.end, 5);
  });
}
