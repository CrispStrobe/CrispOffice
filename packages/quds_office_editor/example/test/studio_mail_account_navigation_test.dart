import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_account_navigation.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_strings.dart';

MailLocalAccountRecord _record({
  String provider = 'imap',
  String? endpoint,
  String? login,
  String sender = 'Writer@example.test',
  int revision = 7,
}) {
  final identity = StudioMailDraftAccount(
    provider: provider,
    endpoint:
        endpoint ??
        switch (provider) {
          'imap' => 'imaps://imap.example.test:993',
          'ews' => 'https://exchange.example.test/EWS/Exchange.asmx',
          'gmail' => 'https://gmail.googleapis.com/gmail/v1',
          'graph' => 'https://graph.microsoft.com/v1.0',
          _ => throw StateError('Unknown fixture provider'),
        },
    login:
        login ??
        switch (provider) {
          'ews' => jsonEncode(['DOMAIN', 'Writer']),
          'graph' => jsonEncode(['common', sender]),
          _ => sender,
        },
    sender: sender,
  );
  return MailLocalAccountRecord(
    id: identity.account.value,
    provider: identity.provider,
    endpoint: identity.endpoint,
    login: identity.login,
    sender: identity.sender,
    lastConnectedAt: DateTime.utc(2026, 11, 22),
    revision: revision,
  );
}

Matcher _problem(MailProblemCode code) => isA<StudioMailDraftStoreException>()
    .having((error) => error.code, 'code', code);

final class _Directory implements StudioMailLocalAccountStore {
  _Directory(this.rows);

  List<MailLocalAccountRecord> rows;
  Completer<void>? gate;
  int loads = 0;

  @override
  Future<List<MailLocalAccountRecord>> load() async {
    loads++;
    await gate?.future;
    return List.unmodifiable(rows);
  }

  @override
  Future<void> remember(StudioMailDraftAccount identity) =>
      throw StateError('Navigation cannot register an account');

  @override
  Future<void> forget(MailLocalAccountRecord record) =>
      throw StateError('Navigation cannot remove an account');
}

