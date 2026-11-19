import 'dart:convert';
import 'package:quds_office_engine/quds_office_automation.dart';

String source({required int unary, required int blocks}) {
  final lines = <String>['Option Explicit', 'Sub Main()'];
  void openBlocks() {
    for (var level = 0; level < blocks; level++) {
      lines.add(level.isEven
          ? 'If True Then'
          : 'With Worksheets(1).Range("A1")');
    }
  }
  void closeBlocks() {
    for (var level = blocks - 1; level >= 0; level--) {
      lines.add(level.isEven ? 'End If' : 'End With');
    }
  }
  final prefix = List.filled(unary, '+').join(' ');
  openBlocks();
  lines.add('Worksheets(1).Range("A1").Value2 = $prefix F1()');
  closeBlocks();
  lines.add('End Sub');
  for (var index = 1; index <= 31; index++) {
    lines.add('Function F$index() As Long');
    openBlocks();
    final value = index == 31 ? '1' : 'F${index + 1}()';
    lines.add('F$index = $prefix $value');
    closeBlocks();
    lines.add('End Function');
  }
  return lines.join('\n');
}

void main() {
  const cases = <({String name, int unary, int blocks})>[
    (name: '32 frames and 50 unary operators', unary: 50, blocks: 0),
    (name: '32 frames and 20 nested blocks', unary: 0, blocks: 20),
    (name: '32 frames, 50 unary operators, 20 nested blocks', unary: 50, blocks: 20),
  ];
  for (final scenario in cases) {
    final text = source(unary: scenario.unary, blocks: scenario.blocks);
    try {
      final macro = const OfficeVbaMacroLanguage().compile(OfficeMacroSource(
        language: 'vba-excel',
        source: text,
        format: OfficeMacroFormat.xlsx,
        moduleName: 'DepthStress',
        entryPoint: 'Main',
      ));
      if (macro.steps.length != 1 ||
          macro.steps.single.arguments['value'] != 1) {
        throw StateError('Unexpected plan ${macro.encode()}');
      }
      print(jsonEncode(<String, Object>{
        'case': scenario.name,
        'sourceBytes': utf8.encode(text).length,
        'operations': macro.steps.length,
        'value': 1,
        'status': 'passed',
      }));
    } catch (error, stack) {
      print(jsonEncode(<String, Object>{
        'case': scenario.name,
        'status': 'failed',
        'error': error.toString(),
      }));
      print(stack);
      rethrow;
    }
  }
}
