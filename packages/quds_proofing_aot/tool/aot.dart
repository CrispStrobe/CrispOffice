import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';

const _usage =
    '''AOT linguistic analysis and German grammar checks — no daemon required

Run from the workspace after the explicit native setup:
  python packages/quds_proofing_aot/tool/build_native.py
  dart run packages/quds_proofing_aot/tool/aot.dart --mode doctor
  dart run packages/quds_proofing_aot/tool/aot.dart --text 'Ich gehe.'
  dart run packages/quds_proofing_aot/tool/aot.dart --mode check --text 'Ich geht.'
  dart run packages/quds_proofing_aot/tool/aot.dart --mode morphology --text Hund
  cat sample.txt | dart run packages/quds_proofing_aot/tool/aot.dart --stdin

Options:
  --mode syntax|morphology|check|doctor  Default: syntax
  --text TEXT                     Literal input; exactly one input option
  --file PATH                     Read bounded UTF-8 input from this file
  --stdin                         Read bounded UTF-8 input from standard input
  --language de-DE|German|Russian|English
                                  Default: de-DE; English morphology only
  --backend local|http            Default: local (http when --endpoint is given)
  --executable PATH               Native worker; default: built runtime, then PATH
  --rml PATH                      Native resource directory; default: beside worker
  --timeout SECONDS               Complete request/check deadline; default: 60
  --endpoint URL                  Explicit HTTP compatibility mode
  --allow-remote                  Allow a configured HTTP host off this machine
  --get                           Legacy HTTP GET mode (text appears in the URL)
  --help                          Print help without starting an engine

Native defaults also accept QUDS_AOT_EXECUTABLE and QUDS_AOT_RML environment
variables. Only the requested action starts the local worker. It is closed on
exit; there is no server or automatic HTTP fallback. Doctor uses synthetic text
to verify the selected language's installed dictionaries and syntax support.
Output is JSON. Operational failures use exit code 2; findings are suggestions.
''';

const _maximumInputBytes = 256 * 1024;
const _maximumInputCodeUnits = 32768;

