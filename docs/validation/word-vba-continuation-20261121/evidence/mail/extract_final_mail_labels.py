from pathlib import Path
import hashlib,json
base=Path('/workspace/scratch/dca92fad5f00');repo=base/'quds_office_suite';val=base/'validation'
ui_path='packages/quds_mail_ui/lib/src/workspace/message_list.dart'
studio_path='packages/quds_office_editor/example/lib/studio_mail_workspace_strings.dart'
ui=(repo/ui_path).read_text();studio=(repo/studio_path).read_text()
def extract(text,start_marker,end_marker):
    start=text.index(start_marker);end=text.index(end_marker,start)+len(end_marker)
    return text[start:end]
default=extract(ui,'String _defaultSearchError(','\n};')
localized=extract(studio,'  String _mailHeaderSearchError(','\n  };')
pattern=extract(ui,'final _searchExampleLine = RegExp(','\n);')
routing=extract(ui,'textDirection: _searchExampleLine.hasMatch(line)',': null,').removeprefix('textDirection: ').removesuffix(',')
help_value=extract(studio,'    searchHelpText: _text(','\n    ),').removeprefix('    searchHelpText: ').removesuffix(',')
out="import 'dart:convert';\nimport 'package:quds_mail_core/quds_mail_core.dart';\n"+default+'\n'+pattern+'''
enum Language { en, de, ar }
enum TextDirection { ltr, rtl }
TextDirection? sourceDirection(String line) => '''+routing+''';
class Strings {
  const Strings(this.language);
  final Language language;
  String _text(String en, String de, String ar) => switch(language) {
    Language.en => en, Language.de => de, Language.ar => ar,
  };
'''+localized+'\n  String help() => '+help_value+''';
}
void main() {
  var labelChecks = 0;
  var directionChecks = 0;
  var exampleChecks = 0;
  for (final error in MailHeaderSearchError.values) {
    if (_defaultSearchError(error).isEmpty) throw StateError('Empty default $error');
    labelChecks++;
    for (final language in Language.values) {
      final text = Strings(language)._mailHeaderSearchError(error);
      if (text.isEmpty) throw StateError('Empty $language $error');
      labelChecks++;
      if (language != Language.en) {
        if (text == const Strings(Language.en)._mailHeaderSearchError(error)) {
          throw StateError('Untranslated $language $error');
        }
        labelChecks++;
      }
    }
  }
  for (final line in [
    '(from:alice OR from:bob) NOT subject:invoice',
    'NOT from:alice',
    'NOT(from:alice OR from:bob)',
    '-from:alice',
    '-(from:alice OR from:bob)',
    '(NOT from:alice)',
    '  (( - NOT subject:invoice))',
    'NOT NOT subject:invoice',
    '\\u2003NOT - (is:read OR is:flagged)',
    'FROM:ALICE',
    'NOT from:alice OR to:team',
    'subject:"weekly digest"',
    'from:alice -subject:"weekly digest"',
    'to:team@example.test cc:manager',
    'after:2026-10-01 before:2026-11-01 on:2026-10-15',
  ]) {
    if (!_searchExampleLine.hasMatch(line)) throw StateError('Unrecognized example $line');
    directionChecks++;
    // Evaluate the exact production routing expression in an Arabic ambient.
    if ((sourceDirection(line) ?? TextDirection.rtl) != TextDirection.ltr) {
      throw StateError('Example did not override Arabic direction: $line');
    }
    directionChecks++;
    MailHeaderSearchQuery.parse(line);
    exampleChecks++;
  }
  for (final line in [
    'مثال بحث (from:alice)',
    'خيارات الحالة: is:read',
    'المرسل: أحمد',
    'State choices: is:read',
    'Statusauswahl: is:read',
    'NOTHING from:alice',
    'before 2026-10-01',
  ]) {
    if (_searchExampleLine.hasMatch(line)) throw StateError('Prose classified as example: $line');
    directionChecks++;
    if ((sourceDirection(line) ?? TextDirection.rtl) != TextDirection.rtl) {
      throw StateError('Arabic ambient direction was overridden for prose: $line');
    }
    directionChecks++;
  }
  var actualExamples = 0;
  for (final language in Language.values) {
    final help = Strings(language).help();
    if (!help.contains('(from:alice OR from:bob) NOT subject:invoice')) {
      throw StateError('Missing grouped example in $language');
    }
    exampleChecks++;
    for (final line in help.split('\\n')) {
      if (!_searchExampleLine.hasMatch(line)) continue;
      MailHeaderSearchQuery.parse(line);
      exampleChecks++;
      if ((sourceDirection(line) ?? TextDirection.rtl) != TextDirection.ltr) {
        throw StateError('Authored example direction in $language');
      }
      directionChecks++;
      actualExamples++;
    }
  }
  if (actualExamples != 12) throw StateError('Expected 12 authored example lines, got $actualExamples');
  exampleChecks++;
  print(jsonEncode({'labelChecks':labelChecks,'directionChecks':directionChecks,'exampleChecks':exampleChecks,'authoredExamples':actualExamples,'errors':MailHeaderSearchError.values.length,'languages':Language.values.length}));
}
'''
(val/'final_main_mail_labels.dart').write_text(out)
record={'scope':'Exact production error-label methods, example regex, direction-selection expression and localized help text in a minimal Dart wrapper. TextDirection is an equivalent two-value enum; Arabic ambient RTL is simulated. Excludes Flutter widget rendering/full Studio compilation.','sources':{p:hashlib.sha256((repo/p).read_bytes()).hexdigest() for p in [ui_path,studio_path,'packages/quds_mail_core/lib/src/search/header_search.dart']},'extractedSha256':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in {'default':default,'localized':localized,'regex':pattern,'routing':routing,'help':help_value}.items()},'generatedHarnessSha256':hashlib.sha256(out.encode()).hexdigest()}
(val/'logs/final-main-mail-label-derivation.json').write_text(json.dumps(record,indent=2)+'\n')
