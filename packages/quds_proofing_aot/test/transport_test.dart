import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

void main() {
  group('endpoint consent', () {
    test(
      'loopback is allowed, external and ambiguous URLs require opt-in',
      () async {
        for (final String url in <String>[
          'http://127.0.0.1:17018/',
          'http://127.1.2.3/',
          'http://[::1]:17018/',
          'http://localhost:17018/',
        ]) {
          await AotHttpTransport(endpoint: Uri.parse(url)).dispose();
        }
        for (final String url in <String>[
          'https://example.com/aot',
          'http://127.0.0.1.example.com/',
          'http://localhost.example.com/',
          'http://127.0.0.999/',
          'http://0.0.0.0:17018/',
        ]) {
          expect(
            () => AotHttpTransport(endpoint: Uri.parse(url)),
            throwsArgumentError,
          );
        }
        await AotHttpTransport(
          endpoint: Uri.parse('https://example.com/aot'),
          allowRemote: true,
        ).dispose();
      },
    );

    test(
      'rejects credentials, arbitrary schemes and preloaded query parameters',
      () {
        for (final String url in <String>[
          'file:///tmp/aot',
          'http://user:password@localhost/',
          'http://localhost/?query=secret',
          'http://localhost/#fragment',
        ]) {
          expect(
            () => AotHttpTransport(endpoint: Uri.parse(url), allowRemote: true),
            throwsArgumentError,
          );
        }
      },
    );
  });

  test(
    'POST form encodes exact Unicode text and does not follow redirects',
    () async {
      final _Client httpClient = _Client((http.BaseRequest base) async {
        expect(base.method, 'POST');
        expect(base.url, Uri.parse('http://127.0.0.1:17018/'));
        expect(base.followRedirects, isFalse);
        final http.Request request = base as http.Request;
        expect(request.bodyFields, <String, String>{
          'action': 'syntax',
          'langua': 'German',
          'query': '  Für 😀 & + = ?\n',
        });
        expect(
          request.headers['content-type'],
          startsWith('application/x-www-form-urlencoded'),
        );
        return _jsonResponse('[]');
      });
      final AotHttpTransport transport = AotHttpTransport(
        httpClient: httpClient,
      );
      addTearDown(transport.dispose);
      expect(
        await transport.request(
          action: 'syntax',
          language: AotLanguage.german,
          query: '  Für 😀 & + = ?\n',
        ),
        isEmpty,
      );
    },
  );

  test('omits withparadigms unless explicitly true for morphology', () async {
    final List<Map<String, String>> requests = <Map<String, String>>[];
    final AotHttpTransport transport = AotHttpTransport(
      httpClient: _Client((http.BaseRequest base) async {
        requests.add((base as http.Request).bodyFields);
        return _jsonResponse('[]');
      }),
    );
    addTearDown(transport.dispose);
    await transport.request(
      action: 'morph',
      language: AotLanguage.english,
      query: 'goes',
    );
    await transport.request(
      action: 'morph',
      language: AotLanguage.english,
      query: 'goes',
      withParadigms: true,
    );
    expect(requests.first.containsKey('withparadigms'), isFalse);
    expect(requests.last['withparadigms'], '1');
    expect(requests.last['langua'], 'English');
  });

  test(
    'HTTP failure, network failure and malformed JSON remain distinct',
    () async {
      for (final (int, String, AotErrorCode) scenario
          in <(int, String, AotErrorCode)>[
            (400, 'private error body', AotErrorCode.http),
            (302, '', AotErrorCode.http),
            (200, '<html>error</html>', AotErrorCode.malformedResponse),
          ]) {
        final AotHttpTransport transport = AotHttpTransport(
          httpClient: _Client(
            (http.BaseRequest _) async =>
                _jsonResponse(scenario.$2, status: scenario.$1),
          ),
        );
        await expectLater(
          transport.request(
            action: 'syntax',
            language: AotLanguage.german,
            query: 'private text',
          ),
          throwsA(
            isA<AotException>()
                .having((AotException e) => e.code, 'code', scenario.$3)
                .having(
                  (AotException e) => e.toString(),
                  'message',
                  isNot(contains('private')),
                ),
          ),
        );
        await transport.dispose();
      }
      final AotHttpTransport transport = AotHttpTransport(
        httpClient: _Client(
          (http.BaseRequest _) async =>
              throw http.ClientException('secret transport detail'),
        ),
      );
      addTearDown(transport.dispose);
      await expectLater(
        transport.request(
          action: 'syntax',
          language: AotLanguage.german,
          query: 'private',
        ),
        _throwsCode(AotErrorCode.unavailable),
      );
    },
  );

  test('request size rejection happens before any text is sent', () async {
    final _Client client = _Client(
      (http.BaseRequest _) async => _jsonResponse('[]'),
    );
    final AotHttpTransport transport = AotHttpTransport(
      httpClient: client,
      maximumQueryCodeUnits: 3,
    );
    addTearDown(transport.dispose);
    await expectLater(
      transport.request(
        action: 'syntax',
        language: AotLanguage.german,
        query: 'four',
      ),
      _throwsCode(AotErrorCode.limit),
    );
    expect(client.calls, 0);
  });

  test(
    'response bound checks declared size and actual streamed bytes',
    () async {
      for (final bool declared in <bool>[true, false]) {
        final AotHttpTransport transport = AotHttpTransport(
          maximumResponseBytes: 5,
          httpClient: _Client(
            (http.BaseRequest _) async => http.StreamedResponse(
              Stream<List<int>>.fromIterable(<List<int>>[
                utf8.encode('[1,'),
                utf8.encode('2,3]'),
              ]),
              200,
              contentLength: declared ? 7 : null,
            ),
          ),
        );
        await expectLater(
          transport.request(
            action: 'syntax',
            language: AotLanguage.german,
            query: 'word',
          ),
          _throwsCode(AotErrorCode.limit),
        );
        await transport.dispose();
      }
    },
  );

  test(
    'serializes requests and rejects overflow without growing the queue',
    () async {
      final Completer<http.StreamedResponse> first =
          Completer<http.StreamedResponse>();
      final _Client client = _Client(
        (http.BaseRequest _) async => first.future,
      );
      final AotHttpTransport transport = AotHttpTransport(
        httpClient: client,
        maximumPendingRequests: 2,
      );
      addTearDown(transport.dispose);
      final Future<Object?> a = transport.request(
        action: 'syntax',
        language: AotLanguage.german,
        query: 'a',
      );
      final Future<Object?> b = transport.request(
        action: 'syntax',
        language: AotLanguage.german,
        query: 'b',
      );
      await expectLater(
        transport.request(
          action: 'syntax',
          language: AotLanguage.german,
          query: 'c',
        ),
        _throwsCode(AotErrorCode.limit),
      );
      expect(client.calls, 1);
      // The second request receives its own stream instead of reusing the first.
      client.handler = (http.BaseRequest _) async => _jsonResponse('[2]');
      first.complete(_jsonResponse('[1]'));
      expect(await a, <int>[1]);
      expect(await b, <int>[2]);
      expect(client.calls, 2);
    },
  );

  test(
    'deadline covers queue, aborts active work, and bounds an unresponsive client',
    () {
      fakeAsync((FakeAsync time) {
        final Completer<http.StreamedResponse> never =
            Completer<http.StreamedResponse>();
        http.BaseRequest? sent;
        final _Client client = _Client((http.BaseRequest request) async {
          sent = request;
          return never.future;
        });
        final AotHttpTransport transport = AotHttpTransport(
          httpClient: client,
          timeout: const Duration(seconds: 1),
          maximumPendingRequests: 2,
        );
        final List<AotErrorCode> errors = <AotErrorCode>[];
        for (final String value in <String>['a', 'b']) {
          unawaited(
            transport
                .request(
                  action: 'syntax',
                  language: AotLanguage.german,
                  query: value,
                )
                .then<void>(
                  (Object? _) => fail('Unexpected result'),
                  onError: (Object e) => errors.add((e as AotException).code),
                ),
          );
        }
        time.flushMicrotasks();
        bool aborted = false;
        unawaited(
          (sent! as http.AbortableRequest).abortTrigger!.then((_) {
            aborted = true;
          }),
        );
        time.elapse(const Duration(seconds: 1));
        time.flushMicrotasks();
        expect(errors, <AotErrorCode>[
          AotErrorCode.timeout,
          AotErrorCode.timeout,
        ]);
        expect(aborted, isTrue);
        expect(client.calls, 1);
        // A client ignoring abortion cannot receive more in-flight sends.
        unawaited(
          transport
              .request(
                action: 'syntax',
                language: AotLanguage.german,
                query: 'c',
              )
              .then<void>(
                (Object? _) => fail('Unexpected result'),
                onError: (Object e) => errors.add((e as AotException).code),
              ),
        );
        time.flushMicrotasks();
        expect(client.calls, 1);
        unawaited(transport.dispose());
        time.flushMicrotasks();
        expect(errors.last, AotErrorCode.disposed);
        expect(client.closed, isTrue);
      });
    },
  );

  test(
    'dispose promptly rejects active and queued work and closes client',
    () async {
      final Completer<http.StreamedResponse> never =
          Completer<http.StreamedResponse>();
      final _Client client = _Client(
        (http.BaseRequest _) async => never.future,
      );
      final AotHttpTransport transport = AotHttpTransport(httpClient: client);
      final Future<Object?> a = transport.request(
        action: 'syntax',
        language: AotLanguage.german,
        query: 'a',
      );
      final Future<Object?> b = transport.request(
        action: 'morph',
        language: AotLanguage.german,
        query: 'b',
      );
      final Future<void> aCheck = expectLater(
        a,
        _throwsCode(AotErrorCode.disposed),
      );
      final Future<void> bCheck = expectLater(
        b,
        _throwsCode(AotErrorCode.disposed),
      );
      await transport.dispose();
      await Future.wait(<Future<void>>[aCheck, bCheck]);
      await transport.dispose();
      expect(client.calls, 1);
      expect(client.closeCalls, 1);
      await expectLater(
        transport.request(
          action: 'syntax',
          language: AotLanguage.german,
          query: 'c',
        ),
        _throwsCode(AotErrorCode.disposed),
      );
      // A late response is cancelled/ignored, never published as success.
      never.complete(_jsonResponse('[]'));
      await Future<void>.delayed(Duration.zero);
    },
  );
}

Matcher _throwsCode(AotErrorCode code) => throwsA(
  isA<AotException>().having((AotException e) => e.code, 'code', code),
);

http.StreamedResponse _jsonResponse(String value, {int status = 200}) =>
    http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(value)),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf8',
      },
    );

final class _Client extends http.BaseClient {
  _Client(this.handler);
  Future<http.StreamedResponse> Function(http.BaseRequest request) handler;
  int calls = 0;
  bool closed = false;
  int closeCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    return handler(request);
  }

  @override
  void close() {
    closed = true;
    closeCalls++;
  }
}
