// Renders the Mac App Store screenshots of CrispOffice. Not an automatically
// discovered test (no `_test.dart` suffix); .github/workflows/
// app-store-screenshots.yml runs it on a macOS runner after
// tool/build_macos_app.sh:
//
//   APP=.../build/macos/Build/Products/Release/CrispOffice.app
//   QUDS_STUDIO_APP=$APP QUDS_STUDIO_DATA=<scratch directory> \
//   QUDS_SHOTS_DIR=<output directory> \
//   flutter test \
//     --dart-define=QUDS_HARPER_LIBRARY=$APP/Contents/Frameworks/libquds_proofing_harper.dylib \
//     test/app_store_screenshots_gate.dart
//
// Each scene is the real Studio workspace at a logical 1440×900 window,
// captured at device pixel ratio 2 (2880×1800 PNG), light theme, with the
// bundled fonts. Proofing comes from the native libraries packaged in the app
// and the dictionaries/models installed by Studio's own hosts (verified
// downloads), as in studio_macos_bundle_native_gate.dart and
// studio_spacy_bundle_native_gate.dart. Mail uses a local in-memory session
// with fictional example.com accounts; nothing contacts a mail server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_arabic_morph_host.dart';
import 'package:quds_office_studio/studio_arabic_morph_host_native.dart';
import 'package:quds_office_studio/studio_downloads_manager.dart';
import 'package:quds_office_studio/studio_hunspell_host.dart';
import 'package:quds_office_studio/studio_hunspell_host_native.dart';
import 'package:quds_office_studio/studio_language_id_host.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_spacy_host.dart';
import 'package:quds_office_studio/studio_spacy_host_native.dart';
import 'package:quds_office_studio/studio_strings.dart';
import 'package:quds_office_studio/suite_workspace.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';

import 'support/mail_draft_store.dart';
import 'support/studio_download_fakes.dart';

const _logical = Size(1440, 900);
const _pixelRatio = 2.0;
const _strings = StudioStrings(StudioLanguage.en);

/// dart:io's own [HttpClient], bypassing the test binding's mock.
final class _RealHttpOverrides extends HttpOverrides {}

String _required(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) fail('Set $name (see the header).');
  return value;
}

// ---------------------------------------------------------------------------
// Fonts

Future<void> _loadFonts() async {
  await OfficeHostFonts.ensureRegistered();
  final fonts = '${Directory.current.path}/../fonts';
  final local = '${Directory.current.path}/fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      final bytes = File(file).readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  final sans = <String>[
    '$fonts/LiberationSans-Regular.ttf',
    '$fonts/LiberationSans-Bold.ttf',
    '$fonts/LiberationSans-Italic.ttf',
    '$fonts/LiberationSans-BoldItalic.ttf',
  ];
  for (final alias in <String>[
    'Segoe UI',
    'Aptos',
    'Calibri',
    'Calibri Light',
    'Tahoma',
    'Verdana',
    'Arial Black',
    'Roboto',
    '.AppleSystemUIFont',
  ]) {
    await family(alias, sans);
  }
  await family('Cambria', <String>[
    '$fonts/LiberationSerif-Regular.ttf',
    '$fonts/LiberationSerif-Bold.ttf',
  ]);
  await family('Cairo', <String>['$local/Cairo-Regular.ttf']);
  await family('Tajawal', <String>[
    '$local/Tajawal-Regular.ttf',
    '$local/Tajawal-Bold.ttf',
  ]);
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

// ---------------------------------------------------------------------------
// Sample content (fictional)

WmlParagraph _para(
  String text, {
  String? style,
  bool bold = false,
  String? language,
  bool rtl = false,
}) {
  final paragraph = WmlParagraph(
    inlines: <WmlInline>[
      WmlRun(
        text: text,
        properties: WmlRunProps(bold: bold, proofingLanguage: language),
      ),
    ],
  );
  if (style != null) WordStyles.apply(paragraph, style);
  if (rtl) {
    paragraph.properties.rightToLeft = true;
    paragraph.properties.justification = WmlJustification.right;
  }
  return paragraph;
}

const _englishMistakes = <String>['recieved', 'an major'];

