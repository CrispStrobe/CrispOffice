import 'dart:convert';
import 'baseline_compiler.dart' as baseline;
import 'candidate_compiler.dart' as candidate;
import 'package:quds_office_engine/quds_office_automation.dart';

void main() {
  const source = "Sub Main()\n  Helper (1) = 2\nEnd Sub\nSub Helper(ByVal flag As Boolean)\n  Worksheets(1).Range(\"A1\").Value2 = flag\nEnd Sub";
  for (final (name, language) in <(String, OfficeMacroLanguage)>[
    ('baseline', const baseline.OfficeVbaMacroLanguage()),
    ('candidate', const candidate.OfficeVbaMacroLanguage()),
  ]) {
    try {
      final macro = language.compile(OfficeMacroSource(language: 'vba-excel',
        source: source, format: OfficeMacroFormat.xlsx,
        moduleName: 'Probe', entryPoint: 'Main'));
      print(jsonEncode({'compiler': name, 'steps': macro.steps.map((step) => step.arguments).toList()}));
    } on OfficeMacroException catch (error) {
      print(jsonEncode({'compiler': name, 'error': error.toJson()}));
    }
  }
}
