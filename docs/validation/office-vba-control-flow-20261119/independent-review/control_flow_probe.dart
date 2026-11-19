import 'package:quds_office_engine/quds_office_automation.dart';

int cases = 0;
OfficeMacro compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    source: source,
    format: OfficeMacroFormat.xlsx,
    moduleName: 'IndependentProbe',
    entryPoint: 'Main',
  ),
);

void expect(bool condition, String message) {
  cases++;
  if (!condition) throw StateError(message);
}

void reject(String source, {String? code}) {
  try {
    compile(source);
  } on OfficeVbaCompileException catch (error) {
    expect(code == null || error.code == code,
        'Expected $code, got ${error.code}: ${error.message}');
    expect(error.line > 0 && error.column > 0, 'Invalid diagnostic position');
    return;
  }
  throw StateError('Unexpectedly accepted source: $source');
}

String wrap(String body) => 'Sub Main()\n$body\nEnd Sub';

String nested(int depth, String body) {
  final open = <String>[];
  final close = <String>[];
  for (var index = 0; index < depth; index++) {
    final pair = switch (index % 4) {
      0 => ('Do While True', 'Loop'),
      1 => ('While True', 'Wend'),
      2 => ('Select Case 1\nCase 1', 'End Select'),
      _ => ('With Worksheets(1)', 'End With'),
    };
    open.add(pair.$1);
    close.insert(0, pair.$2);
  }
  return '${open.join('\n')}\n$body\n${close.join('\n')}';
}

String depthProgram(int frames, int blocks, int unary) {
  final operators = List<String>.filled(unary, '+').join();
  final mainBody = 'Worksheets(1).Range("A1").Value2 = ${operators}F1()\nExit Sub';
  final source = StringBuffer(wrap(nested(blocks, mainBody)));
  for (var i = 1; i < frames; i++) {
    final value = i == frames - 1 ? '42' : 'F${i + 1}()';
    final body = 'F$i = $operators$value\nExit Function';
    source.write('\nFunction F$i() As Long\n${nested(blocks, body)}\nEnd Function');
  }
  return source.toString();
}

void main() {
  const invalid = <String>[
    'Do\nWend', 'While True\nLoop', 'Select Case 1\nLoop',
    'Do\nEnd Select', 'While True\nEnd Select',
    'Do While True\nLoop While False',
    'Do Until False\nLoop Until True',
    'Do While True\nLoop Until True',
    'Do\nLoop While', 'While\nWend',
    'Select 1\nEnd Select', 'Select Case\nEnd Select',
    'Select Case 1\nCase Else\nCase 1\nEnd Select',
    'Select Case 1\nCase Else\nCase Else\nEnd Select',
    'Select Case 1\nCase Is\nEnd Select',
    'Select Case 1\nCase Is Like 1\nEnd Select',
    'Select Case 1\nCase 1 To\nEnd Select',
    'Select Case 1\nCase To 1\nEnd Select',
    'Select Case 1\nCase 1,\nEnd Select',
    'Select Case 1\nCase 1 To 2 To 3\nEnd Select',
    'Do\nExit While\nLoop', 'While True\nExit Do\nWend',
    'Select Case 1\nCase 1\nExit Do\nEnd Select',
  ];
  for (final body in invalid) {
    reject(wrap(body));
    reject('Sub Main()\nEnd Sub\nSub Unused()\n$body\nEnd Sub');
  }

  // Mismatched inner closing tokens must never escape to a surrounding owner.
  const pairs = <(String, String)>[
    ('Do', 'Loop'), ('While True', 'Wend'),
    ('Select Case 1\nCase 1', 'End Select'),
    ('With Worksheets(1)', 'End With'),
    ('If True Then', 'End If'),
  ];
  for (final outer in pairs) {
    for (final inner in pairs) {
      if (outer.$2 == inner.$2) continue;
      reject(wrap('${outer.$1}\n${inner.$1}\n${outer.$2}\n${inner.$2}'));
    }
  }

  for (final inactive in <String>[
    'Do While False\nUnknown\nLoop',
    'While False\nUnknown\nWend',
    'Select Case 1\nCase 1\nExit Sub\nCase 2\nUnknown\nEnd Select',
    'Select Case 1\nCase 1, Missing()\nEnd Select',
    'Select Case 1\nCase 1 To Missing()\nEnd Select',
    'Do\nExit Do\nUnknown\nLoop',
  ]) {
    reject(wrap(inactive), code: 'vba_unsupported');
  }

  for (final site in <String>[
    'Do While Again()\nLoop',
    'Do\nExit Do\nLoop While Again()',
    'While Again()\nWend',
    'Select Case Again()\nEnd Select',
    'Select Case True\nCase True, Again()\nEnd Select',
  ]) {
    reject('${wrap('')}\nFunction Again() As Boolean\n$site\nEnd Function',
        code: 'vba_unsupported');
  }

  final max = compile(depthProgram(32, 32, 50));
  expect(max.steps.length == 1, 'Combined limits must emit one operation');
  expect(max.steps.single.arguments['value'] == 42, 'Wrong depth result');
  reject(depthProgram(33, 32, 50), code: 'vba_limit_exceeded');
  reject(depthProgram(32, 33, 50), code: 'vba_limit_exceeded');

  // Variant runtime tests must reject non-Boolean loop conditions.
  for (final loop in <String>[
    'Do While n\nLoop', 'Do Until n\nLoop',
    'Do\nLoop While n', 'Do\nLoop Until n', 'While n\nWend',
  ]) {
    reject(wrap('Dim n As Variant\nn = 1\n$loop'), code: 'vba_type_error');
  }

  // A callee cannot reach its caller's loop or With context.
  reject('${wrap('Do\nCall Helper()\nLoop')}\nSub Helper()\nExit Do\nEnd Sub',
      code: 'vba_unsupported');
  reject('${wrap('With Worksheets(1)\nDo While Helper()\nLoop\nEnd With')}\n'
      'Function Helper() As Boolean\n.Range("A1").Value2 = 1\nEnd Function',
      code: 'vba_unsupported');

  print('Independent control flow probe passed: $cases checks; '
      '32 frames x 32 mixed blocks x 50 unary operators.');
}
