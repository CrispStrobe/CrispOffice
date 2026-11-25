import 'package:quds_mail_core/quds_mail_core.dart';

/// Public-cloud APIs use OAuth; Exchange Server keeps its independent EWS path.
enum MailCloudService { gmail, microsoft365 }

final class MailCloudConfiguration {
  MailCloudConfiguration({
    required this.account,
    required this.service,
    required this.mailboxAddress,
  }) {
    if (!validCloudMailAddress(mailboxAddress)) {
      throw ArgumentError('A valid mailbox address is required.');
    }
  }

  final MailAccountId account;
  final MailCloudService service;
  final String mailboxAddress;
}

bool validCloudMailAddress(String value) =>
    value.length <= 320 &&
    RegExp(
      r'^[^\s<>(),;:\\"\[\]\x00-\x1f\x7f@]+@[^\s<>(),;:\\"\[\]\x00-\x1f\x7f@]+$',
    ).hasMatch(value);

/// Native public-client registration. No redirect host is supplied by a caller.
/// The Google desktop client secret, if issued, is registration metadata, not a
/// confidential credential. Never ship a web/server application's client secret.
final class MailOAuthConfiguration {
  MailOAuthConfiguration({
    required this.service,
    required this.clientId,
    this.tenant = 'common',
    this.clientSecret,
    this.includeTasks = false,
  }) {
    if (!RegExp(r'^[A-Za-z0-9._-]{1,1024}$').hasMatch(clientId) ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9.-]{0,253}$').hasMatch(tenant) ||
        tenant.contains('..') ||
        (includeTasks && service != MailCloudService.microsoft365) ||
        (clientSecret != null &&
            (service != MailCloudService.gmail ||
                clientSecret!.isEmpty ||
                clientSecret!.length > 4096 ||
                clientSecret!.contains(RegExp(r'[\x00-\x20\x7f]'))))) {
      throw ArgumentError('Invalid native OAuth client registration.');
    }
  }

  final MailCloudService service;
  final String clientId;
  final String tenant;
  final String? clientSecret;

  /// Request delegated To Do access during a new Microsoft authorization.
  /// Existing mail-only sessions do not gain task consent by changing this flag.
  /// Hosts enable it only when the user connects Tasks, then authorize again.
  final bool includeTasks;

  List<String> get scopes => switch (service) {
    MailCloudService.gmail => const [
      'https://www.googleapis.com/auth/gmail.modify',
    ],
    MailCloudService.microsoft365 => List<String>.unmodifiable([
      'https://graph.microsoft.com/Mail.ReadWrite',
      'https://graph.microsoft.com/Mail.Send',
      'https://graph.microsoft.com/User.Read',
      if (includeTasks) 'https://graph.microsoft.com/Tasks.ReadWrite',
      'offline_access',
    ]),
  };

  Uri get authorizationEndpoint => switch (service) {
    MailCloudService.gmail => Uri.https(
      'accounts.google.com',
      '/o/oauth2/v2/auth',
    ),
    MailCloudService.microsoft365 => Uri.https(
      'login.microsoftonline.com',
      '/$tenant/oauth2/v2.0/authorize',
    ),
  };

  Uri get tokenEndpoint => switch (service) {
    MailCloudService.gmail => Uri.https('oauth2.googleapis.com', '/token'),
    MailCloudService.microsoft365 => Uri.https(
      'login.microsoftonline.com',
      '/$tenant/oauth2/v2.0/token',
    ),
  };

  @override
  String toString() => 'MailOAuthConfiguration(${service.name}, redacted)';
}

final class MailCloudAccessToken {
  MailCloudAccessToken({required this.value, required this.expiresAt}) {
    if (value.isEmpty ||
        value.length > 64 * 1024 ||
        value.contains(RegExp(r'[\x00-\x20\x7f]'))) {
      throw ArgumentError('Invalid OAuth access token.');
    }
  }

  final String value;
  final DateTime expiresAt;

  @override
  String toString() => 'MailCloudAccessToken(redacted)';
}

