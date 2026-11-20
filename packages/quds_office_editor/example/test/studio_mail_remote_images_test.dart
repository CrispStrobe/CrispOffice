import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:quds_office_studio/studio_mail_remote_images.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwaDjwHwAExAJwNooHGQAAAABJRU5ErkJggg==',
);
final a = Uri.parse('https://images.invalid/a');
final b = Uri.parse('https://images.invalid/b');

final class _Client extends http.BaseClient {
  _Client(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  final requests = <http.BaseRequest>[];
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return respond(request);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse response({
  Stream<List<int>>? stream,
  int status = 200,
  int? length,
  String contentType = 'image/png',
}) => http.StreamedResponse(
  stream ?? Stream.value(png),
  status,
  contentLength: length,
  headers: {'content-type': contentType},
);

void main() {
  test(
    'valid static images use anonymous requests without redirects',
    () async {
      final clients = <_Client>[];
      final loader = StudioMailRemoteImageLoader(
        clientFactory: () {
          final client = _Client(
            (_) async => response(contentType: 'IMAGE/PNG; x=y'),
          );
          clients.add(client);
          return client;
        },
      );
      final loaded = await loader.load([a, a, b], isCurrent: () => true);
      expect(loaded, hasLength(2));
      expect(loaded.map((image) => image.attachment.partPath), [
        'remote:$a',
        'remote:$b',
      ]);
      expect(clients.every((client) => client.closed), isTrue);
      for (final request in clients.expand((client) => client.requests)) {
        expect(request.followRedirects, isFalse);
        expect(request.headers, isEmpty);
        expect(request.method, 'GET');
      }
    },
  );

  test(
    'oversized declared bodies are rejected before stream subscription',
    () async {
      var subscribed = false;
      final client = _Client(
        (_) async => response(
          length: 101,
          stream: Stream<List<int>>.multi((sink) {
            subscribed = true;
            sink.add([1]);
            sink.close();
          }),
        ),
      );
      final loader = StudioMailRemoteImageLoader(
        clientFactory: () => client,
        maxImageBytes: 100,
      );
      expect(await loader.load([a], isCurrent: () => true), isEmpty);
      expect(subscribed, isFalse);
      expect(client.closed, isTrue);
    },
  );

  test(
    'unknown-length bodies stop as soon as the byte limit is crossed',
    () async {
      var delivered = 0;
      Stream<List<int>> chunks() async* {
        for (var i = 0; i < 10; i++) {
          delivered++;
          yield List.filled(60, 0);
        }
      }

      final client = _Client((_) async => response(stream: chunks()));
      final loader = StudioMailRemoteImageLoader(
        clientFactory: () => client,
        maxImageBytes: 100,
      );
      expect(await loader.load([a], isCurrent: () => true), isEmpty);
      expect(delivered, 2);
      expect(client.closed, isTrue);
    },
  );

  test(
    'cumulative bytes bound the whole action, including later images',
    () async {
      var requests = 0;
      final loader = StudioMailRemoteImageLoader(
        clientFactory: () => _Client((_) async {
          requests++;
          return response();
        }),
        maxTotalBytes: png.length,
      );
      expect(await loader.load([a, b], isCurrent: () => true), hasLength(1));
      expect(requests, 1);
    },
  );

  test(
    'unadmitted schemes and credentials never create an HTTP client',
    () async {
      var clients = 0;
      final loader = StudioMailRemoteImageLoader(
        clientFactory: () {
          clients++;
          return _Client((_) async => response());
        },
      );
      expect(
        await loader.load([
          Uri.parse('file:///private'),
          Uri.parse('data:image/png,x'),
          Uri.parse('mailto:person@example.invalid'),
          Uri.parse('//relative.invalid/a'),
          Uri.parse('https://user:password@images.invalid/a'),
        ], isCurrent: () => true),
        isEmpty,
      );
      expect(clients, 0);
    },
  );

  test(
    'redirects and unsupported media never reach raster admission',
    () async {
      var requests = 0;
      final loader = StudioMailRemoteImageLoader(
        clientFactory: () => _Client((_) async {
          requests++;
          return requests == 1
              ? response(status: 302)
              : response(contentType: 'image/svg+xml');
        }),
      );
      expect(await loader.load([a, b], isCurrent: () => true), isEmpty);
      expect(requests, 2);
    },
  );

  test(
    'a deadline covers body consumption as well as response headers',
    () async {
      final stream = StreamController<List<int>>();
      final client = _Client((_) async => response(stream: stream.stream));
      final loader = StudioMailRemoteImageLoader(
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 20),
      );
      final loaded = await loader.load([a], isCurrent: () => true);
      expect(loaded, isEmpty);
      expect(client.closed, isTrue);
      await stream.close();
    },
  );

  test(
    'retired scope drops a late response and prevents the next request',
    () async {
      final pending = Completer<http.StreamedResponse>();
      final sent = Completer<void>();
      final client = _Client((_) {
        sent.complete();
        return pending.future;
      });
      var current = true;
      final loader = StudioMailRemoteImageLoader(clientFactory: () => client);
      final result = loader.load([a, b], isCurrent: () => current);
      await sent.future;
      current = false;
      pending.complete(response());
      expect(await result, isEmpty);
      expect(client.requests, hasLength(1));
      expect(client.closed, isTrue);
    },
  );

  test(
    'cancellation closes the owned client and never publishes a late image',
    () async {
      final pending = Completer<http.StreamedResponse>();
      final client = _Client((_) => pending.future);
      final loader = StudioMailRemoteImageLoader(clientFactory: () => client);
      final result = loader.load([a, b], isCurrent: () => true);
      loader.cancel();
      expect(client.closed, isTrue);
      pending.complete(response());
      expect(await result, isEmpty);
      expect(client.requests, hasLength(1));
    },
  );

  test('actual raster pixels are bounded cumulatively', () async {
    final loader = StudioMailRemoteImageLoader(
      clientFactory: () => _Client((_) async => response()),
    );
    expect(
      await loader.load([a, b], isCurrent: () => true, maxImagePixels: 1),
      hasLength(1),
    );
  });

  test(
    'at most eight sources are fetched and a loader cannot be replayed',
    () async {
      var requests = 0;
      final loader = StudioMailRemoteImageLoader(
        clientFactory: () => _Client((_) async {
          requests++;
          return response();
        }),
      );
      expect(
        await loader.load([
          for (var i = 0; i < 20; i++) Uri.parse('https://images.invalid/$i'),
        ], isCurrent: () => true),
        hasLength(8),
      );
      expect(requests, 8);
      await expectLater(
        loader.load([a], isCurrent: () => true),
        throwsStateError,
      );
    },
  );
}
