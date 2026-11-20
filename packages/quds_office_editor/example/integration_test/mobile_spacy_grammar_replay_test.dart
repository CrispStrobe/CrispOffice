// On-device cross-binary replay of the consumed manual German grammar panels
// (W6, W7 and grammar v2 with the 977-sentence clean corpus) on the spaCy
// library the app ships (Android jniLibs / iOS framework). It runs the same
// replay code as the desktop tools (quds_proofing_spacy
// tool/grammar_replay_core.dart) on the worker the Studio host opens for
// grammar (`openGrammarTransport`, no named entities, capability mask 15),
// and compares every case with the retained Linux/macOS results.
//
// The panels and retained results are not packaged in the app. A host-side
// server (tools/proofing/spacy/grammar_replay_server.py) serves them; the
// test pins every input's SHA-256 below and uploads its reports back:
//
//   python3 tools/proofing/spacy/grammar_replay_server.py --port 8765 \
//     --reports <dir> &
//   adb reverse tcp:8765 tcp:8765
//   flutter test integration_test/mobile_spacy_grammar_replay_test.dart \
//     -d emulator-5554 \
//     --dart-define=QUDS_GRAMMAR_REPLAY_URL=http://127.0.0.1:8765
//
// Without QUDS_GRAMMAR_REPLAY_URL the test is skipped. A line
// `QUDS_GRAMMAR_REPLAY {json}` records the outcome.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quds_office_studio/studio_data_root.dart';
import 'package:quds_office_studio/studio_spacy_host_native.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';

import '../../../quds_proofing_spacy/tool/grammar_replay_core.dart';

const _baseUrl = String.fromEnvironment('QUDS_GRAMMAR_REPLAY_URL');

/// Input name -> pinned SHA-256 (the files named in
/// docs/validation/native-spacy-android-grammar-20261120/README.md).
const _inputs = {
  'w6-panel.json':
      '52bede2f915db66489b45657d9b605f357d000b2024c8c734b57c10b3457a826',
  'w6-recorded.json':
      '2e85b9721368e9e69b7fbeba0ec05105190374d757068706b90f2d7e2f615d58',
  'w7-panel.json':
      '92338ceb27d2877a6b0cfbfd1218440f53db6509d80571f85d34cfb0d0118ecd',
  'w7-recorded.json':
      'a6546bb627c997a9e05771030d303cb627dded996b340e256e909ea55829cdaf',
  'v2-protocol.json':
      '6412ccf41b7398ce161db5880562badb04f6359bf0ad6c01385675bf0e2474fc',
  'v2-panel.json':
      '80997c7efbd7891e03510ff300d6d341fa29742c863f446224274be572d3c310',
  'v2-corpus.json':
      'c9e037eee897f27865d5462f5ce1bc4ffb235b34adc7e1a2ecfb81cfcc9bbf9b',
  'v2-recorded.json':
      'c3336e439c5c7fed86e6ea6ed716169c4f141659260bcc2b185e73b7472e0861',
};

/// Rows of the grammar v2 report that differ from the sealed qualification
/// because of the planner source, not the library: the post-qualification
/// subject-person guard `possible-coordinated-subject` (grammar v2 README,
/// "subject-person fails"). Measured first with the qualified macOS library
/// `ccc96620…` on this source, which gives exactly these seven differences
/// and no annotation difference. Subject-person is experimental and off by
/// default; the three qualified families are unaffected. Every annotation
/// digest must still match.
const _v2SourceDifferences = <String>{
  'sp-error-14/decisions',
  'sp-error-14/model',
  'sp-error-14/combined',
  'sp-valid-07/decisions',
  'sp-valid-07/model',
  'sp-valid-07/combined',
  'corpus:test-s256/decisions',
};

Future<List<int>> _fetch(HttpClient client, String name) async {
  final request = await client.getUrl(Uri.parse('$_baseUrl/inputs/$name'));
  final response = await request.close();
  final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
  expect(response.statusCode, 200, reason: name);
  expect(crypto.sha256.convert(bytes).toString(), _inputs[name], reason: name);
  return bytes;
}

