import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

MailAccountId _account({String host = 'office', String id = 'exchange'}) =>
    MailAccountId(id, profile: MailProfileId('personal', hostId: host));

MailOpaqueIdentity _identity({
  MailAccountId? account,
  String value = 'AAMkAGI+/opaque==',
  MailProviderKind provider = MailProviderKind.ews,
}) => MailOpaqueIdentity(
  account: account ?? _account(),
  provider: provider,
  value: value,
);

void main() {
  test('EWS item IDs retain exact case and opaque punctuation', () {
    final identity = _identity();
    expect(identity.value, 'AAMkAGI+/opaque==');
    expect(identity.provider, MailProviderKind.ews);
    expect(identity, _identity());
    expect(identity.hashCode, _identity().hashCode);
    expect(identity, isNot(_identity(value: 'aamkagi+/opaque==')));
  });

  test('equal server IDs remain isolated by host, account and provider', () {
    final identity = _identity();
    expect(identity, isNot(_identity(account: _account(host: 'embedded'))));
    expect(identity, isNot(_identity(account: _account(id: 'other'))));
    expect(identity, isNot(_identity(provider: MailProviderKind.graph)));
    expect(<MailRemoteIdentity>{
      identity,
      _identity(account: _account(host: 'embedded')),
      _identity(account: _account(id: 'other')),
      _identity(provider: MailProviderKind.graph),
    }, hasLength(4));
  });

  test('an Exchange move can replace the server identity', () {
    final before = _identity(value: 'AAMkAGI/source==');
    final after = _identity(value: 'AAMkAGI/destination==');
    expect(after.account, before.account);
    expect(after, isNot(before));
  });

  test('EWS identities reject empty values and control characters', () {
    for (final value in ['', 'item\r\nheader', 'item\u0000', 'item\u007f']) {
      expect(() => _identity(value: value), throwsArgumentError);
    }
  });

  test('cross-account Exchange moves fail before provider work', () {
    expect(
      () => MailMove(
        id: 'operation',
        message: _identity(),
        destination: MailMailboxId(
          'AAMkFolder==',
          account: _account(id: 'other'),
        ),
      ),
      throwsArgumentError,
    );
  });
}
