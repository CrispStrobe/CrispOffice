import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'configuration.dart';
import 'http.dart';

/// One authorization attempt. The random state and verifier are never logged.
final class MailOAuthChallenge {
  MailOAuthChallenge._(this.state, this.verifier);

  factory MailOAuthChallenge.generate() {
    final random = Random.secure();
    String secret() => base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    return MailOAuthChallenge._(secret(), secret());
  }

  final String state;
  final String verifier;
  String get challenge => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  Uri authorizationUri(MailOAuthConfiguration configuration, Uri redirect) =>
      configuration.authorizationEndpoint.replace(
        queryParameters: {
          'client_id': configuration.clientId,
          'response_type': 'code',
          'redirect_uri': redirect.toString(),
          'scope': configuration.scopes.join(' '),
          'state': state,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          if (configuration.service == MailCloudService.gmail) ...{
            'access_type': 'offline',
            'prompt': 'consent',
          } else ...{
            'response_mode': 'query',
            'prompt': 'select_account',
          },
        },
      );

  /// Returns only a valid code. Duplicate parameters and mismatched state are
  /// rejected, even if a malicious callback includes a second valid value.
  MailResult<String> validateCallback(Uri callback, Uri redirect) {
    if (callback.scheme != redirect.scheme ||
        callback.host != redirect.host ||
        callback.port != redirect.port ||
        callback.path != redirect.path ||
        callback.userInfo.isNotEmpty ||
        callback.hasFragment ||
        callback.toString().length > 16 * 1024) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    final Map<String, List<String>> parameters;
    try {
      parameters = callback.queryParametersAll;
    } on FormatException {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    if (parameters.values.any((values) => values.length != 1) ||
        parameters['state']?.single != state ||
        (parameters.containsKey('code') && parameters.containsKey('error'))) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    if (parameters['error']?.single case final error?) {
      return MailFailure(
        MailProblem(
          error == 'access_denied'
              ? MailProblemCode.permissionDenied
              : MailProblemCode.authenticationRequired,
        ),
      );
    }
    final code = parameters['code']?.single;
    if (code == null ||
        code.isEmpty ||
        code.length > 8192 ||
        code.contains(RegExp(r'[\x00-\x20\x7f]'))) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    return MailSuccess(code);
  }

  @override
  String toString() => 'MailOAuthChallenge(redacted)';
}

/// Shared code exchange and token refresh. Native hosts own the lifetime; an
/// embedding host may instead supply a platform-vault MailCloudTokenSource.
final class MailOAuthTokenSession implements MailCloudTokenSource {
  MailOAuthTokenSession._({
    required this.configuration,
    required this.account,
    required this.transport,
    required this.log,
    required this.clock,
  });

  final MailOAuthConfiguration configuration;
  final MailAccountId account;
  final MailCloudHttpTransport transport;
  final MailCloudLogSink? log;
  final DateTime Function() clock;
  MailCloudAccessToken? _token;
  String? _refreshToken;
  Future<MailResult<MailCloudAccessToken>>? _refreshing;
  bool _disposed = false;

