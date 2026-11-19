import 'package:quds_mail_core/quds_mail_core.dart';

import '../configuration.dart';

/// NTLM means NTLMv2 over verified HTTPS. There is no NTLMv1 fallback.
/// Bearer tokens are acquired/refreshed by the host, including on-prem AD FS.
enum MailEwsAuthentication { ntlm, basic, bearer }

/// EWS schema versions, not claims about a server's product support lifecycle.
enum MailEwsServerVersion {
  exchange2013Sp1('Exchange2013_SP1'),
  exchange2016('Exchange2016');

  const MailEwsServerVersion(this.wireValue);
  final String wireValue;
}

/// Explicit on-premises connection settings. Passwords/tokens stay in the vault.
///
/// Use an administrator-supplied URL such as
/// `https://mail.example.com/EWS/Exchange.asmx`. No discovery or redirect can
/// silently change the host to which credentials are sent. Private DNS names
/// and IP addresses are supported with normal certificate/hostname validation.
final class MailEwsConfiguration {
  MailEwsConfiguration({
    required this.account,
    required this.endpoint,
    required this.username,
    required this.credential,
    this.domain = '',
    this.workstation = '',
    this.mailboxAddress,
    this.authentication = MailEwsAuthentication.ntlm,
    this.serverVersion = MailEwsServerVersion.exchange2013Sp1,
  }) {
    if (endpoint.scheme != 'https' ||
        !endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.path.isEmpty ||
        endpoint.path == '/' ||
        endpoint.toString().length > 2048 ||
        !_validText(username, 1024) ||
        !_validText(domain, 255, empty: true) ||
        !_validText(workstation, 255, empty: true) ||
        credential.account != account ||
        !_validText(credential.key, 1024) ||
        (mailboxAddress != null && !validEwsAddress(mailboxAddress!)) ||
        (authentication == MailEwsAuthentication.basic &&
            username.contains(':'))) {
      throw ArgumentError('Invalid account-scoped HTTPS EWS configuration.');
    }
    // Reuse the existing strict DNS/IP and port validation, including IPv6.
    MailServerEndpoint(host: endpoint.host, port: endpoint.port);
    final decodedPath = endpoint.pathSegments.join('/');
    if (decodedPath.contains(RegExp(r'[\x00-\x1f\x7f\\]'))) {
      throw ArgumentError('Invalid EWS endpoint path.');
    }
  }

  final MailAccountId account;
  final Uri endpoint;
  final String username;
  final MailCredentialReference credential;
  final String domain;
  final String workstation;

  /// Optional mailbox SMTP address for explicitly delegated distinguished
  /// folders. Access still depends on Exchange permissions; no impersonation.
  final String? mailboxAddress;
  final MailEwsAuthentication authentication;
  final MailEwsServerVersion serverVersion;
}

bool _validText(String value, int maxLength, {bool empty = false}) =>
    (empty || value.isNotEmpty) &&
    value.length <= maxLength &&
    !value.contains(RegExp(r'[\x00-\x1f\x7f]'));

/// Deliberately conservative SMTP-address boundary for endpoint configuration
/// and submission. Display names, routing prefixes and header syntax belong in
/// separate fields; XML escaping alone is not mailbox validation.
bool validEwsAddress(String value) =>
    value.length <= 320 &&
    RegExp(
      r'^[^\s<>(),;:\\"\[\]\x00-\x1f\x7f@]+@[^\s<>(),;:\\"\[\]\x00-\x1f\x7f@]+$',
    ).hasMatch(value);

/// Per-operation budgets. A host decides when to retry or continue syncing.
final class MailEwsLimits {
  const MailEwsLimits({
    this.maxPageSize = 100,
    this.maxMailboxes = 1000,
    this.maxResponseBytes = 64 * 1024 * 1024,
    this.maxRequestBytes = 64 * 1024 * 1024,
    this.maxCredentialBytes = 16 * 1024,
    this.maxSyncStateBytes = 8192,
    this.maxHeaderBytes = 256 * 1024,
    this.maxXmlDepth = 64,
    this.maxXmlNodes = 100000,
    this.operationTimeout = const Duration(seconds: 30),
    this.cancellationPollInterval = const Duration(milliseconds: 25),
    this.retryAfter = const Duration(seconds: 5),
  });

  final int maxPageSize;
  final int maxMailboxes;
  final int maxResponseBytes;
  final int maxRequestBytes;
  final int maxCredentialBytes;
  final int maxSyncStateBytes;
  final int maxHeaderBytes;
  final int maxXmlDepth;
  final int maxXmlNodes;
  final Duration operationTimeout;
  final Duration cancellationPollInterval;
  final Duration retryAfter;

  void validate() {
    if (maxPageSize < 1 ||
        maxPageSize > 512 ||
        maxMailboxes < 1 ||
        maxMailboxes > 10000 ||
        maxResponseBytes < 1024 ||
        maxResponseBytes > 128 * 1024 * 1024 ||
        maxRequestBytes < 1024 ||
        maxRequestBytes > 128 * 1024 * 1024 ||
        maxCredentialBytes < 1 ||
        maxCredentialBytes > 64 * 1024 ||
        maxSyncStateBytes < 1 ||
        maxSyncStateBytes > 12000 ||
        maxHeaderBytes < 1 ||
        maxHeaderBytes > 1024 * 1024 ||
        maxXmlDepth < 8 ||
        maxXmlDepth > 128 ||
        maxXmlNodes < 16 ||
        maxXmlNodes > 1000000 ||
        operationTimeout <= Duration.zero ||
        operationTimeout > const Duration(minutes: 5) ||
        cancellationPollInterval <= Duration.zero ||
        cancellationPollInterval > const Duration(seconds: 1) ||
        retryAfter < Duration.zero) {
      throw ArgumentError('Invalid EWS transport limits.');
    }
  }
}

/// EWS mail and submission share account/vault ownership and lifecycle rules.
abstract interface class MailEwsProvider
    implements MailProvider, MailSubmissionProvider {}