WmlDocument _partnerUpdate() => WmlDocument(
  proofingLanguage: 'en-US',
  sections: <WmlSection>[
    WmlSection(
      blocks: <WmlBlock>[
        _para('Quarterly Partner Update', style: 'Title'),
        _para(
          'Prepared for the partner network · October to December 2026',
          style: 'Subtitle',
        ),
        _para('Highlights', style: 'Heading1'),
        _para(
          'Our team completed the move to the new document workflow in '
          'October. Average review time fell from four days to two and a '
          'half, and the shared glossary now covers more than 2,400 terms in '
          'English and Arabic.',
        ),
        _para(
          'We recieved positive feedback from partner offices in Lisbon, '
          'Amman and Montreal. The bilingual style guide is an major step '
          'toward consistent publications in both languages.',
        ),
        _para('Summary in Arabic', style: 'Heading1'),
        _para(
          'أكمل فريقنا الانتقال الى نظام المستندات الجديد في شهر أكتوبر، '
          'وانخفض متوسط وقت المراجعة من أربعة أيام إلى يومين ونصف.',
          rtl: true,
        ),
        _para(
          'نشكر جميع الشركاء على دعمهم المستمر لهذه المرحله المهمة من '
          'المشروع، ونتطلع إلى التعاون معكم في العام القادم.',
          rtl: true,
        ),
        _para('Next steps', style: 'Heading1'),
        _para(
          'In the first quarter we will publish the updated style guide, '
          'extend proofing to French and German, and run two training '
          'sessions for new editors. Please send agenda suggestions by '
          '15 January.',
        ),
      ],
    ),
  ],
);

const _germanWrong = 'Die Katzen auf dem Sofa schläft.';

WmlDocument _germanPractice() => WmlDocument(
  proofingLanguage: 'en-US',
  sections: <WmlSection>[
    WmlSection(
      blocks: <WmlBlock>[
        _para('German Practice — Week 3', style: 'Title'),
        _para(
          'Homework sentences from Tuesday’s conversation class. Topic: '
          'subject–verb agreement with plural subjects.',
        ),
        _para('Sentences', style: 'Heading1'),
        _para(
          'Die Kinder spielen im Garten, und der Hund liegt in der Sonne.',
          language: 'de-DE',
        ),
        _para(_germanWrong, language: 'de-DE'),
        _para(
          'Am Wochenende besuchen wir unsere Freunde in Hamburg.',
          language: 'de-DE',
        ),
        _para(
          'Nach dem Unterricht trinken die Studenten zusammen einen Kaffee.',
          language: 'de-DE',
        ),
        _para('Next lesson', style: 'Heading1'),
        _para(
          'Separable verbs and the perfect tense. Bring three sentences about '
          'your weekend.',
        ),
      ],
    ),
  ],
);

SmlCell _set(SmlWorksheet sheet, int col, int row, Object? value) {
  final cell = sheet.cell(SmlCellRef(col, row));
  if (value is String && value.startsWith('=')) {
    cell.type = SmlCellType.formula;
    cell.formula = value;
    cell.value = value;
  } else if (value is num) {
    cell.type = SmlCellType.number;
    cell.value = value;
  } else {
    cell.type = SmlCellType.string;
    cell.value = value;
  }
  return cell;
}

void _header(SmlWorksheet sheet, int row, int count) {
  for (var c = 0; c < count; c++) {
    sheet.cell(SmlCellRef(c, row))
      ..fontBold = true
      ..fillRgb = '217346'
      ..fontRgb = 'FFFFFF';
  }
}

