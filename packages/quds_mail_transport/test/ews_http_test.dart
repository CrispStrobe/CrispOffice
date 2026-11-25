import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/src/configuration.dart';
import 'package:quds_mail_transport/src/ews/configuration.dart';
import 'package:quds_mail_transport/src/ews/errors.dart';
import 'package:quds_mail_transport/src/ews/native/http_client.dart';
import 'package:test/test.dart';

import 'support/tls_server.dart';

final _profile = MailProfileId('ews-test', hostId: 'office.test');
final _account = MailAccountId('exchange', profile: _profile);
const _envelope =
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body><GetFolder/></s:Body></s:Envelope>';
const _result = '<Envelope>fixture-response</Envelope>';
final _challenge = Uint8List.fromList([
  for (final part
      in ('4e544c4d53535000020000000c000c003800000033828ae2'
              '0123456789abcdef00000000000000002400240044000000'
              '060070170000000f530065007200760065007200'
              '02000c0044006f006d00610069006e00'
              '01000c0053006500720076006500720000000000')
          .replaceAllMapped(RegExp(r'.{2}'), (match) => '${match[0]} ')
          .trim()
          .split(' '))
    int.parse(part, radix: 16),
]);

typedef _Handler =
    Future<void> Function(HttpRequest request, _Request observed);

final class _Request {
  const _Request(
    this.method,
    this.path,
    this.authorization,
    this.action,
    this.body,
    this.port,
  );
  final String method;
  final String path;
  final String? authorization;
  final String? action;
  final String body;
  final int? port;
}

final class _Fixture {
  _Fixture(this.server, this.handler) {
    subscription = server.listen(
      (request) {
        unawaited(_handle(request));
      },
      onError: (Object error, StackTrace stack) {
        if (error is! HandshakeException && error is! SocketException) {
          errors.add(error);
        }
      },
    );
  }

  static Future<_Fixture> bind(_Handler handler) async => _Fixture(
    await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      localTlsServerContext(),
    ),
    handler,
  );

  final HttpServer server;
  final _Handler handler;
  final requests = <_Request>[];
  final errors = <Object>[];
  late final StreamSubscription<HttpRequest> subscription;

  Future<void> _handle(HttpRequest request) async {
    try {
      final body = await request
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      final observed = _Request(
        request.method,
        request.uri.path,
        request.headers.value(HttpHeaders.authorizationHeader),
        request.headers.value('SOAPAction'),
        body,
        request.connectionInfo?.remotePort,
      );
      requests.add(observed);
      await handler(request, observed);
    } on SocketException {
      // Cancellation deliberately destroys the test connection.
    } on HttpException {
      // A size limit may close before the fixture finishes writing.
    } on Object catch (error) {
      errors.add(error);
    }
  }

  NativeEwsHttpClient client({
    MailEwsAuthentication authentication = MailEwsAuthentication.basic,
    MailEwsLimits limits = const MailEwsLimits(),
    bool trustFixture = true,
    String secret = 'fixture-only-password',
  }) => NativeEwsHttpClient(
    configuration: MailEwsConfiguration(
      account: _account,
      endpoint: Uri.parse('https://127.0.0.1:${server.port}/EWS/Exchange.asmx'),
      username: 'fixture-user',
      domain: 'EXAMPLE',
      credential: MailCredentialReference(
        account: _account,
        key: 'fixture-vault',
      ),
      authentication: authentication,
    ),
    secret: secret,
    limits: limits,
    clientFactory: trustFixture
        ? () => HttpClient(context: localTlsTrustContext())
        : null,
    securityContext: trustFixture ? localTlsTrustContext() : null,
  );

  Future<void> close() async {
    await server.close(force: true);
    await subscription.cancel();
    expect(errors, isEmpty);
  }
}

Future<void> _reply(
  HttpRequest request,
  String body, {
  int status = 200,
}) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
    ..write(body);
  await request.response.close();
}

Future<bool> _ntlmHandshake(
  HttpRequest request,
  _Request observed, {
  void Function(HttpResponse)? authenticated,
}) async {
  if (observed.method != 'HEAD') return false;
  final auth = observed.authorization!;
  final token = base64.decode(auth.substring(5));
  final type = ByteData.sublistView(token).getUint32(8, Endian.little);
  if (type == 1) {
    request.response
      ..statusCode = HttpStatus.unauthorized
      ..headers.set(
        HttpHeaders.wwwAuthenticateHeader,
        'NTLM ${base64.encode(_challenge)}',
      );
  } else {
    expect(type, 3);
    request.response.statusCode = HttpStatus.methodNotAllowed;
    authenticated?.call(request.response);
  }
  await request.response.close();
  return true;
}

