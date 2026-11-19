@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_language_id/src/language_id_transport.dart';
import 'package:quds_language_id/src/language_id_transport_native.dart';
import 'package:test/test.dart';

void main() {
  final path = Platform.environment['QUDS_LANGUAGE_ID_FIXTURE_LIBRARY'];
  final skip = path == null || path.isEmpty
      ? 'Set QUDS_LANGUAGE_ID_FIXTURE_LIBRARY to the allocation-counter fixture.'
      : null;
  late int Function() handles;
  late int Function() buffers;
  late int Function() activeCalls;
  late void Function(int) failAfter;
  late void Function(int) delay;
  final transports = <LanguageIdTransport>[];

  LanguageIdTransport create() {
    final transport = createLanguageIdTransport(nativeLibraryPath: path);
    transports.add(transport);
    return transport;
  }

  setUpAll(() {
    if (skip != null) return;
    final library = DynamicLibrary.open(path!);
    handles = library.lookupFunction<Int32 Function(), int Function()>(
      'quds_language_id_test_handles',
    );
    buffers = library.lookupFunction<Int32 Function(), int Function()>(
      'quds_language_id_test_buffers',
    );
    activeCalls = library.lookupFunction<Int32 Function(), int Function()>(
      'quds_language_id_test_active_calls',
    );
    failAfter = library
        .lookupFunction<Void Function(Int32), void Function(int)>(
          'quds_language_id_test_fail_after',
        );
    delay = library.lookupFunction<Void Function(Int32), void Function(int)>(
      'quds_language_id_test_delay',
    );
  });

  tearDown(() async {
    if (skip != null) return;
    for (final transport in transports) {
      await transport.dispose();
    }
    transports.clear();
    failAfter(-1);
    delay(0);
    expect(handles(), 0, reason: 'Every native model must be closed.');
    expect(buffers(), 0, reason: 'Every native buffer must be freed.');
  });

  test('normal disposal releases the model and all worker buffers', () async {
    final transport = create();
    await transport.open(Uint8List.fromList([1]));
    expect(handles(), 1);
    expect(buffers(), 3);
    expect(await transport.detect(['text'], 1), [
      [('en', 0.95)],
    ]);
    await transport.dispose();
    expect(handles(), 0);
    expect(buffers(), 0);
    await transport.dispose();
  }, skip: skip);

  test('reopening closes the previous model before replacement', () async {
    final transport = create();
    await transport.open(Uint8List.fromList([1]));
    await transport.open(Uint8List.fromList([2]));
    expect(handles(), 1);
    expect(buffers(), 3);
  }, skip: skip);

  test('disposal during startup still releases initialized buffers', () async {
    final transport = create();
    final opening = expectLater(
      transport.open(Uint8List.fromList([1])),
      throwsA(isA<LanguageIdUnavailableException>()),
    );
    await transport.dispose();
    await opening;
    expect(handles(), 0);
    expect(buffers(), 0);
  }, skip: skip);

  test(
    'disposal settles callers then waits for active native cleanup',
    () async {
      final transport = create();
      await transport.open(Uint8List.fromList([1]));
      delay(100);
      final detecting = expectLater(
        transport.detect(['text'], 1),
        throwsA(isA<LanguageIdUnavailableException>()),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (activeCalls() == 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(activeCalls(), 1);
      await transport.dispose();
      await detecting;
      expect(activeCalls(), 0);
      expect(handles(), 0);
      expect(buffers(), 0);
    },
    skip: skip,
  );

  test('failed initialization releases partial buffer allocations', () async {
    failAfter(1);
    final transport = create();
    await expectLater(
      transport.open(Uint8List.fromList([1])),
      throwsA(isA<LanguageIdUnavailableException>()),
    );
    expect(handles(), 0);
    expect(buffers(), 0);
  }, skip: skip);

  test(
    'failed buffer growth retains the live buffer for later cleanup',
    () async {
      final transport = create();
      await transport.open(Uint8List.fromList([1]));
      failAfter(0);
      await expectLater(
        transport.detect(['x' * 5000], 1),
        throwsA(isA<StateError>()),
      );
      expect(buffers(), 3);
      expect(await transport.detect(['text'], 1), [
        [('en', 0.95)],
      ]);
    },
    skip: skip,
  );
}
