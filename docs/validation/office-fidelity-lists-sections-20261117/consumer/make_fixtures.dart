import 'dart:convert';
import 'dart:io';

// This repository-level fixture uses the checker-verified workspace mapping.
// The workspace root is not itself a package that depends on the engine.
// ignore: depend_on_referenced_packages
import 'package:quds_office_engine/quds_office_engine.dart';

const _firstSize = WmlPageSize(width: 400, height: 500);
const _secondSize = WmlPageSize(width: 600, height: 400);
const _margins = WmlPageMargins(top: 36, bottom: 36, left: 36, right: 36);

WmlParagraph p(String text, {WmlParagraphProps? properties}) => WmlParagraph(
  properties: properties,
  inlines: [WmlRun(text: text)],
);

WmlParagraph item(
  String text, {
  int level = 0,
  String label = '•',
  int numId = 1,
  int? restart,
}) => p(
  text,
  properties: WmlParagraphProps(
    numId: numId,
    ilvl: level,
    listLabel: label,
    listRestart: restart,
  ),
);

WmlSection section(
  List<WmlBlock> blocks, {
  WmlPageSize size = _firstSize,
  WmlSectionBreakKind kind = WmlSectionBreakKind.nextPage,
  String? header,
  String? footer,
}) => WmlSection(
  blocks: blocks,
  pageSize: size,
  margins: _margins,
  breakKind: kind,
  linkToPrevious: false,
  header: header == null ? [] : [p(header)],
  footer: footer == null ? [] : [p(footer)],
);

WmlTable table(String text) => WmlTable(
  grid: [180],
  rows: [
    WmlTableRow(
      cells: [
        WmlTableCell(blocks: [p(text)]),
      ],
    ),
  ],
);

