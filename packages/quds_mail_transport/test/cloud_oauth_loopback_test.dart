import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/src/cloud/configuration.dart';
import 'package:quds_mail_transport/src/cloud/http.dart';
import 'package:quds_mail_transport/src/cloud/native/authorization.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'loopback',
  profile: MailProfileId('tests', hostId: 'crisp-office.test'),
);
const _code = 'loopback-fixture-authorization-code';

/// Only the external OAuth token exchange is mocked. Callback requests use the
/// native listener and a real Dart HTTP client on the OS loopback interface.
final class _TokenTransport implements MailCloudHttpTransport {
  final requests = <MailCloudHttpRequest>[];
  int closeCalls = 0;

  @override
  Future<MailCloudHttpResponse> send(
    MailCloudHttpRequest request, {
    required MailOperationLease lease,
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    requests.add(request);
    return MailCloudHttpResponse(
      statusCode: 200,
      body: utf8.encode(
        jsonEncode({
          'access_token': 'loopback-fixture-access-token',
          'refresh_token': 'loopback-fixture-refresh-token',
          'token_type': 'Bearer',
          'expires_in': 3600,
        }),
      ),
    );
  }

  @override
  void close() => closeCalls++;
}

void main() {
  for (final service in MailCloudService.values) {
    test(
      'real ${service.name} loopback accepts provider redirect and Host',
      () async {
        final session = MailAccountSession(_account);
        final browser = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        final transport = _TokenTransport();
        final browserDone = Completer<(int, Map<String, String?>, String)>();
        late Uri redirect;
        addTearDown(() {
          browser.close(force: true);
          session.dispose();
        });

        final result = await authorizeNativeMailCloud(
          configuration: MailOAuthConfiguration(
            service: service,
            clientId: 'fixture-client-id',
          ),
          account: _account,
          lease: session.begin(),
          timeout: const Duration(seconds: 5),
          transportFactory: () => transport,
          openBrowser: (authorization) async {
            try {
              redirect = Uri.parse(
                authorization.queryParameters['redirect_uri']!,
              );
              expect(redirect.scheme, 'http');
              expect(redirect.port, greaterThan(0));
              expect(
                redirect.host,
                service == MailCloudService.gmail ? '127.0.0.1' : 'localhost',
              );
              expect(
                redirect.path,
                service == MailCloudService.gmail ? '/oauth2/callback' : '/',
              );
              final callback = redirect.replace(
                queryParameters: {
                  'state': authorization.queryParameters['state']!,
                  'code': _code,
                },
              );
              final request = await browser.getUrl(callback);
              final response = await request.close();
              final body = await response.transform(utf8.decoder).join();
              browserDone.complete((
                response.statusCode,
                {
                  'cache-control': response.headers.value('cache-control'),
                  'referrer-policy': response.headers.value('referrer-policy'),
                },
                body,
              ));
              return true;
            } on Object catch (error, stack) {
              browserDone.completeError(error, stack);
              return false;
            }
          },
        );
        expect(result, isA<MailSuccess<MailCloudTokenSource>>());
        final (status, headers, reply) = await browserDone.future;
        expect(status, 200);
        expect(headers['cache-control'], 'no-store');
        expect(headers['referrer-policy'], 'no-referrer');
        expect(reply, contains('Return to CrispOffice'));
        expect(reply, isNot(contains(_code)));
        expect(transport.requests, hasLength(1));
        final form = Uri.splitQueryString(
          utf8.decode(transport.requests.single.body),
        );
        expect(form['redirect_uri'], redirect.toString());
        expect(form['code'], _code);
        expect(form['code_verifier'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
        final tokens = (result as MailSuccess<MailCloudTokenSource>).value;
        expect(
          await tokens.accessToken(session.begin()),
          isA<MailSuccess<MailCloudAccessToken>>(),
        );
        tokens.dispose();
        expect(transport.closeCalls, 1);
      },
    );
  }

  test(
    'cancellation closes real listener and a late callback cannot revive it',
    () async {
      final session = MailAccountSession(_account);
      final cancellation = MailCancellationSource();
      final browser = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1);
      final launched = Completer<Uri>();
      var tokenTransportsCreated = 0;
      final transport = _TokenTransport();
      addTearDown(() {
        browser.close(force: true);
        session.dispose();
      });
      final pending = authorizeNativeMailCloud(
        configuration: MailOAuthConfiguration(
          service: MailCloudService.gmail,
          clientId: 'fixture-client-id',
        ),
        account: _account,
        lease: session.begin(cancellation: cancellation.token),
        timeout: const Duration(seconds: 5),
        transportFactory: () {
          tokenTransportsCreated++;
          return transport;
        },
        openBrowser: (authorization) async {
          final redirect = Uri.parse(
            authorization.queryParameters['redirect_uri']!,
          );
          launched.complete(
            redirect.replace(
              queryParameters: {
                'state': authorization.queryParameters['state']!,
                'code': _code,
              },
            ),
          );
          return true;
        },
      );
      final callback = await launched.future;
      cancellation.cancel();
      final result = await pending;
      expect(
        result,
        isA<MailFailure<MailCloudTokenSource>>().having(
          (r) => r.problem.code,
          'problem',
          MailProblemCode.cancelled,
        ),
      );
      await expectLater(() async {
        final request = await browser.getUrl(callback);
        final response = await request.close();
        await response.drain<void>();
      }, throwsA(isA<SocketException>()));
      expect(tokenTransportsCreated, 0);
      expect(transport.requests, isEmpty);
    },
  );
}
