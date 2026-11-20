import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_remote_images.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAF0lEQVR4nGP4z8DwHwwZ/v8HIyABZgEAqm8O8tH19KMAAAAASUVORK5CYII=',
);
const _url = 'https://images.example/figure.png';
const _html = '<p>Body</p><img src="$_url">';

MailParseResult _result(
  String html, {
  List<MailAttachment> attachments = const [],
}) => MailParseResult(
  status: MailParseStatus.complete,
  message: MailMessage(
    raw: MailBytes(Uint8List(0)),
    envelope: MailEnvelope(subject: 'Remote images'),
    body: MailBody(html: html),
    attachments: attachments,
  ),
);

MailReaderController _reader({
  String html = _html,
  MailReadBudget budget = const MailReadBudget(),
  List<MailAttachment> attachments = const [],
}) => MailReaderController(
  result: _result(html, attachments: attachments),
  budget: budget,
);

http.StreamedResponse _response(
  Stream<List<int>> body, {
  int status = 200,
  int? length,
  String mediaType = 'image/png',
}) => http.StreamedResponse(
  body,
  status,
  contentLength: length,
  headers: {'content-type': mediaType},
);

final class _Client extends http.BaseClient {
  _Client(this.respond);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest) respond;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      respond(request);
  @override
  void close() => closed = true;
}

final class _Harness {
  _Harness(this.respond, {this.timeout = const Duration(seconds: 15)});
  final Duration timeout;
  final FutureOr<http.StreamedResponse> Function(Uri) respond;
  final clients = <_Client>[];
  final requests = <Uri>[];
  late final loader = StudioMailRemoteImageLoader(
    timeout: timeout,
    createClient: () {
      final client = _Client((request) {
        expect(request.method, 'GET');
        requests.add(request.url);
        return respond(request.url);
      });
      clients.add(client);
      return client;
    },
  );
  void expectClosed() =>
      expect(clients.every((client) => client.closed), isTrue);
}

