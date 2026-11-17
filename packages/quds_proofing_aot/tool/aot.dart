import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';

const _usage = '''AOT linguistic analysis and German grammar checks

Run from the workspace:
  dart run packages/quds_proofing_aot/tool/aot.dart --text 'Ich gehe.'
  dart run packages/quds_proofing_aot/tool/aot.dart --mode check --text 'Ich geht.'
  dart run packages/quds_proofing_aot/tool/aot.dart --mode morphology --text Hund

Options:
  --mode syntax|morphology|check    Default: syntax
  --text TEXT                     Literal input; exactly one of --text/--file
  --file PATH                     Read UTF-8 input from this file
  --language de-DE|German|Russian|English
                                  Default: de-DE; English morphology only
  --endpoint URL                  Default: http://127.0.0.1:17018/
  --allow-remote                  Explicitly allow sending text off this machine
  --get                           Legacy GET mode (text appears in the URL)
  --help                          Print this help without connecting

Requires a running AOT SynanDaemon. Output is JSON. Operational failures return
exit code 2; grammar findings are successful reviewable results, not edits.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.write(_usage);
    return;
  }
  AotClient? client;
  try {
    final options = <String, String>{};
    var allowRemote = false;
    var useGet = false;
    const valued = {'--mode', '--text', '--file', '--language', '--endpoint'};
    for (var i = 0; i < arguments.length; i++) {
      final key = arguments[i];
      if (key == '--get') {
        useGet = true;
        continue;
      }
      if (key == '--allow-remote') {
        allowRemote = true;
        continue;
      }
      if (!valued.contains(key) || i + 1 >= arguments.length) {
        throw ArgumentError('Unknown or incomplete option: $key');
      }
      if (options.containsKey(key)) {
        throw ArgumentError('Option specified twice: $key');
      }
      options[key] = arguments[++i];
    }
    if (options.containsKey('--text') == options.containsKey('--file')) {
      throw ArgumentError('Specify exactly one of --text and --file.');
    }
    final text =
        options['--text'] ?? await File(options['--file']!).readAsString();
    final mode = options['--mode'] ?? 'syntax';
    if (!{'syntax', 'morphology', 'check'}.contains(mode)) {
      throw ArgumentError('Mode must be syntax, morphology, or check.');
    }
    final tag = options['--language'] ?? 'de-DE';
    final language = switch (tag.toLowerCase()) {
      'german' || 'de' || 'de-de' || 'de-at' || 'de-ch' => AotLanguage.german,
      'russian' || 'ru' || 'ru-ru' => AotLanguage.russian,
      'english' || 'en' || 'en-us' || 'en-gb' => AotLanguage.english,
      _ => throw ArgumentError('Unknown analysis language: $tag'),
    };
    client = AotClient(
      transport: AotHttpTransport(
        endpoint: Uri.parse(options['--endpoint'] ?? 'http://127.0.0.1:17018/'),
        allowRemote: allowRemote,
        requestMethod: useGet ? AotRequestMethod.get : AotRequestMethod.post,
      ),
    );
    final Map<String, Object?> output;
    if (mode == 'check') {
      final provider = AotProofingProvider(
        analyzer: client,
        ownsAnalyzer: false,
      );
      final locale = tag.toLowerCase() == 'german' ? 'de-DE' : tag;
      final result = await provider.check(
        OfficeProofingRequest(
          documentId: 'aot-cli',
          blockId: 'input',
          revision: 0,
          text: text,
          language: locale,
        ),
      );
      output = <String, Object?>{
        'status': result.status.name,
        'provider': result.providerId,
        if (result.message != null) 'message': result.message,
        'findings': [
          for (final finding in result.findings)
            {
              'ruleId': finding.ruleId,
              'start': finding.start,
              'end': finding.end,
              'original': finding.originalText,
              'message': finding.message,
              'replacements': finding.replacements,
            },
        ],
      };
      if (result.status != OfficeProofingStatus.success) exitCode = 2;
      await provider.dispose();
    } else if (mode == 'morphology') {
      if (text.trim().contains(RegExp(r'\s'))) {
        throw ArgumentError('Morphology accepts one word at a time.');
      }
      final morphology = await client.morphology(
        text,
        language: language,
        withParadigms: true,
      );
      output = <String, Object?>{
        'word': morphology.word,
        'language': language.daemonName,
        'readings': [
          for (final reading in morphology.readings)
            {
              'found': reading.found,
              'lemma': reading.lemma,
              'grammar': reading.grammar.raw,
              'commonGrammems': reading.commonGrammems.toList(),
              if (reading.sourceNorm != null) 'sourceNorm': reading.sourceNorm,
              'forms': [
                for (final form in reading.forms)
                  {'text': form.text, 'grammar': form.grammar.raw},
              ],
            },
        ],
      };
    } else {
      final analysis = await client.analyze(text, language: language);
      output = <String, Object?>{
        'text': analysis.text,
        'language': language.daemonName,
        'fullyAligned': analysis.fullyAligned,
        'sentences': [
          for (final sentence in analysis.sentences)
            [
              for (final clause in sentence.clauses)
                {
                  'words': [
                    for (final word in clause.words)
                      {
                        'text': word.text,
                        'lemmas': word.homonyms,
                        'start': word.start,
                        'end': word.end,
                      },
                  ],
                  'variants': [
                    for (final variant in clause.variants)
                      {
                        'units': [
                          for (final unit in variant.units)
                            {
                              'homonymIndex': unit.homonymIndex,
                              'grammar': unit.grammar.raw,
                              'alternatives': [
                                for (final features
                                    in unit.grammar.alternatives)
                                  features.toList(),
                              ],
                            },
                        ],
                        'groups': [
                          for (final group in variant.groups)
                            {
                              'start': group.start,
                              'last': group.last,
                              'isGroup': group.isGroup,
                              'isSubject': group.isSubject,
                              'description': group.description,
                            },
                        ],
                      },
                  ],
                },
            ],
        ],
      };
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 2;
  } finally {
    await client?.dispose();
  }
}
