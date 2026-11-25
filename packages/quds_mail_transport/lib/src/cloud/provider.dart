import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';

import 'configuration.dart';
import 'cursor.dart';
import 'http.dart';

part 'provider_search.dart';

typedef _Json = Map<String, Object?>;

Never _fail(MailProblemCode code) =>
    throw MailCloudException(MailProblem(code));

_Json _object(Object? value) {
  if (value is! Map<String, Object?>) _fail(MailProblemCode.providerFailure);
  return value;
}

List<Object?> _array(Object? value) {
  if (value is! List<Object?>) _fail(MailProblemCode.providerFailure);
  return value;
}

String _text(Object? value, {bool empty = false, int max = 2048}) {
  if (value is! String ||
      (!empty && value.isEmpty) ||
      value.length > max ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    _fail(MailProblemCode.providerFailure);
  }
  return value;
}

bool _validId(String value) =>
    value.isNotEmpty &&
    value.length <= 2048 &&
    !value.contains(RegExp(r'[\x00-\x1f\x7f]'));

final class _ResponseFailure implements Exception {
  const _ResponseFailure(this.problem, this.status, this.code);
  final MailProblem problem;
  final int status;
  final String? code;
}

final class _Operation {
  _Operation(this.lease, this.kind);
  final MailOperationLease lease;
  final MailCloudOperation kind;
  final Stopwatch watch = Stopwatch()..start();
  bool stopped = false;
  bool mutationPossible = false;
  int requests = 0;
  int? itemCount;
  String token = '';
  _Json profile = const {};

  void check() {
    lease.checkCurrent();
    if (stopped) _fail(MailProblemCode.staleOperation);
  }
}

