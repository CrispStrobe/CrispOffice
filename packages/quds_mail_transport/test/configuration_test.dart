import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('personal', hostId: 'office.test');
final _account = MailAccountId('primary', profile: _profile);

MailImapConfiguration _configuration({
  String username = 'reader@example.test',
  MailCredentialReference? credential,
  MailImapAuthentication authentication = MailImapAuthentication.password,
}) => MailImapConfiguration(
  account: _account,
  endpoint: MailServerEndpoint(host: 'imap.example.test', port: 993),
  username: username,
  credential:
      credential ??
      MailCredentialReference(account: _account, key: 'host-vault-reference'),
  authentication: authentication,
);

void main() {
  group('manual server endpoint', () {
    test('accepts explicit DNS, IPv4 and unbracketed IPv6 hosts', () {
      for (final host in [
        'imap.example.test',
        'IMAP.example.test',
        'xn--bcher-kva.example',
        'localhost',
        '192.0.2.1',
        '2001:db8::1',
        '::1',
        '${List.filled(63, 'a').join()}.example.test',
      ]) {
        final endpoint = MailServerEndpoint(host: host, port: 993);
        expect(endpoint.host, host);
        expect(endpoint.port, 993);
        expect(endpoint.tls, MailTlsMode.implicitTls);
      }
    });

    test(
      'rejects address injection, ambiguous IPs and malformed DNS labels',
      () {
        for (final host in [
          '',
          'imap://mail.example.test',
          'imaps://mail.example.test',
          'user:password@mail.example.test',
          'mail.example.test/path',
          'mail.example.test?verify=false',
          'mail.example.test#fragment',
          'mail.example.test\r\nLOGIN injected',
          ' mail.example.test',
          'mail.example.test ',
          'mail\u0000.example.test',
          'mail..example.test',
          '-mail.example.test',
          'mail-.example.test',
          '.mail.example.test',
          'mail.example.test.',
          '_imap.example.test',
          'bücher.example',
          '999.0.2.1',
          '192.00.2.1',
          '127.1',
          ':',
          'smtp:993',
          '2001:::1',
          '[2001:db8::1]',
          'fe80::1%eth0',
          '${List.filled(64, 'a').join()}.example.test',
          List.filled(4, List.filled(63, 'a').join()).join('.'),
        ]) {
          expect(
            () => MailServerEndpoint(host: host, port: 993),
            throwsArgumentError,
            reason: 'Rejected endpoint syntax',
          );
        }
      },
    );

    test(
      'requires an explicit usable port without a service-port assumption',
      () {
        for (final invalid in [-1, 0, 65536]) {
          expect(
            () => MailServerEndpoint(host: 'imap.example.test', port: invalid),
            throwsArgumentError,
          );
        }
        expect(MailServerEndpoint(host: 'imap.example.test', port: 1).port, 1);
        expect(
          MailServerEndpoint(host: 'imap.example.test', port: 65535).port,
          65535,
        );
      },
    );

    test(
      'port selection never silently downgrades the mandatory TLS policy',
      () {
        expect(MailTlsMode.values, [
          MailTlsMode.implicitTls,
          MailTlsMode.startTls,
        ]);
        expect(
          MailServerEndpoint(host: 'imap.example.test', port: 143).tls,
          MailTlsMode.implicitTls,
        );
        final startTls = MailServerEndpoint(
          host: 'imap.example.test',
          port: 143,
          tls: MailTlsMode.startTls,
        );
        expect(startTls.tls, MailTlsMode.startTls);
        expect(startTls.port, 143);
      },
    );
  });

  group('host-owned account configuration', () {
    test(
      'keeps the login identity, authentication mode and scoped vault locator',
      () {
        final reference = MailCredentialReference(
          account: _account,
          key: 'vault/imap/1',
        );
        final configuration = _configuration(
          username: 'reader+é@example.test',
          credential: reference,
          authentication: MailImapAuthentication.xoauth2,
        );
        expect(configuration.account, _account);
        expect(configuration.username, 'reader+é@example.test');
        expect(configuration.credential, same(reference));
        expect(configuration.authentication, MailImapAuthentication.xoauth2);
        expect(
          _configuration(
            authentication: MailImapAuthentication.oauthBearer,
          ).authentication,
          MailImapAuthentication.oauthBearer,
        );
        expect(
          _configuration().authentication,
          MailImapAuthentication.password,
        );
      },
    );

    test('rejects empty, overlong and control-bearing login identities', () {
      for (final username in [
        '',
        List.filled(1025, 'u').join(),
        'reader\r\nLOGIN other',
        'reader\u0000',
        'reader\t',
        'reader\u007f',
      ]) {
        expect(() => _configuration(username: username), throwsArgumentError);
      }
      final boundary = List.filled(1024, 'u').join();
      expect(_configuration(username: boundary).username, boundary);
    });

    test(
      'vault references cannot cross accounts, profiles or host applications',
      () {
        final foreignAccounts = [
          MailAccountId('other', profile: _profile),
          MailAccountId(
            _account.value,
            profile: MailProfileId('other', hostId: _profile.hostId),
          ),
          MailAccountId(
            _account.value,
            profile: MailProfileId(_profile.value, hostId: 'other.host.test'),
          ),
        ];
        for (final foreign in foreignAccounts) {
          expect(
            () => _configuration(
              credential: MailCredentialReference(
                account: foreign,
                key: 'host-vault-reference',
              ),
            ),
            throwsArgumentError,
          );
        }
        final equivalent = MailAccountId(
          _account.value,
          profile: MailProfileId(_profile.value, hostId: _profile.hostId),
        );
        expect(
          _configuration(
            credential: MailCredentialReference(
              account: equivalent,
              key: 'same-namespace',
            ),
          ).credential.account,
          _account,
        );
      },
    );

    test(
      'vault locators are bounded identifiers rather than protocol lines',
      () {
        for (final key in [
          '',
          List.filled(1025, 'k').join(),
          'key\nother',
          'key\u0000',
          'key\u007f',
        ]) {
          expect(
            () => _configuration(
              credential: MailCredentialReference(account: _account, key: key),
            ),
            throwsArgumentError,
          );
        }
        final boundary = List.filled(1024, 'k').join();
        expect(
          _configuration(
            credential: MailCredentialReference(
              account: _account,
              key: boundary,
            ),
          ).credential.key,
          boundary,
        );
      },
    );
  });

  group('finite transport resource bounds', () {
    test(
      'validates defaults and supported lower and upper policy boundaries',
      () {
        const MailTransportLimits().validate();
        const MailTransportLimits(
          maxPageSize: 1,
          maxMailboxes: 1,
          maxUidScan: 1,
          maxDiscoveredUids: 1,
          maxHeaderBytes: 1,
          maxProtocolLineBytes: 128,
          maxResponseBytes: 128,
          maxCredentialBytes: 1,
          operationTimeout: Duration(microseconds: 1),
          cancellationPollInterval: Duration(microseconds: 1),
          retryAfter: Duration.zero,
        ).validate();
        const MailTransportLimits(
          maxPageSize: 1000,
          maxMailboxes: 10000,
          maxUidScan: 100000,
          maxDiscoveredUids: 100000,
          maxHeaderBytes: 1024 * 1024,
          maxProtocolLineBytes: 1024 * 1024,
          maxResponseBytes: 128 * 1024 * 1024,
          maxCredentialBytes: 64 * 1024,
          operationTimeout: Duration(minutes: 5),
          cancellationPollInterval: Duration(seconds: 1),
        ).validate();
      },
    );

    test('rejects empty or excessive message, mailbox and UID sweep work', () {
      for (final limits in const [
        MailTransportLimits(maxPageSize: 0),
        MailTransportLimits(maxPageSize: 1001),
        MailTransportLimits(maxMailboxes: 0),
        MailTransportLimits(maxMailboxes: 10001),
        MailTransportLimits(maxUidScan: 0),
        MailTransportLimits(maxUidScan: 100001),
        MailTransportLimits(maxDiscoveredUids: 0),
        MailTransportLimits(maxDiscoveredUids: 100001),
      ]) {
        expect(limits.validate, throwsArgumentError);
      }
    });

    test(
      'rejects unusable or excessive literal, line, response and credential budgets',
      () {
        for (final limits in const [
          MailTransportLimits(maxHeaderBytes: 0),
          MailTransportLimits(maxHeaderBytes: 1024 * 1024 + 1),
          MailTransportLimits(maxProtocolLineBytes: 127),
          MailTransportLimits(maxProtocolLineBytes: 1024 * 1024 + 1),
          MailTransportLimits(maxResponseBytes: 127),
          MailTransportLimits(maxResponseBytes: 128 * 1024 * 1024 + 1),
          MailTransportLimits(maxCredentialBytes: 0),
          MailTransportLimits(maxCredentialBytes: 64 * 1024 + 1),
        ]) {
          expect(limits.validate, throwsArgumentError);
        }
      },
    );

    test('rejects unbounded waits, invalid polling and negative backoff', () {
      for (final limits in const [
        MailTransportLimits(operationTimeout: Duration.zero),
        MailTransportLimits(operationTimeout: Duration(milliseconds: -1)),
        MailTransportLimits(operationTimeout: Duration(seconds: 301)),
        MailTransportLimits(cancellationPollInterval: Duration.zero),
        MailTransportLimits(
          cancellationPollInterval: Duration(milliseconds: -1),
        ),
        MailTransportLimits(
          cancellationPollInterval: Duration(milliseconds: 1001),
        ),
        MailTransportLimits(retryAfter: Duration(milliseconds: -1)),
      ]) {
        expect(limits.validate, throwsArgumentError);
      }
    });
  });
}
