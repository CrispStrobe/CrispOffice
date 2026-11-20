import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quds_mail_core/quds_mail_core.dart';

import 'package:quds_office_studio/studio_mail_remote_images.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwaDjwHwAExAJwNooHGQAAAABJRU5ErkJggg==',
);
final _uri = Uri.parse('https://images.example.test/one.png');

class _Client extends http.BaseClient {
  _Client(this.response);
  final Future<http.StreamedResponse> Function(http.BaseRequest) response;
  final requests = <http.BaseRequest>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return response(request);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse _image() => http.StreamedResponse(
  Stream.fromIterable([_png.sublist(0, 20), _png.sublist(20)]),
  200,
  headers: {'content-type': 'Image/PNG; charset=binary'},
);

void main() {
  test(
    'explicit requests admit bounded static rasters and do not follow redirects',
    () async {
      final client = _Client((_) async => _image());
      final images = await loadStudioMailRemoteImages(
        candidates: [_uri, _uri],
        client: client,
        isCurrent: () => true,
        budget: const MailReadBudget(),
        availablePixels: 10,
      );
      expect(client.requests, hasLength(1));
      expect(client.requests.single.followRedirects, isFalse);
      expect(images, hasLength(1));
      expect((images.single.width, images.single.height), (1, 1));
      expect(images.single.attachment.content.bytes, _png);
      expect(() => images.clear(), throwsUnsupportedError);
    },
  );

  test(
    'image requests stop at the candidate and cumulative pixel limits',
    () async {
      final client = _Client((_) async => _image());
      final candidates = [
        for (var i = 0; i < 12; i++)
          Uri.parse('https://images.example.test/$i.png'),
      ];
      final images = await loadStudioMailRemoteImages(
        candidates: candidates,
        client: client,
        isCurrent: () => true,
        budget: const MailReadBudget(),
        availablePixels: 3,
      );
      expect(images, hasLength(3));
      expect(client.requests, hasLength(3));
      client.requests.clear();
      final bounded = await loadStudioMailRemoteImages(
        candidates: candidates,
        client: client,
        isCurrent: () => true,
        budget: const MailReadBudget(),
        availablePixels: 100,
      );
      expect(bounded, hasLength(8));
      expect(client.requests, hasLength(8));
    },
  );

  test(
    'untrusted content types, redirects and oversized declarations are not consumed',
    () async {
      for (final response in [
        (302, 'image/png', 0),
        (200, 'text/html', 0),
        (200, 'image/png', 100),
      ]) {
        var consumed = 0;
        final client = _Client(
          (_) async => http.StreamedResponse(
            Stream.value(_png).map((bytes) {
              consumed++;
              return bytes;
            }),
            response.$1,
            contentLength: response.$3,
            headers: {'content-type': response.$2},
          ),
        );
        final images = await loadStudioMailRemoteImages(
          candidates: [_uri],
          client: client,
          isCurrent: () => true,
          budget: const MailReadBudget(maxAttachmentBytes: 90),
          availablePixels: 10,
        );
        expect(images, isEmpty);
        expect(consumed, 0);
      }
    },
  );

  test(
    'streaming byte cap cancels before buffering an oversized body',
    () async {
      var chunks = 0;
      Stream<List<int>> bytes() async* {
        for (var i = 0; i < 3; i++) {
          chunks++;
          yield List.filled(6, 0);
        }
      }

      final client = _Client(
        (_) async => http.StreamedResponse(
          bytes(),
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      final images = await loadStudioMailRemoteImages(
        candidates: [_uri],
        client: client,
        isCurrent: () => true,
        budget: const MailReadBudget(maxAttachmentBytes: 10),
        availablePixels: 10,
      );
      expect(images, isEmpty);
      expect(chunks, 2);
    },
  );

  test('retired reader refuses a late response and further requests', () async {
    var current = true;
    final pending = Completer<http.StreamedResponse>();
    final client = _Client((_) => pending.future);
    final future = loadStudioMailRemoteImages(
      candidates: [_uri, Uri.parse('https://images.example.test/two.png')],
      client: client,
      isCurrent: () => current,
      budget: const MailReadBudget(),
      availablePixels: 10,
    );
    current = false;
    pending.complete(_image());
    expect(await future, isEmpty);
    expect(client.requests, hasLength(1));
  });

  test('timeout closes its client without replaying a request', () async {
    final client = _Client((_) => Completer<http.StreamedResponse>().future);
    final images = await loadStudioMailRemoteImages(
      candidates: [_uri],
      client: client,
      isCurrent: () => true,
      budget: const MailReadBudget(),
      availablePixels: 10,
      timeout: const Duration(milliseconds: 1),
    );
    expect(images, isEmpty);
    expect(client.closed, isTrue);
    expect(client.requests, hasLength(1));
  });

  test(
    'unsupported URI schemes and credential-bearing URLs are never requested',
    () async {
      final client = _Client((_) async => _image());
      final images = await loadStudioMailRemoteImages(
        candidates: [
          Uri.parse('file:///private/image.png'),
          Uri.parse('https://user:secret@images.example.test/a'),
        ],
        client: client,
        isCurrent: () => true,
        budget: const MailReadBudget(),
        availablePixels: 10,
      );
      expect(images, isEmpty);
      expect(client.requests, isEmpty);
    },
  );
}
