import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_measurements_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_measurements.bas';
const _target = 'ActiveDocument.Paragraphs(1).Format';

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'Measurements',
    'source': source,
  },
};

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'actual measurement BAS preserves DOCM and repeats after saving',
    () async {
      final result = await portable.runWordMeasurementExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 13);
      expect(result['revisionAfterReplay'], 2);
      expect(result['additionalReopens'], 2);
      expect(result['opaqueVbaPreserved'], isTrue);
      expect(result['nativeIndentGroupReplaced'], isTrue);
    },
  );

  test(
    'converted plans respect native policy, limits and late rollback',
    () async {
      final result = await portable.runWordMeasurementGuards();
      expect(result['refusedPolicies'], 3);
      expect(result['completeAllowlistRevision'], 1);
      expect(result['lateFailureStep'], 1);
      expect(result['validateAndRunRollback'], isTrue);
    },
  );

  test(
    'cancellation refuses converted edits without publishing bytes',
    () async {
      final input = portable.wordMeasurementInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final cancellation = OfficeMacroCancellation()..cancel();
      final plan = portable.wordMeasurementPlan(
        '$_target.LeftIndent = InchesToPoints(0.5)',
      );
      await expectLater(
        session.run(plan, cancellation: cancellation),
        throwsA(
          isA<OfficeMacroException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'late failure preserves a previously published revision and recording',
    () async {
      final session = OfficeMacroSession(
        portable.wordMeasurementInput(),
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Existing successful edit');
      await session.callTool('docx.paragraphFormat', {
        'paragraph': 0,
        'left': 18,
      });
      final previous = session.bytes;
      final plan = portable.wordMeasurementPlan('''
$_target.LeftIndent = InchesToPoints(0.5)
ActiveDocument.Paragraphs(99).Format.RightIndent = PicasToPoints(3)
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>()
                .having((error) => error.code, 'code', 'operation_failed')
                .having((error) => error.stepIndex, 'step', 1),
          ),
        );
        expect(session.bytes, previous);
        expect(session.revision, 1);
      }
      final recording = session.stopRecording();
      expect(recording.steps, hasLength(1));
      expect(recording.steps.single.arguments['left'], 18);
    },
  );

  test(
    'MCP compiles the exact BAS, validates, then publishes the same plan',
    () async {
      final input = portable.wordMeasurementInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final compiled = await adapter.callTool(
        'office_macro_compile',
        _sourceArguments(File(_example).readAsStringSync()),
      );
      expect(compiled['isError'], isFalse, reason: '$compiled');
      final arguments = <String, Object?>{
        'macro': _structured(compiled)['macro'],
      };
      final validation = await adapter.callTool(
        'office_macro_validate',
        arguments,
      );
      expect(validation['isError'], isFalse, reason: '$validation');
      expect(_structured(validation)['completedSteps'], 13);
      expect(_structured(validation)['validatedOnly'], isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
      final result = await adapter.callTool('office_macro_run', arguments);
      expect(result['isError'], isFalse, reason: '$result');
      expect(_structured(result)['completedSteps'], 13);
      expect(session.revision, 1);
      portable.checkWordMeasurementExample(session.bytes, input);
    },
  );

  for (final (expression, code) in [
    ('InchesToPoints(9007199254740991)', 'vba_type_error'),
    ('CentimetersToPoints(1)', 'vba_type_error'),
    ('MillimetersToPoints(True)', 'vba_type_error'),
  ]) {
    test('MCP refuses $expression without returning a partial plan', () async {
      final input = portable.wordMeasurementInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final result = await OfficeMacroMcp(session).callTool(
        'office_macro_compile',
        _sourceArguments('''
Sub Main()
  $_target.LeftIndent = InchesToPoints(0.5)
  $_target.RightIndent = $expression
End Sub
'''),
      );
      expect(result['isError'], isTrue);
      expect(_structured(result).containsKey('macro'), isFalse);
      final error = _structured(result)['error']! as Map<String, Object?>;
      expect(error['code'], code);
      expect(error['moduleName'], 'Measurements');
      expect(error['line'], greaterThan(0));
      expect(error['column'], greaterThan(0));
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test(
    'CLI executes the committed measurement BAS into a preserved DOCM',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-measurements-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordMeasurementInput());
      final before = input.readAsBytesSync();
      final output = File('${directory.path}/result.docm');
      final result = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        File(_example).absolute.path,
        output.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final report =
          jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(report['language'], 'vba-word');
      expect(input.readAsBytesSync(), before);
      final guard = (await WordPackagePreservation.capture(
        before,
        input.path,
      ))!;
      await guard.validateSaved(output.readAsBytesSync());
      portable.checkWordMeasurementExample(output.readAsBytesSync(), before);
    },
    timeout: officeMacroCliTestTimeout,
  );

  test(
    'CLI failed converted plan leaves input and existing output unchanged',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-measurement-refusal-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordMeasurementInput());
      final before = input.readAsBytesSync();
      final source = File('${directory.path}/late-failure.bas')
        ..writeAsStringSync('''
Sub Main()
  $_target.LeftIndent = InchesToPoints(0.5)
  ActiveDocument.Paragraphs(99).Format.RightIndent = PicasToPoints(3)
End Sub
''');
      final output = File('${directory.path}/result.docm')
        ..writeAsStringSync('Previous output must survive');
      final previousOutput = output.readAsBytesSync();
      final result = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source.path,
        output.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(input.readAsBytesSync(), before);
      expect(output.readAsBytesSync(), previousOutput);
    },
    timeout: officeMacroCliTestTimeout,
  );
}