SmlWorkbook _salesWorkbook() {
  final sales = SmlWorksheet(name: 'Regional Sales', sheetId: 1, freezeRows: 1);
  const regions = <(String, List<int>)>[
    ('North America', <int>[48200, 51750, 55300, 61900]),
    ('Europe', <int>[39400, 41200, 44850, 47600]),
    ('Middle East', <int>[18750, 21300, 24100, 26800]),
    ('Asia Pacific', <int>[31600, 33900, 35250, 39400]),
    ('Latin America', <int>[12300, 13850, 14900, 16450]),
  ];
  const head = <String>['Region', 'Q1', 'Q2', 'Q3', 'Q4', 'Total', 'Share'];
  for (var c = 0; c < head.length; c++) {
    _set(sales, c, 0, head[c]);
  }
  _header(sales, 0, head.length);
  for (var r = 0; r < regions.length; r++) {
    final row = r + 1;
    _set(sales, 0, row, regions[r].$1);
    for (var q = 0; q < 4; q++) {
      _set(sales, q + 1, row, regions[r].$2[q]);
    }
    _set(sales, 5, row, '=SUM(B${row + 1}:E${row + 1})');
    _set(sales, 6, row, '=ROUND(F${row + 1}/F\$7*100,1)');
  }
  final total = regions.length + 1;
  _set(sales, 0, total, 'Total').fontBold = true;
  for (var c = 1; c <= 5; c++) {
    final col = String.fromCharCode(65 + c);
    _set(sales, c, total, '=SUM(${col}2:${col}6)').fontBold = true;
  }
  _set(sales, 6, total, '=SUM(G2:G6)').fontBold = true;
  _set(sales, 0, total + 2, 'Average per region');
  _set(sales, 5, total + 2, '=AVERAGE(F2:F6)');
  _set(sales, 0, total + 3, 'Best quarter (all regions)');
  _set(sales, 5, total + 3, '=MAX(B7:E7)');
  sales.columnWidths[0] = 170;
  for (var c = 1; c <= 6; c++) {
    sales.columnWidths[c] = 84;
  }
  int quarter(int q) => regions.fold(0, (sum, r) => sum + r.$2[q]);
  sales.drawings
    ..add(
      SmlDrawing(
        visual: OfficeVisual(
          kind: OfficeVisualKind.chartColumn,
          title: 'Revenue by quarter (USD)',
          points: <ChartPoint>[
            ChartPoint(
              label: 'Q1',
              value: quarter(0).toDouble(),
              color: '2B579A',
            ),
            ChartPoint(
              label: 'Q2',
              value: quarter(1).toDouble(),
              color: '217346',
            ),
            ChartPoint(
              label: 'Q3',
              value: quarter(2).toDouble(),
              color: 'B7472A',
            ),
            ChartPoint(
              label: 'Q4',
              value: quarter(3).toDouble(),
              color: 'ED7D31',
            ),
          ],
          width: 360,
          height: 250,
        ),
        col: 7,
        row: 1,
        sourceFromA1: 'B7',
        sourceToA1: 'E7',
      ),
    )
    ..add(
      SmlDrawing(
        visual: OfficeVisual(
          kind: OfficeVisualKind.chartPie,
          title: 'Share of annual revenue',
          points: <ChartPoint>[
            for (final (i, region) in regions.indexed)
              ChartPoint(
                label: region.$1,
                value: region.$2.fold(0, (a, b) => a + b).toDouble(),
                color: const [
                  '2B579A',
                  '217346',
                  'B7472A',
                  'ED7D31',
                  '7030A0',
                ][i],
              ),
          ],
          width: 360,
          height: 250,
        ),
        col: 7,
        row: 15,
      ),
    );

  final targets = SmlWorksheet(name: 'Targets 2027', sheetId: 2);
  const targetHead = <String>['Region', 'Target', 'Owner', 'Status'];
  for (var c = 0; c < targetHead.length; c++) {
    _set(targets, c, 0, targetHead[c]);
  }
  _header(targets, 0, targetHead.length);
  const targetRows = <List<Object>>[
    <Object>['North America', 240000, 'Sales East', 'On track'],
    <Object>['Europe', 195000, 'Sales Europe', 'On track'],
    <Object>['Middle East', 110000, 'Sales MENA', 'Ahead'],
    <Object>['Asia Pacific', 160000, 'Sales APAC', 'At risk'],
    <Object>['Latin America', 65000, 'Sales LATAM', 'On track'],
  ];
  for (var r = 0; r < targetRows.length; r++) {
    for (var c = 0; c < targetRows[r].length; c++) {
      _set(targets, c, r + 1, targetRows[r][c]);
    }
  }
  targets.columnWidths[0] = 160;

  final notes = SmlWorksheet(name: 'Notes', sheetId: 3);
  _set(notes, 0, 0, 'Figures in USD, rounded to the nearest 50.');
  _set(notes, 0, 1, 'Source: regional sales reports, reviewed 4 January 2027.');

  return SmlWorkbook(sheets: <SmlWorksheet>[sales, targets, notes]);
}

PmlShape _box({
  required int id,
  required String name,
  required String text,
  required String fill,
  required int x,
  required int y,
  required int cx,
  required int cy,
  String color = 'FFFFFF',
  double size = 0,
  bool bold = false,
  PmlTextAlign align = PmlTextAlign.left,
  PmlTextAnchor anchor = PmlTextAnchor.top,
  PmlShapePreset preset = PmlShapePreset.rect,
}) => PmlShape(
  id: id,
  name: name,
  text: text,
  fillColor: fill,
  textColor: color,
  fontSizePt: size,
  textBold: bold ? true : null,
  textAlign: align,
  textAnchor: anchor,
  preset: preset,
  transform: PmlTransform(x: x, y: y, cx: cx, cy: cy),
);

