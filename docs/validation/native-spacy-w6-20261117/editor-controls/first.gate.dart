// Explicit real-model editor gate; intentionally not automatically discovered.
// Run from the workspace root with the verified native/model environment:
// flutter test --no-pub packages/quds_office_editor/example/test/studio_spacy_grammar_native_gate.dart --reporter expanded
// Missing assets fail. No fake native result or conditional skip is used.
// The one delayed-reply wrapper is a lifecycle harness control: it delays an
// actual worker response without changing any token, request or identity.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_spacy_config.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';

const _wrong = 'Die Katzen im Garten schläft.';
const _correct = 'Die Katzen im Garten schlafen.';
const _prefix = '😀 English. ';
const _replacement = 'schlafen';
const _deadline = Duration(seconds: 30);

final class _ReplyHold {
  final ready = Completer<LinguisticAnalysisResult>();
  final _released = Completer<void>();

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

final class _ObservedRealTransport implements SpacyTransport {
  _ObservedRealTransport(this.delegate);

  final SpacyTransport delegate;
  final requests = <LinguisticAnalysisRequest>[];
  final replies = <LinguisticAnalysisResult>[];
  final _holds = <_ReplyHold>[];
  _ReplyHold? _nextHold;
  Future<void>? _closing;
  int disposalCalls = 0;

  _ReplyHold holdNextActualReply() {
    if (_nextHold != null) throw StateError('A reply is already scheduled.');
    final hold = _ReplyHold();
    _holds.add(hold);
    _nextHold = hold;
    return hold;
  }

  @override
  SpacyBackendIdentity get identity => delegate.identity;

  @override
  Future<LinguisticAnalysisResult> analyze(
    LinguisticAnalysisRequest request,
  ) async {
    final hold = _nextHold;
    _nextHold = null;
    requests.add(request);
    try {
      final reply = await delegate.analyze(request);
      replies.add(reply);
      if (hold != null) {
        hold.ready.complete(reply);
        await hold._released.future;
      }
      return reply;
    } on Object catch (error, stack) {
      if (hold != null && !hold.ready.isCompleted) {
        hold.ready.completeError(error, stack);
      }
      rethrow;
    }
  }

  @override
  void cancel(String key) => delegate.cancel(key);

  @override
  Future<void> dispose() {
    if (_closing != null) return _closing!;
    disposalCalls++;
    for (final hold in _holds) {
      hold.release();
    }
    return _closing = delegate.dispose();
  }
}

WmlDocument _mixedDocument() => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        WmlParagraph(
          inlines: [
            WmlRun(
              text: _prefix,
              properties: WmlRunProps(proofingLanguage: 'en-US'),
            ),
            WmlRun(
              text: _wrong,
              properties: WmlRunProps(proofingLanguage: 'de-DE', bold: true),
            ),
          ],
        ),
      ],
    ),
  ],
)..proofingLanguage = 'en-US';

WmlDocument _plainDocument({String language = 'de-DE'}) =>
    WmlDocument.empty(text: _wrong)..proofingLanguage = language;

final class _Harness {
  _Harness(this.controller, this.transport, this.provider);

  final WordEditorController controller;
  final _ObservedRealTransport transport;
  final SpacyGrammarProvider provider;
  bool _closed = false;

  WmlParagraph get paragraph => controller.document.paragraphs.single;

  static Future<_Harness> open({WmlDocument? document}) async {
    final controller = WordEditorController(
      document: document ?? _mixedDocument(),
      config: const OfficeSurfaceConfig(autofocus: false),
    );
    controller.proofing.configure(
      OfficeProofingService(providers: [GermanWritingRulesProvider()]),
    );
    _ObservedRealTransport? opened;
    try {
      final transport = opened = _ObservedRealTransport(
        await openStudioSpacyTransport().timeout(_deadline),
      );
      expect(
        transport.identity,
        const SpacyBackendIdentity(librarySha256: spacyGrammarNativeSha256),
      );
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
        vocabulary: controller.proofing.vocabulary,
      );
      controller.proofing.configureManual(
        OfficeProofingService(providers: [provider], timeout: _deadline),
      );
      final harness = _Harness(controller, transport, provider);
      addTearDown(harness.close);
      return harness;
    } on Object {
      controller.dispose();
      await opened?.dispose();
      rethrow;
    }
  }

  Future<WordProofingSummary> check() =>
      controller.checkDocumentProofing().timeout(_deadline);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    controller.dispose();
    // Session disposal starts the provider shutdown. Await its idempotent
    // Future so this gate never abandons a live isolate/context.
    await provider.dispose().timeout(_deadline);
    expect(transport.disposalCalls, 1);
  }
}

