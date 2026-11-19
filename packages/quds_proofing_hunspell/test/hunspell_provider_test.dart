import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:test/test.dart';

/// Scripted transport: words in [wrong] are misspelled; suggestions are
/// derived from the word so ordering can be asserted.
final class _FakeTransport implements HunspellTransport {
  _FakeTransport(this.wrong);
  final Set<String> wrong;
  final checks = <(List<String>, List<bool>)>[];
  int opens = 0;
  bool disposed = false;
  @override
  Future<void> open(HunspellDictionary dictionary) async => opens++;
  @override
  Future<String> check(List<String> words, List<bool> suggest) async {
    checks.add((words, suggest));
    return jsonEncode({
      'status': 'success',
      'results': [
        for (var i = 0; i < words.length; i++)
          wrong.contains(words[i])
              ? {
                  'ok': false,
                  'suggestions': suggest[i]
                      ? ['${words[i]}1', '${words[i]}2']
                      : <String>[],
                }
              : {'ok': true},
      ],
    });
  }

  @override
  Future<void> dispose() async => disposed = true;
}

OfficeProofingRequest _request(
  String text, {
  String language = 'ar',
  int startOffset = 0,
  Set<String> ignored = const {},
}) => OfficeProofingRequest(
  documentId: 'd',
  blockId: 'b',
  revision: 1,
  text: text,
  language: language,
  startOffset: startOffset,
  ignoredRuleIds: ignored,
);

HunspellProofingProvider _provider(
  _FakeTransport transport, {
  OfficeProofingVocabulary? vocabulary,
  int maxSuggestedWords = 24,
}) => HunspellProofingProvider(
  bundle: ayaspellArabic,
  dictionary: const HunspellDictionaryFiles(affPath: 'a', dicPath: 'd'),
  transport: transport,
  vocabulary: vocabulary,
  maxSuggestedWords: maxSuggestedWords,
);

