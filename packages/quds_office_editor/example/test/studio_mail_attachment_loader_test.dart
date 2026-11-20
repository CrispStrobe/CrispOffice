import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_attachment.dart';
import 'package:quds_office_studio/studio_mail_attachment_loader.dart';

PlatformFile _bytes(String name, List<int> data, {int? size}) => PlatformFile(
  name: name,
  size: size ?? data.length,
  bytes: Uint8List.fromList(data),
);
Matcher _problem(StudioMailAttachmentProblem problem) => throwsA(
  isA<StudioMailAttachmentException>().having(
    (error) => error.problem,
    'problem',
    problem,
  ),
);

void main() {
  test('reads selected streams in order and owns their exact bytes', () async {
    final source = Uint8List.fromList([0, 255, 128, 42]);
    final existing = StudioMailAttachments.from([
      StudioMailAttachment(name: 'existing.docx', bytes: Uint8List(0)),
    ]);
    final result = await StudioMailAttachmentLoader().read([
      PlatformFile(name: '研究.pdf', size: 4, bytes: source),
      PlatformFile(
        name: 'same.xlsx',
        size: 4,
        readStream: Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
      ),
      _bytes('same.xlsx', [9]),
    ], existing: existing);
    source.fillRange(0, source.length, 0);
    expect(result.items.map((item) => item.name), [
      'existing.docx',
      '研究.pdf',
      'same.xlsx',
      'same.xlsx',
    ]);
    expect(result.totalBytes, 9);
    expect(result.items[1].content.bytes, [0, 255, 128, 42]);
    expect(result.items[2].content.bytes, [1, 2, 3, 4]);
    expect(result.items[3].content.bytes, [9]);
    expect(existing.items, hasLength(1));
  });

  test('validates all names before starting the first file read', () async {
    var listened = false;
    final stream = StreamController<List<int>>(onListen: () => listened = true);
    await expectLater(
      StudioMailAttachmentLoader().read([
        PlatformFile(name: 'good.pdf', size: 0, readStream: stream.stream),
        _bytes('../private.txt', []),
      ]),
      _problem(StudioMailAttachmentProblem.invalidName),
    );
    expect(listened, isFalse);
    // An unlistened single-subscription controller's close future waits for
    // a subscriber. Its stream is deliberately never opened in this case.
    unawaited(stream.close());
  });

  test(
    'preflights count and total metadata against existing selection',
    () async {
      final ten = StudioMailAttachments.from(
        List.generate(
          10,
          (index) =>
              StudioMailAttachment(name: '$index.txt', bytes: Uint8List(0)),
        ),
      );
      await expectLater(
        StudioMailAttachmentLoader().read([
          _bytes('eleven.txt', []),
        ], existing: ten),
        _problem(StudioMailAttachmentProblem.tooMany),
      );
      final existing = StudioMailAttachments.from([
        StudioMailAttachment(name: 'one.bin', bytes: Uint8List.fromList([1])),
      ]);
      await expectLater(
        StudioMailAttachmentLoader().read([
          PlatformFile(
            name: 'large.bin',
            size: StudioMailAttachments.maxTotalBytes,
          ),
        ], existing: existing),
        _problem(StudioMailAttachmentProblem.tooLarge),
      );
      await expectLater(
        StudioMailAttachmentLoader().read([
          PlatformFile(name: 'negative.bin', size: -1),
        ]),
        throwsA(isA<StudioMailAttachmentReadFailure>()),
      );
      expect(existing.totalBytes, 1);
    },
  );

  for (final declared in [0, 2]) {
    test(
      'refuses picker bytes whose actual size differs from $declared',
      () async {
        await expectLater(
          StudioMailAttachmentLoader().read([
            _bytes('changed.txt', [42], size: declared),
          ]),
          throwsA(isA<StudioMailAttachmentReadFailure>()),
        );
      },
    );
  }

  test('refuses streams that grow or are truncated after selection', () async {
    for (final chunks in <List<List<int>>>[
      [
        [1],
      ],
      [
        [1, 2],
        [3],
      ],
    ]) {
      await expectLater(
        StudioMailAttachmentLoader().read([
          PlatformFile(
            name: 'changed.bin',
            size: 2,
            readStream: Stream.fromIterable(chunks),
          ),
        ]),
        throwsA(isA<StudioMailAttachmentReadFailure>()),
      );
    }
  });

  test(
    'actual stream quota is enforced before retaining a large chunk',
    () async {
      await expectLater(
        StudioMailAttachmentLoader().read([
          PlatformFile(
            name: 'oversized.bin',
            size: 0,
            readStream: Stream.value(
              Uint8List(StudioMailAttachments.maxTotalBytes + 1),
            ),
          ),
        ]),
        _problem(StudioMailAttachmentProblem.tooLarge),
      );
    },
  );

  test('exact size boundary and empty streams are supported', () async {
    final bytes = Uint8List(StudioMailAttachments.maxTotalBytes);
    bytes[bytes.length - 1] = 255;
    final result = await StudioMailAttachmentLoader().read([
      PlatformFile(
        name: 'maximum.bin',
        size: bytes.length,
        readStream: Stream.value(bytes),
      ),
      PlatformFile(
        name: 'empty.txt',
        size: 0,
        readStream: const Stream.empty(),
      ),
    ]);
    expect(result.totalBytes, StudioMailAttachments.maxTotalBytes);
    expect(result.items.first.content.bytes.last, 255);
    expect(result.items.last.length, 0);
  });

  test(
    'a failed selection leaves the previous immutable bundle untouched',
    () async {
      final existing = StudioMailAttachments.from([
        StudioMailAttachment(name: 'keep.pptx', bytes: Uint8List.fromList([7])),
      ]);
      await expectLater(
        StudioMailAttachmentLoader().read([
          _bytes('first.pdf', [1]),
          PlatformFile(
            name: 'second.pdf',
            size: 1,
            readStream: Stream.error(StateError('/private/secret.pdf')),
          ),
        ], existing: existing),
        throwsA(
          isA<StudioMailAttachmentReadFailure>().having(
            (error) => error.toString(),
            'redacted message',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(existing.items.single.name, 'keep.pptx');
      expect(existing.items.single.content.bytes, [7]);
    },
  );

  test(
    'cancellation completes pending read without waiting for teardown',
    () async {
      final cleanup = Completer<void>();
      final listening = Completer<void>();
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onListen: listening.complete,
        onCancel: () {
          cancelled = true;
          return cleanup.future;
        },
      );
      final loader = StudioMailAttachmentLoader();
      final pending = loader.read([
        PlatformFile(name: 'pending.pdf', size: 1, readStream: stream.stream),
      ]);
      final expectation = expectLater(
        pending,
        throwsA(isA<StudioMailAttachmentReadCancelled>()),
      );
      await listening.future;
      loader.cancel();
      await expectation.timeout(const Duration(seconds: 1));
      expect(cancelled, isTrue);
      cleanup.complete();
      await stream.close();
    },
  );

  test('total per-file deadline rejects an unresponsive source', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final loader = StudioMailAttachmentLoader(
      readTimeout: const Duration(milliseconds: 15),
    );
    await expectLater(
      loader.read([
        PlatformFile(name: 'stalled.pdf', size: 1, readStream: stream.stream),
      ]),
      throwsA(isA<StudioMailAttachmentReadFailure>()),
    );
    expect(cancelled, isTrue);
    await stream.close();
  });

  test('a loader cancelled before selection never subscribes', () async {
    final loader = StudioMailAttachmentLoader()..cancel();
    await expectLater(
      loader.read([
        _bytes('late.pdf', [1]),
      ]),
      throwsA(isA<StudioMailAttachmentReadCancelled>()),
    );
  });

  test('native selected paths use bounded file streams', () async {
    final directory = await Directory.systemTemp.createTemp('mail-attachment-');
    addTearDown(() => directory.delete(recursive: true));
    final path = directory.path;
    final file = File('$path/picked.bin');
    await file.writeAsBytes([0, 128, 255]);
    final result = await StudioMailAttachmentLoader().read([
      PlatformFile(name: 'picked.bin', size: 3, path: file.path),
    ]);
    expect(result.items.single.content.bytes, [0, 128, 255]);
    await file.writeAsBytes([4]);
    expect(result.items.single.content.bytes, [0, 128, 255]);
    await expectLater(
      StudioMailAttachmentLoader().read([
        PlatformFile(name: 'picked.bin', size: 3, path: file.path),
      ]),
      throwsA(isA<StudioMailAttachmentReadFailure>()),
    );
  });
}