// An oversized incoming chunk must be rejected by length before its contents
// are copied into an owned buffer. Reading any element is observable here.
final class _UnreadableChunk extends ListBase<int> {
  _UnreadableChunk(this.length);
  @override
  int length;
  int reads = 0;
  @override
  int operator [](int index) {
    reads++;
    throw StateError('Oversized chunk was read');
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}

void main() {
  test('only an explicit load acquires and admits exact PNG bytes', () async {
    final reader = _reader();
    addTearDown(reader.dispose);
    final harness = _Harness(
      (_) => _response(
        Stream.fromIterable([_png.sublist(0, 20), _png.sublist(20)]),
        mediaType: 'image/png; charset=binary',
      ),
    );
    final loader = harness.loader;
    expect(harness.requests, isEmpty);
    expect(reader.presentation.images, isEmpty);
    expect(await loader.load(reader, isCurrent: () => true), 1);
    final image = reader.presentation.images.single;
    expect((image.width, image.height), (3, 2));
    expect(image.attachment.content.bytes, _png);
    expect(image.attachment.partPath, 'remote:$_url');
    harness.expectClosed();
  });

  test(
    'URL acquisition uses only actual supported unsuppressed img sources',
    () async {
      final reader = _reader(
        html: '''
<!-- <img src="https://comment.example/no"> -->
<script src="https://script.example/no"><img src="https://fake.example/no"></script>
<iframe src="https://frame.example/no"><img src="https://hidden.example/no"></iframe>
<object data="https://object.example/no"><img src="https://object-child.example/no"></object>
<div src="https://div.example/no" data-src="https://data.example/no">Visible</div>
<img data-src="https://data.example/no" src="https://images.example/a.png?a=1&amp;b=2" srcset="https://srcset.example/no 2x">
<IMG SRC=http://images.example/b.png>
<img src="https://images.example/a.png?a=1&amp;b=2">
<img src="file:///no"><img src="mailto:a@example.test"><img src="/relative">
<img src="https://user:secret@example.test/no"><img src="javascript:alert(1)">
''',
      );
      addTearDown(reader.dispose);
      final harness = _Harness((_) => _response(Stream.value(_png)));
      expect(await harness.loader.load(reader, isCurrent: () => true), 2);
      expect(harness.requests.map((uri) => uri.toString()), [
        'https://images.example/a.png?a=1&b=2',
        'http://images.example/b.png',
      ]);
      harness.expectClosed();
    },
  );

  test(
    'one explicit action fetches at most eight unique projected images',
    () async {
      final reader = _reader(
        html: [
          for (var i = 0; i < 10; i++)
            '<img src="https://images.example/$i.png">',
        ].join(),
      );
      addTearDown(reader.dispose);
      final harness = _Harness((_) => _response(Stream.value(_png)));
      expect(await harness.loader.load(reader, isCurrent: () => true), 8);
      expect(harness.requests, hasLength(8));
      harness.expectClosed();
    },
  );

  test(
    'oversized declared content is cancelled without reading a chunk',
    () async {
      var reads = 0;
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final reader = _reader();
      addTearDown(reader.dispose);
      final harness = _Harness(
        (_) => _response(
          body.stream.map((chunk) {
            reads++;
            return chunk;
          }),
          length: StudioMailRemoteImageLoader.maxResponseBytes + 1,
        ),
      );
      expect(await harness.loader.load(reader, isCurrent: () => true), 0);
      expect(reads, 0);
      expect(cancelled, isTrue);
      expect(reader.presentation.images, isEmpty);
      harness.expectClosed();
      await body.close();
    },
  );

  for (final precedingBytes in [
    0,
    StudioMailRemoteImageLoader.maxResponseBytes,
  ]) {
    test(
      'unknown-length response rejects over-cap chunk before copying after $precedingBytes bytes',
      () async {
        final oversized = _UnreadableChunk(
          precedingBytes == 0
              ? StudioMailRemoteImageLoader.maxResponseBytes + 1
              : 1,
        );
        var yielded = 0;
        var cancelled = false;
        Stream<List<int>> body() async* {
          try {
            if (precedingBytes > 0) {
              yielded++;
              yield Uint8List(precedingBytes);
            }
            yielded++;
            yield oversized;
            yielded++;
            yield _png;
          } finally {
            cancelled = true;
          }
        }

        final reader = _reader();
        addTearDown(reader.dispose);
        final harness = _Harness((_) => _response(body()));
        expect(await harness.loader.load(reader, isCurrent: () => true), 0);
        await Future<void>.delayed(Duration.zero);
        expect(oversized.reads, 0);
        expect(yielded, precedingBytes == 0 ? 1 : 2);
        expect(cancelled, isTrue);
        harness.expectClosed();
      },
    );
  }

  for (final delta in [0, -1]) {
    test(
      'actual bytes enforce the reader attachment limit delta=$delta despite declared length',
      () async {
        final reader = _reader(
          budget: MailReadBudget(maxAttachmentBytes: _png.length + delta),
        );
        addTearDown(reader.dispose);
        final harness = _Harness(
          (_) => _response(Stream.value(_png), length: 1),
        );
        expect(
          await harness.loader.load(reader, isCurrent: () => true),
          delta == 0 ? 1 : 0,
        );
        harness.expectClosed();
      },
    );
  }

  for (final (status, mediaType) in [
    (404, 'image/png'),
    (200, 'image/svg+xml'),
  ]) {
    test(
      'unusable response status=$status media=$mediaType cancels body',
      () async {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final reader = _reader();
        addTearDown(reader.dispose);
        final harness = _Harness(
          (_) => _response(body.stream, status: status, mediaType: mediaType),
        );
        expect(await harness.loader.load(reader, isCurrent: () => true), 0);
        expect(cancelled, isTrue);
        harness.expectClosed();
        await body.close();
      },
    );
  }

  test(
    'byte-valid image exceeding the reader pixel limit is not admitted',
    () async {
      final reader = _reader(budget: const MailReadBudget(maxImagePixels: 5));
      addTearDown(reader.dispose);
      final before = reader.presentation;
      final harness = _Harness((_) => _response(Stream.value(_png)));
      expect(await harness.loader.load(reader, isCurrent: () => true), 0);
      expect(reader.presentation, same(before));
      harness.expectClosed();
    },
  );

  test(
    'existing CID and new remote pixels share the same reader budget',
    () async {
      final reader = _reader(
        html:
            '<img src="cid:local"><img src="$_url"><img src="https://images.example/second.png">',
        attachments: [
          MailAttachment(
            partPath: '1.2',
            mediaType: 'image/png',
            displayName: 'local.png',
            content: MailBytes(_png),
            contentId: 'local',
          ),
        ],
        budget: const MailReadBudget(maxImagePixels: 12),
      );
      addTearDown(reader.dispose);
      expect(reader.presentation.images, hasLength(1));
      final harness = _Harness((_) => _response(Stream.value(_png)));
      expect(await harness.loader.load(reader, isCurrent: () => true), 1);
      expect(reader.presentation.images, hasLength(2));
      expect(harness.requests, hasLength(1));
      harness.expectClosed();
    },
  );

  test(
    'final cumulative body and remote byte admission cannot be bypassed by fetching',
    () async {
      const html = '$_html<img src="https://images.example/second.png">';
      final reader = _reader(
        html: html,
        budget: MailReadBudget(
          maxDecodedBytes: html.length + _png.length * 2 - 1,
        ),
      );
      addTearDown(reader.dispose);
      final harness = _Harness((_) => _response(Stream.value(_png)));
      expect(await harness.loader.load(reader, isCurrent: () => true), 1);
      expect(reader.presentation.images, hasLength(1));
      expect(
        utf8.encode(html).length +
            reader.presentation.images.single.attachment.content.length,
        lessThanOrEqualTo(reader.budget.maxDecodedBytes),
      );
      expect(harness.requests, hasLength(2));
      harness.expectClosed();
    },
  );

  for (final stale in ['host', 'message', 'disposed']) {
    test('$stale target cannot receive a late successful response', () async {
      final reader = _reader();
      addTearDown(() {
        if (!reader.isDisposed) reader.dispose();
      });
      final gate = Completer<http.StreamedResponse>();
      var current = true;
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final harness = _Harness((_) => gate.future);
      final loading = harness.loader.load(reader, isCurrent: () => current);
      await Future<void>.delayed(Duration.zero);
      if (stale == 'host') current = false;
      if (stale == 'message') {
        reader.replaceResult(_result('<p>Replacement</p>'));
      }
      if (stale == 'disposed') reader.dispose();
      final retained = reader.presentation;
      gate.complete(_response(body.stream));
      expect(await loading, 0);
      expect(reader.presentation, same(retained));
      expect(cancelled, isTrue);
      harness.expectClosed();
      await body.close();
    });
  }

  test('one deadline covers headers and stalled body, then cancels', () async {
    final reader = _reader();
    addTearDown(reader.dispose);
    final gate = Completer<http.StreamedResponse>();
    var cancelled = false;
    var listened = false;
    final body = StreamController<List<int>>(
      onListen: () => listened = true,
      onCancel: () => cancelled = true,
    );
    final harness = _Harness(
      (_) => gate.future,
      timeout: const Duration(milliseconds: 100),
    );
    var completed = false;
    final loading = harness.loader.load(reader, isCurrent: () => true).then((
      count,
    ) {
      completed = true;
      return count;
    });
    // Headers consume part of the same request deadline. A separately reset
    // body timeout would still be pending when the ordered checkpoint fires.
    final headers = Timer(const Duration(milliseconds: 60), () {
      gate.complete(_response(body.stream));
    });
    addTearDown(headers.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(listened, isTrue);
    expect(completed, isTrue);
    expect(await loading, 0);
    expect(cancelled, isTrue);
    harness.expectClosed();
    await body.close();
  });

  test(
    'timed-out headers close the client and discard any late response',
    () async {
      final reader = _reader();
      addTearDown(reader.dispose);
      final gate = Completer<http.StreamedResponse>();
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final harness = _Harness(
        (_) => gate.future,
        timeout: const Duration(milliseconds: 20),
      );
      expect(
        await harness.loader
            .load(reader, isCurrent: () => true)
            .timeout(const Duration(seconds: 1)),
        0,
      );
      harness.expectClosed();
      gate.complete(_response(body.stream));
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      expect(reader.presentation.images, isEmpty);
      await body.close();
    },
  );
}