List<WordProofingIssue> _nativeIssues(WordProofingSummary summary) => summary
    .issues
    .where((issue) => issue.finding.providerId == spacyGrammarProviderId)
    .toList();

WordProofingIssue _oneNativeIssue(WordProofingSummary summary) {
  final issues = _nativeIssues(summary);
  expect(
    issues,
    hasLength(1),
    reason:
        'The real development sentence must produce its native agreement '
        'proposal. Abstention is a gate failure, never a synthetic fallback. '
        '${summary.statusMessage}',
  );
  final issue = issues.single;
  expect(issue.finding.ruleId, spacyNounVerbRuleId);
  expect(issue.finding.originalText, 'schläft');
  expect(issue.finding.replacements, [_replacement]);
  return issue;
}

Future<WordProofingSummary> _nextBackground(
  WordProofingSession session,
  void Function() change,
) async {
  final finished = Completer<WordProofingSummary>();
  void listener() {
    if (session.summary.hasResults &&
        !session.checking &&
        !finished.isCompleted) {
      finished.complete(session.summary);
    }
  }

  session.addListener(listener);
  try {
    change();
    return await finished.future.timeout(_deadline);
  } finally {
    session.removeListener(listener);
  }
}

WmlContentControlData _lockedControl() => WmlContentControlData(
  xml:
      '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr>'
      '<w:id w:val="42"/><w:lock w:val="contentLocked"/>'
      '</w:sdtPr><w:sdtContent/></w:sdt>',
  sourcePartUri: '/word/document.xml',
  relationships: [],
);