  /// Ownership of transport transfers to the returned session on success and
  /// it is closed on failure. No authorization code is ever automatically retried.
  static Future<MailResult<MailCloudTokenSource>> exchange({
    required MailOAuthConfiguration configuration,
    required MailAccountId account,
    required MailCloudHttpTransport transport,
    required MailOAuthChallenge challenge,
    required String code,
    required Uri redirect,
    required MailOperationLease lease,
    MailCloudLogSink? log,
    DateTime Function()? clock,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final session = MailOAuthTokenSession._(
      configuration: configuration,
      account: account,
      transport: transport,
      log: log,
      clock: clock ?? DateTime.now,
    );
    try {
      if (lease.account != account ||
          !lease.isCurrent ||
          redirect.scheme != 'http' ||
          !const {'127.0.0.1', 'localhost'}.contains(redirect.host) ||
          redirect.port < 1 ||
          redirect.hasQuery ||
          redirect.hasFragment ||
          redirect.userInfo.isNotEmpty ||
          code.isEmpty ||
          code.length > 8192 ||
          code.contains(RegExp(r'[\x00-\x20\x7f]')) ||
          timeout <= Duration.zero ||
          timeout > const Duration(seconds: 30)) {
        throw const MailCloudException(
          MailProblem(MailProblemCode.invalidInput),
        );
      }
      await session._requestToken(
        {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirect.toString(),
          'code_verifier': challenge.verifier,
        },
        lease,
        MailCloudOperation.exchangeToken,
        timeout: timeout,
      );
      lease.checkCurrent();
      return MailSuccess(session);
    } on Object catch (error) {
      session.dispose();
      return MailFailure(_problem(error, lease));
    }
  }

  static MailProblem _problem(Object error, MailOperationLease lease) {
    if (error is MailCloudException) return error.problem;
    if (error is MailCancelled || !lease.isCurrent) {
      return MailProblem(
        lease.cancellation?.isCancelled == true
            ? MailProblemCode.cancelled
            : MailProblemCode.staleOperation,
      );
    }
    return const MailProblem(MailProblemCode.providerFailure);
  }

  @override
  Future<MailResult<MailCloudAccessToken>> accessToken(
    MailOperationLease lease, {
    bool forceRefresh = false,
  }) async {
    if (_disposed) {
      return const MailFailure(MailProblem(MailProblemCode.cancelled));
    }
    if (lease.account != account) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    try {
      lease.checkCurrent();
      final token = _token;
      if (!forceRefresh &&
          token != null &&
          token.expiresAt.isAfter(clock().add(const Duration(seconds: 60)))) {
        return MailSuccess(token);
      }
      if (_refreshToken == null) {
        return const MailFailure(
          MailProblem(MailProblemCode.authenticationRequired),
        );
      }
      // Coalescing prevents simultaneous refreshes from racing rotated tokens.
      final pending = _refreshing ??= _refresh(lease);
      final result = await pending;
      if (identical(_refreshing, pending)) _refreshing = null;
      lease.checkCurrent();
      if (_disposed) {
        return const MailFailure(MailProblem(MailProblemCode.cancelled));
      }
      return result;
    } on Object catch (error) {
      return MailFailure(_problem(error, lease));
    }
  }

  Future<MailResult<MailCloudAccessToken>> _refresh(
    MailOperationLease lease,
  ) async {
    try {
      await _requestToken(
        {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken!,
          if (configuration.service == MailCloudService.microsoft365)
            'scope': configuration.scopes.join(' '),
        },
        lease,
        MailCloudOperation.refreshToken,
      );
      return MailSuccess(_token!);
    } on Object catch (error) {
      final problem = _problem(error, lease);
      if (problem.code == MailProblemCode.authenticationRequired ||
          problem.code == MailProblemCode.permissionDenied) {
        _token = null;
        _refreshToken = null;
      }
      return MailFailure(problem);
    }
  }

  Future<void> _requestToken(
    Map<String, String> parameters,
    MailOperationLease lease,
    MailCloudOperation operation, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final watch = Stopwatch()..start();
    void event(MailCloudLogStage stage, {int? status, MailProblem? problem}) {
      emitMailCloudLog(
        log,
        MailCloudLogEvent(
          service: configuration.service,
          operation: operation,
          stage: stage,
          elapsedMilliseconds: watch.elapsedMilliseconds,
          statusCode: status,
          problemCode: problem?.code,
          retryAfterSeconds: problem?.retryAfter?.inSeconds,
        ),
      );
    }

    event(MailCloudLogStage.started);
    try {
      lease.checkCurrent();
      final body = utf8.encode(
        Uri(
          queryParameters: {
            ...parameters,
            'client_id': configuration.clientId,
            if (configuration.clientSecret != null)
              'client_secret': configuration.clientSecret!,
          },
        ).query,
      );
      final response = await transport.send(
        MailCloudHttpRequest(
          method: 'POST',
          uri: configuration.tokenEndpoint,
          headers: const {'content-type': 'application/x-www-form-urlencoded'},
          body: body,
        ),
        lease: lease,
        timeout: timeout,
        maxResponseBytes: 128 * 1024,
      );
      lease.checkCurrent();
      if (_disposed) {
        throw const MailCloudException(MailProblem(MailProblemCode.cancelled));
      }
      event(MailCloudLogStage.response, status: response.statusCode);
      if (response.body.length > 128 * 1024) {
        throw const MailCloudException(
          MailProblem(MailProblemCode.quotaExceeded),
        );
      }
      if (response.statusCode == 429 || response.statusCode >= 500) {
        final delay = int.tryParse(response.headers['retry-after'] ?? '');
        throw MailCloudException(
          MailProblem(
            response.statusCode == 429
                ? MailProblemCode.quotaExceeded
                : MailProblemCode.unavailable,
            retryAfter: Duration(seconds: (delay ?? 5).clamp(1, 86400)),
          ),
        );
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const MailCloudException(
          MailProblem(MailProblemCode.permissionDenied),
        );
      }
      final Object? decoded = jsonDecode(utf8.decode(response.body));
      if (decoded is! Map<String, Object?>) throw const FormatException();
      if (response.statusCode != 200 || decoded.containsKey('error')) {
        final code = decoded['error'];
        throw MailCloudException(
          MailProblem(
            code == 'access_denied' || code == 'consent_required'
                ? MailProblemCode.permissionDenied
                : MailProblemCode.authenticationRequired,
          ),
        );
      }
      final token = decoded['access_token'];
      final type = decoded['token_type'];
      final expires = decoded['expires_in'];
      final refresh = decoded['refresh_token'];
      if (token is! String ||
          type is! String ||
          type.toLowerCase() != 'bearer' ||
          expires is! int ||
          expires < 1 ||
          expires > 31 * 86400 ||
          (refresh != null &&
              (refresh is! String ||
                  refresh.isEmpty ||
                  refresh.length > 64 * 1024 ||
                  refresh.contains(RegExp(r'[\x00-\x20\x7f]'))))) {
        throw const FormatException();
      }
      final scope = decoded['scope'];
      if (scope != null) {
        if (scope is! String || scope.length > 8192) {
          throw const FormatException();
        }
        String normalized(String value) =>
            value.replaceFirst('https://graph.microsoft.com/', '');
        final granted = scope.split(' ').map(normalized).toSet();
        final required = configuration.scopes
            .where((scope) => scope != 'offline_access')
            .map(normalized);
        if (!granted.containsAll(required)) {
          throw const MailCloudException(
            MailProblem(MailProblemCode.permissionDenied),
          );
        }
      }
      final access = MailCloudAccessToken(
        value: token,
        expiresAt: clock().add(Duration(seconds: expires)),
      );
      lease.checkCurrent();
      if (_disposed) {
        throw const MailCloudException(MailProblem(MailProblemCode.cancelled));
      }
      // Commit both fields only after fully validating the response and lease.
      _token = access;
      if (refresh is String) _refreshToken = refresh;
      event(MailCloudLogStage.completed);
    } on Object catch (error) {
      final problem = _problem(error, lease);
      event(MailCloudLogStage.failed, problem: problem);
      throw MailCloudException(problem);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _token = null;
    _refreshToken = null;
    try {
      transport.close();
    } on Object {
      // A host's transport cannot prevent forgetting session credentials.
    }
  }

  @override
  String toString() => 'MailOAuthTokenSession(redacted)';
}