Matcher _failure(MailProblemCode code) =>
    throwsA(isA<EwsException>().having((error) => error.code, 'code', code));

void main() {
  test(
    'verified HTTPS sends one explicit Basic request and retains operation scope',
    () async {
      final fixture = await _Fixture.bind(
        (request, observed) => _reply(request, _result),
      );
      addTearDown(fixture.close);
      final client = fixture.client();
      addTearDown(client.abort);
      expect(await client.post('GetFolder', _envelope), _result);
      expect(client.mutationStarted, isFalse);
      final request = fixture.requests.single;
      expect(request.method, 'POST');
      expect(request.body, _envelope);
      expect(
        utf8.decode(base64.decode(request.authorization!.substring(6))),
        r'EXAMPLE\fixture-user:fixture-only-password',
      );
      expect(
        request.action,
        '"http://schemas.microsoft.com/exchange/services/2006/messages/GetFolder"',
      );
    },
  );

  test(
    'NTLM uses body-free HEAD handshake then one authenticated connection',
    () async {
      final fixture = await _Fixture.bind((request, observed) async {
        if (!await _ntlmHandshake(request, observed)) {
          await _reply(request, _result);
        }
      });
      addTearDown(fixture.close);
      final client = fixture.client(authentication: MailEwsAuthentication.ntlm);
      addTearDown(client.abort);
      expect(await client.post('GetFolder', _envelope), _result);
      expect(await client.post('GetItem', _envelope), _result);
      expect(fixture.requests.map((request) => request.method), [
        'HEAD',
        'HEAD',
        'POST',
        'POST',
      ]);
      expect(
        fixture.requests.take(2).every((request) => request.body.isEmpty),
        isTrue,
      );
      expect(
        fixture.requests
            .skip(2)
            .every((request) => request.authorization == null),
        isTrue,
      );
      expect(
        fixture.requests.map((request) => request.port).toSet(),
        hasLength(1),
      );
      expect(client.mutationStarted, isFalse);
    },
  );

  test('authenticated HEAD 302 never redirects the EWS SOAP call', () async {
    final fixture = await _Fixture.bind((request, observed) async {
      final handled = await _ntlmHandshake(
        request,
        observed,
        authenticated: (response) {
          response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/EWS/authenticated-help')
            ..headers.set('Persistent-Auth', 'true');
        },
      );
      if (!handled) await _reply(request, _result);
    });
    addTearDown(fixture.close);
    final client = fixture.client(authentication: MailEwsAuthentication.ntlm);
    addTearDown(client.abort);
    expect(await client.post('GetFolder', _envelope), _result);
    expect(fixture.requests.map((request) => request.method), [
      'HEAD',
      'HEAD',
      'POST',
    ]);
    expect(fixture.requests.map((request) => request.path).toSet(), {
      '/EWS/Exchange.asmx',
    });
    expect(
      fixture.requests.map((request) => request.port).toSet(),
      hasLength(1),
    );
    expect(fixture.requests.last.authorization, isNull);
  });

  final rejectedHeadRedirects = [
    (
      name: 'foreign redirect',
      location: 'https://other.example/ews',
      persistent: true,
      challenge: false,
    ),
    (
      name: 'missing persistent auth',
      location: '/EWS/authenticated-help',
      persistent: false,
      challenge: false,
    ),
    (
      name: 'new auth challenge',
      location: '/EWS/authenticated-help',
      persistent: true,
      challenge: true,
    ),
  ];
  for (final variant in rejectedHeadRedirects) {
    test('authenticated HEAD rejects ${variant.name} before SOAP', () async {
      final fixture = await _Fixture.bind((request, observed) async {
        final handled = await _ntlmHandshake(
          request,
          observed,
          authenticated: (response) {
            response
              ..statusCode = HttpStatus.found
              ..headers.set(HttpHeaders.locationHeader, variant.location);
            if (variant.persistent) {
              response.headers.set('Persistent-Auth', 'true');
            }
            if (variant.challenge) {
              response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'NTLM');
            }
          },
        );
        if (!handled) await _reply(request, _result);
      });
      addTearDown(fixture.close);
      final client = fixture.client(authentication: MailEwsAuthentication.ntlm);
      addTearDown(client.abort);
      await expectLater(
        client.post('UpdateItem', _envelope, mutation: true),
        _failure(MailProblemCode.permissionDenied),
      );
      expect(fixture.requests.map((request) => request.method), [
        'HEAD',
        'HEAD',
      ]);
      expect(client.mutationStarted, isFalse);
    });
  }

  test(
    'a same-origin SOAP redirect still fails after NTLM authentication',
    () async {
      final fixture = await _Fixture.bind((request, observed) async {
        if (await _ntlmHandshake(request, observed)) return;
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/EWS/other')
          ..headers.set('Persistent-Auth', 'true');
        await request.response.close();
      });
      addTearDown(fixture.close);
      final client = fixture.client(authentication: MailEwsAuthentication.ntlm);
      addTearDown(client.abort);
      await expectLater(
        client.post('UpdateItem', _envelope, mutation: true),
        _failure(MailProblemCode.permissionDenied),
      );
      expect(fixture.requests.map((request) => request.method), [
        'HEAD',
        'HEAD',
        'POST',
      ]);
      expect(fixture.requests.last.path, '/EWS/Exchange.asmx');
      expect(client.mutationStarted, isTrue);
    },
  );

  test('TLS write backpressure preserves a multi-buffer SOAP body', () async {
    final body = '<Envelope>${'x' * (1024 * 1024)}</Envelope>';
    final fixture = await _Fixture.bind((request, observed) async {
      expect(observed.body, body);
      await _reply(request, _result);
    });
    addTearDown(fixture.close);
    final client = fixture.client();
    addTearDown(client.abort);
    expect(await client.post('CreateItem', body, mutation: true), _result);
    expect(client.mutationStarted, isTrue);
    expect(fixture.requests, hasLength(1));
  });

  test(
    'failed NTLM authentication sends no SOAP and never marks a mutation',
    () async {
      final fixture = await _Fixture.bind((request, observed) async {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(HttpHeaders.wwwAuthenticateHeader, 'Negotiate');
        await request.response.close();
      });
      addTearDown(fixture.close);
      final client = fixture.client(authentication: MailEwsAuthentication.ntlm);
      addTearDown(client.abort);
      await expectLater(
        client.post('CreateItem', _envelope, mutation: true),
        _failure(MailProblemCode.authenticationRequired),
      );
      expect(fixture.requests.single.method, 'HEAD');
      expect(fixture.requests.single.body, isEmpty);
      expect(client.mutationStarted, isFalse);
    },
  );

  test(
    'IIS per-request NTLM policy is rejected before a mailbox mutation',
    () async {
      final fixture = await _Fixture.bind((request, observed) async {
        request.response.headers.set('Persistent-Auth', 'false');
        if (!await _ntlmHandshake(request, observed)) {
          await _reply(request, _result);
        }
      });
      addTearDown(fixture.close);
      final client = fixture.client(authentication: MailEwsAuthentication.ntlm);
      addTearDown(client.abort);
      await expectLater(
        client.post('CreateItem', _envelope, mutation: true),
        _failure(MailProblemCode.unsupported),
      );
      expect(fixture.requests.map((request) => request.method), [
        'HEAD',
        'HEAD',
      ]);
      expect(client.mutationStarted, isFalse);
    },
  );

  for (final deadline in [false, true]) {
    test(
      '${deadline ? 'deadline' : 'abort'} closes peer during stalled TLS handshake',
      () async {
        final fixture = await LocalTlsServer.bind(
          mode: MailTlsMode.implicitTls,
          stallHandshake: true,
        );
        addTearDown(fixture.close);
        final client = NativeEwsHttpClient(
          configuration: MailEwsConfiguration(
            account: _account,
            endpoint: Uri.parse(
              'https://127.0.0.1:${fixture.port}/EWS/Exchange.asmx',
            ),
            username: 'fixture-user',
            credential: MailCredentialReference(
              account: _account,
              key: 'fixture-vault',
            ),
          ),
          secret: 'fixture-only-password',
          limits: MailEwsLimits(
            operationTimeout: deadline
                ? const Duration(milliseconds: 300)
                : const Duration(seconds: 5),
          ),
          securityContext: localTlsTrustContext(),
        );
        addTearDown(client.abort);
        final checked = expectLater(
          client.post('CreateItem', _envelope, mutation: true),
          _failure(
            deadline
                ? MailProblemCode.unavailable
                : MailProblemCode.staleOperation,
          ),
        );
        final peer = await fixture.peer(0);
        await peer.clientHello.future.timeout(const Duration(seconds: 2));
        if (!deadline) client.abort();
        await checked;
        // This must happen before fixture teardown; a settled Future alone does
        // not prove that cancellation closed the SDK's pending TLS transport.
        await peer.closed.future.timeout(const Duration(seconds: 2));
        expect(peer.commands, isEmpty);
        expect(client.mutationStarted, isFalse);
      },
    );
  }

  test(
    'SOAP authentication failure is never retried or reauthenticated',
    () async {
      final fixture = await _Fixture.bind((request, observed) async {
        if (!await _ntlmHandshake(request, observed)) {
          await _reply(
            request,
            'private-server-diagnostic',
            status: HttpStatus.unauthorized,
          );
        }
      });
      addTearDown(fixture.close);
      final client = fixture.client(authentication: MailEwsAuthentication.ntlm);
      addTearDown(client.abort);
      await expectLater(
        client.post('CreateItem', _envelope, mutation: true),
        _failure(MailProblemCode.authenticationRequired),
      );
      expect(client.mutationStarted, isTrue);
      expect(
        fixture.requests.where((request) => request.method == 'POST'),
        hasLength(1),
      );
      await expectLater(
        client.post('CreateItem', _envelope, mutation: true),
        _failure(MailProblemCode.authenticationRequired),
      );
      expect(fixture.requests, hasLength(3));
    },
  );

  test('redirect cannot forward credentials or replay the request', () async {
    final destination = await _Fixture.bind(
      (request, observed) => _reply(request, _result),
    );
    addTearDown(destination.close);
    final fixture = await _Fixture.bind((request, observed) async {
      request.response
        ..statusCode = HttpStatus.temporaryRedirect
        ..headers.set(
          HttpHeaders.locationHeader,
          'https://127.0.0.1:${destination.server.port}/EWS/Exchange.asmx',
        );
      await request.response.close();
    });
    addTearDown(fixture.close);
    final client = fixture.client();
    addTearDown(client.abort);
    await expectLater(
      client.post('GetItem', _envelope),
      _failure(MailProblemCode.permissionDenied),
    );
    expect(fixture.requests, hasLength(1));
    expect(destination.requests, isEmpty);
  });

  test('untrusted TLS certificate blocks credentials and SOAP', () async {
    final fixture = await _Fixture.bind(
      (request, observed) => _reply(request, _result),
    );
    addTearDown(fixture.close);
    final client = fixture.client(trustFixture: false);
    addTearDown(client.abort);
    await expectLater(
      client.post('CreateItem', _envelope, mutation: true),
      _failure(MailProblemCode.permissionDenied),
    );
    expect(fixture.requests, isEmpty);
    expect(client.mutationStarted, isFalse);
  });

  test('chunked response and cumulative responses obey byte budget', () async {
    final fixture = await _Fixture.bind(
      (request, observed) => _reply(request, 'x' * 600),
    );
    addTearDown(fixture.close);
    final client = fixture.client(
      limits: const MailEwsLimits(maxResponseBytes: 1024),
    );
    addTearDown(client.abort);
    expect(await client.post('GetItem', _envelope), 'x' * 600);
    await expectLater(
      client.post('GetItem', _envelope),
      _failure(MailProblemCode.quotaExceeded),
    );
    expect(fixture.requests, hasLength(2));
  });

  test('gzip expansion is bounded by decompressed response bytes', () async {
    final fixture = await _Fixture.bind((request, observed) async {
      final zipped = gzip.encode(utf8.encode('x' * 8192));
      request.response
        ..headers.set(HttpHeaders.contentEncodingHeader, 'gzip')
        ..contentLength = zipped.length
        ..add(zipped);
      await request.response.close();
    });
    addTearDown(fixture.close);
    final client = fixture.client(
      limits: const MailEwsLimits(maxResponseBytes: 1024),
    );
    addTearDown(client.abort);
    await expectLater(
      client.post('GetItem', _envelope),
      _failure(MailProblemCode.quotaExceeded),
    );
  });

  test(
    'oversized requests are rejected before connection and mutation',
    () async {
      final fixture = await _Fixture.bind(
        (request, observed) => _reply(request, _result),
      );
      addTearDown(fixture.close);
      final client = fixture.client(
        limits: const MailEwsLimits(maxRequestBytes: 1024),
      );
      addTearDown(client.abort);
      await expectLater(
        client.post('CreateItem', 'ü' * 800, mutation: true),
        _failure(MailProblemCode.quotaExceeded),
      );
      expect(fixture.requests, isEmpty);
      expect(client.mutationStarted, isFalse);
    },
  );

  test(
    'HTTP 503 reports bounded backoff without retry or server text',
    () async {
      final fixture = await _Fixture.bind((request, observed) async {
        request.response.headers.set(HttpHeaders.retryAfterHeader, '13');
        await _reply(
          request,
          'private-server-diagnostic',
          status: HttpStatus.serviceUnavailable,
        );
      });
      addTearDown(fixture.close);
      final client = fixture.client();
      addTearDown(client.abort);
      await expectLater(
        client.post('GetItem', _envelope),
        throwsA(
          isA<EwsException>()
              .having(
                (error) => error.retryAfter,
                'retryAfter',
                const Duration(seconds: 13),
              )
              .having(
                (error) => error.toString(),
                'diagnostic',
                isNot(contains('private-server-diagnostic')),
              ),
        ),
      );
      expect(fixture.requests, hasLength(1));
    },
  );

  test(
    'closed persistent connection never opens a second connection',
    () async {
      final fixture = await _Fixture.bind((request, observed) async {
        request.response.persistentConnection = false;
        await _reply(request, _result);
      });
      addTearDown(fixture.close);
      final client = fixture.client();
      addTearDown(client.abort);
      expect(await client.post('GetItem', _envelope), _result);
      await expectLater(
        client.post('CreateItem', _envelope, mutation: true),
        _failure(MailProblemCode.unavailable),
      );
      expect(client.mutationStarted, isFalse);
      expect(fixture.requests, hasLength(1));
    },
  );

  test(
    'abort cancels active read, blocks late completion and marks sent mutation',
    () async {
      final arrived = Completer<void>();
      final release = Completer<void>();
      final fixture = await _Fixture.bind((request, observed) async {
        arrived.complete();
        await release.future;
        await _reply(request, _result);
      });
      addTearDown(fixture.close);
      final client = fixture.client();
      addTearDown(client.abort);
      final pending = client.post('CreateItem', _envelope, mutation: true);
      final checked = expectLater(
        pending,
        _failure(MailProblemCode.staleOperation),
      );
      await arrived.future;
      client.abort();
      release.complete();
      await checked;
      expect(client.mutationStarted, isTrue);
      await expectLater(
        client.post('GetFolder', _envelope),
        _failure(MailProblemCode.staleOperation),
      );
      expect(fixture.requests, hasLength(1));
    },
  );

  test('operation deadline aborts a stalled response without retry', () async {
    final release = Completer<void>();
    final fixture = await _Fixture.bind((request, observed) async {
      await release.future;
      await _reply(request, _result);
    });
    addTearDown(fixture.close);
    final client = fixture.client(
      limits: const MailEwsLimits(
        operationTimeout: Duration(milliseconds: 150),
      ),
    );
    addTearDown(client.abort);
    await expectLater(
      client.post('GetFolder', _envelope),
      _failure(MailProblemCode.unavailable),
    );
    release.complete();
    expect(client.mutationStarted, isFalse);
    expect(fixture.requests.length, lessThanOrEqualTo(1));
  });

  test(
    'bearer tokens use explicit HTTPS and reject header injection',
    () async {
      final fixture = await _Fixture.bind(
        (request, observed) => _reply(request, _result),
      );
      addTearDown(fixture.close);
      final client = fixture.client(
        authentication: MailEwsAuthentication.bearer,
        secret: 'fixture.header.payload-signature',
      );
      addTearDown(client.abort);
      expect(await client.post('GetFolder', _envelope), _result);
      expect(
        fixture.requests.single.authorization,
        'Bearer fixture.header.payload-signature',
      );
      expect(
        () => fixture.client(
          authentication: MailEwsAuthentication.bearer,
          secret: 'private-token\r\nInjected: value',
        ),
        throwsA(
          isA<EwsException>().having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains('private-token')),
          ),
        ),
      );
    },
  );
}