WmlContentControlBlock control(List<WmlBlock> blocks) => WmlContentControlBlock(
  control: WmlContentControlData(
    xml: '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtContent/></w:sdt>',
    sourcePartUri: '/word/document.xml',
    relationships: const [],
  ),
  blocks: blocks,
);

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Pass one fresh output directory.');
  }
  final directory = Directory(arguments.single);
  if (directory.existsSync()) {
    throw StateError('Fixture directory must be fresh.');
  }
  directory.createSync(recursive: true);
  final records = <Map<String, Object?>>[];

  void save(
    String name,
    WmlDocument document, {
    required List<List<num>> pages,
    required Map<String, int> words,
    List<List<String>> sameX = const [],
    List<List<String>> indented = const [],
    Map<String, String> labels = const {},
    List<String> order = const [],
    Map<String, Object?> extra = const {},
  }) {
    final bytes = OdtDocumentWriter.writeBytes(document);
    File('${directory.path}/$name.odt').writeAsBytesSync(bytes);
    records.add({
      'name': name,
      'file': '$name.odt',
      'page_sizes_pt': pages,
      'word_pages': words,
      'same_x': sameX,
      'indented': indented,
      'labels': labels,
      'vertical_order': order,
      ...extra,
    });
  }

  void secondSection(String name, List<WmlBlock> blocks, List<String> words) {
    save(
      name,
      WmlDocument(
        sections: [
          section([p('FirstBody')], header: 'FirstHead', footer: 'FirstFoot'),
          section(
            blocks,
            size: _secondSize,
            header: 'SecondHead',
            footer: 'SecondFoot',
          ),
        ],
      ),
      pages: [
        [400, 500],
        [600, 400],
      ],
      words: {
        'FirstBody': 1,
        'FirstHead': 1,
        'FirstFoot': 1,
        'SecondHead': 2,
        'SecondFoot': 2,
        for (final word in words) word: 2,
      },
    );
  }

  secondSection(
    'section-list',
    [
      item('ListFirst', label: '1.', numId: 2),
      item('ListSecond', label: '2.', numId: 2),
    ],
    ['ListFirst', 'ListSecond'],
  );
  secondSection(
    'section-control-list',
    [
      control([
        control([]),
        control([item('ControlFirst'), item('ControlSecond')]),
      ]),
    ],
    ['ControlFirst', 'ControlSecond'],
  );
  secondSection('section-table', [table('TableFirst')], ['TableFirst']);
  secondSection(
    'section-control-table',
    [
      control([
        control([table('ControlTable')]),
      ]),
    ],
    ['ControlTable'],
  );
  secondSection(
    'section-visual',
    [
      WmlVisual(
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          title: 'SectionPicture',
          imageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
          ),
          width: 40,
          height: 20,
        ),
      ),
      p('VisualTail'),
    ],
    ['VisualTail'],
  );
  secondSection(
    'section-frame',
    [
      WmlFrame(
        x: 60,
        y: 100,
        width: 180,
        height: 40,
        blocks: [p('FrameFirst')],
      ),
      p('FrameTail'),
    ],
    ['FrameFirst', 'FrameTail'],
  );
  save(
    'section-empty',
    WmlDocument(
      sections: [
        section([p('BeforeEmpty')]),
        section([], size: _secondSize, header: 'EmptySectionHead'),
        section([p('AfterEmpty')]),
      ],
    ),
    pages: [
      [400, 500],
      [600, 400],
      [400, 500],
    ],
    words: {'BeforeEmpty': 1, 'EmptySectionHead': 2, 'AfterEmpty': 3},
  );
  save(
    'section-continuous',
    WmlDocument(
      sections: [
        section([p('BeforeContinuous')]),
        section([p('AfterContinuous')], kind: WmlSectionBreakKind.continuous),
      ],
    ),
    pages: [
      [400, 500],
    ],
    words: {'BeforeContinuous': 1, 'AfterContinuous': 1},
    order: ['BeforeContinuous', 'AfterContinuous'],
  );
  save(
    'section-continuous-empty',
    WmlDocument(
      sections: [
        section([p('BeforeContinuous')]),
        section([], kind: WmlSectionBreakKind.continuous),
        section([p('AfterContinuous')], kind: WmlSectionBreakKind.continuous),
      ],
    ),
    pages: [
      [400, 500],
    ],
    words: {'BeforeContinuous': 1, 'AfterContinuous': 1},
    order: ['BeforeContinuous', 'AfterContinuous'],
    extra: {'same_layout_as': 'section-continuous'},
  );
  WmlParagraph pictureHeader() => WmlParagraph(
    inlines: [
      WmlRun(text: 'PictureHeader'),
      WmlRun(
        inlineVisual: WmlVisual(
          visual: OfficeVisual(
            kind: OfficeVisualKind.picture,
            title: 'HeaderPixel',
            imageBytes: base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
            ),
            width: 12,
            height: 8,
          ),
        ),
      ),
    ],
  );
  final pictureSections = [
    section([p('BeforeHeaderPicture')]),
    section([p('AfterHeaderPicture')], kind: WmlSectionBreakKind.continuous),
  ];
  for (final s in pictureSections) {
    s.header.add(pictureHeader());
  }
  save(
    'section-continuous-image-header',
    WmlDocument(sections: pictureSections),
    pages: [
      [400, 500],
    ],
    words: {
      'BeforeHeaderPicture': 1,
      'AfterHeaderPicture': 1,
      'PictureHeader': 1,
    },
    order: ['BeforeHeaderPicture', 'AfterHeaderPicture'],
  );
  final commentSections = [
    section([p('BeforeHeaderComment')]),
    section([p('AfterHeaderComment')], kind: WmlSectionBreakKind.continuous),
  ];
  for (final s in commentSections) {
    s.header.add(
      WmlParagraph(
        inlines: [
          WmlRun(text: 'CommentHeader', commentIds: [17]),
        ],
      ),
    );
  }
  save(
    'section-continuous-comment-header',
    WmlDocument(
      sections: commentSections,
      comments: [WmlComment(id: 17, text: 'Header review')],
    ),
    pages: [
      [400, 500],
    ],
    words: {
      'BeforeHeaderComment': 1,
      'AfterHeaderComment': 1,
      'CommentHeader': 1,
    },
    order: ['BeforeHeaderComment', 'AfterHeaderComment'],
    extra: {
      'scope':
          'Equivalent header comments must not force a page break; header annotation visibility is not asserted.',
    },
  );
  save(
    'section-continuous-new-size',
    WmlDocument(
      sections: [
        section([p('BeforeNewSize')]),
        section(
          [p('AfterNewSize')],
          size: _secondSize,
          kind: WmlSectionBreakKind.continuous,
        ),
      ],
    ),
    pages: [
      [400, 500],
      [600, 400],
    ],
    words: {'BeforeNewSize': 1, 'AfterNewSize': 2},
    extra: {'scope': 'Documented page-boundary fallback for changed geometry.'},
  );
  save(
    'section-heading-layout',
    WmlDocument(
      sections: [
        section([p('BeforeHeading')]),
        section([
          p(
            'HeadingFirst\nHeadingSecond',
            properties: WmlParagraphProps(
              headingLevel: 2,
              rightToLeft: true,
              justification: WmlJustification.right,
              lineSpacingRule: WmlLineSpacingRule.exact,
              lineSpacing: 18,
              spacingBefore: 6,
              spacingAfter: 5,
              indent: const WmlIndent(left: 30, right: 24),
            ),
          ),
        ], size: _secondSize),
      ],
    ),
    pages: [
      [400, 500],
      [600, 400],
    ],
    words: {'BeforeHeading': 1, 'HeadingFirst': 2, 'HeadingSecond': 2},
    extra: {
      'line_step': {
        'words': ['HeadingFirst', 'HeadingSecond'],
        'points': 18,
      },
      'right_edge': {
        'words': ['HeadingFirst', 'HeadingSecond'],
        'points': 540,
      },
    },
  );
  save(
    'paragraph-rtl-indent',
    WmlDocument(
      sections: [
        section([
          p(
            'RightFirst\nRightSecond',
            properties: WmlParagraphProps(
              rightToLeft: true,
              justification: WmlJustification.right,
              lineSpacingRule: WmlLineSpacingRule.exact,
              lineSpacing: 18,
              spacingBefore: 6,
              spacingAfter: 5,
              indent: const WmlIndent(left: 30, right: 24),
            ),
          ),
          p(
            'LeftFirst\nLeftSecond',
            properties: WmlParagraphProps(
              rightToLeft: true,
              justification: WmlJustification.left,
              lineSpacingRule: WmlLineSpacingRule.exact,
              lineSpacing: 18,
              spacingBefore: 6,
              spacingAfter: 5,
              indent: const WmlIndent(left: 30, right: 24),
            ),
          ),
        ], size: _secondSize),
      ],
    ),
    pages: [
      [600, 400],
    ],
    words: {'RightFirst': 1, 'RightSecond': 1, 'LeftFirst': 1, 'LeftSecond': 1},
    order: ['RightFirst', 'RightSecond', 'LeftFirst', 'LeftSecond'],
    extra: {
      'line_step': {
        'words': ['RightFirst', 'RightSecond'],
        'points': 18,
      },
      'right_edge': {
        'words': ['RightFirst', 'RightSecond'],
        'points': 540,
      },
      'left_edge': {
        'words': ['LeftFirst', 'LeftSecond'],
        'points': 66,
      },
      'scope':
          'Ordinary RTL paragraphs preserve physical 30 pt left and 24 pt right indents, independently of section activation.',
    },
  );
  for (final kind in [
    WmlSectionBreakKind.oddPage,
    WmlSectionBreakKind.evenPage,
  ]) {
    for (final firstPages in [1, 2]) {
      final startPage = kind == WmlSectionBreakKind.oddPage
          ? 3
          : (firstPages == 1 ? 2 : 4);
      save(
        'section-${kind.name}-after-$firstPages',
        WmlDocument(
          sections: [
            section([
              p('BeforeParity'),
              if (firstPages == 2)
                p(
                  'BeforeParitySecond',
                  properties: WmlParagraphProps(pageBreakBefore: true),
                ),
            ]),
            section([
              p('ParityStart'),
              p(
                'ParityContinue',
                properties: WmlParagraphProps(pageBreakBefore: true),
              ),
            ], kind: kind),
          ],
        ),
        pages: [
          for (var i = 0; i < startPage + 1; i++) [400, 500],
        ],
        words: {
          'BeforeParity': 1,
          if (firstPages == 2) 'BeforeParitySecond': 2,
          'ParityStart': startPage,
          'ParityContinue': startPage + 1,
        },
        extra: {'reopened_section_type': kind.name},
      );
    }
  }
  save(
    'list-skipped-levels',
    WmlDocument(
      sections: [
        section([
          item('RootFirst'),
          item('ChildFirst', level: 3),
          item('ChildSecond', level: 3),
          item('RootSecond'),
        ]),
      ],
    ),
    pages: [
      [400, 500],
    ],
    words: {'RootFirst': 1, 'ChildFirst': 1, 'ChildSecond': 1, 'RootSecond': 1},
    sameX: [
      ['RootFirst', 'RootSecond'],
      ['ChildFirst', 'ChildSecond'],
    ],
    indented: [
      ['RootFirst', 'ChildFirst'],
    ],
    order: ['RootFirst', 'ChildFirst', 'ChildSecond', 'RootSecond'],
  );
  save(
    'list-nonzero-start',
    WmlDocument(
      sections: [
        section([
          item('NonzeroFirst', level: 2),
          item('NonzeroSecond', level: 2),
        ]),
      ],
    ),
    pages: [
      [400, 500],
    ],
    words: {'NonzeroFirst': 1, 'NonzeroSecond': 1},
    sameX: [
      ['NonzeroFirst', 'NonzeroSecond'],
    ],
    order: ['NonzeroFirst', 'NonzeroSecond'],
  );
  save(
    'list-mixed-markers',
    WmlDocument(
      sections: [
        section([
          item('NumberFirst', label: '1.', numId: 8),
          item('BulletChild', label: '•', numId: 8, level: 1),
          item('NumberSecond', label: '2.', numId: 8),
        ]),
      ],
    ),
    pages: [
      [400, 500],
    ],
    words: {'NumberFirst': 1, 'BulletChild': 1, 'NumberSecond': 1},
    labels: {'NumberFirst': '1.', 'BulletChild': '•', 'NumberSecond': '2.'},
    sameX: [
      ['NumberFirst', 'NumberSecond'],
    ],
    indented: [
      ['NumberFirst', 'BulletChild'],
    ],
  );
  save(
    'list-restart-continuation',
    WmlDocument(
      sections: [
        section([
          item('CountFirst', label: '1.', numId: 8),
          p('Interruption'),
          item('CountSecond', label: '1.', numId: 8),
          item('RestartSeven', label: '1.', numId: 8, restart: 7),
          item('AfterRestart', label: '1.', numId: 8),
        ]),
      ],
    ),
    pages: [
      [400, 500],
    ],
    words: {
      'CountFirst': 1,
      'Interruption': 1,
      'CountSecond': 1,
      'RestartSeven': 1,
      'AfterRestart': 1,
    },
    labels: {
      'CountFirst': '1.',
      'CountSecond': '2.',
      'RestartSeven': '7.',
      'AfterRestart': '8.',
    },
  );
  save(
    'list-literal-labels',
    WmlDocument(
      sections: [
        section([
          item('RomanFourth', label: 'IV.', numId: 9),
          item('RomanFifth', label: 'V.', numId: 9),
          item('CompositeLabel', label: '2.3.1)', numId: 10),
        ]),
      ],
    ),
    pages: [
      [400, 500],
    ],
    words: {'RomanFourth': 1, 'RomanFifth': 1, 'CompositeLabel': 1},
    labels: {
      'RomanFourth': 'IV.',
      'RomanFifth': 'V.',
      'CompositeLabel': '2.3.1)',
    },
  );
  final numberingPackage = OpcPackage.create(OpcPackageKind.word);
  numberingPackage.createPart(
    '/word/numbering.xml',
    OfficeContentTypes.wordNumbering,
    utf8.encode(
      '<w:numbering xmlns:w="${OfficeNamespaces.w}">'
      '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
      '<w:start w:val="3"/><w:numFmt w:val="decimal"/>'
      '<w:lvlText w:val="%1)"/></w:lvl></w:abstractNum>'
      '<w:num w:numId="7"><w:abstractNumId w:val="7"/>'
      '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/>'
      '</w:lvlOverride></w:num></w:numbering>',
    ),
  );
  numberingPackage
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.numbering, target: 'numbering.xml');
  save(
    'list-native-start-override',
    WmlDocument(
      package: numberingPackage,
      sections: [
        section([
          p('NativeFive', properties: WmlParagraphProps(numId: 7)),
          p('NativeSix', properties: WmlParagraphProps(numId: 7)),
        ]),
      ],
    ),
    pages: [
      [400, 500],
    ],
    words: {'NativeFive': 1, 'NativeSix': 1},
    labels: {'NativeFive': '5)', 'NativeSix': '6)'},
  );
  File('${directory.path}/fixtures.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(records)}\n',
  );
  print('Generated ${records.length} ODT fixtures.');
}