Future<void> _upload(
  HttpClient client,
  String name,
  Map<String, Object?> report,
) async {
  final request = await client.putUrl(Uri.parse('$_baseUrl/reports/$name'));
  final body = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  request.headers.contentType = ContentType.json;
  request.contentLength = body.length;
  request.add(body);
  final response = await request.close();
  await response.drain<void>();
  expect(response.statusCode, 201, reason: 'upload $name');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeStudioDataRoot);

  test(
    'consumed grammar panels replay identically on the shipped library',
    () async {
      final client = HttpClient();
      addTearDown(client.close);
      final inputs = {
        for (final name in _inputs.keys) name: await _fetch(client, name),
      };
      final bundled = detectMobileBundledSpacyLibrary();
      expect(bundled, isNotNull, reason: 'crispembed-spacy is not packaged');
      final libraryBytes = File(bundled!.path).lengthSync();
      final host = NativeStudioSpacyHost(
        root: Directory(studioSpacyDataDirectory()),
        environment: Platform.environment,
      );
      await host.refresh();
      expect(host.status.bundledLibrary, isTrue);
      if (!host.status.analysisEnabled) await host.install();
      expect(host.status.analysisEnabled, isTrue, reason: host.status.problem);
      final transport = await host.openGrammarTransport();
      addTearDown(transport.dispose);
      expect(transport.identity.librarySha256, bundled.sha256);
      expect(transport.identity.codeSha256, bundled.codeSha256);
      expect(transport.identity.capabilityMask, 15);
      expect(spacyGrammarQualifiedIdentity(transport.identity), isTrue);
      final where = '${Platform.operatingSystem} ${Abi.current()}';
      final dart = Platform.version.split(' ').first;
      final outcome = <String, Object?>{
        'host': where,
        'library_sha256': bundled.sha256,
        'code_sha256': bundled.codeSha256,
        'identity': transport.identity.toJson(),
      };
      for (final (panel, documentId, configurationId) in const [
        ('w6', 'w6-grammar', 'w6-frozen-grammar-evaluation'),
        ('w7', 'w7-expanded-grammar', 'w7-frozen-grammar-evaluation'),
      ]) {
        final report = <String, Object?>{};
        final watch = Stopwatch()..start();
        await replayConsumedPanel(
          report,
          panelBytes: inputs['$panel-panel.json']!,
          recordedBytes: inputs['$panel-recorded.json']!,
          documentId: documentId,
          configurationId: configurationId,
          transport: transport,
          librarySha256: bundled.sha256,
          libraryBytes: libraryBytes,
          host: where,
          dartVersion: dart,
        );
        report['elapsed_microseconds'] = watch.elapsedMicroseconds;
        await _upload(client, '$panel-replay.json', report);
        outcome[panel] = {
          'passed': report['passed'],
          'cases': report['cases_compared'],
          'annotations': report['annotations_compared'],
          'case_differences': (report['case_differences']! as List).length,
          'summary_differences': report['summary_differences'],
          'summary': report['summary'],
        };
      }
      final v2 = <String, Object?>{};
      final watch = Stopwatch()..start();
      await replayGrammarV2(
        v2,
        protocolBytes: inputs['v2-protocol.json']!,
        panelBytes: inputs['v2-panel.json']!,
        corpusBytes: inputs['v2-corpus.json']!,
        recordedBytes: inputs['v2-recorded.json']!,
        transport: transport,
        librarySha256: bundled.sha256,
        libraryBytes: libraryBytes,
        host: where,
        dartVersion: dart,
        expectedSourceDifferences: _v2SourceDifferences,
      );
      v2['elapsed_microseconds'] = watch.elapsedMicroseconds;
      await _upload(client, 'v2-replay.json', v2);
      outcome['v2'] = {
        'passed': v2['passed'],
        'cases': v2['cases_compared'],
        'annotations': v2['annotations_compared'],
        'annotation_differences':
            (v2['annotation_differences']! as List).length,
        'case_differences': [
          for (final d in v2['case_differences']! as List)
            '${(d as Map)['id']}/${d['field']}',
        ],
        'unexpected_differences':
            (v2['unexpected_differences']! as List).length,
        'clean_native_findings':
            ((v2['clean_corpus']! as Map)['native_findings'] as List).length,
      };
      // ignore: avoid_print
      print('QUDS_GRAMMAR_REPLAY ${jsonEncode(outcome)}');
      expect((outcome['w6']! as Map)['passed'], isTrue);
      expect((outcome['w7']! as Map)['passed'], isTrue);
      expect(v2['passed'], isTrue);
    },
    skip: _baseUrl.isEmpty ? 'QUDS_GRAMMAR_REPLAY_URL is not set' : false,
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
