import 'dart:convert';
import 'package:quds_office_engine/quds_office_automation.dart';
const target = 'ActiveDocument.Paragraphs(1).Range';
OfficeMacro source(String code) => const OfficeVbaWordMacroLanguage().compile(OfficeMacroSource(language: 'vba-word', format: OfficeMacroFormat.docx, moduleName: 'IndependentNumericReview', source: code));
OfficeMacro body(String code) => source('Option Explicit\nSub Main()\n$code\nEnd Sub\n');
final results = <Map<String, Object?>>[];
void check(String name, Object? actual, Object? expected) {
  final success = jsonEncode(actual) == jsonEncode(expected);
  results.add({'name': name, 'success': success, 'actual': actual, 'expected': expected});
}
void value(String expression, String expected) {
  final result = body('$target.InsertBefore CStr($expression)');
  check(expression, result.steps.single.arguments['text'], expected);
}
void refuse(String name, String code, String expected, {bool whole = false}) {
  try {
    whole ? source(code) : body(code);
    check(name, 'accepted', expected);
  } on OfficeVbaCompileException catch (error) {
    check(name, error.code, expected);
    check('$name positioned diagnostic', error.line > 0 && error.column > 0, true);
  }
}
void main() {
  for (final intrinsic in ['Abs', 'Int', 'Fix', 'Sgn']) {
    value('$intrinsic(-0.0)', '0');
    value('$intrinsic(Empty)', '0');
    refuse('$intrinsic rejects overflow operand', '$target.InsertBefore CStr($intrinsic(9007199254740992))', 'vba_limit_exceeded');
    refuse('$intrinsic checks inactive text input', 'If False Then\n$target.InsertBefore CStr($intrinsic("4"))\nEnd If', 'vba_type_error');
    refuse('$intrinsic rejects inactive object input', 'If False Then\n$target.InsertBefore CStr($intrinsic(ActiveDocument))\nEnd If', 'vba_type_error');
    refuse('$intrinsic rejects qualified form', '$target.InsertBefore CStr(Application.$intrinsic(-1))', 'vba_unsupported');
    refuse('$intrinsic local reserved name', 'Dim ${intrinsic.toUpperCase()} As Double', 'vba_name_error');
  }
  value('Abs(-5e-324)', '5e-324');
  value('Int(-5e-324)', '-1');
  value('Fix(-5e-324)', '0');
  value('Sgn(-5e-324)', '-1');
  value('Int(5e-324)', '0');
  value('Fix(5e-324)', '0');
  value('Sgn(5e-324)', '1');
  value('Abs(-9007199254740991)', '9007199254740991');
  value('Int(9007199254740991)', '9007199254740991');
  value('Fix(-9007199254740991)', '-9007199254740991');
  value('Sgn(-9007199254740991)', '-1');
  value('Sgn(9007199254740991)', '1');
  value('Abs(CDbl("-2.5"))', '2.5');
  value('Int(CDbl("-2.5"))', '-3');
  value('Fix(CDbl("-2.5"))', '-2');
  value('Sgn(CDbl("-2.5"))', '-1');
  value('IsNull(Abs(Null))', 'True');
  value('IsNull(Int(Fix(Abs(CVar(Null)))))', 'True');
  refuse('nested Null reaches Sgn refusal', '$target.InsertBefore CStr(Sgn(Abs(Null)))', 'vba_invalid_use_of_null');
  refuse('Null refuses typed scalar publication', 'Dim n As Double\nn = Fix(Null)', 'vba_invalid_use_of_null');
  check('unexecuted Sgn Null remains unexecuted', body('If False Then\n$target.InsertBefore CStr(Sgn(Null))\nEnd If').steps.length, 0);
  for (final intrinsic in ['Abs', 'Int', 'Fix', 'Sgn']) {
    final result = source('''
Option Explicit
Function Arg() As Double
  $target.InsertBefore "once"
  Arg = -3.25
End Function
Sub Main()
  $target.InsertBefore CStr($intrinsic(Arg()))
End Sub
''');
    check('$intrinsic argument evaluated once', result.steps.map((s) => s.arguments['text']).toList(), ['once', {'Abs': '3.25', 'Int': '-4', 'Fix': '-3', 'Sgn': '-1'}[intrinsic]]);
  }
  final nullHelper = source('''
Function Arg() As Variant
  $target.InsertBefore "once"
  Arg = Null
End Function
Sub Main()
  $target.InsertBefore CStr(IsNull(Abs(Arg())))
End Sub
''');
  check('Null helper is evaluated once', nullHelper.steps.map((s) => s.arguments['text']).toList(), ['once', 'True']);
  refuse('parameter reserved name', 'Sub Helper(ByVal fIx As Double)\nEnd Sub\nSub Main()\nEnd Sub', 'vba_name_error', whole: true);
  refuse('procedure reserved name', 'Function aBs() As Double\naBs = 1\nEnd Function\nSub Main()\nEnd Sub', 'vba_name_error', whole: true);
  final aliases = body('''
Dim f As Font
Set f = ActiveDocument.Paragraphs(3).Range.Font
With f
  .Position = Int(-2.5)
End With
''');
  check('typed alias preserves original target', aliases.steps.single.arguments, {'paragraph': 2, 'position': -3});
  print(jsonEncode({'success': results.every((r) => r['success'] == true), 'checks': results.length, 'results': results}));
  if (results.any((r) => r['success'] != true)) throw StateError('Independent probe mismatch');
}