void main() {
  for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
    test(
      '$provider target retains exact durable identity and safe details',
      () {
        final record = _record(provider: provider);
        final target = StudioMailAccountNavigationTarget.fromRecord(record);
        expect(target.record, same(record));
        expect(target.provider.name, provider);
        expect(target.identity.account.value, record.id);
        expect(target.identity.sender, record.sender);
        expect(target.description, contains(record.endpoint));
        expect(target.description, isNot(contains(record.id)));
        expect(
          target.toString(),
          'StudioMailAccountNavigationTarget(redacted)',
        );
        expect(
          target.providerLabel(const StudioStrings(StudioLanguage.en)),
          isNotEmpty,
        );
        expect(target.ewsDomain, provider == 'ews' ? 'DOMAIN' : null);
        expect(target.ewsLogin, provider == 'ews' ? 'Writer' : null);
        expect(target.graphTenant, provider == 'graph' ? 'common' : null);
        target.requireMatches(studioMailLocalAccountIdentity(record));
      },
    );
  }

  test('empty EWS domain is a valid explicit login route', () {
    final target = StudioMailAccountNavigationTarget.fromRecord(
      _record(provider: 'ews', login: '["","Writer@example.test"]'),
    );
    expect(target.ewsDomain, '');
    expect(target.ewsLogin, 'Writer@example.test');
    expect(target.description, endsWith('\nWriter@example.test'));
  });

  test('IMAP IPv6 endpoint remains usable', () {
    final target = StudioMailAccountNavigationTarget.fromRecord(
      _record(endpoint: 'imaps://[2001:db8::1]:993'),
    );
    expect(target.identity.endpoint, 'imaps://[2001:db8::1]:993');
  });

  final invalidRoutes = <({String name, MailLocalAccountRecord record})>[
    (name: 'IMAP zero port', record: _record(endpoint: 'imap://host.test:0')),
    (
      name: 'IMAP oversized port',
      record: _record(endpoint: 'imaps://host.test:65536'),
    ),
    (name: 'IMAP path', record: _record(endpoint: 'imaps://host.test/Inbox')),
    (
      name: 'EWS cleartext',
      record: _record(provider: 'ews', endpoint: 'http://host.test/EWS'),
    ),
    (
      name: 'EWS unstructured login',
      record: _record(provider: 'ews', login: 'Writer'),
    ),
    (
      name: 'EWS object login',
      record: _record(provider: 'ews', login: '{"domain":"A","login":"B"}'),
    ),
    (
      name: 'EWS extra login field',
      record: _record(provider: 'ews', login: '["A","B","C"]'),
    ),
    (
      name: 'EWS typed login field',
      record: _record(provider: 'ews', login: '["A",1]'),
    ),
    (
      name: 'EWS empty login',
      record: _record(provider: 'ews', login: '["A",""]'),
    ),
    (
      name: 'EWS padded domain',
      record: _record(provider: 'ews', login: '[" A","B"]'),
    ),
    (
      name: 'EWS escaped control',
      record: _record(provider: 'ews', login: r'["A","B\n"]'),
    ),
    (
      name: 'Gmail foreign endpoint',
      record: _record(
        provider: 'gmail',
        endpoint: 'https://other.example.test/gmail/v1',
      ),
    ),
    (
      name: 'Gmail altered API path',
      record: _record(
        provider: 'gmail',
        endpoint: 'https://gmail.googleapis.com/gmail/v1/',
      ),
    ),
    (
      name: 'Gmail different login',
      record: _record(provider: 'gmail', login: 'Other@example.test'),
    ),
    (
      name: 'Graph foreign endpoint',
      record: _record(
        provider: 'graph',
        endpoint: 'https://other.example.test/v1.0',
      ),
    ),
    (
      name: 'Graph different sender',
      record: _record(
        provider: 'graph',
        login: '["common","Other@example.test"]',
      ),
    ),
    (
      name: 'Graph empty tenant',
      record: _record(provider: 'graph', login: '["","Writer@example.test"]'),
    ),
    (
      name: 'Graph tenant path',
      record: _record(
        provider: 'graph',
        login: '["common/path","Writer@example.test"]',
      ),
    ),
    (
      name: 'Graph dotted tenant',
      record: _record(
        provider: 'graph',
        login: '["example..test","Writer@example.test"]',
      ),
    ),
  ];
  for (final fixture in invalidRoutes) {
    test('rejects ${fixture.name}', () {
      expect(
        () => StudioMailAccountNavigationTarget.fromRecord(fixture.record),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
    });
  }

  test('forged directory fingerprint cannot redirect an account', () {
    final record = _record();
    final forged = MailLocalAccountRecord(
      id: 'different-id',
      provider: record.provider,
      endpoint: record.endpoint,
      login: record.login,
      sender: record.sender,
      lastConnectedAt: record.lastConnectedAt,
      revision: record.revision,
    );
    expect(
      () => StudioMailAccountNavigationTarget.fromRecord(forged),
      throwsA(_problem(MailProblemCode.permissionDenied)),
    );
  });

  test(
    'requireMatches rejects changed sender, endpoint, login and provider',
    () {
      final target = StudioMailAccountNavigationTarget.fromRecord(_record());
      for (final record in [
        _record(sender: 'Other@example.test'),
        _record(endpoint: 'imaps://other.example.test:993'),
        _record(login: 'DifferentLogin'),
        _record(provider: 'gmail'),
      ]) {
        expect(
          () => target.requireMatches(studioMailLocalAccountIdentity(record)),
          throwsA(_problem(MailProblemCode.permissionDenied)),
        );
      }
    },
  );

  test(
    'current validation rereads exact record revision without mutation',
    () async {
      final record = _record();
      final directory = _Directory([record, _record(provider: 'gmail')]);
      final target = StudioMailAccountNavigationTarget.fromRecord(record);
      await target.validateCurrent(directory);
      expect(directory.loads, 1);
      directory.rows = [_record(revision: record.revision + 1)];
      await expectLater(
        target.validateCurrent(directory),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      directory.rows = [];
      await expectLater(
        target.validateCurrent(directory),
        throwsA(_problem(MailProblemCode.conflict)),
      );
    },
  );

  test(
    'duplicate sibling and malformed sibling block target validation',
    () async {
      final record = _record();
      final sibling = _record(provider: 'gmail');
      final directory = _Directory([record, sibling, sibling]);
      final target = StudioMailAccountNavigationTarget.fromRecord(record);
      await expectLater(
        target.validateCurrent(directory),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      directory.rows = [record, _record(provider: 'ews', login: 'invalid')];
      await expectLater(
        target.validateCurrent(directory),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
    },
  );

  test('catalog work is bounded before examining individual rows', () async {
    final record = _record();
    final target = StudioMailAccountNavigationTarget.fromRecord(record);
    final directory = _Directory(List.filled(101, record));
    await expectLater(
      target.validateCurrent(directory),
      throwsA(_problem(MailProblemCode.quotaExceeded)),
    );
  });

  test(
    'removal while directory validation is pending rejects the target',
    () async {
      final record = _record();
      final directory = _Directory([record])..gate = Completer<void>();
      final target = StudioMailAccountNavigationTarget.fromRecord(record);
      final pending = target.validateCurrent(directory);
      final rejected = expectLater(
        pending,
        throwsA(_problem(MailProblemCode.conflict)),
      );
      directory.rows = [];
      directory.gate!.complete();
      await rejected;
    },
  );
}