PmlPresentation _launchDeck() => PmlPresentation(
  slides: <PmlSlide>[
    PmlSlide(
      id: 256,
      shapes: <PmlShape>[
        _box(
          id: 2,
          name: 'Background',
          text: '',
          fill: '1F3864',
          x: 0,
          y: 0,
          cx: 9144000,
          cy: 5143500,
        ),
        _box(
          id: 3,
          name: 'Accent',
          text: '',
          fill: 'ED7D31',
          x: 600000,
          y: 2350000,
          cx: 1200000,
          cy: 60000,
        ),
        _box(
          id: 4,
          name: 'Title',
          text: 'Product Launch Plan',
          fill: '1F3864',
          x: 560000,
          y: 1300000,
          cx: 8000000,
          cy: 950000,
          size: 40,
          bold: true,
        ),
        _box(
          id: 5,
          name: 'Subtitle',
          text: 'Spring 2027 release · Marketing review',
          fill: '1F3864',
          x: 560000,
          y: 2550000,
          cx: 8000000,
          cy: 600000,
          size: 20,
          color: 'D9E2F3',
        ),
      ],
    ),
    PmlSlide(
      id: 257,
      shapes: <PmlShape>[
        _box(
          id: 2,
          name: 'Title',
          text: 'Launch timeline',
          fill: 'FFFFFF',
          color: '1F3864',
          x: 500000,
          y: 300000,
          cx: 8100000,
          cy: 700000,
          size: 30,
          bold: true,
        ),
        PmlShape(
          id: 3,
          name: 'Timeline',
          fillColor: 'FFFFFF',
          transform: const PmlTransform(
            x: 500000,
            y: 1200000,
            cx: 8100000,
            cy: 2000000,
          ),
          visual: OfficeVisual(
            kind: OfficeVisualKind.diagramProcess,
            title: '',
            points: const <ChartPoint>[
              ChartPoint(label: 'Beta (Feb)', value: 1, color: '2B579A'),
              ChartPoint(
                label: 'Press preview (Mar)',
                value: 1,
                color: '217346',
              ),
              ChartPoint(label: 'Launch (Apr)', value: 1, color: 'ED7D31'),
              ChartPoint(label: 'Review (May)', value: 1, color: '7030A0'),
            ],
          ),
        ),
        _box(
          id: 4,
          name: 'Note',
          text:
              'Each milestone has an owner, a budget and a go/no-go review one week before the date.',
          fill: 'F2F2F2',
          color: '404040',
          x: 500000,
          y: 3500000,
          cx: 8100000,
          cy: 900000,
          size: 16,
          anchor: PmlTextAnchor.center,
        ),
      ],
    ),
    PmlSlide(
      id: 258,
      shapes: <PmlShape>[
        _box(
          id: 2,
          name: 'Title',
          text: 'Early customer response',
          fill: 'FFFFFF',
          color: '1F3864',
          x: 500000,
          y: 300000,
          cx: 8100000,
          cy: 700000,
          size: 30,
          bold: true,
        ),
        PmlShape(
          id: 3,
          name: 'Signups chart',
          fillColor: 'FFFFFF',
          transform: const PmlTransform(
            x: 500000,
            y: 1150000,
            cx: 5000000,
            cy: 3500000,
          ),
          visual: OfficeVisual(
            kind: OfficeVisualKind.chartColumn,
            title: 'Beta sign-ups per week',
            points: const <ChartPoint>[
              ChartPoint(label: 'Week 1', value: 420, color: '2B579A'),
              ChartPoint(label: 'Week 2', value: 610, color: '2B579A'),
              ChartPoint(label: 'Week 3', value: 780, color: '2B579A'),
              ChartPoint(label: 'Week 4', value: 1150, color: 'ED7D31'),
            ],
          ),
        ),
        _box(
          id: 4,
          name: 'Takeaways',
          text:
              '2,960 beta sign-ups in four weeks\n\n87% would recommend the product\n\nMost requested: offline editing',
          fill: 'DEEAF6',
          color: '1F3864',
          x: 5800000,
          y: 1150000,
          cx: 2800000,
          cy: 3500000,
          size: 18,
          anchor: PmlTextAnchor.center,
        ),
      ],
    ),
    PmlSlide(
      id: 259,
      shapes: <PmlShape>[
        _box(
          id: 2,
          name: 'Title',
          text: 'Channels and budget',
          fill: 'FFFFFF',
          color: '1F3864',
          x: 500000,
          y: 300000,
          cx: 8100000,
          cy: 700000,
          size: 30,
          bold: true,
        ),
        PmlShape(
          id: 3,
          name: 'Budget chart',
          fillColor: 'FFFFFF',
          transform: const PmlTransform(
            x: 500000,
            y: 1150000,
            cx: 8100000,
            cy: 3500000,
          ),
          visual: OfficeVisual(
            kind: OfficeVisualKind.chartPie,
            title: 'Launch budget by channel',
            points: const <ChartPoint>[
              ChartPoint(label: 'Online ads', value: 42, color: '2B579A'),
              ChartPoint(label: 'Events', value: 23, color: '217346'),
              ChartPoint(label: 'Partners', value: 20, color: 'ED7D31'),
              ChartPoint(label: 'Press', value: 15, color: '7030A0'),
            ],
          ),
        ),
      ],
    ),
    PmlSlide(
      id: 260,
      shapes: <PmlShape>[
        _box(
          id: 2,
          name: 'Background',
          text: '',
          fill: '1F3864',
          x: 0,
          y: 0,
          cx: 9144000,
          cy: 5143500,
        ),
        _box(
          id: 3,
          name: 'Closing',
          text: 'Questions and next steps',
          fill: '1F3864',
          x: 560000,
          y: 2000000,
          cx: 8000000,
          cy: 900000,
          size: 34,
          bold: true,
          align: PmlTextAlign.center,
        ),
      ],
    ),
  ],
);

// ---------------------------------------------------------------------------
// Mail (in memory, fictional accounts)

