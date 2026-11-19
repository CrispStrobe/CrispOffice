import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/src/cloud/configuration.dart';
import 'package:quds_mail_transport/src/cloud/http.dart';
import 'package:quds_mail_transport/src/cloud/native/authorization.dart';
import 'package:quds_mail_transport/src/cloud/oauth.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'oauth',
  profile: MailProfileId('tests', hostId: 'crisp-office.test'),
);
final _google = MailOAuthConfiguration(
  service: MailCloudService.gmail,
  clientId: 'desktop-test.apps.googleusercontent.com',
  clientSecret: 'desktop-registration-metadata',
);
final _microsoft = MailOAuthConfiguration(
  service: MailCloudService.microsoft365,
  clientId: '00000000-0000-0000-0000-000000000001',
  tenant: 'organizations',
);
final _redirect = Uri.parse('http://127.0.0.1:41234/oauth2/callback');
const _tokenSecret = 'fixture-access-token';
const _refreshSecret = 'fixture-refresh-token';
const _codeSecret = 'fixture-authorization-code';

final class _Transport implements MailCloudHttpTransport {
  _Transport(this.handler);
  Future<MailCloudHttpResponse> Function(MailCloudHttpRequest) handler;
  final requests = <MailCloudHttpRequest>[];
  final timeouts = <Duration>[];
  final limits = <int>[];
  int closeCalls = 0;
  bool throwOnClose = false;

  @override
  Future<MailCloudHttpResponse> send(
    MailCloudHttpRequest request, {
    required MailOperationLease lease,
    required Duration timeout,
    required int maxResponseBytes,
  }) {
    requests.add(request);
    timeouts.add(timeout);
    limits.add(maxResponseBytes);
    return handler(request);
  }

  @override
  void close() {
    closeCalls++;
    if (throwOnClose) throw StateError('private-close-secret');
  }
}

MailCloudHttpResponse _tokenResponse({
  int status = 200,
  String access = _tokenSecret,
  String? refresh = _refreshSecret,
  int expires = 3600,
  Object? scope,
  Map<String, Object?> overrides = const {},
  Map<String, String> headers = const {},
}) => MailCloudHttpResponse(
  statusCode: status,
  headers: headers,
  body: utf8.encode(
    jsonEncode({
      'access_token': access,
      'token_type': 'Bearer',
      'expires_in': expires,
      'refresh_token': ?refresh,
      'scope': ?scope,
      ...overrides,
    }),
  ),
);

Map<String, String> _form(MailCloudHttpRequest request) =>
    Uri.splitQueryString(utf8.decode(request.body));

Matcher _failure(MailProblemCode code) =>
    isA<MailFailure<Object?>>().having((f) => f.problem.code, 'problem', code);

final class _Headers implements HttpHeaders {
  final values = <String, String>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = value.toString();
  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected callback headers fixture operation');
}

final class _LocalResponse implements HttpResponse {
  final finished = Completer<void>();
  final text = StringBuffer();
  @override
  int statusCode = 200;
  @override
  final _Headers headers = _Headers();
  @override
  void write(Object? value) => text.write(value);
  @override
  Future<void> close() async {
    if (!finished.isCompleted) finished.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected callback response fixture operation');
}

final class _LocalRequest implements HttpRequest {
  _LocalRequest(
    this.uri, {
    this.method = 'GET',
    String host = '127.0.0.1:41234',
  }) {
    headers.set('host', host);
  }
  @override
  final Uri uri;
  @override
  final String method;
  @override
  final _Headers headers = _Headers();
  @override
  final _LocalResponse response = _LocalResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected callback request fixture operation');
}

final class _Server extends Stream<HttpRequest> implements HttpServer {
  final controller = StreamController<HttpRequest>();
  int closeCalls = 0;
  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;
  @override
  int get port => 41234;
  @override
  Duration? idleTimeout = Duration.zero;
  @override
  Future<HttpServer> close({bool force = false}) async {
    closeCalls++;
    await controller.close();
    return this;
  }

