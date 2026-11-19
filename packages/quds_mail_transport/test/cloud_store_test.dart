@TestOn('vm')
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/src/cloud/configuration.dart';
import 'package:quds_mail_transport/src/cloud/http.dart';
import 'package:quds_mail_transport/src/cloud/provider.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('profile', hostId: 'cloud-store-test');
final _account = MailAccountId('account', profile: _profile);
final _inbox = MailMailboxId('INBOX', account: _account);
final _label = MailMailboxId('Label_1', account: _account);

T _value<T>(MailResult<T> value) {
  expect(value, isA<MailSuccess<T>>());
  return (value as MailSuccess<T>).value;
}

final class _Tokens implements MailCloudTokenSource {
  @override
  Future<MailResult<MailCloudAccessToken>> accessToken(
    MailOperationLease lease, {
    bool forceRefresh = false,
  }) async => MailSuccess(
    MailCloudAccessToken(
      value: 'fixture-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
  @override
  void dispose() {}
}

final class _Gmail implements MailCloudHttpTransport {
  List<String> labels = ['INBOX', 'Label_1'];
  bool changed = false;
  bool corruptHistory = false;

  @override
  Future<MailCloudHttpResponse> send(
    MailCloudHttpRequest request, {
    required MailOperationLease lease,
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    final Object result;
    final route = request.uri.path;
    if (route.endsWith('/profile')) {
      result = {
        'emailAddress': 'owner@example.test',
        'historyId': changed ? '20' : '10',
      };
    } else if (route.endsWith('/history')) {
      if (corruptHistory) {
        return MailCloudHttpResponse(
          statusCode: 200,
          body: utf8.encode('{bad-json'),
        );
      }
      result = {
        'historyId': changed ? '20' : '10',
        if (changed)
          'history': [
            {
              'id': '20',
              'labelsRemoved': [
                {
                  'message': {'id': 'message'},
                  'labelIds': ['INBOX'],
                },
              ],
            },
          ],
      };
    } else if (route.endsWith('/messages')) {
      result = {
        'messages': [
          if (labels.contains(request.uri.queryParameters['labelIds']))
            {'id': 'message'},
        ],
      };
    } else if (route.endsWith('/messages/message')) {
      result = {
        'id': 'message',
        'labelIds': labels,
        'payload': {
          'headers': [
            {'name': 'From', 'value': 'sender@example.test'},
            {'name': 'Subject', 'value': 'Retained shared message'},
            {'name': 'Message-ID', 'value': '<message@example.test>'},
          ],
        },
      };
    } else {
      throw StateError('Unexpected controlled fixture request');
    }
    return MailCloudHttpResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode(result)),
    );
  }

  @override
  void close() {}
}

void main() {
  late SqliteMailRepository store;
  late ApiMailCloudProvider provider;
  late _Gmail remote;
  late MailAccountSession session;
  MailStoreCheckpoint? failAt;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    failAt = null;
    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.memory(),
        profile: _profile,
        faultInjector: (checkpoint) {
          if (checkpoint == failAt) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      ),
    );
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.gmail,
          displayName: 'Fixture',
          credentialReference: 'session',
        ),
      ),
    );
    remote = _Gmail();
    session = MailAccountSession(_account);
    provider = ApiMailCloudProvider(
      configuration: MailCloudConfiguration(
        account: _account,
        service: MailCloudService.gmail,
        mailboxAddress: 'owner@example.test',
      ),
      tokenSource: _Tokens(),
      transport: remote,
    );
  });

  tearDown(() async {
    provider.dispose();
    session.dispose();
    await store.close();
  });

  Future<MailResult<MailSyncPage>> pull(MailMailboxId mailbox) =>
      const MailSyncCoordinator().pullPage(
        provider: provider,
        repository: store,
        session: session,
        mailbox: mailbox,
        limit: 2,
      );

  test(
    'Gmail label removal commits one membership and preserves the other label',
    () async {
      _value(await pull(_inbox));
      _value(await pull(_inbox));
      _value(await pull(_label));
      _value(await pull(_label));
      final original = _value(await store.listHeaders(_label)).single;
      remote.labels = ['Label_1'];
      remote.changed = true;
      final page = _value(await pull(_inbox));
      expect(page.tombstones, hasLength(1));
      expect(_value(await store.listHeaders(_inbox)), isEmpty);
      final retained = _value(await store.listHeaders(_label)).single;
      expect(retained.id, original.id);
      expect(retained.remote, original.remote);
      expect(retained.envelope.subject, 'Retained shared message');
    },
  );

  test(
    'failed cloud page transaction rolls back membership and opaque cursor together',
    () async {
      _value(await pull(_inbox));
      _value(await pull(_inbox));
      final before = _value(await store.readCursor(_inbox))!;
      remote.labels = ['Label_1'];
      remote.changed = true;
      failAt = MailStoreCheckpoint.beforeSyncCursor;
      final failed = await pull(_inbox);
      expect(
        (failed as MailFailure<MailSyncPage>).problem.code,
        MailProblemCode.storageFailure,
      );
      expect(_value(await store.readCursor(_inbox))!.value, before.value);
      expect(_value(await store.listHeaders(_inbox)), hasLength(1));
      failAt = null;
      _value(await pull(_inbox));
      expect(
        _value(await store.readCursor(_inbox))!.value,
        isNot(before.value),
      );
      expect(_value(await store.listHeaders(_inbox)), isEmpty);
    },
  );

  test(
    'malformed cloud history does not advance or clear a persisted mailbox',
    () async {
      _value(await pull(_inbox));
      final before = _value(await store.readCursor(_inbox))!;
      remote.corruptHistory = true;
      expect(await pull(_inbox), isA<MailFailure<MailSyncPage>>());
      expect(_value(await store.readCursor(_inbox))!.value, before.value);
      expect(_value(await store.listHeaders(_inbox)), hasLength(1));
    },
  );

  test(
    'completed empty history pages advance CAS revision and reject stale replay',
    () async {
      _value(await pull(_inbox));
      final before = _value(await store.readCursor(_inbox))!;
      final stale = _value(
        await provider.pullChanges(
          _inbox,
          cursor: before,
          limit: 2,
          lease: session.begin(),
        ),
      );
      final winner = _value(await pull(_inbox));
      expect(winner.next.value, isNot(before.value));
      final replay = await store.commitSyncPage(
        stale,
        expectedCursor: before,
        lease: session.begin(),
      );
      expect(
        (replay as MailFailure<MailUnit>).problem.code,
        MailProblemCode.conflict,
      );
      expect(_value(await store.readCursor(_inbox))!.value, winner.next.value);
    },
  );
}
