/// Hand-written fixtures follow the upstream HTTP serializer, not TestSynan's
/// different CLI output. Source: JVisualSynAnParamBuilder.cpp at aot 0d591d97.
List<Object?> syntaxFixture() => <Object?>[
  <Object?>[
    <String, Object?>{
      'words': <Object?>[
        <String, Object?>{
          'str': 'Ich',
          'homonyms': <String>['SIE'],
        },
        <String, Object?>{
          'str': 'gehe',
          'homonyms': <String>['GEHEN'],
        },
        <String, Object?>{
          'str': 'nach',
          'homonyms': <String>['NACH'],
        },
        <String, Object?>{
          'str': 'Hause',
          'homonyms': <String>['HAUS'],
        },
        <String, Object?>{
          'str': '.',
          'homonyms': <String>['.'],
        },
      ],
      'variants': <Object?>[
        <String, Object?>{
          'units': <Object?>[
            <String, Object?>{'homNo': 0, 'grm': 'PRO nom,sin,1,alg,per,; '},
            <String, Object?>{
              'homNo': 0,
              'grm': 'VER sin,1,prae,non,; sin,imp,non,; sin,3,kj1,non,; ',
            },
            <String, Object?>{'homNo': 0, 'grm': 'PRP dat,lok,tmp,; '},
            <String, Object?>{'homNo': 0, 'grm': 'SUB dat,sin,neu,; '},
            <String, Object?>{'homNo': 0, 'grm': ' '},
          ],
          'groups': <Object?>[
            <String, Object?>{
              'start': 0,
              'last': 4,
              'isGroup': false,
              'isSubj': false,
              'descr': 'verbsatz',
            },
            <String, Object?>{
              'start': 0,
              'last': 1,
              'isGroup': false,
              'isSubj': true,
              'descr': 'sp',
            },
            <String, Object?>{
              'start': 2,
              'last': 3,
              'isGroup': true,
              'isSubj': false,
              'descr': 'pp',
            },
          ],
        },
      ],
    },
  ],
];

List<Object?> tokensFixture(List<List<List<String>>> sentences) => <Object?>[
  for (final List<List<String>> sentence in sentences)
    <Object?>[
      for (final List<String> clause in sentence)
        <String, Object?>{
          'words': <Object?>[
            for (final String word in clause)
              <String, Object?>{
                'str': word,
                'homonyms': <String>[word],
              },
          ],
          'variants': <Object?>[
            <String, Object?>{
              'units': <Object?>[
                for (final String _ in clause)
                  <String, Object?>{'homNo': 0, 'grm': ' '},
              ],
              'groups': <Object?>[],
            },
          ],
        },
    ],
];

List<Object?> morphologyFixture() => <Object?>[
  <String, Object?>{
    'found': true,
    'commonGrammems': 'intra,non',
    'wordForm': 'GEHEN',
    'morphInfo': 'VER sin,plu,1,2,3,prae,imp,kj1',
    'wordWeight': 42,
    'homonymWeight': 7,
    'paradigm': <Object?>[
      <String, Object?>{
        'pos': 'VER non',
        'formsGroups': <Object?>[
          <String, Object?>{
            'grm': 'sin,prae',
            'forms': <Object?>[
              <String, Object?>{'f': 'GEHE', 'grm': '1'},
              <String, Object?>{'f': 'GEHST', 'grm': '2'},
              <String, Object?>{'f': 'GEHT', 'grm': '3'},
            ],
          },
          <String, Object?>{
            'grm': 'plu,prae',
            'forms': <Object?>[
              <String, Object?>{'f': 'GEHEN', 'grm': '1'},
              <String, Object?>{'f': 'GEHT', 'grm': '2'},
              <String, Object?>{'f': 'GEHEN', 'grm': '3'},
            ],
          },
        ],
      },
    ],
  },
];