void _expectCannotApply(_Harness harness, WordProofingIssue issue) {
  final before = harness.paragraph.text;
  expect(harness.controller.canApplyProofingIssue(issue), isFalse);
  expect(
    harness.controller.applyProofingSuggestion(issue, _replacement),
    isFalse,
  );
  expect(harness.paragraph.text, before);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    for (final name in [
      'QUDS_SPACY_BUNDLE',
      'QUDS_SPACY_LIBRARY',
      'QUDS_SPACY_LIBRARY_SHA256',
      'CRISPEMBED_SPACY',
    ]) {
      expect(
        Platform.environment[name],
        isNotNull,
        reason: '$name is required by this explicit native integration gate.',
      );
      expect(Platform.environment[name], isNotEmpty);
    }
    expect(
      Platform.environment['QUDS_SPACY_LIBRARY_SHA256'],
      spacyGrammarNativeSha256,
    );
  });

  test(
    'actual manual grammar maps a German segment after emoji and preserves correction history',
    () async {
      final h = await _Harness.open();
      final controller = h.controller;
      expect(_prefix.length, 12);
      final background = await controller.proofing.checkNow(
        includeManualProviders: false,
      );
      expect(background.manualProvidersSkipped, isTrue);
      expect(h.transport.requests, isEmpty);

      controller.documentCaret
        ..logicalIndex = 7
        ..selectionAnchor = 3;
      final issue = _oneNativeIssue(await h.check());
      final start = _prefix.length + _wrong.indexOf('schläft');
      expect((issue.finding.start, issue.finding.end), (start, start + 7));
      expect(issue.sourceText, '$_prefix$_wrong');
      expect(issue.language, 'de-DE');
      expect(h.transport.requests.single.text, _wrong);
      expect(h.transport.requests.single.startOffset, _prefix.length);
      expect(h.transport.replies.single.isSuccess, isTrue);
      expect(
        h.transport.replies.single.tokens
            .where((token) => token.text == 'schläft')
            .single
            .lemma,
        'schlafen',
      );
      expect(h.paragraph.text, '$_prefix$_wrong');
      expect(controller.canUndo, isFalse);

      expect(controller.canApplyProofingIssue(issue), isTrue);
      expect(controller.applyProofingSuggestion(issue, _replacement), isTrue);
      expect(h.paragraph.text, '$_prefix$_correct');
      expect(
        controller.documentCaret.logicalIndex,
        start + _replacement.length,
      );
      expect(controller.documentCaret.isCollapsed, isTrue);
      expect(controller.canUndo, isTrue);
      _expectCannotApply(h, issue);
      expect(_nativeIssues(await h.check()), isEmpty);
      expect(h.transport.requests, hasLength(2));

      controller.undo();
      expect(h.paragraph.text, '$_prefix$_wrong');
      expect(controller.documentCaret.logicalIndex, 7);
      expect(controller.documentCaret.selectionAnchor, 3);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
      expect(h.transport.requests, hasLength(2));
      _oneNativeIssue(await h.check());
      expect(h.transport.requests, hasLength(3));
      controller.redo();
      expect(h.paragraph.text, '$_prefix$_correct');
      expect(controller.canRedo, isFalse);
      expect(h.transport.requests, hasLength(3));
      expect(_nativeIssues(await h.check()), isEmpty);
      expect(h.transport.requests, hasLength(4));
      expect(h.paragraph.inlines.whereType<WmlRun>().first.text, _prefix);
      expect(
        h.paragraph.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .proofingLanguage,
        'en-US',
      );
      await h.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'native and existing noun agreement rule ignores suppress calls and restore',
    () async {
      final h = await _Harness.open();
      _oneNativeIssue(await h.check());
      for (final rule in [spacyNounVerbRuleId, 'de.grammar.noun-verb']) {
        final count = h.transport.requests.length;
        h.controller.proofing.ignoreRule(rule);
        expect(_nativeIssues(await h.check()), isEmpty);
        expect(h.transport.requests, hasLength(count));
        h.controller.proofing.restoreRule(rule);
        _oneNativeIssue(await h.check());
        expect(h.transport.requests, hasLength(count + 1));
      }
      expect(h.paragraph.text, '$_prefix$_wrong');
      expect(h.controller.canUndo, isFalse);
    },
  );

  test(
    'personal vocabulary invalidates an actual result and can be restored',
    () async {
      final h = await _Harness.open();
      final issue = _oneNativeIssue(await h.check());
      final vocabulary = h.controller.proofing.vocabulary;
      vocabulary.addWord('Katzen', language: 'de-DE');
      h.controller.proofing.refresh();
      _expectCannotApply(h, issue);
      expect(_nativeIssues(await h.check()), isEmpty);
      expect(h.transport.requests, hasLength(2));
      vocabulary.removeWord('Katzen', language: 'de-DE');
      h.controller.proofing.refresh();
      _oneNativeIssue(await h.check());
      expect(h.transport.requests, hasLength(3));
      expect(h.paragraph.text, '$_prefix$_wrong');
      expect(h.controller.canUndo, isFalse);
    },
  );

  test(
    'harness-delayed actual reply cannot survive a document revision',
    () async {
      final h = await _Harness.open();
      final hold = h.transport.holdNextActualReply();
      final pending = h.check();
      final realReply = await hold.ready.future.timeout(_deadline);
      expect(realReply.isSuccess, isTrue);
      expect(realReply.request.text, _wrong);
      h.controller.documentCaret
        ..logicalIndex = h.paragraph.text.length
        ..collapseSelection();
      h.controller.insertText('!');
      h.controller.proofing.observeDocument();
      hold.release();
      final stale = await pending;
      expect(stale.hasResults, isFalse);
      expect(h.controller.proofing.summary.issues, isEmpty);
      expect(h.paragraph.text, '$_prefix$_wrong!');
      h.controller.undo();
      _oneNativeIssue(await h.check());
      expect(h.transport.requests, hasLength(2));
      expect(
        h.transport.requests.last.revision,
        greaterThan(realReply.request.revision),
      );
    },
  );

  test(
    'harness-delayed actual reply cannot survive a vocabulary revision',
    () async {
      final h = await _Harness.open();
      final hold = h.transport.holdNextActualReply();
      final pending = h.check();
      expect((await hold.ready.future.timeout(_deadline)).isSuccess, isTrue);
      h.controller.proofing.vocabulary.addWord('Katzen', language: 'de-DE');
      h.controller.proofing.refresh();
      hold.release();
      expect((await pending).hasResults, isFalse);
      expect(h.controller.proofing.summary.issues, isEmpty);
      expect(_nativeIssues(await h.check()), isEmpty);
      expect(h.transport.requests, hasLength(2));
      expect(h.paragraph.text, '$_prefix$_wrong');
      expect(h.controller.canUndo, isFalse);
    },
  );

  test(
    'actual findings remain reviewable but cannot edit locked content',
    () async {
      final h = await _Harness.open();
      final beforeLock = _oneNativeIssue(await h.check());
      h.paragraph.contentControlWrappers.add(_lockedControl());
      _expectCannotApply(h, beforeLock);
      h.controller.proofing.refresh();
      final locked = _oneNativeIssue(await h.check());
      _expectCannotApply(h, locked);
      expect(h.transport.requests, hasLength(2));
      expect(h.paragraph.text, '$_prefix$_wrong');
      expect(h.controller.canUndo, isFalse);
    },
  );

  for (final kind in ['paragraph', 'complex']) {
    test(
      'a live $kind field rejects an actual finding and excludes cached text',
      () async {
        final h = await _Harness.open(document: _plainDocument());
        final issue = _oneNativeIssue(await h.check());
        if (kind == 'paragraph') {
          h.paragraph.properties.fieldInstruction = ' REF QUDS_SPACY_TEST ';
        } else {
          h.paragraph.inlines.insertAll(0, [
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
            WmlFieldBoundary(
              kind: WmlFieldBoundaryKind.instruction,
              text: ' REF QUDS_SPACY_TEST ',
            ),
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          ]);
          h.paragraph.inlines.add(
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          );
        }
        _expectCannotApply(h, issue);
        h.controller.proofing.refresh();
        final excluded = await h.check();
        expect(excluded.issues, isEmpty);
        expect(excluded.skippedContentCount, greaterThan(0));
        expect(h.transport.requests, hasLength(1));
        expect(h.paragraph.text, _wrong);
        expect(h.controller.canUndo, isFalse);
      },
    );
  }

  test(
    'typing and background checking never call the configured native worker',
    () async {
      final h = await _Harness.open(document: _plainDocument());
      final first = await _nextBackground(
        h.controller.proofing,
        () => h.controller.proofing.enabled = true,
      );
      expect(first.manualProvidersSkipped, isTrue);
      expect(first.complete, isFalse);
      expect(h.transport.requests, isEmpty);
      final afterTyping = await _nextBackground(h.controller.proofing, () {
        h.controller.documentCaret
          ..logicalIndex = h.paragraph.text.length
          ..collapseSelection();
        h.controller.insertText(' ');
      });
      expect(afterTyping.manualProvidersSkipped, isTrue);
      expect(afterTyping.complete, isFalse);
      expect(h.transport.requests, isEmpty);
      expect(h.transport.replies, isEmpty);
      expect(h.paragraph.text, '$_wrong ');
      h.controller.proofing.enabled = false;
    },
  );

  test(
    'unsupported locales return explicit status without native inference',
    () async {
      final h = await _Harness.open(
        document: _plainDocument(language: 'de-AT'),
      );
      for (final locale in ['de-AT', 'de-CH', 'en-US']) {
        h.controller.document.proofingLanguage = locale;
        h.controller.proofing.refresh();
        final summary = await h.check();
        final native = summary.reports.single.results.singleWhere(
          (result) => result.providerId == spacyGrammarProviderId,
        );
        expect(native.status, OfficeProofingStatus.unsupported);
        expect(_nativeIssues(summary), isEmpty);
        expect(h.transport.requests, isEmpty);
      }
      expect(h.paragraph.text, _wrong);
      expect(h.controller.canUndo, isFalse);
    },
  );
}
