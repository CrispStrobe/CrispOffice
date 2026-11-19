import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_transport/src/ews/cursor.dart';
import 'package:quds_mail_transport/src/ews/errors.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'exchange',
  profile: MailProfileId('profile', hostId: 'host'),
);

MailEwsConfiguration _config(String url, {String? mailboxAddress}) =>
    MailEwsConfiguration(
      account: _account,
      endpoint: Uri.parse(url),
      username: 'reader@example.test',
      mailboxAddress: mailboxAddress,
      credential: MailCredentialReference(account: _account, key: 'vault'),
    );

void main() {
  test(
    'on-prem private names, explicit ports and IPv6 retain verified HTTPS',
    () {
      for (final endpoint in [
        'https://exchange.internal/EWS/Exchange.asmx',
        'https://exchange:8443/ews/Exchange.asmx',
        'https://10.1.2.3/EWS/Exchange.asmx',
        'https://[2001:db8::1]/EWS/Exchange.asmx',
      ]) {
        final config = _config(endpoint);
        expect(config.authentication, MailEwsAuthentication.ntlm);
        expect(config.serverVersion.wireValue, 'Exchange2013_SP1');
        expect(config.endpoint.toString(), endpoint);
      }
    },
  );

  test('unsafe or ambiguous endpoints are refused at construction', () {
    for (final endpoint in [
      'http://exchange.test/EWS/Exchange.asmx',
      'https://reader:password@exchange.test/EWS/Exchange.asmx',
      'https://exchange.test/EWS/Exchange.asmx?token=secret',
      'https://exchange.test/EWS/Exchange.asmx#fragment',
      'https://exchange.test/',
      'https://exchange.test/EWS/%0aExchange.asmx',
      'https://exchange.test/EWS/%5cExchange.asmx',
      'https://bad_host/EWS/Exchange.asmx',
    ]) {
      expect(() => _config(endpoint), throwsArgumentError);
    }
  });

  test('delegated mailbox uses a separate SMTP-address field', () {
    final config = _config(
      'https://exchange.test/EWS/Exchange.asmx',
      mailboxAddress: 'shared@example.test',
    );
    expect(config.username, 'reader@example.test');
    expect(config.mailboxAddress, 'shared@example.test');
    for (final address in [
      'Name <shared@example.test>',
      'a@b\r\nInjected',
      'a@b,c@d',
      '',
    ]) {
      expect(
        () => _config(
          'https://exchange.test/EWS/Exchange.asmx',
          mailboxAddress: address,
        ),
        throwsArgumentError,
      );
    }
  });

  test('credential reference cannot cross accounts', () {
    final other = MailAccountId('other', profile: _account.profile);
    expect(
      () => MailEwsConfiguration(
        account: _account,
        endpoint: Uri.https('exchange.test', '/EWS/Exchange.asmx'),
        username: 'reader',
        credential: MailCredentialReference(account: other, key: 'vault'),
      ),
      throwsArgumentError,
    );
  });

  test('work bounds reflect EWS and existing store limits', () {
    const MailEwsLimits().validate();
    for (final invalid in [
      const MailEwsLimits(maxPageSize: 513),
      const MailEwsLimits(maxPageSize: 0),
      const MailEwsLimits(maxSyncStateBytes: 16384),
      const MailEwsLimits(maxResponseBytes: 0),
      const MailEwsLimits(maxXmlDepth: 0),
      const MailEwsLimits(operationTimeout: Duration.zero),
    ]) {
      expect(invalid.validate, throwsArgumentError);
    }
  });

  test('opaque SyncState roundtrips without decoding or normalizing', () {
    final config = _config('https://exchange.test/EWS/Exchange.asmx');
    final folder = MailMailboxId('opaque-folder+/==', account: _account);
    const cursor = EwsSyncCursor(state: 'opaque-state+/==', revision: 42);
    final encoded = cursor.encode(config, folder, const MailEwsLimits());
    final decoded = EwsSyncCursor.decode(
      encoded,
      config,
      folder,
      const MailEwsLimits(),
    )!;
    expect(decoded.state, cursor.state);
    expect(decoded.revision, cursor.revision);
    expect(encoded.value.length, lessThanOrEqualTo(16384));
    expect(
      () => EwsSyncCursor.decode(
        encoded,
        config,
        MailMailboxId('other', account: _account),
        const MailEwsLimits(),
      ),
      throwsA(isA<EwsException>()),
    );
  });

  test('cursor serialized size cannot exceed durable store admission', () {
    final config = _config('https://exchange.test/EWS/Exchange.asmx');
    final folder = MailMailboxId('folder', account: _account);
    expect(
      () => EwsSyncCursor(
        state: '"' * 12000,
        revision: 1,
      ).encode(config, folder, const MailEwsLimits(maxSyncStateBytes: 12000)),
      throwsA(
        isA<EwsException>().having(
          (e) => e.code,
          'code',
          MailProblemCode.quotaExceeded,
        ),
      ),
    );
  });
}
