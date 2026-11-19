@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:quds_proofing_hunspell/src/hunspell_catalog.dart';
import 'package:quds_proofing_hunspell/src/hunspell_transport.dart';
import 'package:quds_proofing_hunspell/src/hunspell_transport_native.dart';
import 'package:test/test.dart';

void main() {
  final libraryPath = Platform.environment['QUDS_HUNSPELL_LIFECYCLE_LIBRARY'];
  if (libraryPath == null) {
    test(
      'native lifecycle fixture is configured',
      () {},
      skip:
          'Build test/fixtures/lifecycle_hunspell.cpp as a shared library and '
          'set QUDS_HUNSPELL_LIFECYCLE_LIBRARY to its absolute path.',
    );
    return;
  }
  final fixture = _Fixture(DynamicLibrary.open(libraryPath));
  late HunspellTransport transport;
  late Directory files;
  late HunspellDictionaryFiles dictionary;
  setUpAll(() {
    files = Directory.systemTemp.createTempSync('hunspell-owned-fixture-');
    File('${files.path}/fixture.aff').writeAsStringSync('SET UTF-8\n');
    File('${files.path}/fixture.dic').writeAsStringSync('1\nword\n');
    File('${files.path}/reject-open.aff').writeAsStringSync('SET UTF-8\n');
    dictionary = HunspellDictionaryFiles(
      affPath: '${files.path}/fixture.aff',
      dicPath: '${files.path}/fixture.dic',
    );
  });
  tearDownAll(() => files.deleteSync(recursive: true));

  setUp(() {
    expect(
      fixture.reset(),
      0,
      reason: 'The previous test must close its handles.',
    );
    transport = createHunspellTransport(nativeLibraryPath: libraryPath);
  });
  tearDown(() async {
    fixture.block(0);
    await transport.dispose();
  });

  test('dispose closes the native handle before completing', () async {
    await transport.open(dictionary);
    expect(fixture.counter(2), 1);
    await transport.dispose();
    expect(fixture.counter(1), 1);
    expect(fixture.counter(2), 0);
    expect(fixture.counter(4), 0);
  });

  test('concurrent and repeated disposal closes exactly once', () async {
    await transport.open(dictionary);
    await Future.wait([transport.dispose(), transport.dispose()]);
    await transport.dispose();
    expect(fixture.counter(1), 1);
    expect(fixture.counter(2), 0);
    expect(fixture.counter(4), 0);
    await expectLater(
      transport.check(['word'], [false]),
      throwsA(isA<HunspellUnavailableException>()),
    );
  });

  test('reopening closes each owned handle exactly once', () async {
    await transport.open(dictionary);
    await transport.open(dictionary);
    expect(fixture.counter(0), 2);
    expect(fixture.counter(1), 1);
    expect(fixture.counter(2), 1);
    await transport.dispose();
    expect(fixture.counter(1), 2);
    expect(fixture.counter(2), 0);
    expect(fixture.counter(4), 0);
  });

  test('failed reopen does not retain or reuse the freed handle', () async {
    await transport.open(dictionary);
    fixture.failAllocations(1);
    await expectLater(
      transport.open(dictionary),
      throwsA(isA<HunspellUnavailableException>()),
    );
    expect(fixture.counter(1), 1);
    expect(fixture.counter(2), 0);
    final response = jsonDecode(await transport.check(['word'], [false]));
    expect((response as Map<String, Object?>)['status'], 'unavailable');
    expect(fixture.counter(3), 0);
    await transport.open(dictionary);
    await transport.dispose();
    expect(fixture.counter(1), 2);
    expect(fixture.counter(4), 0);
  });

  test(
    'dispose rejects pending work then closes after its native call',
    () async {
      await transport.open(dictionary);
      fixture.block(1);
      final pending = expectLater(
        transport.check(['word'], [false]),
        throwsA(isA<HunspellUnavailableException>()),
      );
      await _until(() => fixture.counter(3) == 1);
      var disposed = false;
      final disposal = transport.dispose().then((_) => disposed = true);
      var secondDisposed = false;
      final secondDisposal = transport.dispose().then(
        (_) => secondDisposed = true,
      );
      await pending.timeout(const Duration(seconds: 1));
      expect(
        disposed,
        isFalse,
        reason: 'The native call still owns the handle.',
      );
      expect(
        secondDisposed,
        isFalse,
        reason: 'Every disposer waits for cleanup.',
      );
      expect(fixture.counter(1), 0);
      expect(fixture.counter(2), 1);
      fixture.block(0);
      await Future.wait([disposal, secondDisposal]);
      expect(fixture.counter(1), 1);
      expect(fixture.counter(2), 0);
      expect(fixture.counter(4), 0);
    },
  );

  test('dispose during startup prevents a late dictionary open', () async {
    final opening = expectLater(
      transport.open(dictionary),
      throwsA(isA<HunspellUnavailableException>()),
    );
    await transport.dispose();
    await opening.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(fixture.counter(0), 0);
    expect(fixture.counter(2), 0);
  });

  test('disposing an unused transport never opens a handle', () async {
    await transport.dispose();
    await expectLater(
      transport.open(dictionary),
      throwsA(isA<HunspellUnavailableException>()),
    );
    expect(fixture.counter(0), 0);
  });

  test('native open rejection has no handle to close', () async {
    await expectLater(
      transport.open(
        HunspellDictionaryFiles(
          affPath: '${files.path}/reject-open.aff',
          dicPath: dictionary.dicPath,
        ),
      ),
      throwsA(isA<HunspellUnavailableException>()),
    );
    await transport.dispose();
    expect(fixture.counter(0), 0);
    expect(fixture.counter(1), 0);
    expect(fixture.counter(4), 0);
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Native fixture did not enter.');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

final class _Fixture {
  _Fixture(DynamicLibrary library)
    : counter = library
          .lookupFunction<Int32 Function(Int32), int Function(int)>(
            'lifecycle_counter',
          ),
      block = library.lookupFunction<Void Function(Int32), void Function(int)>(
        'lifecycle_block',
      ),
      failAllocations = library
          .lookupFunction<Void Function(Int32), void Function(int)>(
            'lifecycle_fail_allocations',
          ),
      reset = library.lookupFunction<Int32 Function(), int Function()>(
        'lifecycle_reset',
      );

  final int Function(int) counter;
  final void Function(int) block;
  final void Function(int) failAllocations;
  final int Function() reset;
}
