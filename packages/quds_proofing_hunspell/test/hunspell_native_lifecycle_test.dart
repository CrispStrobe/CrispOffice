@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:quds_proofing_hunspell/src/hunspell_transport_native.dart';
import 'package:test/test.dart';

// Compile test/support/lifecycle_library.cpp as a shared library and set
// QUDS_HUNSPELL_OWNERSHIP_LIBRARY to its absolute path. The counter-only fixture
// makes native ownership observable without requiring a downloaded dictionary.
// The same tests can use a counter-instrumented copy of the real adapter.
final class _Counters {
  _Counters(DynamicLibrary library)
    : live = library.lookupFunction<Size Function(), int Function()>(
        'quds_hunspell_test_live',
      ),
      opens = library.lookupFunction<Size Function(), int Function()>(
        'quds_hunspell_test_opens',
      ),
      closes = library.lookupFunction<Size Function(), int Function()>(
        'quds_hunspell_test_closes',
      ),
      activeOpen = library.lookupFunction<Size Function(), int Function()>(
        'quds_hunspell_test_active_open',
      ),
      activeSpell = library.lookupFunction<Size Function(), int Function()>(
        'quds_hunspell_test_active_spell',
      ),
      delays = library
          .lookupFunction<
            Void Function(Uint32, Uint32),
            void Function(int, int)
          >('quds_hunspell_test_delays');

  final int Function() live;
  final int Function() opens;
  final int Function() closes;
  final int Function() activeOpen;
  final int Function() activeSpell;
  final void Function(int, int) delays;
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < const Duration(seconds: 8)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'Native lifecycle condition timed out.');
}

void main() {
  final library = Platform.environment['QUDS_HUNSPELL_OWNERSHIP_LIBRARY'];
  group('native handle ownership', () {
    late Directory directory;
    late HunspellTransport transport;
    late HunspellDictionaryFiles dictionary;
    late _Counters counters;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('hunspell-lifecycle-');
      // Each case gets independent counters, including when the RED baseline
      // deliberately leaks a handle. No previous case can mask the next one.
      final copy = File(library!).copySync(
        '${directory.path}/${library.split(Platform.pathSeparator).last}',
      );
      counters = _Counters(DynamicLibrary.open(copy.path));
      transport = createHunspellTransport(nativeLibraryPath: copy.path);
      final aff = File('${directory.path}/fixture.aff')
        ..writeAsStringSync('SET UTF-8\n');
      final dic = File('${directory.path}/fixture.dic')
        ..writeAsStringSync('1\nكتب\n');
      dictionary = HunspellDictionaryFiles(
        affPath: aff.path,
        dicPath: dic.path,
      );
    });

    tearDown(() async {
      await transport.dispose();
      directory.deleteSync(recursive: true);
    });

    test('normal and repeated disposal close exactly once', () async {
      await transport.open(dictionary);
      expect(counters.live(), 1);
      await Future.wait([transport.dispose(), transport.dispose()]);
      expect(counters.live(), 0);
      expect(counters.opens(), 1);
      expect(counters.closes(), 1);
      await expectLater(
        transport.check(['كتب'], [false]),
        throwsA(isA<HunspellUnavailableException>()),
      );
    });

    test('reopening replaces and releases each owned handle once', () async {
      await transport.open(dictionary);
      await transport.open(dictionary);
      expect(counters.live(), 1);
      expect(counters.opens(), 2);
      expect(counters.closes(), 1);
      await transport.dispose();
      expect(counters.live(), 0);
      expect(counters.closes(), 2);
    });

    test('dispose during startup settles opening without allocation', () async {
      final opened = expectLater(
        transport.open(dictionary),
        throwsA(isA<HunspellUnavailableException>()),
      );
      await transport.dispose().timeout(const Duration(seconds: 3));
      await opened;
      expect(counters.live(), 0);
    });

    test('forced exit releases a handle after a stalled check', () async {
      await transport.open(dictionary);
      counters.delays(0, 3500);
      final checked = expectLater(
        transport.check(['كتب'], [false]),
        throwsA(isA<HunspellUnavailableException>()),
      );
      await _until(() => counters.activeSpell() == 1);
      final watch = Stopwatch()..start();
      await transport.dispose().timeout(const Duration(seconds: 3));
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 2800)));
      await checked;
      await _until(() => counters.live() == 0);
      expect(counters.opens(), counters.closes());
    });

    test('forced exit preserves ownership while native open returns', () async {
      counters.delays(3500, 0);
      final opened = expectLater(
        transport.open(dictionary),
        throwsA(isA<HunspellUnavailableException>()),
      );
      await _until(() => counters.activeOpen() == 1);
      final watch = Stopwatch()..start();
      await transport.dispose().timeout(const Duration(seconds: 3));
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 2800)));
      await opened;
      await _until(() => counters.live() == 0);
      expect(counters.opens(), counters.closes());
    });

    test('provider timeout settles and releases its native handle', () async {
      // Warm the worker so the deadline exercises a native check, not startup.
      await transport.open(dictionary);
      counters.delays(0, 3500);
      final provider = HunspellProofingProvider(
        bundle: ayaspellArabic,
        dictionary: dictionary,
        transport: transport,
        timeout: const Duration(milliseconds: 100),
      );
      final watch = Stopwatch()..start();
      final result = await provider.check(
        OfficeProofingRequest(
          documentId: 'lifecycle',
          blockId: 'one',
          revision: 1,
          text: 'كتب',
          language: 'ar',
        ),
      );
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.message, contains('timed out'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      await provider.dispose();
      await _until(() => counters.live() == 0);
      expect(counters.opens(), counters.closes());
    });
  }, skip: library == null ? 'Set QUDS_HUNSPELL_OWNERSHIP_LIBRARY.' : false);
}
