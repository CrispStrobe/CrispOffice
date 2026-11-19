import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/src/cloud/configuration.dart';
import 'package:quds_mail_transport/src/cloud/cursor.dart';
import 'package:quds_mail_transport/src/cloud/http.dart';
import 'package:quds_mail_transport/src/cloud/provider.dart';
import 'package:test/test.dart';

const _address = 'owner@example.test';
final _account = MailAccountId(
  'cloud',
  profile: MailProfileId('personal', hostId: 'office'),
);
final _other = MailAccountId('other', profile: _account.profile);
final _mailbox = MailMailboxId('INBOX', account: _account);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

MailProblem _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  final problem = (result as MailFailure<T>).problem;
  expect(problem.code, code);
  return problem;
}

MailCloudHttpResponse _json(
  Object value, {
  int status = 200,
  Map<String, String> headers = const {},
}) => MailCloudHttpResponse(
  statusCode: status,
  headers: headers,
  body: utf8.encode(jsonEncode(value)),
);

MailCloudHttpResponse _error(
  int status, {
  String code = 'fixtureFailure',
  String? retry,
}) => _json(
  {
    'error': {
      'code': code,
      'message': 'secret error text owner@example.test',
      'errors': [
        {'reason': code},
      ],
    },
  },
  status: status,
  headers: {'Retry-After': ?retry},
);

Map<String, Object?> _gmailItem(
  String id, {
  List<String> labels = const ['INBOX', 'UNREAD'],
  String subject = 'Subject',
}) => {
  'id': id,
  'labelIds': labels,
  'payload': {
    'headers': [
      {'name': 'From', 'value': 'sender@example.test'},
      {'name': 'To', 'value': _address},
      {'name': 'Subject', 'value': subject},
      {'name': 'Date', 'value': 'Thu, 19 Nov 2026 12:00:00 +0000'},
      {'name': 'Message-ID', 'value': '<$id@example.test>'},
    ],
  },
};

Map<String, Object?> _graphItem(
  String id, {
  bool read = false,
  String parent = 'INBOX',
  String subject = 'Subject',
}) => {
  'id': id,
  'subject': subject,
  'isRead': read,
  'isDraft': false,
  'flag': {'flagStatus': 'notFlagged'},
  'parentFolderId': parent,
  'from': {
    'emailAddress': {'address': 'sender@example.test', 'name': 'Sender'},
  },
  'toRecipients': [
    {
      'emailAddress': {'address': _address},
    },
  ],
  'replyTo': <Object?>[],
  'ccRecipients': <Object?>[],
  'bccRecipients': <Object?>[],
  'sentDateTime': '2026-11-19T12:00:00Z',
  'internetMessageId': '<$id@example.test>',
};

String _next({
  String folder = 'INBOX',
  bool delta = false,
  String token = 'page2',
  String host = 'graph.microsoft.com',
}) =>
    'https://$host/v1.0/me/mailFolders/$folder/messages${delta ? '/delta' : ''}?%24skiptoken=$token';

const _wireText =
    'From: owner@example.test\r\nTo: visible@example.test\r\n'
    'Subject: Private subject\r\nMIME-Version: 1.0\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n\r\nPrivate body\r\n';

MailPreparedMessage _prepared({
  String wire = _wireText,
  List<String> recipients = const [
    'visible@example.test',
    'hidden@example.test',
  ],
  String sender = _address,
  MailAccountId? account,
}) => MailPreparedMessage(
  account: account ?? _account,
  draftId: 'draft-1',
  draftRevision: 1,
  wire: MailBytes(Uint8List.fromList(utf8.encode(wire))),
  envelope: MailTransportEnvelope(sender: sender, recipients: recipients),
);

final class _Tokens implements MailCloudTokenSource {
  final calls = <bool>[];
  bool disposed = false;
  Future<MailResult<MailCloudAccessToken>> Function(bool)? handler;

