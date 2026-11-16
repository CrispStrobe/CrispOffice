import 'dart:convert';
import 'dart:js_interop';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_harper/quds_proofing_harper.dart';

@JS('qudsHarperWorkerUrl')
external JSString get _workerUrl;

@JS('qudsHarperSmokeDone')
external void _done(JSString result);

/// Compiled JavaScript acceptance for the actual Dart web transport and Wasm.
/// The Node launcher supplies only browser Worker messaging and local fetch.
Future<void> main() async {
  final provider = HarperProofingProvider(
    workerUrl: Uri.parse(_workerUrl.toDart),
  );
  final missing = HarperProofingProvider(
    workerUrl: Uri.parse(_workerUrl.toDart).resolve('missing_worker.mjs'),
  );
  var checks = 0;
  void verify(bool condition, String label) {
    if (!condition) throw StateError(label);
    checks++;
    print('PASS $label');
  }

  OfficeProofingRequest request({
    String text = '😀 This is an test.',
    String language = 'en-US',
    Set<String> ignored = const {},
  }) => OfficeProofingRequest(
    documentId: 'web-doc',
    blockId: 'paragraph',
    revision: 1,
    text: text,
    language: language,
    startOffset: 7,
    ignoredRuleIds: ignored,
  );

  String? error;
  try {
    final first = await provider.check(request());
    verify(first.status == OfficeProofingStatus.success, 'real Wasm success');
    final article = first.findings.firstWhere((f) => f.ruleId == 'harper.AnA');
    verify(
      article.originalText == 'an' &&
          article.start == 18 &&
          article.end == 20 &&
          article.replacements.contains('a'),
      'Dart web transport maps scalar offsets to source UTF16',
    );
    final discretionary = await provider.check(
      request(text: '😀 This is a\u00adn test.'),
    );
    verify(
      discretionary.status == OfficeProofingStatus.success,
      'real Wasm checks across an authored discretionary hyphen',
    );
    final projectedArticle = discretionary.findings.firstWhere(
      (finding) => finding.ruleId == 'harper.AnA',
    );
    verify(
      projectedArticle.originalText == 'a\u00adn' &&
          projectedArticle.start == 18 &&
          projectedArticle.end == 21 &&
          projectedArticle.replacements.contains('a'),
      'real Wasm correction retains original soft-hyphen source span',
    );
    final results = await Future.wait([
      provider.check(request(ignored: {'harper.AnA'})),
      provider.check(request(language: 'en-GB')),
      provider.check(request(language: 'de-DE')),
    ]);
    verify(
      results[0].status == OfficeProofingStatus.success &&
          results[0].findings.every((f) => f.ruleId != 'harper.AnA') &&
          results[1].status == OfficeProofingStatus.success &&
          results[1].findings.any((f) => f.ruleId == 'harper.AnA') &&
          results[2].status == OfficeProofingStatus.unsupported,
      'concurrent checks keep dialects, ignores and unsupported status separate',
    );
    verify(
      (await provider.check(request(text: 'a' * 32769))).status ==
          OfficeProofingStatus.failed,
      'oversized paragraph reports failure',
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      verify(
        (await missing.check(request())).status ==
            OfficeProofingStatus.unavailable,
        'missing worker reports unavailable on attempt ${attempt + 1}',
      );
    }
    final pending = provider.check(request());
    await provider.dispose();
    verify(
      (await pending).status == OfficeProofingStatus.unavailable,
      'disposal invalidates an outstanding web request',
    );
    verify(
      (await provider.check(request())).status ==
          OfficeProofingStatus.unavailable,
      'disposed web provider rejects future requests',
    );
  } on Object catch (caught) {
    error = caught.toString();
  } finally {
    await provider.dispose();
    await missing.dispose();
  }
  _done(
    jsonEncode({
      'status': error == null ? 'passed' : 'failed',
      'checks': checks,
      'error': ?error,
      'scope':
          'Compiled Dart web transport and real shipped Wasm worker; Node '
          'substitutes browser Worker messaging and local file fetch. '
          'This is not browser CSP or HTTP hosting acceptance.',
    }).toJS,
  );
}
