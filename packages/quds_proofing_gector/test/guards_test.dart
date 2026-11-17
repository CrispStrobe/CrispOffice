import 'dart:convert';

import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestBundle fixtures;
  late GectorGermanGuards guards;
  setUpAll(() async {
    fixtures = await TestBundle.load();
  });
  setUp(() {
    guards = GectorGermanGuards.fromJson(
      fixtures.bundle.guardsJson,
      configuration: fixtures.bundle.configuration,
      lexicon: GectorWordSetLexicon(<String>[
        'konnte',
        'könnte',
        'schon',
        'schön',
        'höre',
        'hörte',
        'Mal',
        'mal',
        'gehst',
        'gehe',
        'geht',
        'die',
        'der',
        'lernen',
        'Lernen',
        'Haus',
        'gut',
        'müde',
        'Müde',
        'Frage',
        'Fragen',
        'Du',
        'du',
        'gehen',
        'war',
        'wäre',
      ]),
    );
  });
  Future<String> apply(
    List<String> words,
    int at,
    String label,
    String next, {
    Set<String> personal = const <String>{},
  }) => guards.apply(
    words: words,
    index: at,
    label: label,
    replacement: next,
    personalWords: personal,
  );

  test('subjunctive mood needs an explicit cue', () async {
    expect(
      await apply(
        <String>['Ich', 'konnte', 'kommen'],
        1,
        r'$REPLACE_könnte',
        'könnte',
      ),
      'konnte',
    );
    expect(
      await apply(
        <String>['Ich', 'konnte', 'gern', 'kommen'],
        1,
        r'$REPLACE_könnte',
        'könnte',
      ),
      'könnte',
    );
  });
  test('schon to schön needs a previous intensifier or copula end', () async {
    expect(
      await apply(
        <String>['Ich', 'bin', 'schon', 'da'],
        2,
        r'$REPLACE_schön',
        'schön',
      ),
      'schon',
    );
    expect(
      await apply(
        <String>['Das', 'ist', 'sehr', 'schon'],
        3,
        r'$REPLACE_schön',
        'schön',
      ),
      'schön',
    );
  });
  test(
    'deletion allows duplicates but holds demonstrative and case-changing pairs',
    () async {
      expect(
        await apply(<String>['Das', 'ist', 'ist', 'gut'], 2, r'$DELETE', ''),
        '',
      );
      expect(
        await apply(<String>['Ist', 'das', 'das', 'Haus'], 2, r'$DELETE', ''),
        'das',
      );
      expect(
        await apply(<String>['das', 'Lernen', 'lernen'], 2, r'$DELETE', ''),
        'lernen',
      );
      expect(
        await apply(
          <String>['Das', 'ist', 'wirklich', 'gut'],
          2,
          r'$DELETE',
          '',
        ),
        'wirklich',
      );
    },
  );
  test(
    'closed class, unknown targets and unsolicited appends are suppressed',
    () async {
      expect(await apply(<String>['Haus'], 0, r'$REPLACE_die', 'die'), 'Haus');
      expect(
        await apply(<String>['Haus'], 0, r'$REPLACE_Zorb', 'Zorb'),
        'Haus',
      );
      expect(
        await apply(<String>['Haus'], 0, r'$APPEND_der', 'Haus der'),
        'Haus',
      );
    },
  );
  test(
    'subject person, redirects, known capitalization and personal words are respected',
    () async {
      expect(
        await apply(
          <String>['Du', 'geht'],
          1,
          r'$TRANSFORM_VERB_P2P_P2S',
          'gehst',
        ),
        'gehst',
      );
      expect(
        await apply(
          <String>['Du', 'geht'],
          1,
          r'$TRANSFORM_VERB_P2P_P1S',
          'gehe',
        ),
        'geht',
      );
      expect(
        await apply(<String>['ich', 'hore'], 1, r'$REPLACE_hörte', 'hörte'),
        'höre',
      );
      expect(
        await apply(<String>['das', 'mal'], 1, r'$REPLACE_Mal', 'Mal'),
        'mal',
      );
      expect(
        await apply(<String>['du'], 0, r'$TRANSFORM_CASE_CAPITAL', 'Du'),
        'du',
      );
      expect(
        await apply(
          <String>['Mude'],
          0,
          r'$REPLACE_Müde',
          'Müde',
          personal: <String>{'Mude'},
        ),
        'Mude',
      );
      expect(
        await apply(<String>['die', 'Fragen'], 1, r'$REPLACE_Frage', 'Frage'),
        'Fragen',
      );
    },
  );
  test('unknown rule schemas fail rather than silently ignore new policy', () {
    expect(
      () => GectorGermanGuards.fromJson(
        jsonEncode(<String, Object>{
          'guards': <Object>[
            <String, Object>{'type': 'new_semantics'},
          ],
        }),
        configuration: fixtures.bundle.configuration,
        lexicon: GectorWordSetLexicon(const []),
      ),
      throwsFormatException,
    );
  });

  test(
    'nearby coordination cannot justify a singular verb-person change',
    () async {
      expect(
        await apply(
          <String>['Du', 'und', 'ich', 'gehen'],
          3,
          r'$TRANSFORM_VERB_P1P_P1S',
          'gehe',
        ),
        'gehen',
      );
      expect(
        await apply(
          <String>['ich', 'gehen'],
          1,
          r'$TRANSFORM_VERB_P1P_P1S',
          'gehe',
        ),
        'gehe',
      );
    },
  );

  test(
    'mood, past-year and copula cues do not cross sentence boundaries',
    () async {
      expect(
        await apply(
          <String>['Vielleicht', 'regnet', 'es', '.', 'Ich', 'war', 'müde'],
          5,
          r'$REPLACE_wäre',
          'wäre',
        ),
        'war',
      );
      expect(
        await apply(
          <String>['2020', 'regnete', 'es', '.', 'Ich', 'wäre', 'müde'],
          5,
          r'$REPLACE_war',
          'war',
        ),
        'wäre',
      );
      expect(
        await apply(
          <String>['Das', 'ist', 'erledigt', '.', 'Ich', 'gehe', 'schon'],
          6,
          r'$REPLACE_schön',
          'schön',
        ),
        'schon',
      );
      expect(
        await apply(
          <String>['Vielleicht', 'war', 'ich', 'müde'],
          1,
          r'$REPLACE_wäre',
          'wäre',
        ),
        'wäre',
      );
    },
  );
}