  @override
  Future<MailResult<MailCloudAccessToken>> accessToken(
    MailOperationLease lease, {
    bool forceRefresh = false,
  }) async {
    calls.add(forceRefresh);
    return handler?.call(forceRefresh) ??
        MailSuccess(
          MailCloudAccessToken(
            value: forceRefresh
                ? 'refreshed-secret-token'
                : 'initial-secret-token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
  }

  @override
  void dispose() {
    disposed = true;
  }
}

typedef _Handler =
    FutureOr<MailCloudHttpResponse> Function(MailCloudHttpRequest request);

final class _Transport implements MailCloudHttpTransport {
  _Transport(this.service);
  final MailCloudService service;
  final requests = <MailCloudHttpRequest>[];
  _Handler? handler;
  _Handler? profileHandler;
  bool closed = false;
  Duration? lastTimeout;
  int? lastResponseLimit;

  bool profile(MailCloudHttpRequest request) =>
      request.uri.path == '/gmail/v1/users/me/profile' ||
      request.uri.path == '/v1.0/me';

  List<MailCloudHttpRequest> get mailRequests =>
      requests.where((request) => !profile(request)).toList();

  @override
  Future<MailCloudHttpResponse> send(
    MailCloudHttpRequest request, {
    required MailOperationLease lease,
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    requests.add(request);
    lastTimeout = timeout;
    lastResponseLimit = maxResponseBytes;
    if (profile(request)) {
      return profileHandler?.call(request) ??
          _json(
            service == MailCloudService.gmail
                ? {'emailAddress': _address, 'historyId': '100'}
                : {
                    'id': 'remote-user-1',
                    'mail': _address,
                    'userPrincipalName': _address,
                  },
          );
    }
    if (handler == null) throw StateError('Unexpected fixture mail request');
    return handler!(request);
  }

  @override
  void close() {
    closed = true;
  }
}

final class _Harness {
  _Harness(
    this.service, {
    MailCloudLimits limits = const MailCloudLimits(),
    MailCloudLogSink? log,
    String address = _address,
    MailAccountId? account,
  }) {
    transport = _Transport(service);
    provider = ApiMailCloudProvider(
      configuration: MailCloudConfiguration(
        account: account ?? _account,
        service: service,
        mailboxAddress: address,
      ),
      tokenSource: tokens,
      transport: transport,
      limits: limits,
      log: log,
    );
  }
  final MailCloudService service;
  final session = MailAccountSession(_account);
  final tokens = _Tokens();
  late final _Transport transport;
  late final ApiMailCloudProvider provider;
  MailOperationLease get lease => session.begin();
  MailOpaqueIdentity identity([String id = 'message-1']) => MailOpaqueIdentity(
    account: _account,
    provider: service == MailCloudService.gmail
        ? MailProviderKind.gmail
        : MailProviderKind.graph,
    value: id,
  );
  Future<MailResult<MailHeaderPage>> headers({
    MailCursor? cursor,
    int limit = 10,
  }) => provider.fetchHeaders(
    _mailbox,
    cursor: cursor,
    limit: limit,
    lease: lease,
  );
  Future<MailResult<MailSyncPage>> changes({
    MailCursor? cursor,
    int limit = 10,
  }) => provider.pullChanges(
    _mailbox,
    cursor: cursor,
    limit: limit,
    lease: lease,
  );
  Future<MailSubmissionResult> send({
    MailPreparedMessage? message,
    MailOperationLease? lease,
  }) => provider.submit(
    message ?? _prepared(),
    attemptId: 'attempt-1',
    lease: lease ?? this.lease,
  );
}

void main() {
  for (final service in MailCloudService.values) {
    group(service.name, () {
      test(
        'capabilities verifies mailbox and reports only implemented operations',
        () async {
          final h = _Harness(service);
          final capabilities = _value(await h.provider.capabilities(h.lease));
          expect(capabilities.supports(MailCapability.mail), isTrue);
          expect(capabilities.supports(MailCapability.send), isTrue);
          expect(
            capabilities.supports(MailCapability.move),
            service == MailCloudService.microsoft365,
          );
          expect(
            capabilities.supports(MailCapability.labels),
            service == MailCloudService.gmail,
          );
          expect(h.transport.requests, hasLength(1));
        },
      );

      test(
        'wrong signed-in account is rejected before any mailbox operation',
        () async {
          final h = _Harness(service, address: 'different@example.test');
          _problem(
            await h.provider.listMailboxes(h.lease),
            MailProblemCode.permissionDenied,
          );
          expect(h.transport.mailRequests, isEmpty);
        },
      );

      test(
        'profile authentication refresh is bounded and verifies refreshed identity',
        () async {
          final h = _Harness(service);
          h.transport.profileHandler = (request) {
            if (request.headers['Authorization'] ==
                'Bearer initial-secret-token') {
              return _error(401);
            }
            return _json(
              service == MailCloudService.gmail
                  ? {'emailAddress': 'other@example.test'}
                  : {'id': 'other', 'mail': 'other@example.test'},
            );
          };
          _problem(
            await h.provider.capabilities(h.lease),
            MailProblemCode.permissionDenied,
          );
          expect(h.tokens.calls, [false, true]);
          expect(h.transport.mailRequests, isEmpty);
        },
      );

      test('repeated profile 401 stops after one refresh', () async {
        final h = _Harness(service);
        h.transport.profileHandler = (_) => _error(401);
        _problem(
          await h.provider.capabilities(h.lease),
          MailProblemCode.authenticationRequired,
        );
        expect(h.tokens.calls, [false, true]);
        expect(h.transport.requests, hasLength(2));
      });

      test(
        'token-source failure and stale tokens never reach transport',
        () async {
          final h = _Harness(service);
          h.tokens.handler = (_) async => const MailFailure(
            MailProblem(MailProblemCode.authenticationRequired),
          );
          _problem(
            await h.provider.capabilities(h.lease),
            MailProblemCode.authenticationRequired,
          );
          h.tokens.handler = (_) async => MailSuccess(
            MailCloudAccessToken(value: 'old', expiresAt: DateTime(2000)),
          );
          _problem(
            await h.provider.capabilities(h.lease),
            MailProblemCode.authenticationRequired,
          );
          expect(h.transport.requests, isEmpty);
        },
      );

      test(
        'unexpected host errors are normalized and logs contain no sensitive text',
        () async {
          final logs = <MailCloudLogEvent>[];
          final h = _Harness(service, log: logs.add);
          h.transport.profileHandler = (_) =>
              throw StateError('secret-token owner@example.test private body');
          _problem(
            await h.provider.capabilities(h.lease),
            MailProblemCode.providerFailure,
          );
          final text = jsonEncode(logs.map((event) => event.toJson()).toList());
          for (final secret in [
            'secret-token',
            'owner@example.test',
            'private body',
            'Authorization',
          ]) {
            expect(text, isNot(contains(secret)));
          }
          expect(logs.first.stage, MailCloudLogStage.started);
          expect(logs.last.problemCode, MailProblemCode.providerFailure);
        },
      );

      test('throwing logger cannot fail a successful operation', () async {
        final h = _Harness(
          service,
          log: (_) => throw StateError('logger failed'),
        );
        _value(await h.provider.capabilities(h.lease));
      });

      test(
        'account lease and cancellation are checked before acquiring credentials',
        () async {
          final h = _Harness(service);
          _problem(
            await h.provider.capabilities(MailAccountSession(_other).begin()),
            MailProblemCode.invalidInput,
          );
          final cancelled = h.lease;
          h.session.invalidate();
          _problem(
            await h.provider.capabilities(cancelled),
            MailProblemCode.staleOperation,
          );
          expect(h.tokens.calls, isEmpty);
        },
      );

      test(
        'invalid identity, mailbox and page bounds do not touch credentials',
        () async {
          final h = _Harness(service);
          _problem(await h.headers(limit: 0), MailProblemCode.invalidInput);
          _problem(await h.headers(limit: 101), MailProblemCode.invalidInput);
          _problem(
            await h.provider.fetchHeaders(
              MailMailboxId('INBOX', account: _other),
              limit: 1,
              lease: h.lease,
            ),
            MailProblemCode.invalidInput,
          );
          _problem(
            await h.provider.fetchMessage(
              MailOpaqueIdentity(
                account: _other,
                provider: MailProviderKind.gmail,
                value: 'a',
              ),
              budget: const MailReadBudget(),
              lease: h.lease,
            ),
            MailProblemCode.invalidInput,
          );
          expect(h.tokens.calls, isEmpty);
        },
      );

      test('bounded operation timeout prevents later mailbox work', () async {
        final h = _Harness(
          service,
          limits: const MailCloudLimits(
            operationTimeout: Duration(milliseconds: 30),
          ),
        );
        final gate = Completer<MailCloudHttpResponse>();
        h.transport.profileHandler = (_) => gate.future;
        _problem(
          await h.provider.listMailboxes(h.lease),
          MailProblemCode.unavailable,
        );
        gate.complete(
          _json(
            service == MailCloudService.gmail
                ? {'emailAddress': _address}
                : {'id': 'id', 'mail': _address},
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(h.transport.mailRequests, isEmpty);
      });

      test(
        'parallel operations fail safely and disposal closes only transport',
        () async {
          final h = _Harness(service);
          final gate = Completer<MailCloudHttpResponse>();
          h.transport.profileHandler = (_) => gate.future;
          final first = h.provider.capabilities(h.lease);
          _problem(
            await h.provider.capabilities(h.lease),
            MailProblemCode.unavailable,
          );
          h.provider.dispose();
          _problem(await first, MailProblemCode.staleOperation);
          gate.complete(_json({}));
          expect(h.transport.closed, isTrue);
          expect(h.tokens.disposed, isFalse);
          _problem(
            await h.provider.capabilities(h.lease),
            MailProblemCode.staleOperation,
          );
        },
      );

      test(
        'HTTP errors carry useful safe classifications and retry delay',
        () async {
          final h = _Harness(service);
          for (final pair in <(int, MailProblemCode)>[
            (403, MailProblemCode.permissionDenied),
            (429, MailProblemCode.quotaExceeded),
            (503, MailProblemCode.unavailable),
            (302, MailProblemCode.providerFailure),
          ]) {
            h.transport.profileHandler = (_) => _error(pair.$1, retry: '42');
            final problem = _problem(
              await h.provider.capabilities(h.lease),
              pair.$2,
            );
            if (pair.$1 == 429 || pair.$1 == 503) {
              expect(problem.retryAfter, const Duration(seconds: 42));
            }
          }
          expect(h.transport.requests, hasLength(4));
        },
      );

      test(
        'malformed and oversized success responses are never empty success',
        () async {
          final h = _Harness(
            service,
            limits: const MailCloudLimits(maxResponseBytes: 1024),
          );
          h.transport.profileHandler = (_) => MailCloudHttpResponse(
            statusCode: 200,
            body: utf8.encode('{broken'),
          );
          _problem(
            await h.provider.capabilities(h.lease),
            MailProblemCode.providerFailure,
          );
          h.transport.profileHandler = (_) => MailCloudHttpResponse(
            statusCode: 200,
            body: List.filled(1025, 32),
          );
          _problem(
            await h.provider.capabilities(h.lease),
            MailProblemCode.quotaExceeded,
          );
        },
      );

      test('request budget prevents unbounded service traversal', () async {
        final h = _Harness(
          service,
          limits: const MailCloudLimits(maxRequestsPerOperation: 1),
        );
        _problem(
          await h.provider.listMailboxes(h.lease),
          MailProblemCode.quotaExceeded,
        );
        expect(h.transport.requests, hasLength(1));
      });

      test(
        'raw MIME retrieval reuses bounded codec and stable scoped identity',
        () async {
          final h = _Harness(service);
          h.transport.handler = (_) => service == MailCloudService.gmail
              ? _json({
                  'id': 'message-1',
                  'raw': base64Url.encode(utf8.encode(_wireText)),
                })
              : MailCloudHttpResponse(
                  statusCode: 200,
                  body: utf8.encode(_wireText),
                );
          final result = _value(
            await h.provider.fetchMessage(
              h.identity(),
              budget: const MailReadBudget(),
              lease: h.lease,
            ),
          );
          expect(result.envelope.subject, 'Private subject');
          expect(result.body.plainText, contains('Private body'));
          expect(result.remoteIdentity, h.identity());
          expect(result.localId, cloudMessageId(h.identity()));
          _problem(
            await h.provider.fetchMessage(
              h.identity(),
              budget: const MailReadBudget(maxRawBytes: 10),
              lease: h.lease,
            ),
            MailProblemCode.quotaExceeded,
          );
        },
      );

      test(
        'successful API sends restore hidden recipients without modifying frozen wire',
        () async {
          final h = _Harness(service);
          final message = _prepared();
          final original = message.wireHash;
          h.transport.handler = (request) {
            final encoded = service == MailCloudService.gmail
                ? (jsonDecode(utf8.decode(request.body))
                          as Map<String, Object?>)['raw']
                      as String
                : ascii.decode(request.body);
            final sent = utf8.decode(base64.decode(encoded));
            expect(sent, startsWith('Bcc: hidden@example.test\r\n'));
            expect(sent, contains('To: visible@example.test\r\n'));
            return service == MailCloudService.gmail
                ? _json({'id': 'sent-id'})
                : MailCloudHttpResponse(statusCode: 202);
          };
          final result = await h.send(message: message);
          expect(result.outcome, MailSubmissionOutcome.accepted);
          expect(result.recipients, isEmpty);
          expect(message.wireHash, original);
          expect(
            utf8.decode(message.wire.bytes),
            isNot(contains('hidden@example.test')),
          );
          expect(h.transport.mailRequests, hasLength(1));
        },
      );

      test(
        'sender mismatch and unapproved visible recipient cannot send',
        () async {
          final h = _Harness(service);
          for (final message in [
            _prepared(sender: 'spoof@example.test'),
            _prepared(recipients: const ['hidden@example.test']),
            _prepared(wire: _wireText.replaceFirst('To:', 'Bcc:')),
            _prepared(account: _other),
          ]) {
            final result = await h.send(message: message);
            expect(result.outcome, MailSubmissionOutcome.rejected);
            expect(result.problem?.code, MailProblemCode.invalidInput);
          }
          expect(h.transport.requests, isEmpty);
        },
      );

      test(
        'potentially accepted send is uncertain and is attempted exactly once',
        () async {
          final h = _Harness(service);
          for (final response in [
            _error(500),
            MailCloudHttpResponse(
              statusCode: 200,
              body: utf8.encode('{malformed'),
            ),
            MailCloudHttpResponse(statusCode: 408),
          ]) {
            h.transport.requests.clear();
            h.transport.handler = (_) => response;
            expect((await h.send()).outcome, MailSubmissionOutcome.uncertain);
            expect(h.transport.mailRequests, hasLength(1));
          }
          h.transport.requests.clear();
          h.transport.handler = (_) =>
              throw StateError('socket vanished after write');
          expect((await h.send()).outcome, MailSubmissionOutcome.uncertain);
          expect(h.transport.mailRequests, hasLength(1));
        },
      );

      test(
        'definite send rejection is distinguished from a lost response',
        () async {
          final h = _Harness(service);
          h.transport.handler = (_) => _error(403);
          expect((await h.send()).outcome, MailSubmissionOutcome.rejected);
          h.transport.handler = (_) => _error(429, retry: '90');
          final throttled = await h.send();
          expect(throttled.outcome, MailSubmissionOutcome.retryableFailure);
          expect(throttled.problem?.retryAfter, const Duration(seconds: 90));
          h.transport.handler = (_) => throw const MailCloudException(
            MailProblem(MailProblemCode.unavailable),
          );
          expect(
            (await h.send()).outcome,
            MailSubmissionOutcome.retryableFailure,
          );
          h.transport.handler = (_) => throw const MailCloudException(
            MailProblem(MailProblemCode.unavailable),
            requestMayHaveReachedServer: true,
          );
          expect((await h.send()).outcome, MailSubmissionOutcome.uncertain);
        },
      );

      for (final status in const [404, 409, 410, 412]) {
        test(
          'definite send $status is rejected without uncertainty or replay',
          () async {
            final h = _Harness(service);
            h.transport.handler = (_) => _error(status);
            final result = await h.send();
            expect(result.outcome, MailSubmissionOutcome.rejected);
            expect(result.problem?.code, MailProblemCode.invalidInput);
            expect(h.transport.mailRequests, hasLength(1));
          },
        );
      }

      test(
        'profile 404 before submission is a definite unsent failure',
        () async {
          final h = _Harness(service);
          h.transport.profileHandler = (_) => _error(404);
          final result = await h.send();
          expect(result.outcome, MailSubmissionOutcome.rejected);
          expect(result.problem?.code, MailProblemCode.invalidInput);
          expect(h.transport.mailRequests, isEmpty);
        },
      );

      test('cancellation after send starts is uncertain', () async {
        final h = _Harness(service);
        h.transport.handler = (_) {
          h.session.invalidate();
          return service == MailCloudService.gmail
              ? _json({'id': 'sent'})
              : MailCloudHttpResponse(statusCode: 202);
        };
        expect((await h.send()).outcome, MailSubmissionOutcome.uncertain);
      });

      test('unconfirmed mutation is conflict, never success', () async {
        final h = _Harness(service);
        h.transport.handler = (_) => _json(
          service == MailCloudService.gmail
              ? {
                  'id': 'message-1',
                  'labelIds': ['UNREAD'],
                }
              : {'id': 'message-1', 'isRead': false},
        );
        _problem(
          await h.provider.apply(
            MailSetRead(id: 'op', message: h.identity(), read: true),
            h.lease,
          ),
          MailProblemCode.conflict,
        );
        expect(h.transport.mailRequests, hasLength(1));
      });
    });
  }

  group('cloud boundary regressions', () {
    for (final service in MailCloudService.values) {
      test(
        '${service.name} rejects duplicate or resent delivery headers',
        () async {
          final h = _Harness(service);
          for (final header in [
            'To: attacker@example.test\r\n',
            'From: attacker@example.test\r\n',
            'Bcc: \r\n',
            'Resent-To: attacker@example.test\r\n',
            'Sender: attacker@example.test\r\n',
          ]) {
            final result = await h.send(
              message: _prepared(wire: '$header$_wireText'),
            );
            expect(result.outcome, MailSubmissionOutcome.rejected);
            expect(result.problem?.code, MailProblemCode.invalidInput);
          }
          expect(h.transport.requests, isEmpty);
        },
      );

      test(
        '${service.name} pending send timeout remains uncertain after late response',
        () async {
          final h = _Harness(
            service,
            limits: const MailCloudLimits(
              operationTimeout: Duration(milliseconds: 30),
            ),
          );
          final gate = Completer<MailCloudHttpResponse>();
          h.transport.handler = (_) => gate.future;
          final result = await h.send();
          expect(result.outcome, MailSubmissionOutcome.uncertain);
          gate.complete(
            service == MailCloudService.gmail
                ? _json({'id': 'sent'})
                : MailCloudHttpResponse(statusCode: 202),
          );
          await Future<void>.delayed(const Duration(milliseconds: 1));
          expect(h.transport.mailRequests, hasLength(1));
        },
      );

      test(
        '${service.name} corrupt cursor is rejected before account lookup',
        () async {
          final h = _Harness(service);
          for (final value in ['{broken', '{}', '[]', 'x' * 16001]) {
            _problem(
              await h.headers(
                cursor: MailCursor(mailbox: _mailbox, value: value),
              ),
              MailProblemCode.invalidInput,
            );
          }
          expect(h.transport.requests, isEmpty);
        },
      );

      test(
        '${service.name} successful verbose logs expose only structured counters',
        () async {
          final events = <MailCloudLogEvent>[];
          final h = _Harness(service, log: events.add);
          h.transport.handler = (_) => service == MailCloudService.gmail
              ? _json({
                  'id': 'message-1',
                  'raw': base64Url.encode(utf8.encode(_wireText)),
                })
              : MailCloudHttpResponse(
                  statusCode: 200,
                  body: utf8.encode(_wireText),
                );
          _value(
            await h.provider.fetchMessage(
              h.identity(),
              budget: const MailReadBudget(),
              lease: h.lease,
            ),
          );
          final text = jsonEncode(
            events.map((event) => event.toJson()).toList(),
          );
          for (final value in [
            'Private subject',
            'Private body',
            'example.test',
            'secret-token',
            'message-1',
            'https://',
          ]) {
            expect(text, isNot(contains(value)));
          }
          expect(
            events.where((event) => event.stage == MailCloudLogStage.completed),
            hasLength(1),
          );
          expect(
            events.where((event) => event.stage == MailCloudLogStage.response),
            hasLength(2),
          );
        },
      );
    }

    test(
      'Gmail metadata requests only projection headers and accepts legal folding',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) {
          if (request.uri.path.endsWith('/messages')) {
            return _json({
              'messages': [
                {'id': 'folded'},
              ],
            });
          }
          expect(
            request.uri.queryParametersAll['metadataHeaders'],
            containsAll(['Subject', 'From', 'References']),
          );
          expect(
            request.uri.queryParametersAll['metadataHeaders'],
            isNot(contains('Received')),
          );
          return _json(_gmailItem('folded', subject: 'Folded\r\n\tsubject'));
        };
        expect(
          _value(await h.headers()).messages.single.envelope.subject,
          'Folded subject',
        );
      },
    );

    test(
      'Gmail no-label messages produce membership tombstones after removal',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) {
          if (request.uri.path.endsWith('/messages')) return _json({});
          if (request.uri.path.endsWith('/history')) {
            return _json({
              'historyId': '101',
              'history': [
                {
                  'id': '101',
                  'labelsRemoved': [
                    {
                      'message': {'id': 'a'},
                      'labelIds': ['INBOX'],
                    },
                  ],
                },
              ],
            });
          }
          final item = _gmailItem('a')..remove('labelIds');
          return _json(item);
        };
        final initial = _value(await h.changes());
        final changes = _value(await h.changes(cursor: initial.next));
        expect(changes.tombstones, [h.identity('a')]);
        expect(changes.upserts, isEmpty);
      },
    );

    test(
      'Gmail history pagination retains start checkpoint until final page',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) {
          if (request.uri.path.endsWith('/messages')) return _json({});
          expect(request.uri.queryParameters['startHistoryId'], '100');
          return _json(
            request.uri.queryParameters['pageToken'] == null
                ? {'historyId': '250', 'nextPageToken': 'h2'}
                : {'historyId': '300'},
          );
        };
        final initial = _value(await h.changes());
        final first = _value(await h.changes(cursor: initial.next));
        expect(first.hasMore, isTrue);
        final second = _value(await h.changes(cursor: first.next));
        expect(second.hasMore, isFalse);
        final data =
            (jsonDecode(second.next.value) as Map<String, Object?>)['data']
                as Map<String, Object?>;
        expect(data['start'], '300');
      },
    );

    test(
      'Gmail repeated browse token is rejected without claiming completion',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (_) => _json({'nextPageToken': 'same'});
        final first = _value(await h.headers());
        _problem(
          await h.headers(cursor: first.next),
          MailProblemCode.providerFailure,
        );
      },
    );

