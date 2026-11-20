import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Object? _canonical(Object? value) {
  if (value is num && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

Map<String, Object?> _step(
  String operation,
  String shape,
  Map<String, Object?> fields,
) => <String, Object?>{
  'tool': 'pptx.$operation',
  'arguments': <String, Object?>{
    'topLevel': true,
    'slide': 0,
    'shapeName': shape,
    ...fields,
  },
};

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Pass the actual report BAS path');
  final source = File(args.single).readAsStringSync();
  // Omit entryPoint deliberately: this checks the public default Main behavior.
  final plan = OfficeMacroLanguages().compile(
    OfficeMacroSource(
      language: 'vba-powerpoint',
      format: OfficeMacroFormat.pptx,
      moduleName: 'PowerPointReportExample',
      source: source,
    ),
  );
  final expected = <Map<String, Object?>>[
    _step('shapeText', 'Title', {'text': 'Weekly supply report'}),
    for (final field in <Map<String, Object?>>[
      {'font': 'Arial'},
      {'size': 28.5},
      {'bold': true},
      {'italic': false},
      {'underline': false},
      {'color': '1F4E79'},
      {'alignment': 'center'},
    ])
      _step('shapeFormat', 'Title', field),
    for (final field in <Map<String, Object?>>[
      {'x': 24},
      {'y': 36},
      {'width': 640},
      {'height': 72},
    ])
      _step('shapeGeometry', 'Title', field),
    _step('shapeText', 'Body', {
      'text': 'Source records: 3; total units: 14',
    }),
    for (final field in <Map<String, Object?>>[
      {'font': 'Arial'},
      {'size': 18},
      {'bold': false},
      {'underline': false},
      {'alignment': 'left'},
    ])
      _step('shapeFormat', 'Body', field),
  ];
  final actual = plan.steps.map((step) => step.toJson()).toList();
  if (jsonEncode(_canonical(actual)) != jsonEncode(_canonical(expected))) {
    throw StateError('The committed example did not produce the 18 specified '
        'writes from default Main: ${jsonEncode(actual)}');
  }
  final original = SlideSerializer().writeBytes(
    PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          shapes: <PmlShape>[
            PmlShape(id: 2, name: 'Title', text: 'Initial title'),
            PmlShape(id: 3, name: 'Body', text: 'Initial body'),
            PmlShape(id: 4, name: 'Untouched', text: 'Keep me'),
          ],
        ),
      ],
    ),
  );
  final session = OfficeMacroSession(original, format: OfficeMacroFormat.pptx);
  await session.validate(plan);
  if (session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(original)) {
    throw StateError('Example validation mutated the input deck');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  final deck = SlideDeserializer().readBytes(session.bytes);
  final title = deck.slides.single.shapes[0];
  final body = deck.slides.single.shapes[1];
  final titleRuns = title.resolvedRichText.expand((p) => p.runs).toList();
  final bodyRuns = body.resolvedRichText.expand((p) => p.runs).toList();
  if (session.revision != 1 ||
      title.text != 'Weekly supply report' ||
      title.fontSizePt != 28.5 ||
      title.textColor != '1F4E79' ||
      title.textAlign != PmlTextAlign.center ||
      title.transform.xPoints != 24 ||
      title.transform.yPoints != 36 ||
      title.transform.widthPoints != 640 ||
      title.transform.heightPoints != 72 ||
      titleRuns.isEmpty ||
      titleRuns.any((r) => r.fontFamily != 'Arial' || !r.bold || r.italic || r.underline) ||
      body.text != 'Source records: 3; total units: 14' ||
      body.fontSizePt != 18 ||
      body.textAlign != PmlTextAlign.left ||
      bodyRuns.isEmpty ||
      bodyRuns.any((r) => r.fontFamily != 'Arial' || r.bold || r.underline) ||
      deck.slides.single.shapes[2].text != 'Keep me') {
    throw StateError('The example did not survive native PPTX write/readback');
  }
  print(jsonEncode({
    'source': 'example/macros/powerpoint_report.bas',
    'defaultEntryPoint': 'Main',
    'nativeOperationCount': plan.steps.length,
    'textWrites': 2,
    'formatWrites': 12,
    'geometryWrites': 4,
    'titleText': title.text,
    'bodyText': body.text,
    'computedTotal': 14,
    'validationNonPublication': true,
    'nativeReadback': true,
    'unaddressedShapePreserved': true,
    'revision': session.revision,
    'nativeOperations': actual,
  }));
}