mail.Mailbox _box2(String name, [List<mail.MailboxFlag> flags = const []]) =>
    mail.Mailbox(
      encodedName: name,
      encodedPath: name,
      flags: <mail.MailboxFlag>[...flags],
      pathSeparator: '/',
      uidValidity: 41,
    );

const _reportUid = 108;

String _minimalPdf() {
  const objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return out.toString();
}

String _reportMessage() {
  final pdf = base64.encode(utf8.encode(_minimalPdf()));
  final wrapped = StringBuffer();
  for (var i = 0; i < pdf.length; i += 76) {
    wrapped.write(
      '${pdf.substring(i, i + 76 > pdf.length ? pdf.length : i + 76)}\r\n',
    );
  }
  return 'From: Leo <leo@example.com>\r\n'
      'To: Anna <anna@example.com>\r\n'
      'Cc: Design Team <design@example.com>\r\n'
      'Subject: Q4 partner report and agenda for Thursday\r\n'
      'Date: Thu, 19 Nov 2026 09:42:00 +0100\r\n'
      'Message-ID: <q4-report@example.com>\r\n'
      'MIME-Version: 1.0\r\n'
      'Content-Type: multipart/mixed; boundary=report-boundary\r\n'
      '\r\n'
      '--report-boundary\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n'
      'Content-Transfer-Encoding: 8bit\r\n'
      '\r\n'
      'Hi Anna,\r\n'
      '\r\n'
      'attached is the final Q4 partner report. Review times are down to two '
      'and a half days, and the shared glossary passed 2,400 terms.\r\n'
      '\r\n'
      'Could you check the Arabic summary on page 2 before Thursday? I have '
      'booked the large meeting room from 10:00 to 11:30.\r\n'
      '\r\n'
      'Agenda for Thursday:\r\n'
      '1. Q4 results and the updated style guide\r\n'
      '2. Training plan for new editors\r\n'
      '3. Budget for the spring launch\r\n'
      '\r\n'
      'Thanks,\r\n'
      'Leo\r\n'
      '\r\n'
      '--report-boundary\r\n'
      'Content-Type: application/pdf; name="Q4 Partner Report.pdf"\r\n'
      'Content-Disposition: attachment; filename="Q4 Partner Report.pdf"\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      '\r\n'
      '$wrapped'
      '--report-boundary--\r\n';
}

const _inbox = <(int, String, String, String, bool)>[
  (
    _reportUid,
    'Leo <leo@example.com>',
    'Q4 partner report and agenda for Thursday',
    'Thu, 19 Nov 2026 09:42:00 +0100',
    false,
  ),
  (
    107,
    'Design Team <design@example.com>',
    'New cover drafts for the style guide',
    'Thu, 19 Nov 2026 08:15:00 +0100',
    false,
  ),
  (
    106,
    'Calendar <calendar@example.com>',
    'Reminder: Editors’ training on Monday',
    'Wed, 18 Nov 2026 17:30:00 +0100',
    true,
  ),
  (
    105,
    'Mia <mia@example.com>',
    'Glossary: 120 new terms ready for review',
    'Wed, 18 Nov 2026 14:05:00 +0100',
    true,
  ),
  (
    104,
    'Support <support@example.com>',
    'Your workspace storage report',
    'Tue, 17 Nov 2026 11:20:00 +0100',
    true,
  ),
  (
    103,
    'Omar <omar@example.com>',
    'Translation of the spring announcement',
    'Mon, 16 Nov 2026 16:48:00 +0100',
    true,
  ),
  (
    102,
    'Leo <leo@example.com>',
    'Room booking confirmed',
    'Mon, 16 Nov 2026 09:02:00 +0100',
    true,
  ),
];

mail.MimeMessage _envelope(int uid) {
  final entry = _inbox.firstWhere((e) => e.$1 == uid);
  final message = mail.MimeMessage.parseFromText(
    'From: ${entry.$2}\r\n'
    'To: Anna <anna@example.com>\r\n'
    'Subject: ${entry.$3}\r\n'
    'Date: ${entry.$4}\r\n'
    '${uid == _reportUid ? 'Content-Type: multipart/mixed; boundary=report-boundary\r\n' : 'Content-Type: text/plain; charset=utf-8\r\n'}'
    '\r\n',
  )..uid = uid;
  message.flags = <String>[if (entry.$5) r'\Seen'];
  return message;
}

String _plainMessage(int uid) {
  final entry = _inbox.firstWhere((e) => e.$1 == uid);
  return 'From: ${entry.$2}\r\n'
      'To: Anna <anna@example.com>\r\n'
      'Subject: ${entry.$3}\r\n'
      'Date: ${entry.$4}\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n'
      '\r\n'
      'Hi Anna,\r\n\r\nplease see the details below.\r\n';
}