    test(
      'Gmail history overlarge pending cursor fails without committing a partial page',
      () async {
        final h = _Harness(
          MailCloudService.gmail,
          limits: const MailCloudLimits(maxCursorBytes: 512),
        );
        h.transport.handler = (request) =>
            request.uri.path.endsWith('/messages')
            ? _json({})
            : _json({
                'historyId': '200',
                'history': [
                  {
                    'id': '101',
                    'messages': [
                      for (var i = 0; i < 40; i++)
                        {'id': 'message-$i-with-a-long-id'},
                    ],
                  },
                ],
              });
        final initial = _value(await h.changes(limit: 1));
        _problem(
          await h.changes(cursor: initial.next, limit: 1),
          MailProblemCode.quotaExceeded,
        );
        expect(
          h.transport.mailRequests.where(
            (r) => r.uri.path.contains('/messages/'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'Graph canonical user links are bound to verified profile identity',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        for (final actor in ['users/remote-user-1', "users('remote-user-1')"]) {
          final next =
              'https://graph.microsoft.com/v1.0/$actor/mailFolders/INBOX/messages?%24skiptoken=2';
          h.transport.handler = (request) => _json({
            'value': <Object?>[],
            if (!request.uri.queryParameters.containsKey(r'$skiptoken'))
              '@odata.nextLink': next,
          });
          final first = _value(await h.headers());
          _value(await h.headers(cursor: first.next));
          expect(h.transport.mailRequests.last.uri.toString(), next);
        }
        h.transport.handler = (_) => _json({
          'value': <Object?>[],
          '@odata.nextLink':
              'https://graph.microsoft.com/v1.0/users/other-user/mailFolders/INBOX/messages?%24skiptoken=2',
        });
        _problem(await h.headers(), MailProblemCode.invalidInput);
        expect(
          h.transport.requests.any(
            (request) => request.uri.path.contains('other-user'),
          ),
          isFalse,
        );
      },
    );

    test(
      'Graph delta page preference stays bounded across continuations',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        h.transport.handler = (request) {
          expect(
            request.headers['Prefer'],
            'IdType="ImmutableId", odata.maxpagesize=2',
          );
          return _json({
            'value': <Object?>[],
            '@odata.deltaLink': _next(delta: true),
          });
        };
        final first = _value(await h.changes(limit: 2));
        _value(await h.changes(cursor: first.next, limit: 2));
      },
    );

    test(
      'Graph detects recursive folder cycles with no truncated success',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        h.transport.handler = (_) => _json({
          'value': [
            {'id': 'cycle', 'displayName': 'Cycle', 'childFolderCount': 1},
          ],
        });
        _problem(
          await h.provider.listMailboxes(h.lease),
          MailProblemCode.providerFailure,
        );
        expect(h.transport.mailRequests, hasLength(2));
      },
    );
  });

  group('Gmail semantics', () {
    test(
      'labels retain provider IDs and reject duplicates or oversize collections',
      () async {
        final h = _Harness(
          MailCloudService.gmail,
          limits: const MailCloudLimits(maxMailboxes: 1),
        );
        h.transport.handler = (_) => _json({
          'labels': [
            {'id': 'INBOX', 'name': 'Inbox'},
          ],
        });
        final result = _value(await h.provider.listMailboxes(h.lease));
        expect(result.single.isLabel, isTrue);
        expect(result.single.id, _mailbox);
        h.transport.handler = (_) => _json({
          'labels': [
            {'id': 'INBOX', 'name': 'Inbox'},
            {'id': 'work', 'name': 'Work'},
          ],
        });
        _problem(
          await h.provider.listMailboxes(h.lease),
          MailProblemCode.quotaExceeded,
        );
        h.transport.handler = (_) => _json({
          'labels': [
            {'id': 'INBOX', 'name': 'Inbox'},
            {'id': 'INBOX', 'name': 'Inbox'},
          ],
        });
        _problem(
          await h.provider.listMailboxes(h.lease),
          MailProblemCode.providerFailure,
        );
      },
    );

    test(
      'headers page metadata, observe flags and reject foreign cursors',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) =>
            request.uri.path.endsWith('/messages')
            ? _json({
                'messages': [
                  {'id': 'a'},
                ],
                'nextPageToken': 'next',
              })
            : _json(_gmailItem('a', labels: ['INBOX', 'STARRED']));
        final page = _value(await h.headers());
        expect(page.messages.single.envelope.subject, 'Subject');
        expect(page.messages.single.flags?.isRead, isTrue);
        expect(page.messages.single.flags?.isFlagged, isTrue);
        final other = MailMailboxId('OTHER', account: _account);
        _problem(
          await h.provider.fetchHeaders(
            other,
            cursor: page.next,
            limit: 10,
            lease: h.lease,
          ),
          MailProblemCode.invalidInput,
        );
        _problem(
          await h.changes(cursor: page.next),
          MailProblemCode.invalidInput,
        );
        final renamed = _Harness(
          MailCloudService.gmail,
          address: 'renamed@example.test',
        );
        _problem(
          await renamed.headers(cursor: page.next),
          MailProblemCode.invalidInput,
        );
        expect(renamed.transport.requests, isEmpty);
      },
    );

    test(
      'forged metadata header injection and mismatched message IDs fail closed',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) =>
            request.uri.path.endsWith('/messages')
            ? _json({
                'messages': [
                  {'id': 'a'},
                ],
              })
            : _json(
                _gmailItem('a', subject: 'hello\r\nBcc: attacker@example.test'),
              );
        _problem(await h.headers(), MailProblemCode.providerFailure);
        h.transport.handler = (request) =>
            request.uri.path.endsWith('/messages')
            ? _json({
                'messages': [
                  {'id': 'a'},
                ],
              })
            : _json(_gmailItem('b'));
        _problem(await h.headers(), MailProblemCode.providerFailure);
      },
    );

    test('a disappeared listed message is not a fabricated header', () async {
      final h = _Harness(MailCloudService.gmail);
      h.transport.handler = (request) => request.uri.path.endsWith('/messages')
          ? _json({
              'messages': [
                {'id': 'a'},
              ],
            })
          : _error(404);
      expect(_value(await h.headers()).messages, isEmpty);
    });

    test('move is explicitly unsupported and makes no request', () async {
      final h = _Harness(MailCloudService.gmail);
      _problem(
        await h.provider.apply(
          MailMove(id: 'move', message: h.identity(), destination: _mailbox),
          h.lease,
        ),
        MailProblemCode.unsupported,
      );
      expect(h.transport.requests, isEmpty);
    });

    test(
      'read, star and trash use exact targeted changes and require confirmation',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) {
          expect(request.method, 'POST');
          if (request.uri.path.endsWith('/trash')) {
            return _json({
              'id': 'message-1',
              'labelIds': ['TRASH'],
            });
          }
          final Object? body = jsonDecode(utf8.decode(request.body));
          if ((body as Map<String, Object?>).containsKey('removeLabelIds')) {
            expect(body, {
              'removeLabelIds': ['UNREAD'],
            });
            return _json({
              'id': 'message-1',
              'labelIds': ['INBOX'],
            });
          }
          expect(body, {
            'addLabelIds': ['STARRED'],
          });
          return _json({
            'id': 'message-1',
            'labelIds': ['INBOX', 'STARRED'],
          });
        };
        _value(
          await h.provider.apply(
            MailSetRead(id: 'r', message: h.identity(), read: true),
            h.lease,
          ),
        );
        _value(
          await h.provider.apply(
            MailSetFlagged(id: 'f', message: h.identity(), flagged: true),
            h.lease,
          ),
        );
        _value(
          await h.provider.apply(
            MailDelete(id: 'd', message: h.identity()),
            h.lease,
          ),
        );
        expect(
          h.transport.mailRequests.any((r) => r.method == 'DELETE'),
          isFalse,
        );
      },
    );

    test(
      'snapshot checkpoint starts before listing and catches concurrent changes',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) {
          if (request.uri.path.endsWith('/messages')) {
            return _json({
              'messages': [
                {'id': 'a'},
              ],
            });
          }
          if (request.uri.path.endsWith('/history')) {
            expect(request.uri.queryParameters['startHistoryId'], '100');
            expect(request.uri.queryParameters.containsKey('labelId'), isFalse);
            return _json({
              'historyId': '200',
              'history': [
                {
                  'id': '101',
                  'labelsRemoved': [
                    {
                      'message': {'id': 'a'},
                      'labelIds': ['INBOX'],
                    },
                  ],
                },
              ],
            });
          }
          return _json(
            _gmailItem(
              'a',
              labels:
                  h.transport.requests
                      .where((r) => r.uri.path.endsWith('/history'))
                      .isEmpty
                  ? ['INBOX']
                  : ['OTHER'],
            ),
          );
        };
        final first = _value(await h.changes());
        expect(first.resetRequired, isTrue);
        expect(first.hasMore, isTrue);
        expect(first.upserts, hasLength(1));
        final second = _value(await h.changes(cursor: first.next));
        expect(second.resetRequired, isFalse);
        expect(second.hasMore, isFalse);
        expect(second.tombstones, [h.identity('a')]);
        expect(second.upserts, isEmpty);
      },
    );

    test('snapshot paging only resets membership on first page', () async {
      final h = _Harness(MailCloudService.gmail);
      h.transport.handler = (request) {
        if (request.uri.path.endsWith('/messages')) {
          return _json(
            request.uri.queryParameters['pageToken'] == null
                ? {
                    'messages': [
                      {'id': 'a'},
                    ],
                    'nextPageToken': 'p2',
                  }
                : {
                    'messages': [
                      {'id': 'b'},
                    ],
                  },
          );
        }
        return _json(_gmailItem(request.uri.pathSegments.last));
      };
      final first = _value(await h.changes(limit: 1));
      final second = _value(await h.changes(cursor: first.next, limit: 1));
      expect(first.resetRequired, isTrue);
      expect(second.resetRequired, isFalse);
      expect(second.upserts.single.remote, h.identity('b'));
    });

    test(
      'history changes deduplicate IDs and persist bounded pending detail work',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) {
          if (request.uri.path.endsWith('/messages')) return _json({});
          if (request.uri.path.endsWith('/history')) {
            return _json({
              'historyId': '200',
              'history': [
                {
                  'id': '101',
                  'messages': [
                    {'id': 'a'},
                    {'id': 'b'},
                    {'id': 'a'},
                  ],
                },
              ],
            });
          }
          return request.uri.pathSegments.last == 'a'
              ? _json(_gmailItem('a'))
              : _error(404);
        };
        final first = _value(await h.changes(limit: 1));
        final changes = _value(await h.changes(cursor: first.next, limit: 1));
        expect(changes.upserts.single.remote, h.identity('a'));
        expect(changes.hasMore, isTrue);
        final pending = _value(await h.changes(cursor: changes.next, limit: 1));
        expect(pending.tombstones, [h.identity('b')]);
        expect(pending.hasMore, isFalse);
        expect(
          h.transport.requests.where((r) => r.uri.path.endsWith('/history')),
          hasLength(1),
        );
      },
    );

    test(
      'expired history resets from a new profile baseline and revision advances',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) =>
            request.uri.path.endsWith('/history') ? _error(404) : _json({});
        final first = _value(await h.changes());
        h.transport.profileHandler = (_) =>
            _json({'emailAddress': _address, 'historyId': '300'});
        final reset = _value(await h.changes(cursor: first.next));
        expect(reset.resetRequired, isTrue);
        expect(reset.next.value, isNot(first.next.value));
        expect(
          ((jsonDecode(reset.next.value) as Map<String, Object?>)['data']
              as Map<String, Object?>)['start'],
          '300',
        );
      },
    );

    test(
      'empty history advances local revision without inventing deletions',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.handler = (request) => request.uri.path.endsWith('/history')
            ? _json({'historyId': '100'})
            : _json({});
        final first = _value(await h.changes());
        final second = _value(await h.changes(cursor: first.next));
        final third = _value(await h.changes(cursor: second.next));
        expect(second.hasMore, isFalse);
        expect(third.next.value, isNot(second.next.value));
        expect(third.tombstones, isEmpty);
      },
    );

    test(
      '403 quota reason maps to retryable quota without exposing provider text',
      () async {
        final h = _Harness(MailCloudService.gmail);
        h.transport.profileHandler = (_) =>
            _error(403, code: 'userRateLimitExceeded', retry: '17');
        final problem = _problem(
          await h.provider.capabilities(h.lease),
          MailProblemCode.quotaExceeded,
        );
        expect(problem.retryAfter, const Duration(seconds: 17));
      },
    );
  });

  group('Graph semantics', () {
    test(
      'nested folder traversal follows pages and retains immutable ID preference',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        h.transport.handler = (request) {
          if (request.uri.path.endsWith('/childFolders')) {
            return _json({
              'value': [
                {'id': 'child', 'displayName': 'Child', 'childFolderCount': 0},
              ],
            });
          }
          return _json({
            'value': [
              {'id': 'INBOX', 'displayName': 'Inbox', 'childFolderCount': 1},
            ],
          });
        };
        final folders = _value(await h.provider.listMailboxes(h.lease));
        expect(folders.map((f) => f.id.value), ['INBOX', 'child']);
        for (final request in h.transport.requests) {
          expect(request.headers['Prefer'], 'IdType="ImmutableId"');
        }
      },
    );

    test('headers and cursor preserve ID case and page URLs', () async {
      final h = _Harness(MailCloudService.microsoft365);
      h.transport.handler = (request) => _json({
        'value': [_graphItem('AaBb')],
        if (!request.uri.queryParameters.containsKey(r'$skiptoken'))
          '@odata.nextLink': _next(),
      });
      final first = _value(await h.headers());
      expect(first.messages.single.remote, h.identity('AaBb'));
      final second = _value(await h.headers(cursor: first.next));
      expect(second.next, isNull);
      expect(h.transport.mailRequests.last.uri.toString(), _next());
    });

    test(
      'foreign-host, foreign-folder and fragment continuation URLs are refused',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        for (final url in [
          _next(host: 'attacker.example'),
          _next(folder: 'Other'),
          '${_next()}#secret',
          'http://graph.microsoft.com/v1.0/me/mailFolders/INBOX/messages',
          'https://graph.microsoft.com/v1.0/users/other/messages',
          'https://attacker@graph.microsoft.com/v1.0/me/mailFolders/INBOX/messages',
        ]) {
          h.transport.handler = (_) =>
              _json({'value': <Object?>[], '@odata.nextLink': url});
          _problem(await h.headers(), MailProblemCode.invalidInput);
        }
        expect(
          h.transport.requests.any((r) => r.uri.host != 'graph.microsoft.com'),
          isFalse,
        );
      },
    );

    test('OData parenthesized same-folder continuations are accepted', () async {
      final h = _Harness(MailCloudService.microsoft365);
      const next =
          "https://graph.microsoft.com/v1.0/me/mailfolders('INBOX')/messages?%24skiptoken=2";
      h.transport.handler = (request) => _json({
        'value': <Object?>[],
        if (!request.uri.queryParameters.containsKey(r'$skiptoken'))
          '@odata.nextLink': next,
      });
      final first = _value(await h.headers());
      _value(await h.headers(cursor: first.next));
      expect(h.transport.mailRequests.last.uri.toString(), next);
    });

    test(
      'read, flag, move and recoverable delete require observed confirmation',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        h.transport.handler = (request) {
          if (request.uri.path.endsWith('/deleteditems')) {
            return _json({'id': 'trash-id'});
          }
          final data =
              jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;
          if (request.uri.path.endsWith('/move')) {
            return _json({
              'id': 'message-1',
              'parentFolderId': data['destinationId'],
            }, status: 201);
          }
          return _json({'id': 'message-1', ...data});
        };
        _value(
          await h.provider.apply(
            MailSetRead(id: 'r', message: h.identity(), read: true),
            h.lease,
          ),
        );
        _value(
          await h.provider.apply(
            MailSetFlagged(id: 'f', message: h.identity(), flagged: true),
            h.lease,
          ),
        );
        _value(
          await h.provider.apply(
            MailMove(id: 'm', message: h.identity(), destination: _mailbox),
            h.lease,
          ),
        );
        _value(
          await h.provider.apply(
            MailDelete(id: 'd', message: h.identity()),
            h.lease,
          ),
        );
        expect(
          h.transport.mailRequests.any((r) => r.method == 'DELETE'),
          isFalse,
        );
      },
    );

    test(
      'delta applies updates and membership tombstones across complete pages',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        h.transport.handler = (request) => _json(
          request.uri.queryParameters.containsKey(r'$skiptoken')
              ? {
                  'value': [
                    {
                      'id': 'deleted',
                      '@removed': {'reason': 'deleted'},
                    },
                    _graphItem('moved', parent: 'Other'),
                  ],
                  '@odata.deltaLink': _next(delta: true, token: 'done'),
                }
              : {
                  'value': [_graphItem('initial')],
                  '@odata.nextLink': _next(delta: true),
                },
        );
        final first = _value(await h.changes());
        expect(first.resetRequired, isTrue);
        expect(first.hasMore, isTrue);
        final second = _value(await h.changes(cursor: first.next));
        expect(second.resetRequired, isFalse);
        expect(second.hasMore, isFalse);
        expect(second.tombstones, [h.identity('deleted'), h.identity('moved')]);
      },
    );

    test(
      'partial delta update retrieves full selected metadata before upsert',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        h.transport.handler = (request) => request.uri.path.endsWith('/delta')
            ? _json({
                'value': [
                  {'id': 'a', 'isRead': true},
                ],
                '@odata.deltaLink': _next(delta: true),
              })
            : _json(_graphItem('a', read: true));
        final page = _value(await h.changes());
        expect(page.upserts.single.envelope.subject, 'Subject');
        expect(page.upserts.single.flags?.isRead, isTrue);
        expect(h.transport.mailRequests, hasLength(2));
      },
    );

    test(
      'explicit expired delta state resets, unrelated failures do not',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        h.transport.handler = (_) => _json({
          'value': <Object?>[],
          '@odata.deltaLink': _next(delta: true),
        });
        final first = _value(await h.changes());
        h.transport.handler = (request) =>
            request.uri.queryParameters.containsKey(r'$skiptoken')
            ? _error(410, code: 'SyncStateNotFound')
            : _json({
                'value': <Object?>[],
                '@odata.deltaLink': _next(delta: true, token: 'new'),
              });
        final reset = _value(await h.changes(cursor: first.next));
        expect(reset.resetRequired, isTrue);
        h.transport.handler = (_) => _error(404);
        _problem(await h.changes(cursor: reset.next), MailProblemCode.conflict);
      },
    );

    test('delta requires exactly one terminal or continuation link', () async {
      final h = _Harness(MailCloudService.microsoft365);
      for (final links in [
        <String, Object?>{},
        {
          '@odata.nextLink': _next(delta: true),
          '@odata.deltaLink': _next(delta: true),
        },
      ]) {
        h.transport.handler = (_) => _json({'value': <Object?>[], ...links});
        _problem(await h.changes(), MailProblemCode.providerFailure);
      }
    });

    test(
      'unchanged delta state still advances the local CAS revision',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        h.transport.handler = (_) => _json({
          'value': <Object?>[],
          '@odata.deltaLink': _next(delta: true),
        });
        final first = _value(await h.changes());
        final second = _value(await h.changes(cursor: first.next));
        expect(first.next.value, isNot(second.next.value));
      },
    );

    test(
      'wrong message ID in confirmed move remains uncertain conflict',
      () async {
        final h = _Harness(MailCloudService.microsoft365);
        h.transport.handler = (_) =>
            _json({'id': 'changed-id', 'parentFolderId': 'INBOX'}, status: 201);
        _problem(
          await h.provider.apply(
            MailMove(id: 'm', message: h.identity(), destination: _mailbox),
            h.lease,
          ),
          MailProblemCode.conflict,
        );
      },
    );
  });
}