Future<String> _readBounded(Stream<List<int>> source) async {
  final bytes = <int>[];
  await for (final chunk in source) {
    if (chunk.length > _maximumInputBytes - bytes.length) {
      throw const AotException(
        AotErrorCode.limit,
        'Input exceeds the byte limit.',
      );
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

String _defaultExecutable() {
  final configured = Platform.environment['QUDS_AOT_EXECUTABLE'];
  if (configured != null && configured.trim().isNotEmpty) return configured;
  // Resolve relative to this checked-out tool, independent of caller directory.
  final root = File.fromUri(Platform.script).parent.parent.parent.parent;
  final name = Platform.isWindows ? 'quds_aot_worker.exe' : 'quds_aot_worker';
  final candidate = File(
    '${root.path}/.dart_tool/quds_aot_native/runtime/Bin/$name',
  );
  return candidate.existsSync() ? candidate.absolute.path : name;
}

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
    var useStdin = false;
    const valued = {
      '--mode',
      '--text',
      '--file',
      '--language',
      '--endpoint',
      '--backend',
      '--executable',
      '--rml',
      '--timeout',
    };
    for (var i = 0; i < arguments.length; i++) {
      final key = arguments[i];
      if (key == '--stdin') {
        if (useStdin) throw ArgumentError('Option specified twice: --stdin');
        useStdin = true;
        continue;
      }
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
    final mode = options['--mode'] ?? 'syntax';
    if (!{'syntax', 'morphology', 'check', 'doctor'}.contains(mode)) {
      throw ArgumentError('Mode must be syntax, morphology, check, or doctor.');
    }
    final inputCount =
        (options.containsKey('--text') ? 1 : 0) +
        (options.containsKey('--file') ? 1 : 0) +
        (useStdin ? 1 : 0);
    if (inputCount != (mode == 'doctor' ? 0 : 1)) {
      throw ArgumentError(
        mode == 'doctor'
            ? 'Doctor uses synthetic examples and accepts no document input.'
            : 'Specify exactly one of --text, --file, and --stdin.',
      );
    }
    final timeoutSeconds = int.tryParse(options['--timeout'] ?? '60');
    if (timeoutSeconds == null || timeoutSeconds < 1 || timeoutSeconds > 600) {
      throw ArgumentError('Timeout must be between 1 and 600 seconds.');
    }
    final timeout = Duration(seconds: timeoutSeconds);
    final backend =
        options['--backend'] ??
        (options.containsKey('--endpoint') ? 'http' : 'local');
    if (!{'local', 'http'}.contains(backend)) {
      throw ArgumentError('Backend must be local or http.');
    }
    if (backend == 'local' &&
        (options.containsKey('--endpoint') || allowRemote || useGet)) {
      throw ArgumentError('HTTP options require the http backend.');
    }
    if (backend == 'http' &&
        (options.containsKey('--executable') || options.containsKey('--rml'))) {
      throw ArgumentError(
        'Worker and resource paths require the local backend.',
      );
    }
    final text = mode == 'doctor'
        ? ''
        : options['--text'] ??
              await _readBounded(
                useStdin ? stdin : File(options['--file']!).openRead(),
              );
    if (text.length > _maximumInputCodeUnits) {
      throw const AotException(
        AotErrorCode.limit,
        'Input exceeds 32768 UTF-16 code units.',
      );
    }
    final tag = options['--language'] ?? 'de-DE';
    final language = switch (tag.toLowerCase()) {
      'german' || 'de' || 'de-de' || 'de-at' || 'de-ch' => AotLanguage.german,
      'russian' || 'ru' || 'ru-ru' => AotLanguage.russian,
      'english' || 'en' || 'en-us' || 'en-gb' => AotLanguage.english,
      _ => throw ArgumentError('Unknown analysis language: $tag'),
    };
    client = backend == 'local'
        ? AotClient.local(
            executable: options['--executable'] ?? _defaultExecutable(),
            rmlDirectory:
                options['--rml'] ?? Platform.environment['QUDS_AOT_RML'],
            timeout: timeout,
          )
        : AotClient.http(
            endpoint: Uri.parse(
              options['--endpoint'] ?? 'http://127.0.0.1:17018/',
            ),
            allowRemote: allowRemote,
            requestMethod: useGet
                ? AotRequestMethod.get
                : AotRequestMethod.post,
            timeout: timeout,
          );
    final Map<String, Object?> output;
    if (mode == 'doctor') {
      final probe = switch (language) {
        AotLanguage.german => 'Hund',
        AotLanguage.russian => 'кот',
        AotLanguage.english => 'dog',
      };
      final morphology = await client.morphology(
        probe,
        language: language,
        withParadigms: true,
      );
      final known = morphology.readings
          .where((reading) => reading.found)
          .toList();
      if (known.isEmpty || known.every((reading) => reading.forms.isEmpty)) {
        throw const AotException(
          AotErrorCode.unavailable,
          'The installed engine did not return the expected dictionary forms.',
        );
      }
      AotAnalysis? syntax;
      if (language.supportsSyntax) {
        syntax = await client.analyze(
          language == AotLanguage.german ? 'Ich gehe.' : 'Мама читает книгу.',
          language: language,
        );
        if (!syntax.fullyAligned ||
            syntax.tokens.isEmpty ||
            syntax.sentences.any(
              (sentence) =>
                  sentence.clauses.any((clause) => clause.variants.isEmpty),
            )) {
          throw const AotException(
            AotErrorCode.unavailable,
            'The installed engine did not return complete syntax analysis.',
          );
        }
      }
      output = <String, Object?>{
        'status': 'ready',
        'backend': backend,
        'language': language.daemonName,
        'dictionaryReadings': known.length,
        'inflectedForms': known.fold<int>(
          0,
          (count, reading) => count + reading.forms.length,
        ),
        'syntax': syntax != null ? 'verified' : 'unsupported',
        'grammar': language == AotLanguage.german ? 'de-DE' : 'unsupported',
      };
    } else if (mode == 'check') {
      final provider = AotProofingProvider(
        analyzer: client,
        ownsAnalyzer: false,
        timeout: timeout,
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
        text.trim(),
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
                        if (word.isNormalized)
                          'analysisText': word.analysisText,
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
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'backend': backend,
        ...output,
      }),
    );
  } on Object catch (error) {
    final message = error is AotException
        ? error.message
        : error is ArgumentError
        ? error.message.toString()
        : error is FormatException
        ? 'Input or response is not valid UTF-8/JSON.'
        : error is FileSystemException
        ? 'The input file could not be read.'
        : 'AOT could not complete the requested action.';
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'status': 'error',
        'code': error is AotException ? error.code.name : 'input',
        'message': message,
      }),
    );
    exitCode = 2;
  } finally {
    await client?.dispose();
  }
}