final class _Client extends Fake implements mail.MailClient {
  final boxes = <mail.Mailbox>[
    _box2('INBOX', [mail.MailboxFlag.inbox]),
    _box2('Drafts', [mail.MailboxFlag.drafts]),
    _box2('Sent', [mail.MailboxFlag.sent]),
    _box2('Archive', [mail.MailboxFlag.archive]),
    _box2('Projects'),
  ];
  mail.Mailbox? _selected;

  @override
  mail.Mailbox? get selectedMailbox => _selected ?? boxes.first;

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 20),
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async => boxes;

  @override
  Future<List<mail.MimeMessage>> fetchMessages({
    mail.Mailbox? mailbox,
    int count = 20,
    int page = 1,
    mail.FetchPreference fetchPreference =
        mail.FetchPreference.fullWhenWithinSize,
  }) async {
    _selected = mailbox ?? _selected;
    return <mail.MimeMessage>[for (final e in _inbox) _envelope(e.$1)];
  }

  @override
  Future<mail.Mailbox> selectMailbox(
    mail.Mailbox mailbox, {
    bool enableCondStore = false,
    mail.QResyncParameters? qresync,
  }) async => _selected = mailbox;

  @override
  Future<mail.MimeMessage> fetchMessageContents(
    mail.MimeMessage message, {
    int? maxSize,
    bool markAsSeen = false,
    List<mail.MediaToptype>? includedInlineTypes,
    Duration? responseTimeout,
  }) async => message;

  @override
  Future<void> sendMessage(
    mail.MimeMessage message, {
    mail.MailAddress? from,
    bool appendToSent = true,
    bool supportUnicode = false,
    mail.Mailbox? sentMailbox,
    bool use8BitEncoding = false,
    List<mail.MailAddress>? recipients,
  }) async {}
}

final class _Loader implements StudioMailMessageLoader {
  @override
  Future<Uint8List> fetch(mail.Mailbox mailbox, mail.MimeMessage header) async {
    final uid = header.uid ?? _reportUid;
    final text = uid == _reportUid ? _reportMessage() : _plainMessage(uid);
    return Uint8List.fromList(utf8.encode(text));
  }

  @override
  Future<void> markRead(mail.Mailbox mailbox, mail.MimeMessage header) async {}

  @override
  void cancel() {}

  @override
  void dispose() {}
}

final class _CredentialStore extends Fake implements StudioMailCredentialStore {
  @override
  Future<StudioMailCredentials?> load() async => null;

  @override
  Future<bool> save(StudioMailCredentials credentials) async => true;

  @override
  Future<bool> clear() async => true;
}

// ---------------------------------------------------------------------------
// Hosts

// The hosts' verification runs on real I/O, which the widget-test clock does
// not drive; a refresh started from a widget (the Downloads dialog) would
// never finish there. Once the test has refreshed them in real time, later
// widget-initiated refreshes reuse that verified state.
class _SettledHunspell extends NativeStudioHunspellHost {
  _SettledHunspell({required super.root, required super.libraryPath});

  bool settled = false;

  @override
  Future<void> refresh() => settled ? Future<void>.value() : super.refresh();
}

class _SettledMorphology extends NativeStudioArabicMorphHost {
  _SettledMorphology({required super.root, required super.libraryPath});

  bool settled = false;

  @override
  Future<void> refresh() => settled ? Future<void>.value() : super.refresh();
}

