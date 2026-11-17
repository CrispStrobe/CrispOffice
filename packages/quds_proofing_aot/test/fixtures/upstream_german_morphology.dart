// Minimal linguistic test-output data, not an engine or dictionary bundle.
// Original canonical LemmatizeJson results, with the TSV word labels moved
// into JSON keys. Pinned source (retrieved 2026-11-17):
// https://github.com/sokirko74/nlp_base/blob/244b3d1f9a09e4a81e75ea83c3b55b209c663503/test_lem/test/German/morphan.txt.morph.canon
// AOT's license text: https://github.com/sokirko74/aot/blob/0d591d972c7bb2729f4764d3bc32611ea6fd142a/copying
// (GNU Lesser General Public License 2.1). No native implementation is copied.

const String upstreamGermanMorphologyJson = r'''
{
  "Mutter": [
    {
      "found": true,
      "commonGrammems": "",
      "wordForm": "MUTTER",
      "morphInfo": "SUB akk,dat,gen,nom,sin,fem",
      "paradigm": [
        {
          "pos": "SUB fem",
          "formsGroups": [
            {
              "grm": "",
              "forms": [
                {
                  "f": "MUTTER",
                  "grm": "akk,sin"
                },
                {
                  "f": "MUTTER",
                  "grm": "dat,sin"
                },
                {
                  "f": "MUTTER",
                  "grm": "gen,sin"
                },
                {
                  "f": "MUTTER",
                  "grm": "nom,sin"
                },
                {
                  "f": "MÜTTER",
                  "grm": "akk,plu"
                },
                {
                  "f": "MÜTTER",
                  "grm": "gen,plu"
                },
                {
                  "f": "MÜTTER",
                  "grm": "nom,plu"
                },
                {
                  "f": "MÜTTERN",
                  "grm": "dat,plu"
                }
              ]
            }
          ]
        }
      ],
      "wordWeight": 0,
      "homonymWeight": 0
    }
  ],
  "VÖGEL": [
    {
      "found": true,
      "commonGrammems": "",
      "wordForm": "VOGEL",
      "morphInfo": "SUB akk,gen,nom,plu,mas",
      "paradigm": [
        {
          "pos": "SUB mas",
          "formsGroups": [
            {
              "grm": "",
              "forms": [
                {
                  "f": "VOGEL",
                  "grm": "akk,sin"
                },
                {
                  "f": "VOGEL",
                  "grm": "dat,sin"
                },
                {
                  "f": "VOGEL",
                  "grm": "nom,sin"
                },
                {
                  "f": "VOGELS",
                  "grm": "gen,sin"
                },
                {
                  "f": "VÖGEL",
                  "grm": "akk,plu"
                },
                {
                  "f": "VÖGEL",
                  "grm": "gen,plu"
                },
                {
                  "f": "VÖGEL",
                  "grm": "nom,plu"
                },
                {
                  "f": "VÖGELN",
                  "grm": "dat,plu"
                }
              ]
            }
          ]
        }
      ],
      "wordWeight": 0,
      "homonymWeight": 0
    }
  ]
}
''';