/// Gmail and Microsoft Graph adapters share bounded HTTP and MIME boundaries.
/// No mail submission or mutation is retried. Each operation verifies that the
/// supplied credential still belongs to its configured mailbox before mail IO.
final class ApiMailCloudProvider
    implements
        MailCloudProvider,
        MailFlagObserver,
        MailMembershipObserver,
        MailArchiveDestinationResolver,
        MailProviderSearch {
  ApiMailCloudProvider({
    required this.configuration,
    required this.tokenSource,
    required this.transport,
    this.codec = const QudsMimeCodec(),
    this.limits = const MailCloudLimits(),
    this.log,
  }) {
    limits.validate();
  }

  final MailCloudConfiguration configuration;
  final MailCloudTokenSource tokenSource;
  final MailCloudHttpTransport transport;
  final MailCodec codec;
  final MailCloudLimits limits;
  final MailCloudLogSink? log;
  bool _busy = false;
  bool _disposed = false;
  _Operation? _active;

  bool get _gmail => configuration.service == MailCloudService.gmail;
  MailProviderKind get _kind =>
      _gmail ? MailProviderKind.gmail : MailProviderKind.graph;

  @override
  MailAccountId get account => configuration.account;

  @override
  Set<MailProviderSearchField> get searchFields => _gmail
      ? const {
          MailProviderSearchField.subject,
          MailProviderSearchField.from,
          MailProviderSearchField.to,
        }
      : const {
          MailProviderSearchField.body,
          MailProviderSearchField.subject,
          MailProviderSearchField.from,
          MailProviderSearchField.to,
        };

  @override
  Future<MailResult<MailProviderSearchResult>> search(
    MailProviderSearchRequest request, {
    required MailOperationLease lease,
  }) => _search(request, lease: lease);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active?.stopped = true;
    try {
      transport.close();
    } on Object {
      // Disposal must not leak host exceptions or dispose a host-owned token.
    }
  }

  void _event(
    _Operation operation,
    MailCloudLogStage stage, {
    int? status,
    int? requestBytes,
    int? responseBytes,
    int? items,
    MailProblem? problem,
  }) => emitMailCloudLog(
    log,
    MailCloudLogEvent(
      service: configuration.service,
      operation: operation.kind,
      stage: stage,
      statusCode: status,
      elapsedMilliseconds: operation.watch.elapsedMilliseconds,
      requestBytes: requestBytes,
      responseBytes: responseBytes,
      itemCount: items,
      attempt: operation.requests,
      problemCode: problem?.code,
      retryAfterSeconds: problem?.retryAfter?.inSeconds,
    ),
  );

  MailFailure<T> _failure<T>(MailProblemCode code) =>
      MailFailure(MailProblem(code, mutationMayHaveOccurred: false));

  bool _mailboxValid(MailMailboxId mailbox) =>
      mailbox.account == account && _validId(mailbox.value);

  bool _identityValid(MailRemoteIdentity identity) =>
      identity is MailOpaqueIdentity &&
      identity.account == account &&
      identity.provider == _kind &&
      _validId(identity.value);

  MailOpaqueIdentity _identity(String id) =>
      MailOpaqueIdentity(account: account, provider: _kind, value: id);

  Uri _gmailUri(List<String> path, [Map<String, Object?>? query]) => Uri(
    scheme: 'https',
    host: 'gmail.googleapis.com',
    pathSegments: ['gmail', 'v1', 'users', 'me', ...path],
    queryParameters: query,
  );

  Uri _graphUri(List<String> path, [Map<String, String>? query]) => Uri(
    scheme: 'https',
    host: 'graph.microsoft.com',
    pathSegments: ['v1.0', 'me', ...path],
    queryParameters: query,
  );

  Future<MailResult<T>> _run<T>(
    MailOperationLease lease,
    MailCloudOperation kind,
    Future<T> Function(_Operation operation) action,
  ) async {
    if (lease.account != account) return _failure(MailProblemCode.invalidInput);
    if (_disposed) return _failure(MailProblemCode.staleOperation);
    if (_busy) return _failure(MailProblemCode.unavailable);
    _busy = true;
    final operation = _Operation(lease, kind);
    _active = operation;
    Timer? poll;
    _event(operation, MailCloudLogStage.started);
    try {
      operation.check();
      final cancelled = Completer<T>();
      poll = Timer.periodic(const Duration(milliseconds: 25), (_) {
        try {
          operation.check();
        } on Object catch (error, stack) {
          if (!cancelled.isCompleted) cancelled.completeError(error, stack);
        }
      });
      final work = () async {
        await _verify(operation);
        operation.check();
        return action(operation);
      }();
      final result = await Future.any([work, cancelled.future])
          .timeout(limits.operationTimeout);
      operation.check();
      _event(
        operation,
        MailCloudLogStage.completed,
        items: result is MailSyncPage
            ? result.upserts.length
            : operation.itemCount,
      );
      return MailSuccess(result);
    } on Object catch (error) {
      final MailProblem problem;
      if (operation.mutationPossible) {
        problem = const MailProblem(MailProblemCode.conflict);
      } else if (error is MailCloudException) {
        problem = error.problem;
      } else if (error is _ResponseFailure) {
        problem = error.problem;
      } else if (error is MailCancelled) {
        problem = MailProblem(
          error.reason == MailCancellationReason.user ||
                  error.reason == MailCancellationReason.budgetExpired
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
        );
      } else if (error is TimeoutException) {
        problem = MailProblem(
          MailProblemCode.unavailable,
          retryAfter: limits.retryAfter,
        );
      } else {
        problem = const MailProblem(MailProblemCode.providerFailure);
      }
      // For submission, conflict is reserved for possible server acceptance.
      // A missing mailbox discovered during verification or an explicit 4xx
      // send rejection must not strand a safely unsent draft as uncertain.
      final reported =
          kind == MailCloudOperation.submit &&
              !operation.mutationPossible &&
              problem.code == MailProblemCode.conflict
          ? const MailProblem(MailProblemCode.invalidInput)
          : problem;
      _event(
        operation,
        reported.code == MailProblemCode.cancelled ||
                reported.code == MailProblemCode.staleOperation
            ? MailCloudLogStage.cancelled
            : MailCloudLogStage.failed,
        problem: reported,
      );
      return MailFailure(
        MailProblem(
          reported.code,
          retryAfter: reported.retryAfter,
          mutationMayHaveOccurred: operation.mutationPossible,
        ),
      );
    } finally {
      operation.stopped = true;
      poll?.cancel();
      _active = null;
      _busy = false;
    }
  }

  Future<void> _token(_Operation operation, {bool refresh = false}) async {
    operation.check();
    final result = await tokenSource.accessToken(
      operation.lease,
      forceRefresh: refresh,
    );
    operation.check();
    if (result case MailFailure<MailCloudAccessToken>(:final problem)) {
      throw MailCloudException(problem);
    }
    final token = (result as MailSuccess<MailCloudAccessToken>).value;
    if (!token.expiresAt.isAfter(DateTime.now())) {
      _fail(MailProblemCode.authenticationRequired);
    }
    operation.token = token.value;
  }

  Future<void> _verify(_Operation operation) async {
    await _token(operation);
    final uri = _gmail
        ? _gmailUri(['profile'])
        : _graphUri([], {r'$select': 'id,mail,userPrincipalName'});
    _Json profile;
    try {
      profile = await _json(operation, 'GET', uri);
    } on _ResponseFailure catch (error) {
      if (error.status != 401) rethrow;
      _event(operation, MailCloudLogStage.refresh);
      await _token(operation, refresh: true);
      profile = await _json(operation, 'GET', uri);
    }
    final expected = configuration.mailboxAddress.toLowerCase();
    final addresses = _gmail
        ? [_text(profile['emailAddress'])]
        : [
            if (profile['mail'] is String && profile['mail'] != '')
              _text(profile['mail']),
            if (profile['userPrincipalName'] is String &&
                profile['userPrincipalName'] != '')
              _text(profile['userPrincipalName']),
          ];
    if (addresses.isEmpty ||
        !addresses.any((value) => value.toLowerCase() == expected)) {
      _fail(MailProblemCode.permissionDenied);
    }
    if (!_gmail) _text(profile['id']);
    operation.profile = profile;
  }

  Future<MailCloudHttpResponse> _request(
    _Operation operation,
    String method,
    Uri uri, {
    List<int> body = const [],
    String contentType = 'application/json',
    bool mutation = false,
    int? responseLimit,
    int? pageSize,
  }) async {
    operation.check();
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.port != 443 ||
        uri.host != (_gmail ? 'gmail.googleapis.com' : 'graph.microsoft.com')) {
      _fail(MailProblemCode.invalidInput);
    }
    if (++operation.requests > limits.maxRequestsPerOperation ||
        body.length > limits.maxRequestBytes) {
      _fail(MailProblemCode.quotaExceeded);
    }
    final remaining = limits.operationTimeout - operation.watch.elapsed;
    if (remaining <= Duration.zero) _fail(MailProblemCode.unavailable);
    _event(operation, MailCloudLogStage.request, requestBytes: body.length);
    final request = MailCloudHttpRequest(
      method: method,
      uri: uri,
      headers: {
        'Authorization': 'Bearer ${operation.token}',
        'Accept': 'application/json',
        if (!_gmail)
          'Prefer':
              'IdType="ImmutableId"${pageSize == null ? '' : ', odata.maxpagesize=$pageSize'}',
        if (body.isNotEmpty) 'Content-Type': contentType,
      },
      body: body,
    );
    if (mutation) operation.mutationPossible = true;
    MailCloudHttpResponse response;
    try {
      response = await transport.send(
        request,
        lease: operation.lease,
        timeout: remaining,
        maxResponseBytes: math.min(
          responseLimit ?? limits.maxResponseBytes,
          limits.maxResponseBytes,
        ),
      );
    } on MailCloudException catch (error) {
      if (mutation && !error.requestMayHaveReachedServer) {
        operation.mutationPossible = false;
      }
      rethrow;
    }
    // Foreground mutations use a narrow no-write evidence set. A dispatched
    // 410 response does not establish the requested flag's final state; retain
    // uncertainty and stop the batch. Submission keeps its separate existing
    // client-rejection and Retry-After contract.
    final rejectedWithoutMutation = operation.kind == MailCloudOperation.apply
        ? const {
            400,
            401,
            403,
            404,
            409,
            412,
            429,
          }.contains(response.statusCode)
        : response.statusCode >= 400 &&
              response.statusCode < 500 &&
              response.statusCode != 408;
    if (mutation && rejectedWithoutMutation) {
      operation.mutationPossible = false;
    }
    operation.check();
    if (response.body.length > (responseLimit ?? limits.maxResponseBytes) ||
        response.body.length > limits.maxResponseBytes) {
      _fail(MailProblemCode.quotaExceeded);
    }
    _event(
      operation,
      MailCloudLogStage.response,
      status: response.statusCode,
      responseBytes: response.body.length,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _responseError(response);
    }
    return response;
  }

  Future<_Json> _json(
    _Operation operation,
    String method,
    Uri uri, {
    _Json? body,
    bool mutation = false,
    int? pageSize,
    int? responseLimit,
  }) async {
    final response = await _request(
      operation,
      method,
      uri,
      body: body == null ? const [] : utf8.encode(jsonEncode(body)),
      mutation: mutation,
      pageSize: pageSize,
      responseLimit: responseLimit,
    );
    return _object(jsonDecode(utf8.decode(response.body)));
  }

  _ResponseFailure _responseError(MailCloudHttpResponse response) {
    String? code;
    try {
      final error = _object(
        _object(jsonDecode(utf8.decode(response.body)))['error'],
      );
      if (error['code'] is String) code = error['code'] as String;
      if (_gmail && error['errors'] is List<Object?>) {
        for (final entry in error['errors'] as List<Object?>) {
          final reason = _object(entry)['reason'];
          if (reason is String) {
            code = reason;
            break;
          }
        }
      }
    } on Object {
      // Status remains useful when an error body is absent or malformed.
    }
    final status = response.statusCode;
    final quota =
        status == 429 ||
        (status == 403 &&
            const {
              'rateLimitExceeded',
              'userRateLimitExceeded',
              'quotaExceeded',
              'dailyLimitExceeded',
            }.contains(code));
    final problem = MailProblem(
      quota
          ? MailProblemCode.quotaExceeded
          : switch (status) {
              401 => MailProblemCode.authenticationRequired,
              403 => MailProblemCode.permissionDenied,
              404 || 409 || 410 || 412 => MailProblemCode.conflict,
              413 => MailProblemCode.quotaExceeded,
              400 || 405 || 422 => MailProblemCode.invalidInput,
              408 || 500 || 502 || 503 || 504 => MailProblemCode.unavailable,
              _ => MailProblemCode.providerFailure,
            },
      retryAfter: quota || status == 408 || status >= 500
          ? _retryAfter(response.headers) ?? limits.retryAfter
          : null,
    );
    return _ResponseFailure(problem, status, code);
  }

  Duration? _retryAfter(Map<String, String> headers) {
    String? value;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'retry-after') value = entry.value.trim();
    }
    if (value == null || value.length > 128) return null;
    final seconds = int.tryParse(value);
    if (seconds != null && seconds >= 0 && seconds <= 0x7fffffff) {
      return Duration(seconds: seconds);
    }
    final match = RegExp(
      r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    if (match == null) return null;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months.indexOf(match[2]!);
    if (month < 0) return null;
    final time = DateTime.utc(
      int.parse(match[3]!),
      month + 1,
      int.parse(match[1]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
    final delay = time.difference(DateTime.now().toUtc());
    return delay < Duration.zero ? Duration.zero : delay;
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(MailOperationLease lease) =>
      _run(
        lease,
        MailCloudOperation.capabilities,
        (_) async => MailCapabilities([
          MailCapability.mail,
          MailCapability.folders,
          MailCapability.send,
          MailCapability.delete,
          if (_gmail) MailCapability.labels else MailCapability.move,
          if (_gmail) MailCapability.archive,
        ]),
      );

  @override
  Future<MailResult<MailMailbox>> resolveArchiveDestination(
    MailOperationLease lease,
  ) async {
    if (_gmail) return _failure(MailProblemCode.unsupported);
    return _run(lease, MailCloudOperation.listMailboxes, (operation) async {
      final _Json folder;
      try {
        folder = await _json(
          operation,
          'GET',
          _graphUri(['mailFolders', 'archive'], {r'$select': 'id,displayName'}),
          responseLimit: limits.maxHeaderBytes,
        );
      } on _ResponseFailure catch (error) {
        // A missing ordinary archive permits explicit user selection. Other
        // failures must not masquerade as a harmless discovery fallback.
        if (error.status == 404) _fail(MailProblemCode.unsupported);
        rethrow;
      }
      return MailMailbox(
        id: MailMailboxId(_text(folder['id']), account: account),
        displayName: _text(folder['displayName']),
      );
    });
  }

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) => _run(lease, MailCloudOperation.listMailboxes, (operation) async {
    final result = <MailMailbox>[];
    final seenIds = <String>{};
    if (_gmail) {
      final data = await _json(operation, 'GET', _gmailUri(['labels']));
      for (final value in _array(data['labels'])) {
        final label = _object(value);
        final id = _text(label['id']);
        if (!seenIds.add(id)) _fail(MailProblemCode.providerFailure);
        result.add(
          MailMailbox(
            id: MailMailboxId(id, account: account),
            displayName: _text(label['name']),
            isLabel: true,
          ),
        );
        if (result.length > limits.maxMailboxes) {
          _fail(MailProblemCode.quotaExceeded);
        }
      }
    } else {
      final parents = <String?>[null];
      for (var index = 0; index < parents.length; index++) {
        final parent = parents[index];
        final route = parent == null
            ? ['mailFolders']
            : ['mailFolders', parent, 'childFolders'];
        Uri? uri = _graphUri(route, {
          r'$top': '${limits.maxPageSize}',
          r'$select': 'id,displayName,childFolderCount',
        });
        final visited = <String>{};
        while (uri != null) {
          if (!visited.add(uri.toString())) {
            _fail(MailProblemCode.providerFailure);
          }
          final data = await _json(operation, 'GET', uri);
          for (final value in _array(data['value'])) {
            final folder = _object(value);
            final id = _text(folder['id']);
            if (!seenIds.add(id)) _fail(MailProblemCode.providerFailure);
            result.add(
              MailMailbox(
                id: MailMailboxId(id, account: account),
                displayName: _text(folder['displayName']),
              ),
            );
            if (result.length > limits.maxMailboxes) {
              _fail(MailProblemCode.quotaExceeded);
            }
            final count = folder['childFolderCount'];
            if (count is! int || count < 0) {
              _fail(MailProblemCode.providerFailure);
            }
            if (count > 0) parents.add(id);
          }
          uri = data['@odata.nextLink'] == null
              ? null
              : _graphContinuation(
                  _text(data['@odata.nextLink'], max: limits.maxCursorBytes),
                  route,
                  operation,
                );
        }
      }
    }
    operation.itemCount = result.length;
    return result;
  });

  static const _graphSelect =
      'id,subject,from,toRecipients,ccRecipients,'
      'bccRecipients,replyTo,sentDateTime,internetMessageId,isRead,isDraft,flag,parentFolderId';

  /// Continuations may use slash or OData parenthesized folder syntax. Only
  /// the same mailbox collection may be followed, never arbitrary Graph URLs.
  Uri _graphContinuation(
    String value,
    List<String> route,
    _Operation operation,
  ) {
    if (value.length > limits.maxCursorBytes) {
      _fail(MailProblemCode.invalidInput);
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'graph.microsoft.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      _fail(MailProblemCode.invalidInput);
    }
    final parts = uri.pathSegments;
    final normalized = <String>[];
    for (final part in parts) {
      final match = RegExp(
        r"^mailfolders\('((?:[^']|'')*)'\)$",
        caseSensitive: false,
      ).firstMatch(part);
      if (match == null) {
        normalized.add(part);
      } else {
        normalized.addAll(['mailFolders', match[1]!.replaceAll("''", "'")]);
      }
    }
    if (normalized.length >= 3 && normalized[1].toLowerCase() == 'users') {
      if (normalized[2] != _text(operation.profile['id'])) {
        _fail(MailProblemCode.invalidInput);
      }
      normalized.replaceRange(1, 3, ['me']);
    } else if (normalized.length >= 2) {
      final user = RegExp(
        r"^users\('((?:[^']|'')*)'\)$",
        caseSensitive: false,
      ).firstMatch(normalized[1]);
      if (user != null) {
        if (user[1]!.replaceAll("''", "'") != _text(operation.profile['id'])) {
          _fail(MailProblemCode.invalidInput);
        }
        normalized[1] = 'me';
      }
    }
    final expected = ['v1.0', 'me', ...route];
    if (normalized.length != expected.length) {
      _fail(MailProblemCode.invalidInput);
    }
    for (var i = 0; i < expected.length; i++) {
      // Folder identifiers remain case-sensitive; static path names do not.
      final isFolderId =
          i > 0 &&
          expected[i - 1] == 'mailFolders' &&
          expected[i] != 'childFolders';
      if (isFolderId
          ? normalized[i] != expected[i]
          : normalized[i].toLowerCase() != expected[i].toLowerCase()) {
        _fail(MailProblemCode.invalidInput);
      }
    }
    return uri;
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    if (!_mailboxValid(mailbox) || limit < 1 || limit > limits.maxPageSize) {
      return _failure(MailProblemCode.invalidInput);
    }
    CloudCursor? state;
    try {
      state = CloudCursor.decode(
        cursor,
        configuration,
        mailbox,
        limits,
        'headers',
      );
      if (state != null) state.string('next');
    } on Object {
      return _failure(MailProblemCode.invalidInput);
    }
    return _run(lease, MailCloudOperation.fetchHeaders, (operation) async {
      final records = <MailHeaderRecord>[];
      String? next;
      if (_gmail) {
        final data = await _json(
          operation,
          'GET',
          _gmailUri(
            ['messages'],
            {
              'labelIds': mailbox.value,
              'maxResults': '${math.min(limit, 500)}',
              'includeSpamTrash': 'true',
              if (state != null) 'pageToken': state.string('next'),
            },
          ),
        );
        final ids = _gmailListIds(data, limit);
        for (final id in ids) {
          final item = await _gmailMetadata(operation, id, allowMissing: true);
          if (item != null && _labels(item).contains(mailbox.value)) {
            records.add(_gmailRecord(item));
          }
        }
        if (data['nextPageToken'] != null) {
          next = _text(data['nextPageToken'], max: limits.maxCursorBytes);
        }
      } else {
        final route = ['mailFolders', mailbox.value, 'messages'];
        final uri = state == null
            ? _graphUri(route, {
                r'$select': _graphSelect,
                r'$top': '$limit',
                r'$orderby': 'receivedDateTime desc',
              })
            : _graphContinuation(state.string('next'), route, operation);
        final data = await _json(operation, 'GET', uri);
        final values = _array(data['value']);
        if (values.length > limit) _fail(MailProblemCode.quotaExceeded);
        final seen = <String>{};
        for (final value in values) {
          final item = _object(value);
          final id = _text(item['id']);
          if (!seen.add(id)) _fail(MailProblemCode.providerFailure);
          if (item['parentFolderId'] != null &&
              item['parentFolderId'] != mailbox.value) {
            _fail(MailProblemCode.providerFailure);
          }
          records.add(_graphRecord(item));
        }
        if (data['@odata.nextLink'] != null) {
          next = _text(data['@odata.nextLink'], max: limits.maxCursorBytes);
          _graphContinuation(next, route, operation);
        }
      }
      if (next != null && state != null && next == state.string('next')) {
        _fail(MailProblemCode.providerFailure);
      }
      operation.itemCount = records.length;
      return MailHeaderPage(
        messages: records,
        next: next == null
            ? null
            : CloudCursor(
                {'next': next},
                revision: state?.revision ?? 0,
              ).encode(configuration, mailbox, limits, 'headers'),
      );
    });
  }

  List<String> _gmailListIds(_Json data, int limit) {
    final values = data['messages'] == null
        ? <Object?>[]
        : _array(data['messages']);
    if (values.length > limit) _fail(MailProblemCode.quotaExceeded);
    final ids = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final id = _text(_object(value)['id']);
      if (!seen.add(id)) _fail(MailProblemCode.providerFailure);
      ids.add(id);
    }
    return ids;
  }

  Future<_Json?> _gmailMetadata(
    _Operation operation,
    String id, {
    bool allowMissing = false,
  }) async {
    try {
      final data = await _json(
        operation,
        'GET',
        _gmailUri(
          ['messages', id],
          {
            'format': 'metadata',
            'metadataHeaders': const [
              'Subject',
              'From',
              'To',
              'Cc',
              'Bcc',
              'Reply-To',
              'Date',
              'Message-ID',
              'In-Reply-To',
              'References',
            ],
          },
        ),
      );
      if (_text(data['id']) != id) _fail(MailProblemCode.providerFailure);
      return data;
    } on _ResponseFailure catch (error) {
      if (allowMissing && error.status == 404) return null;
      rethrow;
    }
  }

  Set<String> _labels(_Json data) => data['labelIds'] == null
      ? <String>{}
      : _array(data['labelIds']).map((value) => _text(value)).toSet();

  Set<String> _archiveLabels(_Json data) {
    // Removing Inbox is confirmed only by an explicit complete label array.
    // Missing labels must never be interpreted as an empty successful result.
    final values = _array(data['labelIds']);
    if (values.length > limits.maxMailboxes) {
      _fail(MailProblemCode.quotaExceeded);
    }
    final labels = <String>{};
    for (final value in values) {
      if (!labels.add(_text(value))) _fail(MailProblemCode.providerFailure);
    }
    return labels;
  }

  String _headerValue(Object? value) {
    if (value is! String || value.length > limits.maxHeaderBytes) {
      _fail(MailProblemCode.providerFailure);
    }
    // RFC folding is whitespace, not another header. Bare newlines remain
    // invalid so an API value cannot inject an independent envelope field.
    return _text(
      value.replaceAll(RegExp(r'\r\n[ \t]+'), ' ').replaceAll('\t', ' '),
      empty: true,
      max: limits.maxHeaderBytes,
    );
  }

  MailHeaderRecord _gmailRecord(_Json data) {
    final id = _text(data['id']);
    final labels = _labels(data);
    final headers = _array(_object(data['payload'])['headers']);
    final text = StringBuffer();
    for (final value in headers) {
      final header = _object(value);
      final name = _text(header['name'], max: 256);
      if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(name)) {
        _fail(MailProblemCode.providerFailure);
      }
      text.write('$name: ${_headerValue(header['value'])}\r\n');
      if (text.length > limits.maxHeaderBytes) {
        _fail(MailProblemCode.quotaExceeded);
      }
    }
    text.write('\r\n');
    final bytes = Uint8List.fromList(utf8.encode(text.toString()));
    if (bytes.length > limits.maxHeaderBytes) {
      _fail(MailProblemCode.quotaExceeded);
    }
    final message = _complete(
      codec.parse(
        bytes,
        budget: MailReadBudget(
          maxRawBytes: limits.maxHeaderBytes,
          maxHeaderBytes: limits.maxHeaderBytes,
        ),
      ),
    );
    final identity = _identity(id);
    return MailHeaderRecord(
      id: cloudMessageId(identity),
      remote: identity,
      envelope: message.envelope,
      flags: MailMessageFlags(
        isRead: !labels.contains('UNREAD'),
        isFlagged: labels.contains('STARRED'),
        isDraft: labels.contains('DRAFT'),
        isDeleted: labels.contains('TRASH'),
      ),
    );
  }

  List<MailAddress> _addresses(Object? value) {
    if (value == null) return const [];
    final values = _array(value);
    if (values.length > 1000) _fail(MailProblemCode.quotaExceeded);
    return [for (final item in values) _address(_object(item))];
  }

  MailAddress _address(_Json value) {
    final email = _object(value['emailAddress']);
    return MailAddress(
      _text(email['address'], max: 320),
      displayName: email['name'] == null
          ? null
          : _text(email['name'], empty: true),
    );
  }

  MailHeaderRecord _graphRecord(_Json data) {
    if (utf8.encode(jsonEncode(data)).length > limits.maxHeaderBytes) {
      _fail(MailProblemCode.quotaExceeded);
    }
    final identity = _identity(_text(data['id']));
    if (data['isRead'] is! bool || data['isDraft'] is! bool) {
      _fail(MailProblemCode.providerFailure);
    }
    DateTime? sentAt;
    if (data['sentDateTime'] != null) {
      sentAt = DateTime.tryParse(_text(data['sentDateTime']));
      if (sentAt == null) _fail(MailProblemCode.providerFailure);
    }
    final flag = data['flag'] == null
        ? null
        : _object(data['flag'])['flagStatus'];
    if (flag != null &&
        !const ['flagged', 'notFlagged', 'complete'].contains(flag)) {
      _fail(MailProblemCode.providerFailure);
    }
    return MailHeaderRecord(
      id: cloudMessageId(identity),
      remote: identity,
      envelope: MailEnvelope(
        subject: data['subject'] == null
            ? ''
            : _text(data['subject'], empty: true, max: limits.maxHeaderBytes),
        from: data['from'] == null
            ? const []
            : [_address(_object(data['from']))],
        to: _addresses(data['toRecipients']),
        cc: _addresses(data['ccRecipients']),
        bcc: _addresses(data['bccRecipients']),
        replyTo: _addresses(data['replyTo']),
        sentAt: sentAt,
        messageId: data['internetMessageId'] == null
            ? null
            : _text(data['internetMessageId']),
      ),
      flags: MailMessageFlags(
        isRead: data['isRead'] as bool,
        isDraft: data['isDraft'] as bool,
        isFlagged: flag == 'flagged',
      ),
    );
  }

  MailMessage _complete(MailParseResult parsed) {
    if (parsed.status == MailParseStatus.complete && parsed.message != null) {
      return parsed.message!;
    }
    _fail(switch (parsed.status) {
      MailParseStatus.rejected => MailProblemCode.quotaExceeded,
      MailParseStatus.unsupported => MailProblemCode.unsupported,
      MailParseStatus.cancelled => MailProblemCode.cancelled,
      _ => MailProblemCode.providerFailure,
    });
  }

  @override
  Future<MailResult<MailFlagObservation>> observeFlags(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    if (!_identityValid(identity)) {
      return _failure(MailProblemCode.invalidInput);
    }
    final remote = identity as MailOpaqueIdentity;
    return _run(lease, MailCloudOperation.observeFlags, (operation) async {
      final _Json data;
      try {
        data = await _json(
          operation,
          'GET',
          _gmail
              ? _gmailUri(
                  ['messages', remote.value],
                  {'format': 'minimal', 'fields': 'id,labelIds'},
                )
              : _graphUri(
                  ['messages', remote.value],
                  {r'$select': 'id,isRead,isDraft,flag'},
                ),
          responseLimit: limits.maxHeaderBytes,
        );
      } on _ResponseFailure catch (error) {
        // This catch covers only the exact message GET, after account/profile
        // verification. Other errors, including 410, do not establish absence.
        if (error.status == 404) {
          return MailFlagObservation.missing(identity: identity);
        }
        rethrow;
      }
      if (_text(data['id']) != remote.value) {
        _fail(MailProblemCode.providerFailure);
      }
      final MailMessageFlags flags;
      if (_gmail) {
        // An explicit empty label list is valid. An omitted or malformed list
        // cannot certify that an uncertain read/flag command currently matches.
        final labels = _array(data['labelIds'])
            .map((value) => _text(value))
            .toSet();
        flags = MailMessageFlags(
          isRead: !labels.contains('UNREAD'),
          isFlagged: labels.contains('STARRED'),
          isDraft: labels.contains('DRAFT'),
          isDeleted: labels.contains('TRASH'),
        );
      } else {
        if (data['isRead'] is! bool || data['isDraft'] is! bool) {
          _fail(MailProblemCode.providerFailure);
        }
        final flag = _object(data['flag'])['flagStatus'];
        if (!const ['flagged', 'notFlagged', 'complete'].contains(flag)) {
          _fail(MailProblemCode.providerFailure);
        }
        flags = MailMessageFlags(
          isRead: data['isRead'] as bool,
          isDraft: data['isDraft'] as bool,
          isFlagged: flag == 'flagged',
        );
      }
      return MailFlagObservation.present(identity: identity, flags: flags);
    });
  }

  @override
  Future<MailResult<MailMembershipObservation>> observeMembership(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    if (!_identityValid(identity)) {
      return _failure(MailProblemCode.invalidInput);
    }
    final remote = identity as MailOpaqueIdentity;
    return _run(lease, MailCloudOperation.observeMembership, (operation) async {
      final _Json data;
      try {
        data = await _json(
          operation,
          'GET',
          _gmail
              ? _gmailUri(
                  ['messages', remote.value],
                  {'format': 'minimal', 'fields': 'id,labelIds'},
                )
              : _graphUri(
                  ['messages', remote.value],
                  {r'$select': 'id,parentFolderId'},
                ),
          responseLimit: limits.maxHeaderBytes,
        );
      } on _ResponseFailure catch (error) {
        // Only the exact message GET, after account verification, can certify
        // that this identity is currently unavailable. Graph also uses 404
        // for mailbox-level failures; an unknown/malformed error cannot supply
        // item-level evidence. Neither result establishes historical success.
        final itemUnavailable = _gmail
            ? error.code == 'notFound'
            : const {'ErrorItemNotFound', 'itemNotFound'}.contains(error.code);
        if (error.status == 404 && itemUnavailable) {
          return MailMembershipObservation.missing(identity: identity);
        }
        rethrow;
      }
      if (_text(data['id']) != remote.value) {
        _fail(MailProblemCode.providerFailure);
      }
      if (_gmail) {
        final labels = _array(data['labelIds'])
            .map((value) => _text(value))
            .toList();
        if (labels.length >
            math.min(
              limits.maxMailboxes,
              MailMembershipObservation.maxMailboxes,
            )) {
          _fail(MailProblemCode.quotaExceeded);
        }
        if (labels.toSet().length != labels.length) {
          _fail(MailProblemCode.providerFailure);
        }
        return MailMembershipObservation.folders(
          identity: remote,
          mailboxes: [
            for (final label in labels) MailMailboxId(label, account: account),
          ],
          deletionMailbox: MailMailboxId('TRASH', account: account),
        );
      }
      final parent = _text(data['parentFolderId']);
      // The transport includes Prefer: IdType="ImmutableId" on every Graph
      // request. Resolve the actual Deleted Items ID; its well-known alias is
      // not comparable with an opaque parentFolderId.
      final deletedItems = await _json(
        operation,
        'GET',
        _graphUri(['mailFolders', 'deleteditems'], {r'$select': 'id'}),
        responseLimit: limits.maxHeaderBytes,
      );
      return MailMembershipObservation.folders(
        identity: remote,
        mailboxes: [MailMailboxId(parent, account: account)],
        deletionMailbox: MailMailboxId(
          _text(deletedItems['id']),
          account: account,
        ),
      );
    });
  }

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    if (!_identityValid(identity)) {
      return _failure(MailProblemCode.invalidInput);
    }
    try {
      budget.validate();
    } on Object {
      return _failure(MailProblemCode.invalidInput);
    }
    final remote = identity as MailOpaqueIdentity;
    return _run(lease, MailCloudOperation.fetchMessage, (operation) async {
      Uint8List bytes;
      if (_gmail) {
        final data = await _json(
          operation,
          'GET',
          _gmailUri(['messages', remote.value], {'format': 'raw'}),
        );
        if (_text(data['id']) != remote.value) {
          _fail(MailProblemCode.providerFailure);
        }
        final raw = data['raw'];
        if (raw is! String ||
            raw.length > ((budget.maxRawBytes + 2) ~/ 3) * 4) {
          _fail(MailProblemCode.quotaExceeded);
        }
        bytes = base64Url.decode(raw);
      } else {
        final response = await _request(
          operation,
          'GET',
          _graphUri(['messages', remote.value, r'$value']),
          responseLimit: math.min(budget.maxRawBytes, limits.maxResponseBytes),
        );
        bytes = Uint8List.fromList(response.body);
      }
      if (bytes.length > budget.maxRawBytes) {
        _fail(MailProblemCode.quotaExceeded);
      }
      operation.check();
      final message = _complete(
        codec.parse(bytes, budget: budget, cancellation: lease.cancellation),
      );
      operation.check();
      return MailMessage(
        raw: message.raw,
        envelope: message.envelope,
        body: message.body,
        attachments: message.attachments,
        localId: cloudMessageId(remote),
        remoteIdentity: remote,
      );
    });
  }

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    if (!_mailboxValid(mailbox) || limit < 1 || limit > limits.maxPageSize) {
      return _failure(MailProblemCode.invalidInput);
    }
    CloudCursor? state;
    try {
      state = CloudCursor.decode(
        cursor,
        configuration,
        mailbox,
        limits,
        'sync',
      );
      if (state != null) {
        final phase = state.string('phase');
        if (!_gmail && phase != 'delta' ||
            _gmail &&
                !const ['snapshot', 'history', 'pending'].contains(phase)) {
          return _failure(MailProblemCode.invalidInput);
        }
      }
    } on Object {
      return _failure(MailProblemCode.invalidInput);
    }
    return _run(
      lease,
      MailCloudOperation.pullChanges,
      (operation) => _gmail
          ? _gmailChanges(operation, mailbox, state, limit)
          : _graphChanges(operation, mailbox, state, limit),
    );
  }

  Future<MailSyncPage> _graphChanges(
    _Operation operation,
    MailMailboxId mailbox,
    CloudCursor? state,
    int limit,
  ) async {
    final route = ['mailFolders', mailbox.value, 'messages', 'delta'];
    final initial = _graphUri(route, {
      r'$select': _graphSelect,
      r'$top': '$limit',
    });
    var reset = state == null;
    final uri = state == null
        ? initial
        : _graphContinuation(state.string('next'), route, operation);
    _Json data;
    try {
      data = await _json(operation, 'GET', uri, pageSize: limit);
    } on _ResponseFailure catch (error) {
      if (state == null ||
          error.status != 410 ||
          !const {
            'SyncStateNotFound',
            'syncStateNotFound',
            'resyncRequired',
            'InvalidDeltaToken',
          }.contains(error.code)) {
        rethrow;
      }
      reset = true;
      data = await _json(operation, 'GET', initial, pageSize: limit);
    }
    final values = _array(data['value']);
    if (values.length > limit) _fail(MailProblemCode.quotaExceeded);
    final latest = <String, _Json>{};
    for (final value in values) {
      final item = _object(value);
      latest[_text(item['id'])] = item;
    }
    final upserts = <MailHeaderRecord>[];
    final tombstones = <MailRemoteIdentity>[];
    for (final entry in latest.entries) {
      var item = entry.value;
      if (item['@removed'] != null) {
        _object(item['@removed']);
        tombstones.add(_identity(entry.key));
      } else {
        if (item['isRead'] is! bool ||
            item['isDraft'] is! bool ||
            !const [
              'subject',
              'from',
              'toRecipients',
              'ccRecipients',
              'bccRecipients',
              'replyTo',
              'sentDateTime',
              'internetMessageId',
              'flag',
              'parentFolderId',
            ].every(item.containsKey)) {
          try {
            item = await _json(
              operation,
              'GET',
              _graphUri(['messages', entry.key], {r'$select': _graphSelect}),
            );
          } on _ResponseFailure catch (error) {
            if (error.status != 404) rethrow;
            tombstones.add(_identity(entry.key));
            continue;
          }
        }
        if (_text(item['id']) != entry.key) {
          _fail(MailProblemCode.providerFailure);
        }
        if (item['parentFolderId'] != null &&
            item['parentFolderId'] != mailbox.value) {
          tombstones.add(_identity(entry.key));
        } else {
          upserts.add(_graphRecord(item));
        }
      }
    }
    final more = data['@odata.nextLink'] != null;
    if (more && data['@odata.deltaLink'] != null) {
      _fail(MailProblemCode.providerFailure);
    }
    final next = _text(
      more ? data['@odata.nextLink'] : data['@odata.deltaLink'],
      max: limits.maxCursorBytes,
    );
    _graphContinuation(next, route, operation);
    if (more && state != null && next == state.string('next')) {
      _fail(MailProblemCode.providerFailure);
    }
    return MailSyncPage(
      mailbox: mailbox,
      upserts: upserts,
      tombstones: tombstones,
      next: CloudCursor(
        {'phase': 'delta', 'next': next},
        revision: state?.revision ?? 0,
      ).encode(configuration, mailbox, limits, 'sync'),
      hasMore: more,
      resetRequired: reset,
    );
  }

  Future<MailSyncPage> _gmailChanges(
    _Operation operation,
    MailMailboxId mailbox,
    CloudCursor? state,
    int limit,
  ) async {
    final phase = state?.string('phase') ?? 'snapshot';
    if (phase == 'snapshot') {
      return _gmailSnapshot(operation, mailbox, state, limit);
    }
    final start = state!.string('start');
    List<String> ids;
    String nextPage;
    String end;
    if (phase == 'pending') {
      ids = state.strings('pending');
      nextPage = state.string('nextPage', empty: true);
      end = state.string('end');
    } else {
      _Json data;
      try {
        data = await _json(
          operation,
          'GET',
          _gmailUri(
            ['history'],
            {
              'startHistoryId': start,
              'maxResults': '${math.min(limit, 500)}',
              if (state.string('nextPage', empty: true).isNotEmpty)
                'pageToken': state.string('nextPage'),
            },
          ),
        );
      } on _ResponseFailure catch (error) {
        if (error.status != 404) rethrow;
        return _gmailSnapshot(
          operation,
          mailbox,
          null,
          limit,
          revision: state.revision,
        );
      }
      end = _text(data['historyId']);
      nextPage = data['nextPageToken'] == null
          ? ''
          : _text(data['nextPageToken'], max: limits.maxCursorBytes);
      if (nextPage.isNotEmpty &&
          nextPage == state.string('nextPage', empty: true)) {
        _fail(MailProblemCode.providerFailure);
      }
      final changed = <String>{};
      final history = data['history'] == null
          ? <Object?>[]
          : _array(data['history']);
      if (history.length > math.min(limit, 500)) {
        _fail(MailProblemCode.quotaExceeded);
      }
      for (final value in history) {
        final entry = _object(value);
        for (final key in [
          'messages',
          'messagesAdded',
          'messagesDeleted',
          'labelsAdded',
          'labelsRemoved',
        ]) {
          if (entry[key] == null) continue;
          for (final change in _array(entry[key])) {
            final message = key == 'messages'
                ? _object(change)
                : _object(_object(change)['message']);
            changed.add(_text(message['id']));
            if (changed.length > limits.maxCursorBytes ~/ 3) {
              _fail(MailProblemCode.quotaExceeded);
            }
          }
        }
      }
      ids = changed.toList();
    }
    final take = math.min(limit, ids.length);
    final pending = ids.skip(take).toList();
    final nextData = pending.isNotEmpty
        ? <String, Object?>{
            'phase': 'pending',
            'start': start,
            'pending': pending,
            'nextPage': nextPage,
            'end': end,
          }
        : <String, Object?>{
            'phase': 'history',
            'start': nextPage.isEmpty ? end : start,
            'nextPage': nextPage,
          };
    // Reject an unrepresentable page before making all of its detail requests.
    final next = CloudCursor(
      nextData,
      revision: state.revision,
    ).encode(configuration, mailbox, limits, 'sync');
    final upserts = <MailHeaderRecord>[];
    final tombstones = <MailRemoteIdentity>[];
    for (final id in ids.take(take)) {
      final item = await _gmailMetadata(operation, id, allowMissing: true);
      if (item == null || !_labels(item).contains(mailbox.value)) {
        tombstones.add(_identity(id));
      } else {
        upserts.add(_gmailRecord(item));
      }
    }
    return MailSyncPage(
      mailbox: mailbox,
      upserts: upserts,
      tombstones: tombstones,
      next: next,
      hasMore: pending.isNotEmpty || nextPage.isNotEmpty,
    );
  }

  Future<MailSyncPage> _gmailSnapshot(
    _Operation operation,
    MailMailboxId mailbox,
    CloudCursor? state,
    int limit, {
    int revision = 0,
  }) async {
    final start =
        state?.string('start') ?? _text(operation.profile['historyId']);
    final data = await _json(
      operation,
      'GET',
      _gmailUri(
        ['messages'],
        {
          'labelIds': mailbox.value,
          'includeSpamTrash': 'true',
          'maxResults': '${math.min(limit, 500)}',
          if (state != null) 'pageToken': state.string('nextPage'),
        },
      ),
    );
    final ids = _gmailListIds(data, limit);
    final nextPage = data['nextPageToken'] == null
        ? null
        : _text(data['nextPageToken'], max: limits.maxCursorBytes);
    if (nextPage != null &&
        state != null &&
        nextPage == state.string('nextPage')) {
      _fail(MailProblemCode.providerFailure);
    }
    final upserts = <MailHeaderRecord>[];
    for (final id in ids) {
      final item = await _gmailMetadata(operation, id, allowMissing: true);
      if (item != null && _labels(item).contains(mailbox.value)) {
        upserts.add(_gmailRecord(item));
      }
    }
    return MailSyncPage(
      mailbox: mailbox,
      upserts: upserts,
      tombstones: const [],
      next: CloudCursor(
        {
          'phase': nextPage == null ? 'history' : 'snapshot',
          'start': start,
          'nextPage': nextPage ?? '',
        },
        revision: state?.revision ?? revision,
      ).encode(configuration, mailbox, limits, 'sync'),
      // Close the snapshot race by catching up from the pre-list history ID.
      hasMore: true,
      resetRequired: state == null,
    );
  }

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation command,
    MailOperationLease lease,
  ) async {
    if (!_identityValid(command.message) ||
        !_validId(command.id) ||
        command is MailMove && !_mailboxValid(command.destination)) {
      return _failure(MailProblemCode.invalidInput);
    }
    if (_gmail && command is MailMove) {
      return _failure(MailProblemCode.unsupported);
    }
    if (!_gmail && command is MailArchive) {
      return _failure(MailProblemCode.unsupported);
    }
    final remote = command.message as MailOpaqueIdentity;
    return _run(lease, MailCloudOperation.apply, (operation) async {
      if (_gmail) {
        final _Json data;
        if (command is MailDelete) {
          data = await _json(
            operation,
            'POST',
            _gmailUri(['messages', remote.value, 'trash']),
            mutation: true,
          );
        } else {
          final (label, add) = switch (command) {
            MailSetRead(:final read) => ('UNREAD', !read),
            MailSetFlagged(:final flagged) => ('STARRED', flagged),
            MailArchive() => ('INBOX', false),
            _ => throw const MailCloudException(
              MailProblem(MailProblemCode.unsupported),
            ),
          };
          data = await _json(
            operation,
            'POST',
            _gmailUri(['messages', remote.value, 'modify']),
            body: {
              add ? 'addLabelIds' : 'removeLabelIds': [label],
            },
            mutation: true,
          );
        }
        if (_text(data['id']) != remote.value) _fail(MailProblemCode.conflict);
        final labels = command is MailArchive
            ? _archiveLabels(data)
            : _labels(data);
        final confirmed = switch (command) {
          MailSetRead(:final read) => labels.contains('UNREAD') == !read,
          MailSetFlagged(:final flagged) =>
            labels.contains('STARRED') == flagged,
          MailDelete() => labels.contains('TRASH'),
          MailArchive() => !labels.contains('INBOX'),
          _ => false,
        };
        if (!confirmed) _fail(MailProblemCode.conflict);
      } else {
        final _Json data;
        String? destination;
        if (command is MailMove || command is MailDelete) {
          destination = command is MailMove
              ? command.destination.value
              : 'deleteditems';
          if (command is MailDelete) {
            final folder = await _json(
              operation,
              'GET',
              _graphUri(['mailFolders', 'deleteditems'], {r'$select': 'id'}),
            );
            destination = _text(folder['id']);
          }
          data = await _json(
            operation,
            'POST',
            _graphUri(['messages', remote.value, 'move']),
            body: {'destinationId': destination},
            mutation: true,
          );
        } else {
          final body = switch (command) {
            MailSetRead(:final read) => <String, Object?>{'isRead': read},
            MailSetFlagged(:final flagged) => <String, Object?>{
              'flag': {'flagStatus': flagged ? 'flagged' : 'notFlagged'},
            },
            _ => throw const MailCloudException(
              MailProblem(MailProblemCode.unsupported),
            ),
          };
          data = await _json(
            operation,
            'PATCH',
            _graphUri(['messages', remote.value]),
            body: body,
            mutation: true,
          );
        }
        if (_text(data['id']) != remote.value) _fail(MailProblemCode.conflict);
        final confirmed = switch (command) {
          MailSetRead(:final read) => data['isRead'] == read,
          MailSetFlagged(:final flagged) =>
            _object(data['flag'])['flagStatus'] ==
                (flagged ? 'flagged' : 'notFlagged'),
          MailMove() || MailDelete() => data['parentFolderId'] == destination,
          MailArchive() => false,
        };
        if (!confirmed) _fail(MailProblemCode.conflict);
      }
      return MailUnit.value;
    });
  }

  @override
  Future<MailSubmissionResult> submit(
    MailPreparedMessage message, {
    required String attemptId,
    required MailOperationLease lease,
  }) async {
    if (attemptId.isEmpty) {
      throw ArgumentError('Submission requires a persisted attempt identity.');
    }
    final result = await _submit(message, attemptId, lease);
    if (result is MailSuccess<MailUnit>) {
      return MailSubmissionResult(
        attemptId: attemptId,
        outcome: MailSubmissionOutcome.accepted,
      );
    }
    final problem = (result as MailFailure<MailUnit>).problem;
    return MailSubmissionResult(
      attemptId: attemptId,
      problem: problem,
      outcome: switch (problem.code) {
        MailProblemCode.conflict => MailSubmissionOutcome.uncertain,
        MailProblemCode.unavailable ||
        MailProblemCode.providerFailure ||
        MailProblemCode.cancelled ||
        MailProblemCode.staleOperation ||
        MailProblemCode.quotaExceeded => MailSubmissionOutcome.retryableFailure,
        _ => MailSubmissionOutcome.rejected,
      },
    );
  }

  Future<MailResult<MailUnit>> _submit(
    MailPreparedMessage message,
    String attemptId,
    MailOperationLease lease,
  ) async {
    if (message.account != account ||
        lease.account != account ||
        !_validId(attemptId) ||
        !validCloudMailAddress(message.envelope.sender) ||
        message.envelope.sender.toLowerCase() !=
            configuration.mailboxAddress.toLowerCase() ||
        message.envelope.recipients.length > 500 ||
        message.envelope.recipients.any(
          (value) => !validCloudMailAddress(value),
        )) {
      return _failure(MailProblemCode.invalidInput);
    }
    if (message.wire.length >
            const MailReadBudget(maxRawBytes: 48 * 1024 * 1024).maxRawBytes ||
        ((message.wire.length + 2) ~/ 3) * 4 > limits.maxRequestBytes) {
      return _failure(MailProblemCode.quotaExceeded);
    }
    Uint8List wire;
    try {
      lease.checkCurrent();
      _validateSubmissionHeaders(message.wire.bytes);
      final headers = _complete(
        codec.parse(message.wire.bytes, cancellation: lease.cancellation),
      ).envelope;
      if (headers.from.length != 1 ||
          headers.from.single.address != message.envelope.sender ||
          headers.bcc.isNotEmpty) {
        _fail(MailProblemCode.invalidInput);
      }
      final intended = message.envelope.recipients.toSet();
      final visible = <String>{};
      for (final address in [...headers.to, ...headers.cc]) {
        if (!validCloudMailAddress(address.address) ||
            !intended.contains(address.address) ||
            !visible.add(address.address)) {
          _fail(MailProblemCode.invalidInput);
        }
      }
      final hidden = message.envelope.recipients
          .where((address) => !visible.contains(address))
          .toList();
      // API delivery derives its envelope from MIME headers, unlike SMTP DATA.
      // Add only validated hidden recipients; the immutable prepared copy stays
      // unchanged and the service removes Bcc for the recipient-facing copy.
      final prefix = hidden.isEmpty
          ? const <int>[]
          : utf8.encode('Bcc: ${hidden.join(',\r\n ')}\r\n');
      wire = Uint8List.fromList([...prefix, ...message.wire.bytes]);
      if (((wire.length + 2) ~/ 3) * 4 + 32 > limits.maxRequestBytes) {
        _fail(MailProblemCode.quotaExceeded);
      }
      lease.checkCurrent();
    } on MailCloudException catch (error) {
      return MailFailure(error.problem);
    } on MailCancelled {
      return _failure(MailProblemCode.cancelled);
    } on Object {
      return _failure(MailProblemCode.invalidInput);
    }
    return _run(lease, MailCloudOperation.submit, (operation) async {
      if (_gmail) {
        final data = await _json(
          operation,
          'POST',
          _gmailUri(['messages', 'send']),
          body: {'raw': base64Url.encode(wire)},
          mutation: true,
        );
        _text(data['id']);
      } else {
        final response = await _request(
          operation,
          'POST',
          _graphUri(['sendMail']),
          body: ascii.encode(base64.encode(wire)),
          contentType: 'text/plain',
          mutation: true,
        );
        if (response.statusCode != 202 || response.body.isNotEmpty) {
          _fail(MailProblemCode.conflict);
        }
      }
      operation.check();
      return MailUnit.value;
    });
  }

  void _validateSubmissionHeaders(Uint8List bytes) {
    var end = -1;
    for (var i = 0; i + 1 < bytes.length && i < limits.maxHeaderBytes; i++) {
      if (bytes[i] == 10 && bytes[i + 1] == 10) {
        end = i;
        break;
      }
      if (i + 3 < bytes.length &&
          bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        end = i;
        break;
      }
    }
    if (end < 0) _fail(MailProblemCode.invalidInput);
    final seen = <String>{};
    for (final line
        in latin1
            .decode(Uint8List.sublistView(bytes, 0, end))
            .split(RegExp(r'\r?\n'))) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (seen.isEmpty) _fail(MailProblemCode.invalidInput);
        continue;
      }
      final colon = line.indexOf(':');
      if (colon < 1) _fail(MailProblemCode.invalidInput);
      final name = line.substring(0, colon).toLowerCase();
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name) ||
          name == 'bcc' ||
          name.startsWith('resent-') ||
          name == 'sender') {
        _fail(MailProblemCode.invalidInput);
      }
      if (!seen.add(name) && const {'from', 'to', 'cc'}.contains(name)) {
        _fail(MailProblemCode.invalidInput);
      }
    }
  }
}
