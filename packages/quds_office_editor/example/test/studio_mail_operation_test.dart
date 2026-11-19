// These tests deliberately exercise the protocol library's print side effect.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_operation.dart';

void main() {
  test(
    'contains synchronous protocol prints and preserves the return value',
    () {
      final output = <String>[];
      final result = _capture(output, () {
        print('caller before');
        final result = runStudioMailOperation(() {
          print('private protocol reply');
          return 42;
        });
        print('caller after');
        return result;
      });

      expect(result, 42);
      expect(output, ['caller before', 'caller after']);
    },
  );

  test('contains asynchronous prints before and after an await', () async {
    final output = <String>[];
    final result = await _capture(output, () async {
      final result = await runStudioMailOperation(() async {
        print('private before await');
        await Future<void>.delayed(Duration.zero);
        print('private after await');
        return 'completed';
      });
      print('caller resumed');
      return result;
    });

    expect(result, 'completed');
    expect(output, ['caller resumed']);
  });

  test(
    'registered future and timer callbacks retain the private zone',
    () async {
      final output = <String>[];
      final source = Completer<int>();
      final timerDone = Completer<void>();
      await _capture(output, () async {
        final future = runStudioMailOperation(() {
          Timer.run(() {
            print('private timer output');
            timerDone.complete();
          });
          return source.future.then((value) {
            print('private listener output');
            return value + 1;
          });
        });
        print('unrelated completion output');
        source.complete(5);
        expect(await future, 6);
        await timerDone.future;
        print('caller finished');
      });

      expect(output, ['unrelated completion output', 'caller finished']);
    },
  );

  test(
    'stream listeners registered during client construction stay contained',
    () async {
      final output = <String>[];
      final stream = StreamController<String>();
      final received = Completer<void>();
      await _capture(output, () async {
        final subscription = runStudioMailOperation(
          () => stream.stream.listen((event) {
            print('private event: $event');
            received.complete();
          }),
        );
        print('producer outside client zone');
        stream.add('private server field');
        await received.future;
        await subscription.cancel();
        await stream.close();
        print('outside cleanup complete');
      });

      expect(output, [
        'producer outside client zone',
        'outside cleanup complete',
      ]);
    },
  );

  test('a pending Mail operation does not suppress unrelated output', () async {
    final output = <String>[];
    final release = Completer<void>();
    await _capture(output, () async {
      final pending = runStudioMailOperation(() async {
        await release.future;
        print('private operation resumed');
      });
      await Future<void>.delayed(Duration.zero);
      print('unrelated asynchronous task');
      release.complete();
      await pending;
      print('unrelated task after completion');
    });

    expect(output, [
      'unrelated asynchronous task',
      'unrelated task after completion',
    ]);
  });

  test('does not swallow or replace a synchronous failure', () {
    final failure = StateError('controlled synchronous failure');
    final output = <String>[];
    _capture(output, () {
      expect(
        () => runStudioMailOperation<void>(() {
          print('private error context');
          throw failure;
        }),
        throwsA(same(failure)),
      );
      print('caller handled failure');
    });

    expect(output, ['caller handled failure']);
  });

  test('does not swallow or replace an asynchronous failure', () async {
    final failure = StateError('controlled asynchronous failure');
    final output = <String>[];
    await _capture(output, () async {
      final pending = runStudioMailOperation(() async {
        await Future<void>.delayed(Duration.zero);
        print('private asynchronous error context');
        throw failure;
      });
      await expectLater(pending, throwsA(same(failure)));
      print('caller handled asynchronous failure');
    });

    expect(output, ['caller handled asynchronous failure']);
  });
}

T _capture<T>(List<String> output, T Function() work) => runZoned(
  work,
  zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) => output.add(line),
  ),
);