// ---------------------------------------------------------------------------
// Capture helpers

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  final shotsDir = Platform.environment['QUDS_SHOTS_DIR'];

  testWidgets('App Store screenshots', (tester) async {
    final app = _required('QUDS_STUDIO_APP');
    final data = _required('QUDS_STUDIO_DATA');
    final out = Directory(shotsDir ?? _required('QUDS_SHOTS_DIR'))
      ..createSync(recursive: true);
    const harper = String.fromEnvironment('QUDS_HARPER_LIBRARY');
    final frameworks = '$app/Contents/Frameworks';
    expect(harper, startsWith(frameworks));
    final problems = <String>[];

    await tester.runAsync(_loadFonts);
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);

    // Native hosts, as in the bundle gates.
    final root = Directory(data);
    final hunspell = _SettledHunspell(
      root: root,
      libraryPath: '$frameworks/libquds_proofing_hunspell.dylib',
    );
    final morph = _SettledMorphology(
      root: root,
      libraryPath: '$frameworks/libquds_arabic_morph.dylib',
    );
    final languageId = BundledStudioLanguageIdHost(
      createIdentifier: (model) => Cld3LanguageIdentifier(
        model: model,
        nativeLibraryPath: '$frameworks/libquds_language_id.dylib',
      ),
    );
    final bundled = detectBundledSpacyLibrary(const {
      'QUDS_SPACY_BUNDLED': '1',
    }, executable: '$app/Contents/MacOS/CrispOffice');
    expect(bundled, isNotNull, reason: 'no spacy-native.json in $app');
    final spacy = NativeStudioSpacyHost(
      root: Directory('$data/spacy'),
      environment: const {},
      platform: SpacyPlatform.macosArm64,
      bundledLibrary: bundled,
    );
    await tester.runAsync(() async {
      await hunspell.refresh();
      await morph.refresh();
      await spacy.refresh();
      await HttpOverrides.runWithHttpOverrides(() async {
        for (final item in hunspell.statuses) {
          if (!item.installed) await hunspell.install(item.bundle);
        }
        if (!morph.status.installed) await morph.install();
        if (spacy.status.source == StudioSpacySource.none) {
          await spacy.install();
        }
      }, _RealHttpOverrides());
      if (!spacy.status.analysisEnabled) {
        await spacy.setAnalysisEnabled(true);
      }
      await languageId.load();
    });
    expect(hunspell.statuses.single.installed, isTrue);
    expect(morph.status.loaded, isTrue, reason: morph.status.problem);
    expect(languageId.detector, isNotNull, reason: languageId.problem);
    expect(spacy.status.grammarOffered, isTrue, reason: '${spacy.status}');
    studioHunspellHost = hunspell;
    studioArabicMorphHost = morph;
    studioLanguageIdHost = languageId;
    studioSpacyHost = spacy;

    tester.view.physicalSize = _logical * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    final boundary = GlobalKey();

    Future<void> settle([int rounds = 6]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> waitFor(
      String what,
      bool Function() done, {
      Duration limit = const Duration(seconds: 90),
    }) async {
      final watch = Stopwatch()..start();
      while (!done()) {
        if (watch.elapsed > limit) {
          problems.add('timed out waiting for $what');
          return;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpStudio(SuiteWorkspace workspace) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(2);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: QudsOfficeStudioApp(home: workspace),
        ),
      );
      await settle();
    }

    Future<void> capture(String name) async {
      await settle(3);
      // Let the caret blink settle into its visible phase.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: _pixelRatio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${out.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('captured $name.png ${image.width}x${image.height}');
        image.dispose();
      });
      final error = tester.takeException();
      if (error != null) problems.add('$name: $error');
    }

    WordEditorController word() =>
        tester.widget<QudsWordEditor>(find.byType(QudsWordEditor)).controller;

    Map<String, Set<String>> findings(WordEditorController controller) {
      final byText = <String, Set<String>>{};
      controller.proofing.findingsByParagraph.forEach((paragraph, list) {
        byText[paragraph.text] = {
          for (final f in list) '${f.providerId}/${f.ruleId}',
        };
      });
      return byText;
    }

    // --- 2: German grammar suggestion -------------------------------------
    await pumpStudio(
      SuiteWorkspace(
        initialWord: (
          name: 'German practice.docx',
          document: _germanPractice(),
        ),
      ),
    );
    {
      final controller = word();
      // Toggle the opt-in so the workspace registers the manual provider.
      await tester.runAsync(() async {
        if (spacy.status.grammarEnabled) await spacy.setGrammarEnabled(false);
        await spacy.setGrammarEnabled(true);
      });
      await settle(10);
      controller.openReviewPane();
      WordProofingIssue? grammar() => controller.proofing.summary.issues
          .where((i) => i.finding.providerId == spacyGrammarProviderId)
          .firstOrNull;
      final watch = Stopwatch()..start();
      // Retry until one explicit check completes for every provider (a
      // provider can miss its deadline on a loaded machine).
      while ((grammar() == null || !controller.proofing.summary.complete) &&
          watch.elapsed < const Duration(seconds: 240)) {
        await tester.runAsync(() async {
          try {
            await controller.checkDocumentProofing().timeout(
              const Duration(seconds: 40),
            );
          } on Object catch (error) {
            // ignore: avoid_print
            print('check: $error');
          }
        });
        await settle(4);
      }
      final issue = grammar();
      if (!controller.proofing.summary.complete) {
        problems.add(
          'incomplete check: ${controller.proofing.summary.statusMessage}',
        );
      }
      if (issue == null) {
        problems.add(
          'no spaCy grammar finding: ${controller.proofing.summary.statusMessage}',
        );
      } else {
        // ignore: avoid_print
        print(
          'grammar: ${issue.finding.originalText} -> '
          '${issue.finding.replacements}',
        );
        expect(issue.finding.originalText, 'schläft');
        expect(issue.finding.replacements, contains('schlafen'));
        final index = controller.document.paragraphs.toList().indexWhere(
          (p) => p.text == _germanWrong,
        );
        controller.caret
          ..paragraphIndex = index
          ..logicalIndex = _germanWrong.indexOf('schläft') + 3
          ..collapseSelection();
        controller.selectProofingIssue(issue, reveal: false);
        controller.refreshView();
      }
      await settle(6);
      await capture('02-german-grammar');
    }

    // --- 1, 6, 3, 4, 5: one workspace ------------------------------------
    await pumpStudio(
      SuiteWorkspace(
        initialWord: (
          name: 'Quarterly Partner Update.docx',
          document: _partnerUpdate(),
        ),
        initialWorkbook: (
          name: 'Regional Sales 2026.xlsx',
          workbook: _salesWorkbook(),
        ),
        initialPresentation: (
          name: 'Product Launch.pptx',
          presentation: _launchDeck(),
        ),
        mailBuilder: (strings, chrome) => StudioMailDialog(
          strings: strings,
          chromeBuilder: chrome,
          clientFactory: (_) => _Client(),
          messageLoaderFactory: (_) => _Loader(),
          credentialStore: _CredentialStore(),
          draftStoreFactory: MemoryStudioMailDrafts().open,
        ),
      ),
    );

    // 1: Word, English and Arabic with live proofing.
    {
      final controller = word();
      bool ready() {
        final found = findings(controller);
        bool has(String needle, bool Function(String) rule) => found.entries
            .any((e) => e.key.contains(needle) && e.value.any(rule));
        return has('recieved', (r) => r.startsWith('harper')) &&
            has('الى', (r) => r.contains('ar.') || r.startsWith('hunspell')) &&
            has(
              'المرحله',
              (r) => r.contains('ar.') || r.startsWith('hunspell'),
            );
      }

      // A host that finishes loading reconfigures proofing and starts a
      // fresh check; wait until the findings are back and checking is idle.
      bool idle() => ready() && !controller.proofing.checking;
      await waitFor('English and Arabic proofing', idle);
      await settle(10);
      await waitFor('settled proofing', idle);
      // ignore: avoid_print
      print('findings: ${findings(controller)}');
      for (final mistake in _englishMistakes) {
        if (!findings(controller).keys.any((k) => k.contains(mistake))) {
          problems.add('no finding in the paragraph with "$mistake"');
        }
      }
      controller.caret
        ..paragraphIndex = 0
        ..logicalIndex = 0
        ..collapseSelection();
      controller.refreshView();
      await capture('01-word-english-arabic');
      if (!idle()) problems.add('01: proofing changed while capturing');
    }

    // 6: Downloads manager with the installed language packs.
    await tester.runAsync(() async {
      await hunspell.refresh();
      await morph.refresh();
    });
    hunspell.settled = true;
    morph.settled = true;
    {
      final context = tester.element(find.byType(QudsWordEditor));
      unawaited(
        showStudioDownloadsManager(
          context,
          language: StudioLanguage.en,
          fontPacks: FakeFontPacks(),
        ),
      );
      await settle(4);
      // The dialog refreshes every host before enabling its actions.
      await waitFor('the Downloads refresh', () {
        final remove = find.ancestor(
          of: find.text('Remove'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        return remove.evaluate().isNotEmpty &&
            tester.widget<ButtonStyleButton>(remove.first).enabled;
      }, limit: const Duration(seconds: 60));
      await capture('06-downloads');
      Navigator.of(context).pop();
      await settle(3);
    }

    // 3: Spreadsheet.
    {
      await tester.tap(find.byTooltip(_strings.spreadsheets).first);
      await settle();
      final sheet = tester
          .widget<QudsSheetEditor>(find.byType(QudsSheetEditor))
          .controller;
      sheet.selection.selectCell(const SmlCellRef(5, 3));
      sheet.refresh();
      await capture('03-excel');
    }

    // 4: Presentation, editing the second slide.
    {
      await tester.tap(find.byTooltip(_strings.presentations).first);
      await settle();
      final slides = tester
          .widget<QudsSlideEditor>(find.byType(QudsSlideEditor))
          .controller;
      slides.setActiveSlide(2);
      await settle(2);
      slides.selectShape(slides.slide.shapes.last);
      await capture('04-powerpoint');
    }

    // 5: Mail reader with an attachment.
    {
      await tester.tap(find.byTooltip(_strings.mail).first);
      await settle();
      await tester.enterText(_field(_strings.emailAddress), 'anna@example.com');
      await tester.enterText(_field(_strings.password), 'example-password');
      await tester.tap(
        find.widgetWithText(SwitchListTile, _strings.manualServers),
      );
      await settle(2);
      await tester.enterText(_field(_strings.imapHost), 'imap.example.com');
      await tester.enterText(_field(_strings.smtpHost), 'smtp.example.com');
      final connect = find.widgetWithText(FilledButton, _strings.connect);
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await settle(8);
      await tester.tap(
        find.text('Q4 partner report and agenda for Thursday').first,
      );
      await settle(8);
      await capture('05-mail');
    }

    // Release native transports (bounded disposal grace timers).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 11));
    await tester.runAsync(() async {
      morph.dispose();
      languageId.dispose();
    });

    // ignore: avoid_print
    print('problems: $problems');
    debugDisableShadows = true;
    expect(problems, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