  @override
  StreamSubscription<HttpRequest> listen(
    void Function(HttpRequest)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected callback server fixture operation');
}

void main() {
  group('PKCE challenge and callback', () {
    test('uses independent random URL-safe state and verifier with S256', () {
      final first = MailOAuthChallenge.generate();
      final second = MailOAuthChallenge.generate();
      expect(first.state, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(first.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(first.state, isNot(first.verifier));
      expect(first.state, isNot(second.state));
      expect(first.verifier, isNot(second.verifier));
      expect(
        first.challenge,
        base64Url
            .encode(sha256.convert(ascii.encode(first.verifier)).bytes)
            .replaceAll('=', ''),
      );
      expect(first.toString(), isNot(contains(first.state)));
      expect(first.toString(), isNot(contains(first.verifier)));
    });

    test('builds provider-specific authorization requests without secrets', () {
      final challenge = MailOAuthChallenge.generate();
      for (final configuration in [_google, _microsoft]) {
        final url = challenge.authorizationUri(configuration, _redirect);
        expect(url.scheme, 'https');
        expect(url.host, configuration.authorizationEndpoint.host);
        expect(url.queryParameters['state'], challenge.state);
        expect(url.queryParameters['code_challenge'], challenge.challenge);
        expect(url.queryParameters['code_challenge_method'], 'S256');
        expect(url.queryParameters['response_type'], 'code');
        expect(url.queryParameters['redirect_uri'], _redirect.toString());
        expect(url.queryParameters['scope'], configuration.scopes.join(' '));
        expect(url.queryParameters, isNot(contains('client_secret')));
        expect(url.toString(), isNot(contains(challenge.verifier)));
      }
      expect(
        challenge
            .authorizationUri(_google, _redirect)
            .queryParameters['access_type'],
        'offline',
      );
      expect(
        challenge
            .authorizationUri(_microsoft, _redirect)
            .queryParameters['response_mode'],
        'query',
      );
      expect(
        _microsoft.scopes,
        contains('https://graph.microsoft.com/Mail.Send'),
      );
    });

    test(
      'accepts only the one code bound to the expected redirect and state',
      () {
        final challenge = MailOAuthChallenge.generate();
        final callback = _redirect.replace(
          queryParameters: {'state': challenge.state, 'code': _codeSecret},
        );
        expect(
          challenge.validateCallback(callback, _redirect),
          isA<MailSuccess<String>>().having(
            (r) => r.value,
            'code',
            _codeSecret,
          ),
        );
        final invalid = [
          callback.replace(scheme: 'https'),
          callback.replace(host: 'localhost'),
          callback.replace(port: 41235),
          callback.replace(path: '/another'),
          callback.replace(userInfo: 'secret'),
          callback.replace(fragment: 'secret'),
          callback.replace(query: 'state=wrong&code=$_codeSecret'),
          callback.replace(
            query: 'state=${challenge.state}&state=${challenge.state}&code=x',
          ),
          callback.replace(query: 'state=${challenge.state}&code=x&code=y'),
          callback.replace(
            query: 'state=${challenge.state}&code=x&error=access_denied',
          ),
          callback.replace(query: 'state=${challenge.state}&code='),
          callback.replace(query: 'state=${challenge.state}'),
          callback.replace(
            queryParameters: {'state': challenge.state, 'code': 'bad\r\ncode'},
          ),
          callback.replace(
            queryParameters: {'state': challenge.state, 'code': 'x' * 8193},
          ),
        ];
        for (final value in invalid) {
          expect(
            challenge.validateCallback(value, _redirect),
            _failure(MailProblemCode.invalidInput),
          );
        }
      },
    );

    test('malformed UTF-8 callback query is a typed validation failure', () {
      final challenge = MailOAuthChallenge.generate();
      final callback = _redirect.replace(
        query: 'state=${challenge.state}&code=%FF',
      );
      expect(
        challenge.validateCallback(callback, _redirect),
        _failure(MailProblemCode.invalidInput),
      );
    });

    test(
      'provider denial requires valid state and never returns server text',
      () {
        final challenge = MailOAuthChallenge.generate();
        for (final entry in {
          'access_denied': MailProblemCode.permissionDenied,
          'server_error': MailProblemCode.authenticationRequired,
        }.entries) {
          final result = challenge.validateCallback(
            _redirect.replace(
              queryParameters: {
                'state': challenge.state,
                'error': entry.key,
                'error_description': _tokenSecret,
              },
            ),
            _redirect,
          );
          expect(result, _failure(entry.value));
          expect(result.toString(), isNot(contains(_tokenSecret)));
        }
      },
    );
  });

  group('OAuth token session', () {
    late MailAccountSession accountSession;
    late MailOperationLease lease;
    late _Transport transport;
    late DateTime now;
    late List<MailCloudLogEvent> logs;
    late List<MailCloudTokenSource> adopted;

    setUp(() {
      accountSession = MailAccountSession(_account);
      lease = accountSession.begin();
      transport = _Transport((_) async => _tokenResponse());
      now = DateTime.utc(2026, 11, 19, 12);
      logs = [];
      adopted = [];
    });
    tearDown(() {
      for (final source in adopted) {
        source.dispose();
      }
      accountSession.dispose();
    });

    Future<MailResult<MailCloudTokenSource>> exchange({
      MailOAuthConfiguration? configuration,
      MailOperationLease? operation,
      MailCloudLogSink? logger,
      Uri? redirect,
      String code = _codeSecret,
    }) async {
      final result = await MailOAuthTokenSession.exchange(
        configuration: configuration ?? _google,
        account: _account,
        transport: transport,
        challenge: MailOAuthChallenge.generate(),
        code: code,
        redirect: redirect ?? _redirect,
        lease: operation ?? lease,
        log: logger ?? logs.add,
        clock: () => now,
      );
      if (result case MailSuccess<MailCloudTokenSource>(:final value)) {
        adopted.add(value);
      }
      return result;
    }

    Future<MailCloudTokenSource> source({
      MailOAuthConfiguration? configuration,
    }) async {
      final result = await exchange(configuration: configuration);
      expect(result, isA<MailSuccess<MailCloudTokenSource>>());
      return (result as MailSuccess<MailCloudTokenSource>).value;
    }

    test(
      'exchanges exactly once with verifier and bounded form transport',
      () async {
        final session = await source();
        expect(transport.requests, hasLength(1));
        final request = transport.requests.single;
        expect(request.method, 'POST');
        expect(request.uri, _google.tokenEndpoint);
        expect(
          request.headers['content-type'],
          'application/x-www-form-urlencoded',
        );
        final form = _form(request);
        expect(form['grant_type'], 'authorization_code');
        expect(form['code'], _codeSecret);
        expect(form['redirect_uri'], _redirect.toString());
        expect(form['client_id'], _google.clientId);
        expect(form['client_secret'], _google.clientSecret);
        expect(form['code_verifier'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
        expect(transport.timeouts.single, const Duration(seconds: 30));
        expect(transport.limits.single, 128 * 1024);
        final token = await session.accessToken(lease);
        expect(
          token,
          isA<MailSuccess<MailCloudAccessToken>>()
              .having((r) => r.value.value, 'access', _tokenSecret)
              .having(
                (r) => r.value.expiresAt,
                'expires',
                now.add(const Duration(hours: 1)),
              ),
        );
        expect(transport.requests, hasLength(1));
        final rendered = logs.map((e) => e.toJson()).toString();
        for (final secret in [
          _tokenSecret,
          _refreshSecret,
          _codeSecret,
          _google.clientSecret!,
          form['code_verifier']!,
        ]) {
          expect(rendered, isNot(contains(secret)));
        }
        expect(logs.map((e) => e.stage), [
          MailCloudLogStage.started,
          MailCloudLogStage.response,
          MailCloudLogStage.completed,
        ]);
      },
    );

    test(
      'rejects foreign account, invalid code and non-loopback redirect before IO',
      () async {
        final foreign = MailAccountSession(
          MailAccountId('other', profile: _account.profile),
        );
        addTearDown(foreign.dispose);
        for (final result in [
          await exchange(operation: foreign.begin()),
          await exchange(code: 'bad\ncode'),
          await exchange(redirect: Uri.parse('https://evil.test/callback')),
        ]) {
          expect(result, _failure(MailProblemCode.invalidInput));
        }
        expect(transport.requests, isEmpty);
      },
    );

    test(
      'refreshes before expiry and preserves refresh token when omitted',
      () async {
        final session = await source();
        now = now.add(const Duration(minutes: 59, seconds: 1));
        transport.handler = (_) async =>
            _tokenResponse(access: 'refreshed', refresh: null);
        expect(
          await session.accessToken(lease),
          isA<MailSuccess<MailCloudAccessToken>>().having(
            (r) => r.value.value,
            'access',
            'refreshed',
          ),
        );
        expect(_form(transport.requests.last)['refresh_token'], _refreshSecret);
        now = now.add(const Duration(hours: 1));
        await session.accessToken(lease);
        expect(_form(transport.requests.last)['refresh_token'], _refreshSecret);
        expect(transport.requests, hasLength(3));
      },
    );

    test(
      'commits token rotation before the next refresh and coalesces concurrent callers',
      () async {
        final session = await source();
        final pending = Completer<MailCloudHttpResponse>();
        transport.handler = (_) => pending.future;
        final first = session.accessToken(lease, forceRefresh: true);
        final second = session.accessToken(lease, forceRefresh: true);
        expect(transport.requests, hasLength(2));
        pending.complete(
          _tokenResponse(access: 'rotated-access', refresh: 'rotated-refresh'),
        );
        final results = await Future.wait([first, second]);
        for (final result in results) {
          expect(
            result,
            isA<MailSuccess<MailCloudAccessToken>>().having(
              (r) => r.value.value,
              'access',
              'rotated-access',
            ),
          );
        }
        transport.handler = (_) async =>
            _tokenResponse(access: 'next', refresh: null);
        await session.accessToken(lease, forceRefresh: true);
        expect(
          _form(transport.requests.last)['refresh_token'],
          'rotated-refresh',
        );
      },
    );

    test(
      'revoked refresh token clears credentials and requires new authorization',
      () async {
        final session = await source();
        transport.handler = (_) async => _tokenResponse(
          status: 400,
          overrides: {
            'error': 'invalid_grant',
            'error_description': _tokenSecret,
          },
        );
        expect(
          await session.accessToken(lease, forceRefresh: true),
          _failure(MailProblemCode.authenticationRequired),
        );
        expect(
          await session.accessToken(lease),
          _failure(MailProblemCode.authenticationRequired),
        );
        expect(transport.requests, hasLength(2));
        expect(logs.toString(), isNot(contains(_tokenSecret)));
      },
    );

    test(
      'throttled refresh retains rotation state and exposes bounded retry delay',
      () async {
        final session = await source();
        transport.handler = (_) async =>
            _tokenResponse(status: 429, headers: {'retry-after': '999999999'});
        final result = await session.accessToken(lease, forceRefresh: true);
        expect(result, _failure(MailProblemCode.quotaExceeded));
        expect(
          (result as MailFailure).problem.retryAfter,
          const Duration(days: 1),
        );
        transport.handler = (_) async => _tokenResponse();
        expect(
          await session.accessToken(lease, forceRefresh: true),
          isA<MailSuccess<MailCloudAccessToken>>(),
        );
        expect(_form(transport.requests.last)['refresh_token'], _refreshSecret);
      },
    );

    test(
      'non-retryable exchange never automatically replays an authorization code',
      () async {
        transport.handler = (_) async => throw StateError(_tokenSecret);
        expect(await exchange(), _failure(MailProblemCode.providerFailure));
        expect(transport.requests, hasLength(1));
        expect(transport.closeCalls, 1);
        expect(logs.toString(), isNot(contains(_tokenSecret)));
      },
    );

    test(
      'optional missing refresh token permits current access only',
      () async {
        transport.handler = (_) async => _tokenResponse(refresh: null);
        final session = await source();
        expect(
          await session.accessToken(lease),
          isA<MailSuccess<MailCloudAccessToken>>(),
        );
        now = now.add(const Duration(hours: 2));
        expect(
          await session.accessToken(lease),
          _failure(MailProblemCode.authenticationRequired),
        );
        expect(transport.requests, hasLength(1));
      },
    );

    test('rejects insufficient Gmail and Microsoft delegated scopes', () async {
      for (final (configuration, scope) in [
        (_google, 'https://www.googleapis.com/auth/gmail.readonly'),
        (_microsoft, 'Mail.ReadWrite User.Read'),
        (_microsoft, 'Mail.Send User.Read'),
      ]) {
        transport.handler = (_) async => _tokenResponse(scope: scope);
        expect(
          await exchange(configuration: configuration),
          _failure(MailProblemCode.permissionDenied),
        );
      }
      transport.handler = (_) async =>
          _tokenResponse(scope: 'Mail.ReadWrite Mail.Send User.Read');
      expect(
        await exchange(configuration: _microsoft),
        isA<MailSuccess<MailCloudTokenSource>>(),
      );
    });

    test(
      'Microsoft refresh requests all delegated mail scopes and no client secret',
      () async {
        final session = await source(configuration: _microsoft);
        await session.accessToken(lease, forceRefresh: true);
        final form = _form(transport.requests.last);
        expect(form['scope'], _microsoft.scopes.join(' '));
        expect(form, isNot(contains('client_secret')));
        expect(transport.requests.last.uri, _microsoft.tokenEndpoint);
      },
    );

    test(
      'malformed token responses are rejected before credentials are adopted',
      () async {
        for (final overrides in <Map<String, Object?>>[
          {'access_token': ''},
          {'access_token': 'bad\r\ntoken'},
          {'token_type': 'Basic'},
          {'expires_in': 0},
          {'expires_in': '3600'},
          {'expires_in': 32 * 86400},
          {'refresh_token': ''},
          {'refresh_token': 'bad token'},
          {'scope': 5},
        ]) {
          transport.handler = (_) async => _tokenResponse(overrides: overrides);
          expect(await exchange(), _failure(MailProblemCode.providerFailure));
        }
        expect(transport.requests, hasLength(9));
      },
    );

    test(
      'redirects, malformed JSON, oversized and server errors stay typed',
      () async {
        final cases = <(MailCloudHttpResponse, MailProblemCode)>[
          (
            MailCloudHttpResponse(
              statusCode: 302,
              headers: {'location': 'https://evil.test'},
              body: [],
            ),
            MailProblemCode.permissionDenied,
          ),
          (
            MailCloudHttpResponse(
              statusCode: 200,
              body: utf8.encode('not json $_tokenSecret'),
            ),
            MailProblemCode.providerFailure,
          ),
          (
            MailCloudHttpResponse(
              statusCode: 200,
              body: List.filled(128 * 1024 + 1, 32),
            ),
            MailProblemCode.quotaExceeded,
          ),
          (_tokenResponse(status: 503), MailProblemCode.unavailable),
        ];
        for (final (response, code) in cases) {
          transport.handler = (_) async => response;
          expect(await exchange(), _failure(code));
        }
      },
    );

    test('stale exchange completion cannot adopt or leak the token', () async {
      final pending = Completer<MailCloudHttpResponse>();
      transport.handler = (_) => pending.future;
      final result = exchange();
      accountSession.invalidate();
      pending.complete(_tokenResponse());
      expect(await result, _failure(MailProblemCode.staleOperation));
      expect(transport.closeCalls, 1);
      expect(adopted, isEmpty);
    });

    test('each coalesced refresh caller validates its own lease', () async {
      final session = await source();
      final otherAccountSession = MailAccountSession(_account);
      addTearDown(otherAccountSession.dispose);
      final pending = Completer<MailCloudHttpResponse>();
      transport.handler = (_) => pending.future;
      final first = session.accessToken(lease, forceRefresh: true);
      final stale = session.accessToken(
        otherAccountSession.begin(),
        forceRefresh: true,
      );
      otherAccountSession.invalidate();
      pending.complete(_tokenResponse());
      expect(await first, isA<MailSuccess<MailCloudAccessToken>>());
      expect(await stale, _failure(MailProblemCode.staleOperation));
      expect(transport.requests, hasLength(2));
    });

    test(
      'disposal prevents a pending refresh from restoring credentials',
      () async {
        final session = await source();
        final pending = Completer<MailCloudHttpResponse>();
        transport.handler = (_) => pending.future;
        final result = session.accessToken(lease, forceRefresh: true);
        session.dispose();
        pending.complete(_tokenResponse());
        expect(await result, _failure(MailProblemCode.cancelled));
        expect(
          await session.accessToken(lease),
          _failure(MailProblemCode.cancelled),
        );
        session.dispose();
        expect(transport.closeCalls, 1);
      },
    );

    test(
      'throwing diagnostics never turn successful OAuth into failure',
      () async {
        expect(
          await exchange(logger: (_) => throw StateError(_tokenSecret)),
          isA<MailSuccess<MailCloudTokenSource>>(),
        );
      },
    );

    test('throwing cleanup cannot escape a typed failed exchange', () async {
      transport.throwOnClose = true;
      transport.handler = (_) async =>
          _tokenResponse(status: 400, overrides: {'error': 'invalid_grant'});
      expect(
        await exchange(),
        _failure(MailProblemCode.authenticationRequired),
      );
      expect(transport.closeCalls, 1);
    });
  });

  group('native browser callback ownership', () {
    late MailAccountSession session;
    late _Server server;
    late _Transport transport;
    setUp(() {
      session = MailAccountSession(_account);
      server = _Server();
      transport = _Transport((_) async => _tokenResponse());
    });
    tearDown(() {
      session.dispose();
    });

    Future<MailResult<MailCloudTokenSource>> authorize({
      required Future<bool> Function(Uri) launch,
      MailOAuthConfiguration? configuration,
      MailOperationLease? lease,
      Duration timeout = const Duration(seconds: 1),
      Future<HttpServer> Function()? bind,
    }) => authorizeNativeMailCloud(
      configuration: configuration ?? _google,
      account: _account,
      lease: lease ?? session.begin(),
      openBrowser: launch,
      bindServer: bind ?? (() async => server),
      transportFactory: () => transport,
      timeout: timeout,
    );

    test(
      'rejects foreign callback requests then accepts one valid response',
      () async {
        final invalids = <_LocalRequest>[];
        late _LocalRequest valid;
        final result = await authorize(
          launch: (uri) async {
            final state = uri.queryParameters['state']!;
            final callback = Uri(
              path: '/oauth2/callback',
              queryParameters: {'state': state, 'code': _codeSecret},
            );
            invalids.addAll([
              _LocalRequest(callback, method: 'POST'),
              _LocalRequest(callback, host: 'evil.test:41234'),
              _LocalRequest(callback.replace(path: '/wrong')),
              _LocalRequest(callback.replace(query: 'state=wrong&code=x')),
              _LocalRequest(
                callback.replace(query: 'state=$state&code=x&code=y'),
              ),
            ]);
            for (final request in invalids) {
              server.controller.add(request);
              await request.response.finished.future;
            }
            valid = _LocalRequest(callback);
            server.controller.add(valid);
            return true;
          },
        );
        expect(result, isA<MailSuccess<MailCloudTokenSource>>());
        for (final request in invalids) {
          expect(request.response.statusCode, 400);
        }
        await valid.response.finished.future;
        expect(valid.response.statusCode, 200);
        expect(valid.response.headers.values['cache-control'], 'no-store');
        expect(valid.response.headers.values['referrer-policy'], 'no-referrer');
        expect(valid.response.text.toString(), isNot(contains(_codeSecret)));
        expect(transport.requests, hasLength(1));
        expect(server.closeCalls, 1);
        (result as MailSuccess<MailCloudTokenSource>).value.dispose();
      },
    );

    test(
      'Microsoft uses registered localhost root redirect and exact Host header',
      () async {
        final result = await authorize(
          configuration: _microsoft,
          launch: (uri) async {
            expect(
              uri.queryParameters['redirect_uri'],
              'http://localhost:41234/',
            );
            server.controller.add(
              _LocalRequest(
                Uri(
                  path: '/',
                  queryParameters: {
                    'state': uri.queryParameters['state']!,
                    'code': _codeSecret,
                  },
                ),
                host: 'localhost:41234',
              ),
            );
            return true;
          },
        );
        expect(result, isA<MailSuccess<MailCloudTokenSource>>());
        (result as MailSuccess<MailCloudTokenSource>).value.dispose();
      },
    );

    test(
      'a stalled browser launcher still times out and closes its listener',
      () async {
        final pending = Completer<bool>();
        final result = await authorize(
          launch: (_) => pending.future,
          timeout: const Duration(milliseconds: 20),
        );
        expect(result, _failure(MailProblemCode.cancelled));
        expect(server.closeCalls, 1);
        expect(transport.requests, isEmpty);
        pending.complete(true);
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'user cancellation retires a stalled launch and rejects late completion',
      () async {
        final cancellation = MailCancellationSource();
        final launched = Completer<void>();
        final pending = Completer<bool>();
        final result = authorize(
          lease: session.begin(cancellation: cancellation.token),
          launch: (_) {
            launched.complete();
            return pending.future;
          },
        );
        await launched.future;
        cancellation.cancel();
        expect(await result, _failure(MailProblemCode.cancelled));
        expect(server.closeCalls, 1);
        expect(transport.requests, isEmpty);
        pending.complete(false);
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'failed browser launch closes listener without opening token transport',
      () async {
        expect(
          await authorize(launch: (_) async => false),
          _failure(MailProblemCode.unavailable),
        );
        expect(server.closeCalls, 1);
        expect(transport.requests, isEmpty);
        expect(transport.closeCalls, 0);
      },
    );

    test('callback denial never exchanges a code', () async {
      final result = await authorize(
        launch: (uri) async {
          server.controller.add(
            _LocalRequest(
              Uri(
                path: '/oauth2/callback',
                queryParameters: {
                  'state': uri.queryParameters['state']!,
                  'error': 'access_denied',
                  'error_description': _codeSecret,
                },
              ),
            ),
          );
          return true;
        },
      );
      expect(result, _failure(MailProblemCode.permissionDenied));
      expect(transport.requests, isEmpty);
      expect(server.closeCalls, 1);
    });

    test('invalid callback flood has a finite rejection budget', () async {
      final result = await authorize(
        launch: (_) async {
          for (var i = 0; i < 16; i++) {
            final request = _LocalRequest(Uri(path: '/wrong'));
            server.controller.add(request);
            await request.response.finished.future;
          }
          return true;
        },
      );
      expect(result, _failure(MailProblemCode.invalidInput));
      expect(transport.requests, isEmpty);
      expect(server.closeCalls, 1);
    });

    test(
      'binding deadline closes a late listener without launching browser',
      () async {
        final pending = Completer<HttpServer>();
        var launched = false;
        final result = authorize(
          bind: () => pending.future,
          timeout: const Duration(milliseconds: 20),
          launch: (_) async {
            launched = true;
            return true;
          },
        );
        try {
          expect(
            await result.timeout(const Duration(milliseconds: 500)),
            _failure(MailProblemCode.cancelled),
          );
        } finally {
          pending.complete(server);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(launched, isFalse);
        expect(server.closeCalls, 1);
      },
    );
  });
}
