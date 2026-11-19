import 'package:quds_mail_core/quds_mail_core.dart';

/// Both modes require validated TLS before any credential is sent.
enum MailTlsMode { implicitTls, startTls }

/// A token is supplied by the host vault; this is not an OAuth authorization UI.
enum MailImapAuthentication { password, xoauth2, oauthBearer }

/// Manual endpoint settings contain no password, token or certificate bypass.
final class MailServerEndpoint {
  MailServerEndpoint({
    required this.host,
    required this.port,
    this.tls = MailTlsMode.implicitTls,
  }) {
    if (!_validHost(host) || port < 1 || port > 65535) {
      throw ArgumentError(
        'A valid explicit server host and port are required.',
      );
    }
  }

  static bool _validHost(String host) {
    if (host.isEmpty ||
        host.length > 253 ||
        !RegExp(r'^[A-Za-z0-9.:-]+$').hasMatch(host)) {
      return false;
    }
    if (host.contains(':')) {
      try {
        Uri.parseIPv6Address(host);
        return true;
      } on FormatException {
        return false;
      }
    }
    final labels = host.split('.');
    if (RegExp(r'^[0-9.]+$').hasMatch(host)) {
      return labels.length == 4 &&
          labels.every((label) {
            final value = int.tryParse(label);
            return value != null &&
                value >= 0 &&
                value <= 255 &&
                label == value.toString();
          });
    }
    final labelPattern = RegExp(
      r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
    );
    return labels.every((label) => labelPattern.hasMatch(label));
  }

  final String host;
  final int port;
  final MailTlsMode tls;
}

/// The host owns configuration persistence, account sessions and vault lifecycle.
final class MailImapConfiguration {
  MailImapConfiguration({
    required this.account,
    required this.endpoint,
    required this.username,
    required this.credential,
    this.authentication = MailImapAuthentication.password,
  }) {
    if (username.isEmpty ||
        username.length > 1024 ||
        username.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        credential.account != account ||
        credential.key.isEmpty ||
        credential.key.length > 1024 ||
        credential.key.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw ArgumentError('Invalid account-scoped IMAP configuration.');
    }
  }

  final MailAccountId account;
  final MailServerEndpoint endpoint;
  final String username;
  final MailCredentialReference credential;
  final MailImapAuthentication authentication;
}

/// Per-operation work bounds. There is no automatic retry or background loop.
final class MailTransportLimits {
  const MailTransportLimits({
    this.maxPageSize = 100,
    this.maxMailboxes = 1000,
    this.maxUidScan = 10000,
    this.maxHeaderBytes = 256 * 1024,
    this.maxProtocolLineBytes = 64 * 1024,
    this.maxResponseBytes = 16 * 1024 * 1024,
    this.maxCredentialBytes = 16 * 1024,
    this.operationTimeout = const Duration(seconds: 30),
    this.cancellationPollInterval = const Duration(milliseconds: 25),
    this.retryAfter = const Duration(seconds: 5),
  });

  final int maxPageSize;
  final int maxMailboxes;

  /// Whole UID-window sweep bound. Larger mailboxes report unsupported before IO fetch.
  final int maxUidScan;
  final int maxHeaderBytes;
  final int maxProtocolLineBytes;
  final int maxResponseBytes;
  final int maxCredentialBytes;
  final Duration operationTimeout;
  final Duration cancellationPollInterval;
  final Duration retryAfter;

  void validate() {
    if (maxPageSize < 1 ||
        maxPageSize > 1000 ||
        maxMailboxes < 1 ||
        maxMailboxes > 10000 ||
        maxUidScan < 1 ||
        maxUidScan > 100000 ||
        maxHeaderBytes < 1 ||
        maxHeaderBytes > 1024 * 1024 ||
        maxProtocolLineBytes < 128 ||
        maxProtocolLineBytes > 1024 * 1024 ||
        maxResponseBytes < 128 ||
        maxResponseBytes > 128 * 1024 * 1024 ||
        maxCredentialBytes < 1 ||
        maxCredentialBytes > 64 * 1024 ||
        operationTimeout <= Duration.zero ||
        operationTimeout > const Duration(minutes: 5) ||
        cancellationPollInterval <= Duration.zero ||
        cancellationPollInterval > const Duration(seconds: 1) ||
        retryAfter < Duration.zero) {
      throw ArgumentError('Invalid native mail transport limits.');
    }
  }
}