/// Hosts may implement this with their own platform vault. Native interactive
/// authorization returns an in-memory source which forgets tokens on dispose.
abstract interface class MailCloudTokenSource {
  Future<MailResult<MailCloudAccessToken>> accessToken(
    MailOperationLease lease, {
    bool forceRefresh = false,
  });
  void dispose();
}

abstract interface class MailCloudProvider
    implements MailProvider, MailSubmissionProvider {
  void dispose();
}

final class MailCloudLimits {
  const MailCloudLimits({
    this.maxPageSize = 100,
    this.maxMailboxes = 1000,
    this.maxResponseBytes = 48 * 1024 * 1024,
    this.maxRequestBytes = 64 * 1024 * 1024,
    this.maxCursorBytes = 16000,
    this.maxHeaderBytes = 256 * 1024,
    this.maxRequestsPerOperation = 256,
    this.operationTimeout = const Duration(seconds: 30),
    this.retryAfter = const Duration(seconds: 5),
  });

  final int maxPageSize;
  final int maxMailboxes;
  final int maxResponseBytes;
  final int maxRequestBytes;
  final int maxCursorBytes;
  final int maxHeaderBytes;
  final int maxRequestsPerOperation;
  final Duration operationTimeout;
  final Duration retryAfter;

  void validate() {
    if (maxPageSize < 1 ||
        maxPageSize > 1000 ||
        maxMailboxes < 1 ||
        maxMailboxes > 10000 ||
        maxResponseBytes < 1024 ||
        maxResponseBytes > 128 * 1024 * 1024 ||
        maxRequestBytes < 1024 ||
        maxRequestBytes > 128 * 1024 * 1024 ||
        maxCursorBytes < 128 ||
        maxCursorBytes > 64 * 1024 ||
        maxHeaderBytes < 128 ||
        maxHeaderBytes > 1024 * 1024 ||
        maxRequestsPerOperation < 1 ||
        maxRequestsPerOperation > 2048 ||
        operationTimeout <= Duration.zero ||
        operationTimeout > const Duration(minutes: 5) ||
        retryAfter < Duration.zero ||
        retryAfter > const Duration(days: 1)) {
      throw ArgumentError('Invalid cloud mail operation limits.');
    }
  }
}

enum MailCloudOperation {
  authorize,
  exchangeToken,
  refreshToken,
  capabilities,
  listMailboxes,
  fetchHeaders,
  observeFlags,
  observeMembership,
  fetchMessage,
  pullChanges,
  apply,
  submit,
}

enum MailCloudLogStage {
  started,
  request,
  response,
  refresh,
  completed,
  failed,
  cancelled,
}

/// Deliberately has no free-text field. Even verbose diagnostics cannot carry
/// addresses, message IDs/content, URLs, tokens, OAuth codes, or exceptions.
final class MailCloudLogEvent {
  const MailCloudLogEvent({
    required this.service,
    required this.operation,
    required this.stage,
    this.statusCode,
    this.elapsedMilliseconds,
    this.requestBytes,
    this.responseBytes,
    this.itemCount,
    this.attempt,
    this.problemCode,
    this.retryAfterSeconds,
  });

  final MailCloudService service;
  final MailCloudOperation operation;
  final MailCloudLogStage stage;
  final int? statusCode;
  final int? elapsedMilliseconds;
  final int? requestBytes;
  final int? responseBytes;
  final int? itemCount;
  final int? attempt;
  final MailProblemCode? problemCode;
  final int? retryAfterSeconds;

  Map<String, Object> toJson() => {
    'service': service.name,
    'operation': operation.name,
    'stage': stage.name,
    'statusCode': ?statusCode,
    'elapsedMilliseconds': ?elapsedMilliseconds,
    'requestBytes': ?requestBytes,
    'responseBytes': ?responseBytes,
    'itemCount': ?itemCount,
    'attempt': ?attempt,
    'problemCode': ?problemCode?.name,
    'retryAfterSeconds': ?retryAfterSeconds,
  };

  @override
  String toString() => toJson().toString();
}

typedef MailCloudLogSink = void Function(MailCloudLogEvent event);

void emitMailCloudLog(MailCloudLogSink? sink, MailCloudLogEvent event) {
  try {
    sink?.call(event);
  } on Object {
    // Host logging is observational and must never change an operation result.
  }
}
