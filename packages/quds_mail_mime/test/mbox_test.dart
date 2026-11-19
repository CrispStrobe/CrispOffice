import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:test/test.dart';

const _separator = 'From sender@example.test Thu Nov 19 14:20:00 2026\n';
const _first = 'From: sender@example.test\nSubject: First\n\nfirst body\n\n';
const _second =
    'From: second@example.test\r\nSubject: Second\r\n\r\nsecond body';

void main() {
  group('streaming MBOX framing and byte preservation', () {
    for (final size in [1, 2, 3, 5, 17, 64, 1024]) {
      test(
        'split size $size preserves both records and line endings',
        () async {
          final entries = await readMailMbox(
            _chunks(utf8.encode('$_separator$_first$_separator$_second'), size),
          ).toList();
          expect(entries.map((entry) => entry.ordinal), [1, 2]);
          expect(entries.map((entry) => entry.problem), [null, null]);
          expect(entries[0].bytes, utf8.encode(_first));
          expect(entries[1].bytes, utf8.encode(_second));
        },
      );
    }

    test(
      'every single boundary split preserves the exact wire bytes',
      () async {
        final wire = utf8.encode('$_separator$_first$_separator$_second');
        for (var split = 0; split <= wire.length; split++) {
          final entries = await readMailMbox(
            Stream.fromIterable([wire.sublist(0, split), wire.sublist(split)]),
          ).toList();
          expect(entries, hasLength(2), reason: 'split $split');
          expect(entries[0].bytes, utf8.encode(_first), reason: 'split $split');
          expect(
            entries[1].bytes,
            utf8.encode(_second),
            reason: 'split $split',
          );
        }
      },
    );

    test(
      'unencoded non-UTF8 octets and a final partial line survive',
      () async {
        final record = <int>[
          ...ascii.encode('Subject: bytes\r\n\r\n'),
          0,
          127,
          128,
          255,
          13,
          10,
          254,
        ];
        final entries = await readMailMbox(
          _chunks([...ascii.encode(_separator), ...record], 1),
        ).toList();
        expect(entries.single.bytes, record);
      },
    );

    test('mboxrd removes exactly one quoting level from From lines', () async {
      const quoted =
          'Subject: quotes\n\n>From one\n>>From two\n>>>From three\n'
          '>Other\n>>Another\n>Fro\n>From\n';
      const expected =
          'Subject: quotes\n\nFrom one\n>From two\n>>From three\n'
          '>Other\n>>Another\n>Fro\n>From\n';
      final entries = await _read('$_separator$quoted', chunkSize: 1);
      expect(entries.single.bytes, utf8.encode(expected));
    });

    test('mboxo preserves multiple leading quote characters', () async {
      const quoted = 'Subject: quotes\n\n>From one\n>>From two\n>>>From three';
      const expected = 'Subject: quotes\n\nFrom one\n>>From two\n>>>From three';
      final entries = await readMailMbox(
        _chunks(utf8.encode('$_separator$quoted'), 1),
        dialect: MailMboxDialect.mboxo,
      ).toList();
      expect(entries.single.bytes, utf8.encode(expected));
    });

    test(
      'long quote runs retain mboxrd semantics without a line allocation',
      () async {
        final quotes = '>' * 5000;
        final entries = await _read(
          '${_separator}Subject: quotes\n\n${quotes}From content\n',
          chunkSize: 37,
        );
        expect(
          entries.single.bytes,
          utf8.encode('Subject: quotes\n\n${'>' * 4999}From content\n'),
        );
      },
    );

    test(
      'unterminated quote runs and incomplete From prefixes survive',
      () async {
        for (final suffix in [
          '>',
          '>>>>',
          '>F',
          '>>Fro',
          'F',
          'Fro',
          'From text',
        ]) {
          final record = 'Subject: ending\n\n$suffix';
          final entries = await _read('$_separator$record', chunkSize: 1);
          expect(entries.single.bytes, utf8.encode(record), reason: suffix);
        }
      },
    );

    test(
      'From-looking body lines without a complete envelope are preserved',
      () async {
        const record =
            'Subject: boundary\n\nFrom this is ordinary prose\n'
            'From x Thu Nov 99 25:99:99 2026\nFrom x Date: today\n';
        final entries = await _read('$_separator$record', chunkSize: 3);
        expect(entries.single.bytes, utf8.encode(record));
      },
    );

    test(
      'overlong From candidate becomes ordinary bounded body data',
      () async {
        final record = 'Subject: boundary\n\nFrom ${'x' * 2000}\n';
        final entries = await _read('$_separator$record', chunkSize: 29);
        expect(entries.single.bytes, utf8.encode(record));
      },
    );

    for (final line in [
      'From MAILER-DAEMON Thu Nov  9 01:02:03 2026\n',
      'From sender Thu Nov 09 01:02:03 2026\n',
      'From sender Thu Nov 19 01:02:03 UTC 2026\n',
      'From sender Thu Nov 19 01:02:03 +0100 2026\n',
      'From sender Thu Nov 19 01:02:03 2026 +0100\n',
      'From sender Thu Nov 19 01:02:03 2026 remote from mailhost\n',
      'From <> Thu Nov 19 01:02:03 2026\r\n',
    ]) {
      test('accepts documented envelope variation ${line.trim()}', () async {
        final entries = await _read('$line$_first');
        expect(entries.single.bytes, utf8.encode(_first));
      });
    }

    test(
      'consecutive separators surface an empty record and continue',
      () async {
        final entries = await _read('$_separator$_separator$_first');
        expect(entries, hasLength(2));
        _problem(entries[0], MailProblemCode.invalidInput, ordinal: 1);
        expect(entries[1].ordinal, 2);
        expect(entries[1].bytes, utf8.encode(_first));
      },
    );

    for (final prefix in [
      '',
      '\n',
      'Subject: an EML is not an mbox\n\nbody\n',
      'junk\n$_separator$_first',
      '\ufeff$_separator$_first',
      'From sender invalid date\n$_first',
      _separator.trimRight(),
    ]) {
      test('rejects empty or malformed preamble ${prefix.length}', () async {
        final entries = await _read(prefix, chunkSize: 1);
        expect(entries, hasLength(1));
        _problem(entries.single, MailProblemCode.invalidInput);
      });
    }

    test('empty chunks do not create messages', () async {
      final entries = await readMailMbox(
        Stream.fromIterable([
          <int>[],
          utf8.encode(_separator),
          <int>[],
          utf8.encode(_first),
          <int>[],
        ]),
      ).toList();
      expect(entries.single.bytes, utf8.encode(_first));
    });

    test(
      'Content-Length variants reject mboxcl and stop before false splits',
      () async {
        for (final header in [
          'Content-Length',
          'content-length',
          'CONTENT-LENGTH',
        ]) {
          final entries = await _read(
            '${_separator}Subject: cl\n$header: 9000\n\nbody\n'
            '$_separator$_first',
            chunkSize: 2,
          );
          expect(entries, hasLength(1));
          _problem(entries.single, MailProblemCode.unsupported);
        }
      },
    );

    test(
      'Content-Length in the body does not reject an ordinary message',
      () async {
        const record = 'Subject: ordinary\n\nContent-Length: documentation\n';
        final entries = await _read('$_separator$record');
        expect(entries.single.bytes, utf8.encode(record));
      },
    );

    test('extracted records are independently owned byte buffers', () async {
      final entries = await _read('$_separator$_first$_separator$_second');
      entries[0].bytes![0] = 0;
      expect(entries[1].bytes, utf8.encode(_second));
    });
  });

  group('MBOX bounds and source failure handling', () {
    test('a message exactly at the raw budget is admitted', () async {
      final bytes = utf8.encode(_first);
      final entries = await readMailMbox(
        Stream.value([...utf8.encode(_separator), ...bytes]),
        maxMessageBytes: bytes.length,
      ).toList();
      expect(entries.single.bytes, bytes);
    });

    test('one byte over budget fails without truncated success', () async {
      final entries = await readMailMbox(
        Stream.value(utf8.encode('$_separator$_first')),
        maxMessageBytes: utf8.encode(_first).length - 1,
      ).toList();
      _problem(entries.single, MailProblemCode.quotaExceeded);
    });

    test(
      'quoted container bytes do not count toward extracted MIME budget',
      () async {
        const decoded = 'Subject: quotes\n\nFrom line\n';
        const encoded = 'Subject: quotes\n\n>From line\n';
        final entries = await readMailMbox(
          _chunks(utf8.encode('$_separator$encoded'), 1),
          maxMessageBytes: decoded.length,
        ).toList();
        expect(entries.single.bytes, utf8.encode(decoded));
      },
    );

    test(
      'oversized record is isolated and the following record succeeds',
      () async {
        final oversized = 'Subject: huge\n\n${'x' * 200000}\n';
        final entries = await readMailMbox(
          _chunks(utf8.encode('$_separator$oversized$_separator$_first'), 17),
          maxMessageBytes: 100,
        ).toList();
        expect(entries, hasLength(2));
        _problem(entries[0], MailProblemCode.quotaExceeded, ordinal: 1);
        expect(entries[1].ordinal, 2);
        expect(entries[1].bytes, utf8.encode(_first));
      },
    );

    test(
      'oversized quote run is discarded and the next frame is retained',
      () async {
        final oversized = 'Subject: huge\n\n${'>' * 200000}From data\n';
        final entries = await readMailMbox(
          Stream.value(utf8.encode('$_separator$oversized$_separator$_first')),
          maxMessageBytes: 100,
        ).toList();
        expect(entries, hasLength(2));
        _problem(entries[0], MailProblemCode.quotaExceeded);
        expect(entries[1].bytes, utf8.encode(_first));
      },
    );

    test('one-byte content limit still recognizes a full separator', () async {
      final entries = await readMailMbox(
        Stream.value(utf8.encode('${_separator}x')),
        maxMessageBytes: 1,
      ).toList();
      expect(entries.single.bytes, [120]);
    });

    test(
      'exact message-count budget does not create a false overflow',
      () async {
        final entries = await readMailMbox(
          Stream.value(utf8.encode('$_separator$_first')),
          maxMessages: 1,
        ).toList();
        expect(entries.single.bytes, utf8.encode(_first));
      },
    );

    test(
      'next record beyond maxMessages produces a terminal quota result',
      () async {
        var closed = false;
        final controller = StreamController<List<int>>(
          onCancel: () => closed = true,
        );
        final result = readMailMbox(controller.stream, maxMessages: 1).toList();
        controller.add(utf8.encode('$_separator$_first$_separator$_second'));
        final entries = await result.timeout(const Duration(seconds: 2));
        expect(closed, isTrue);
        expect(entries, hasLength(2));
        expect(entries.first.bytes, utf8.encode(_first));
        _problem(entries.last, MailProblemCode.quotaExceeded, ordinal: 2);
        await controller.close();
      },
    );

    test('invalid limits never subscribe to the input stream', () async {
      for (final (bytes, messages) in [
        (0, 1),
        (1, 0),
        (-1, 1),
        (1, 10000001),
      ]) {
        var listened = false;
        final controller = StreamController<List<int>>(
          onListen: () => listened = true,
        );
        final entries = await readMailMbox(
          controller.stream,
          maxMessageBytes: bytes,
          maxMessages: messages,
        ).toList();
        _problem(entries.single, MailProblemCode.invalidInput);
        expect(listened, isFalse);
        unawaited(controller.close());
      }
    });

    test('source exceptions become content-free fixed failures', () async {
      final entries = await readMailMbox(
        Stream<List<int>>.error(StateError('SECRET_FILE_PATH_AND_MESSAGE')),
      ).toList();
      _problem(entries.single, MailProblemCode.storageFailure);
      expect(entries.single.problem.toString(), isNot(contains('SECRET')));
    });

    test('a source failure never emits an incomplete MIME record', () async {
      final controller = StreamController<List<int>>();
      final result = readMailMbox(controller.stream).toList();
      controller.add(utf8.encode('$_separator$_first'));
      controller.addError(StateError('SECRET'));
      final entries = await result;
      _problem(entries.single, MailProblemCode.storageFailure);
      await controller.close();
    });

    test(
      'non-byte values are rejected rather than silently truncated',
      () async {
        for (final byte in [-1, 256, 100000]) {
          final entries = await readMailMbox(
            Stream.value([...utf8.encode('$_separator$_first'), byte]),
          ).toList();
          _problem(entries.single, MailProblemCode.invalidInput);
        }
      },
    );
  });

  group('MBOX cancellation and timer ownership', () {
    test('pre-cancellation does not open the source', () async {
      final cancellation = MailCancellationSource()..cancel();
      var listened = false;
      final controller = StreamController<List<int>>(
        onListen: () => listened = true,
      );
      final entries = await readMailMbox(
        controller.stream,
        cancellation: cancellation.token,
      ).toList();
      _problem(entries.single, MailProblemCode.cancelled);
      expect(listened, isFalse);
      unawaited(controller.close());
    });

    test(
      'stalled source cancellation cancels upstream and all polling timers',
      () async {
        final timers = <Timer>[];
        await runZoned(
          () async {
            final cancellation = MailCancellationSource();
            var closed = false;
            final controller = StreamController<List<int>>(
              onCancel: () => closed = true,
            );
            final result = readMailMbox(
              controller.stream,
              cancellation: cancellation.token,
            ).toList();
            Timer(const Duration(milliseconds: 5), cancellation.cancel);
            final entries = await result.timeout(const Duration(seconds: 2));
            _problem(entries.single, MailProblemCode.cancelled);
            expect(closed, isTrue);
            expect(timers, isNotEmpty);
            expect(timers.every((timer) => !timer.isActive), isTrue);
            // A late source event after cancellation is not an unhandled read.
            controller.addError(StateError('LATE_SECRET_SOURCE_ERROR'));
            await controller.close();
          },
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              final timer = parent.createPeriodicTimer(
                zone,
                duration,
                callback,
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
      },
    );

    test('normal completion leaves no periodic cancellation timer', () async {
      final timers = <Timer>[];
      await runZoned(
        () async {
          final cancellation = MailCancellationSource();
          final entries = await readMailMbox(
            _chunks(utf8.encode('$_separator$_first'), 7),
            cancellation: cancellation.token,
          ).toList();
          expect(entries.single.bytes, utf8.encode(_first));
          expect(timers, isNotEmpty);
          expect(timers.every((timer) => !timer.isActive), isTrue);
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createPeriodicTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
    });

    test(
      'cancellation while scanning a large chunk yields to the event loop',
      () async {
        final cancellation = MailCancellationSource();
        final bytes = utf8.encode(
          '${_separator}Subject: huge\n\n${'x' * 500000}',
        );
        final chunk = _SignalList(bytes, () => Timer.run(cancellation.cancel));
        final entries = await readMailMbox(
          Stream.value(chunk),
          cancellation: cancellation.token,
        ).toList().timeout(const Duration(seconds: 2));
        _problem(entries.single, MailProblemCode.cancelled);
        expect(chunk.reads, lessThan(bytes.length));
      },
    );

    test('consumer cancellation after one record closes upstream', () async {
      var closed = false;
      final controller = StreamController<List<int>>(
        onCancel: () => closed = true,
      );
      final result = readMailMbox(controller.stream).first;
      controller.add(utf8.encode('$_separator$_first$_separator$_second'));
      final entry = await result;
      expect(entry.bytes, utf8.encode(_first));
      expect(closed, isTrue);
      await controller.close();
    });

    test(
      'cancellation after an emitted record identifies the incomplete next one',
      () async {
        final cancellation = MailCancellationSource();
        final result = <MailMboxEntry>[];
        await for (final entry in readMailMbox(
          Stream.value(utf8.encode('$_separator$_first$_separator$_second')),
          cancellation: cancellation.token,
        )) {
          result.add(entry);
          if (entry.isSuccess) cancellation.cancel();
        }
        expect(result, hasLength(2));
        expect(result.first.bytes, utf8.encode(_first));
        _problem(result.last, MailProblemCode.cancelled, ordinal: 2);
      },
    );
  });
}

Future<List<MailMboxEntry>> _read(String input, {int chunkSize = 4096}) =>
    readMailMbox(_chunks(utf8.encode(input), chunkSize)).toList();

Stream<List<int>> _chunks(List<int> bytes, int size) async* {
  for (var start = 0; start < bytes.length; start += size) {
    final end = start + size < bytes.length ? start + size : bytes.length;
    yield bytes.sublist(start, end);
  }
}

void _problem(MailMboxEntry entry, MailProblemCode code, {int ordinal = 1}) {
  expect(entry.ordinal, ordinal);
  expect(entry.bytes, isNull);
  expect(entry.isSuccess, isFalse);
  expect(entry.problem?.code, code);
}

final class _SignalList extends ListBase<int> {
  _SignalList(this.bytes, this.signal);
  final List<int> bytes;
  final void Function() signal;
  int reads = 0;
  @override
  int get length => bytes.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  int operator [](int index) {
    if (++reads == 5000) signal();
    return bytes[index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}