void main() {
  group('words', () {
    test('keep harakat and tatweel inside a word with UTF-16 offsets', () {
      const text = 'كَتَبَ الطالـــب، 3 دروس';
      final words = hunspellWords(text, script: arabicScriptLetter);
      expect(words.map((w) => w.text), ['كَتَبَ', 'الطالـــب', 'دروس']);
      for (final word in words) {
        expect(text.substring(word.start, word.end), word.text);
      }
    });

    test('Latin words in Arabic prose are left to other providers', () {
      final words = hunspellWords(
        'قال Donald ترامب',
        script: arabicScriptLetter,
      );
      expect(words.map((w) => w.text), ['قال', 'ترامب']);
    });

    test('ZWNJ, digits and punctuation end words', () {
      final words = hunspellWords('أ‌ب ج٣د ؟هـ', script: arabicScriptLetter);
      expect(words.map((w) => w.text), ['أ', 'ب', 'ج', 'د', 'هـ']);
    });
  });

  group('catalog', () {
    test('AyaSpell resolves only at its immutable revision', () {
      expect(
        ayaspellArabic.url(ayaspellArabic.aff).toString(),
        'https://huggingface.co/cstr/ayaspell-ar-hunspell/resolve/'
        'e9ace7cca3844bef906d8d9fc5431c4e15bd2740/ar.aff',
      );
      expect(ayaspellArabic.files.map((f) => f.file).toSet().length, 8);
      expect(ayaspellArabic.totalBytes, 7332691);
      expect(hunspellCatalog, contains(ayaspellArabic));
    });

    test('verified bytes reject anything but the pinned files', () {
      expect(
        () => HunspellDictionaryBytes.verified(
          ayaspellArabic,
          aff: Uint8List(3),
          dic: Uint8List(3),
        ),
        throwsFormatException,
      );
    });
  });

  group('provider', () {
    test('reports findings at block offsets with capped suggestions', () async {
      final transport = _FakeTransport({'الى', 'المدرسه'});
      final provider = _provider(transport);
      const text = 'ذهب الى المدرسه ثم الى البيت';
      final result = await provider.check(_request(text, startOffset: 10));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.map((f) => f.originalText), [
        'الى',
        'المدرسه',
        'الى',
      ]);
      final first = result.findings.first;
      expect(first.start, 10 + text.indexOf('الى'));
      expect(first.end, first.start + 3);
      expect(first.ruleId, hunspellSpellingRule);
      expect(first.category, OfficeProofingCategory.spelling);
      expect(first.replacements, ['الى1', 'الى2']);
      // Distinct words are checked once; suggestions only for misspellings.
      expect(transport.checks.first.$1, [
        'ذهب',
        'الى',
        'المدرسه',
        'ثم',
        'البيت',
      ]);
      expect(transport.checks.last.$1, ['الى', 'المدرسه']);
      expect(transport.opens, 1);
      await provider.check(_request(text));
      expect(transport.opens, 1);
    });

    test('suggestion budget bounds work but keeps every finding', () async {
      final transport = _FakeTransport({'اا', 'بب', 'تت'});
      final provider = _provider(transport, maxSuggestedWords: 2);
      final result = await provider.check(_request('اا بب تت'));
      expect(result.findings, hasLength(3));
      expect(result.findings[2].replacements, isEmpty);
      expect(result.findings[0].replacements, isNotEmpty);
    });

    test('personal and ignored words are not reported', () async {
      final vocabulary = OfficeProofingVocabulary()
        ..addWord('ترامب', language: 'ar')
        ..ignoreWord('هاذا', language: 'ar');
      final transport = _FakeTransport({'ترامب', 'هاذا', 'الى'});
      final provider = _provider(transport, vocabulary: vocabulary);
      final result = await provider.check(_request('ترامب هاذا الى'));
      expect(result.findings.map((f) => f.originalText), ['الى']);
      expect(transport.checks.first.$1, ['الى']);
    });

    test('ignored rule, protected links and other languages', () async {
      final transport = _FakeTransport({'الى'});
      final provider = _provider(transport);
      final ignored = await provider.check(
        _request('الى', ignored: {hunspellSpellingRule}),
      );
      expect(ignored.findings, isEmpty);
      final link = await provider.check(
        _request('انظر https://example.com/الى الى'),
      );
      expect(link.findings, hasLength(1));
      expect(provider.supportsLanguage('ar-EG'), isTrue);
      expect(provider.supportsLanguage('de-DE'), isFalse);
      final german = await provider.check(_request('Haus', language: 'de-DE'));
      expect(german.status, OfficeProofingStatus.unsupported);
    });

    test('malformed backend output fails, never reports clean', () async {
      final provider = HunspellProofingProvider(
        bundle: ayaspellArabic,
        dictionary: const HunspellDictionaryFiles(affPath: 'a', dicPath: 'd'),
        transport: _BrokenTransport(),
      );
      final result = await provider.check(_request('الى'));
      expect(result.status, OfficeProofingStatus.failed);
      await provider.dispose();
      final disposed = await provider.check(_request('الى'));
      expect(disposed.status, OfficeProofingStatus.unavailable);
    });

    test('concurrent disposal waits for transport cleanup', () async {
      final transport = _DelayedCloseTransport();
      final provider = HunspellProofingProvider(
        bundle: ayaspellArabic,
        dictionary: const HunspellDictionaryFiles(affPath: 'a', dicPath: 'd'),
        transport: transport,
      );
      final first = provider.dispose();
      var secondCompleted = false;
      final second = provider.dispose().then((_) => secondCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondCompleted, isFalse);
      expect(transport.closeCalls, 1);
      transport.closed.complete();
      await Future.wait([first, second]);
      expect(secondCompleted, isTrue);
      await provider.dispose();
      expect(transport.closeCalls, 1);
    });
  });
}

final class _DelayedCloseTransport implements HunspellTransport {
  final closed = Completer<void>();
  int closeCalls = 0;
  @override
  Future<void> open(HunspellDictionary dictionary) async {}
  @override
  Future<String> check(List<String> words, List<bool> suggest) async =>
      '{"status":"success","results":[]}';
  @override
  Future<void> dispose() {
    closeCalls++;
    return closed.future;
  }
}

final class _BrokenTransport implements HunspellTransport {
  @override
  Future<void> open(HunspellDictionary dictionary) async {}
  @override
  Future<String> check(List<String> words, List<bool> suggest) async =>
      '{"status":"success","results":[]}';
  @override
  Future<void> dispose() async {}
}
