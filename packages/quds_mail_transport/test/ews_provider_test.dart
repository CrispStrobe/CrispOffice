@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_transport/src/ews/cursor.dart';
import 'package:quds_mail_transport/src/ews/errors.dart';
import 'package:quds_mail_transport/src/ews/native/http_client.dart';
import 'package:quds_mail_transport/src/ews/native/provider.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'exchange',
  profile: MailProfileId('personal', hostId: 'office'),
);
final _mailbox = MailMailboxId('inbox-id', account: _account);
MailOpaqueIdentity _identity(String id) => MailOpaqueIdentity(
  account: _account,
  provider: MailProviderKind.ews,
  value: id,
);

MailEwsConfiguration _configuration({String host = 'exchange.example.test'}) =>
    MailEwsConfiguration(
      account: _account,
      endpoint: Uri.https(host, '/EWS/Exchange.asmx'),
      username: r'EXAMPLE\reader',
      credential: MailCredentialReference(account: _account, key: 'ews-secret'),
    );

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

String _response(String action, String responses) =>
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
    'xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages" '
    'xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">'
    '<s:Body><m:${action}Response><m:ResponseMessages>$responses'
    '</m:ResponseMessages></m:${action}Response></s:Body></s:Envelope>';

String _success(String action, String payload) =>
    '<m:${action}ResponseMessage ResponseClass="Success">'
    '<m:ResponseCode>NoError</m:ResponseCode>$payload'
    '</m:${action}ResponseMessage>';

String _error(String action, String code) =>
    '<m:${action}ResponseMessage ResponseClass="Error">'
    '<m:MessageText>fixture text must stay private</m:MessageText>'
    '<m:ResponseCode>$code</m:ResponseCode>'
    '</m:${action}ResponseMessage>';

String _item(
  String id, {
  String key = 'fresh-key',
  bool read = false,
  bool flagged = false,
  String? parent = 'inbox-id',
  List<int>? mime,
}) => _success(
  'GetItem',
  '<m:Items><t:Message><t:ItemId Id="$id" ChangeKey="$key"/>'
      '${parent == null ? '' : '<t:ParentFolderId Id="$parent"/>'}'
      '${mime == null ? '' : '<t:MimeContent>${base64.encode(mime)}</t:MimeContent>'}'
      '<t:Subject>Exchange message</t:Subject><t:IsDraft>false</t:IsDraft>'
      '<t:From><t:Mailbox><t:EmailAddress>sender@example.test</t:EmailAddress>'
      '</t:Mailbox></t:From><t:IsRead>$read</t:IsRead>'
      '<t:Flag><t:FlagStatus>${flagged ? 'Flagged' : 'NotFlagged'}</t:FlagStatus></t:Flag>'
      '</t:Message></m:Items>',
);

String _sync(String state, String changes, {bool last = true}) => _response(
  'SyncFolderItems',
  _success(
    'SyncFolderItems',
    '<m:SyncState>$state</m:SyncState>'
        '<m:IncludesLastItemInRange>$last</m:IncludesLastItemInRange>'
        '<m:Changes>$changes</m:Changes>',
  ),
);

String _change(String kind, String id) => kind == 'Delete'
    ? '<t:Delete><t:ItemId Id="$id"/></t:Delete>'
    : '<t:$kind><t:Message><t:ItemId Id="$id" ChangeKey="old-key"/>'
          '</t:Message></t:$kind>';

String _folder(String id, {String kind = 'IPF.Note'}) =>
    '<t:Folder><t:FolderId Id="$id" ChangeKey="folder-key"/>'
    '<t:DisplayName>$id</t:DisplayName><t:FolderClass>$kind</t:FolderClass>'
    '</t:Folder>';

String _membershipItem(String id, {String parent = 'inbox-id'}) => _success(
  'GetItem',
  '<m:Items><t:Message><t:ItemId Id="$id" ChangeKey="current-key"/>'
      '<t:ParentFolderId Id="$parent"/></t:Message></m:Items>',
);

String _deletedItems() => _response(
  'GetFolder',
  _success('GetFolder', '<m:Folders>${_folder('trash-id')}</m:Folders>'),
);

final class _Vault implements MailCredentialStore {
  int loads = 0;
  String password = 'first-password';
  bool missing = false;
  Future<void> Function()? beforeLoad;
  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  ) async {
    loads++;
    await beforeLoad?.call();
    return MailSuccess(
      missing
          ? null
          : MailCredentialRecord(
              reference: reference,
              opaqueData: MailBytes(Uint8List.fromList(utf8.encode(password))),
            ),
    );
  }

  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) =>
      throw UnimplementedError('Provider must never write vault entries');
  @override
  Future<MailResult<MailUnit>> delete(MailCredentialReference reference) =>
      throw UnimplementedError('Provider must never delete vault entries');
  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) =>
      throw UnimplementedError('Provider must never delete accounts');
}

typedef _Step = (String, FutureOr<String> Function(String));

final class _Client implements EwsHttpClient {
  _Client(this.steps);
  final List<_Step> steps;
  final requests = <(String, String, bool)>[];
  bool aborted = false;
  @override
  bool mutationStarted = false;

  @override
  Future<String> post(
    String action,
    String envelope, {
    bool mutation = false,
  }) async {
    if (aborted) throw const EwsException(MailProblemCode.cancelled);
    expect(
      steps,
      isNotEmpty,
      reason: 'Unexpected/replayed SOAP request $action',
    );
    final step = steps.removeAt(0);
    expect(action, step.$1);
    requests.add((action, envelope, mutation));
    mutationStarted |= mutation;
    return await step.$2(envelope);
  }

  @override
  void abort() => aborted = true;
}

final class _Fixture {
  final vault = _Vault();
  final session = MailAccountSession(_account);
  final clients = <_Client>[];
  final secrets = <String>[];
  final scripts = <List<_Step>>[];

  NativeMailEwsProvider provider({
    MailEwsLimits limits = const MailEwsLimits(),
  }) => NativeMailEwsProvider(
    configuration: _configuration(),
    credentialStore: vault,
    codec: const QudsMimeCodec(),
    limits: limits,
    clientFactory:
        ({required configuration, required secret, required limits}) {
          secrets.add(secret);
          final client = _Client(scripts.removeAt(0));
          clients.add(client);
          return client;
        },
  );
}

MailPreparedMessage _prepared({List<String>? recipients}) =>
    MailPreparedMessage(
      account: _account,
      draftId: 'draft',
      draftRevision: 1,
      wire: MailBytes(
        Uint8List.fromList(
          utf8.encode(
            'From: sender@example.test\r\n'
            'To: visible@example.test\r\n'
            'Subject: Test\r\nMIME-Version: 1.0\r\n'
            'Content-Type: text/plain; charset=utf-8\r\n\r\nHello.\r\n',
          ),
        ),
      ),
      envelope: MailTransportEnvelope(
        sender: 'sender@example.test',
        recipients:
            recipients ?? ['visible@example.test', 'hidden@example.test'],
      ),
    );

void main() {
  test('EWS rejects Gmail Archive before credentials or SOAP', () async {
    final fixture = _Fixture();
    final provider = fixture.provider();
    expect(provider, isNot(isA<MailArchiveDestinationResolver>()));
    final result = await provider.apply(
      MailArchive(id: 'archive', message: _identity('one')),
      fixture.session.begin(),
    );
    _problem(result, MailProblemCode.unsupported);
    expect(
      (result as MailFailure<MailUnit>).problem.mutationMayHaveOccurred,
      isFalse,
    );
    expect(fixture.clients, isEmpty);
    expect(fixture.secrets, isEmpty);
  });

  for (final stableIdentity in [false, true]) {
    test(
      'MoveItem ${stableIdentity ? 'stable' : 'replacement'} ID is verified in the exact destination',
      () async {
        final fixture = _Fixture();
        final newId = stableIdentity ? 'one' : 'replacement-id';
        fixture.scripts.add([
          (
            'GetItem',
            (envelope) {
              expect(envelope, contains('item:ParentFolderId'));
              expect(envelope, isNot(contains('item:Subject')));
              return _response('GetItem', _membershipItem('one'));
            },
          ),
          (
            'MoveItem',
            (envelope) {
              expect(
                envelope,
                contains('<m:ReturnNewItemIds>true</m:ReturnNewItemIds>'),
              );
              expect(envelope, contains('Id="one" ChangeKey="current-key"'));
              return _response(
                'MoveItem',
                _success(
                  'MoveItem',
                  '<m:Items><t:Message><t:ItemId Id="$newId" ChangeKey="new-key"/></t:Message></m:Items>',
                ),
              );
            },
          ),
          if (!stableIdentity)
            (
              'GetItem',
              (envelope) {
                expect(envelope, contains('Id="one"'));
                return _response(
                  'GetItem',
                  _error('GetItem', 'ErrorItemNotFound'),
                );
              },
            ),
          (
            'GetItem',
            (envelope) {
              expect(envelope, contains('Id="$newId"'));
              expect(envelope, contains('item:ParentFolderId'));
              expect(envelope, isNot(contains('item:Subject')));
              return _response(
                'GetItem',
                _membershipItem(newId, parent: 'destination'),
              );
            },
          ),
        ]);
        final command = MailMove(
          id: 'move:0',
          message: _identity('one'),
          destination: MailMailboxId('destination', account: _account),
        );
        final receipt = _value(
          await fixture.provider().applyWithReceipt(
            command,
            fixture.session.begin(),
          ),
        );
        final transition = receipt.identityTransition!;
        expect(transition.matches(command, sourceMailbox: _mailbox), isTrue);
        expect(transition.destination, _identity(newId));
        expect(transition.destinationMessageId, ewsMessageId(_identity(newId)));
        expect(fixture.clients.single.steps, isEmpty);
        expect(
          fixture.clients.single.requests.where((request) => request.$3),
          hasLength(1),
        );
      },
    );
  }

  test(
    'MoveItem without returned ID preserves generic success after exact source check',
    () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        ('GetItem', (_) => _response('GetItem', _membershipItem('one'))),
        (
          'MoveItem',
          (_) => _response('MoveItem', _success('MoveItem', '<m:Items/>')),
        ),
        (
          'GetItem',
          (_) => _response('GetItem', _error('GetItem', 'ErrorItemNotFound')),
        ),
      ]);
      final receipt = _value(
        await fixture.provider().applyWithReceipt(
          MailMove(
            id: 'move:0',
            message: _identity('one'),
            destination: MailMailboxId('destination', account: _account),
          ),
          fixture.session.begin(),
        ),
      );
      expect(receipt.identityTransition, isNull);
      expect(
        fixture.clients.single.requests.where(
          (request) => request.$1 == 'GetItem',
        ),
        hasLength(2),
      );
      expect(fixture.clients.single.steps, isEmpty);
    },
  );

  test(
    'MoveItem to its observed source folder fails before mutation',
    () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        ('GetItem', (_) => _response('GetItem', _membershipItem('one'))),
      ]);
      final result = await fixture.provider().applyWithReceipt(
        MailMove(
          id: 'move:0',
          message: _identity('one'),
          destination: _mailbox,
        ),
        fixture.session.begin(),
      );
      _problem(result, MailProblemCode.invalidInput);
      expect(
        (result as MailFailure<MailMutationReceipt>)
            .problem
            .mutationMayHaveOccurred,
        isFalse,
      );
      expect(
        fixture.clients.single.requests.where((request) => request.$3),
        isEmpty,
      );
    },
  );

  for (final invalidDestination in [
    'wrong-id',
    'wrong-parent',
    'missing-parent',
    'missing-item',
  ]) {
    test(
      'MoveItem $invalidDestination evidence stays uncertain without inferred destination',
      () async {
        final fixture = _Fixture();
        fixture.scripts.add([
          ('GetItem', (_) => _response('GetItem', _membershipItem('one'))),
          (
            'MoveItem',
            (_) => _response(
              'MoveItem',
              _success(
                'MoveItem',
                '<m:Items><t:Message><t:ItemId Id="replacement" ChangeKey="new"/></t:Message></m:Items>',
              ),
            ),
          ),
          (
            'GetItem',
            (_) => _response('GetItem', _error('GetItem', 'ErrorItemNotFound')),
          ),
          (
            'GetItem',
            (_) => _response('GetItem', switch (invalidDestination) {
              'wrong-id' => _membershipItem('other', parent: 'destination'),
              'wrong-parent' => _membershipItem('replacement', parent: 'other'),
              'missing-parent' => _item('replacement', parent: null),
              _ => _error('GetItem', 'ErrorItemNotFound'),
            }),
          ),
        ]);
        final result = await fixture.provider().applyWithReceipt(
          MailMove(
            id: 'move:0',
            message: _identity('one'),
            destination: MailMailboxId('destination', account: _account),
          ),
          fixture.session.begin(),
        );
        _problem(result, MailProblemCode.conflict);
        expect(
          (result as MailFailure<MailMutationReceipt>)
              .problem
              .mutationMayHaveOccurred,
          isTrue,
        );
        expect(
          fixture.clients.single.requests.where((request) => request.$3),
          hasLength(1),
        );
        expect(fixture.clients.single.steps, isEmpty);
      },
    );
  }

  for (final payload in [
    '<m:Items><t:Message><t:ItemId Id="replacement" ChangeKey="key"/></t:Message><t:Message><t:ItemId Id="extra" ChangeKey="key"/></t:Message></m:Items>',
    '<m:Items><t:Message><t:ItemId Id="" ChangeKey="key"/></t:Message></m:Items>',
    '<m:Items><t:Message><t:ItemId Id="replacement"/></t:Message></m:Items>',
  ]) {
    test(
      'MoveItem malformed ID response is uncertain without a replacement lookup ($payload)',
      () async {
        final fixture = _Fixture();
        fixture.scripts.add([
          ('GetItem', (_) => _response('GetItem', _membershipItem('one'))),
          (
            'MoveItem',
            (_) => _response('MoveItem', _success('MoveItem', payload)),
          ),
        ]);
        final result = await fixture.provider().applyWithReceipt(
          MailMove(
            id: 'move:0',
            message: _identity('one'),
            destination: MailMailboxId('destination', account: _account),
          ),
          fixture.session.begin(),
        );
        _problem(result, MailProblemCode.conflict);
        expect(
          (result as MailFailure<MailMutationReceipt>)
              .problem
              .mutationMayHaveOccurred,
          isTrue,
        );
        expect(fixture.clients.single.requests, hasLength(2));
      },
    );
  }

  test('capabilities explicitly include recoverable delete', () async {
    final fixture = _Fixture();
    fixture.scripts.add([
      (
        'GetFolder',
        (_) => _response(
          'GetFolder',
          _success(
            'GetFolder',
            '<m:Folders>${_folder('inbox-id')}</m:Folders>',
          ),
        ),
      ),
    ]);
    final capabilities = _value(
      await fixture.provider().capabilities(fixture.session.begin()),
    );
    expect(capabilities.supports(MailCapability.move), isTrue);
    expect(capabilities.supports(MailCapability.delete), isTrue);
    expect(fixture.clients.single.mutationStarted, isFalse);
  });

  test('oversize move destination is rejected before credentials', () async {
    final fixture = _Fixture();
    final result = await fixture.provider().apply(
      MailMove(
        id: 'invalid-destination',
        message: _identity('one'),
        destination: MailMailboxId('x' * 1025, account: _account),
      ),
      fixture.session.begin(),
    );
    _problem(result, MailProblemCode.invalidInput);
    expect(
      (result as MailFailure<MailUnit>).problem.mutationMayHaveOccurred,
      isFalse,
    );
    expect(fixture.vault.loads, 0);
    expect(fixture.clients, isEmpty);
  });

  for (final action in [MailBulkFlagAction.move, MailBulkFlagAction.delete]) {
    for (final lostReply in [true, false]) {
      test(
        '${action.name} ${lostReply ? 'lost reply' : 'source still present'} stays uncertain without replay',
        () async {
          final fixture = _Fixture();
          final soapAction = action == MailBulkFlagAction.move
              ? 'MoveItem'
              : 'DeleteItem';
          fixture.scripts.add([
            ('GetItem', (_) => _response('GetItem', _item('one'))),
            (
              soapAction,
              (envelope) {
                expect(envelope, contains('Id="one" ChangeKey="fresh-key"'));
                expect(envelope, isNot(contains('HardDelete')));
                if (action == MailBulkFlagAction.delete) {
                  expect(envelope, contains('DeleteType="MoveToDeletedItems"'));
                } else {
                  expect(envelope, contains('Id="destination"'));
                }
                if (lostReply) {
                  throw const EwsException(MailProblemCode.unavailable);
                }
                return _response(
                  soapAction,
                  _success(
                    soapAction,
                    action == MailBulkFlagAction.move
                        ? '<m:Items><t:Message><t:ItemId Id="moved-id" ChangeKey="new"/></t:Message></m:Items>'
                        : '',
                  ),
                );
              },
            ),
            if (!lostReply)
              ('GetItem', (_) => _response('GetItem', _item('one'))),
          ]);
          final provider = fixture.provider();
          final report = await MailBulkFlagRunner().run(
            plan: MailBulkFlagPlan(
              id: 'membership-evidence',
              mailbox: _mailbox,
              action: action,
              destination: action == MailBulkFlagAction.move
                  ? MailMailboxId('destination', account: _account)
                  : null,
              messages: [_identity('one'), _identity('two')],
            ),
            lease: fixture.session.begin(),
            apply: provider.apply,
            isScopeCurrent: () => true,
          );
          expect(report.uncertainCount, 1);
          expect(report.unattemptedCount, 1);
          expect(report.items.first.problem?.mutationMayHaveOccurred, isTrue);
          expect(report.requiresRefresh, isTrue);
          expect(fixture.clients, hasLength(1));
          expect(
            fixture.clients.single.requests.where((request) => request.$3),
            hasLength(1),
          );
          expect(fixture.clients.single.steps, isEmpty);
        },
      );
    }
  }

  group('read-only membership observation', () {
    for (final parent in ['inbox-id', 'Archive_CASE', 'trash-id']) {
      test(
        'observes original EWS identity currently in $parent without flags or MIME',
        () async {
          final fixture = _Fixture();
          fixture.scripts.add([
            (
              'GetItem',
              (request) {
                expect(request, contains('FieldURI="item:ParentFolderId"'));
                expect(request, isNot(contains('message:IsRead')));
                expect(request, isNot(contains('item:Subject')));
                expect(request, isNot(contains('ExtendedFieldURI')));
                expect(request, isNot(contains('IncludeMimeContent')));
                return _response(
                  'GetItem',
                  _membershipItem('one', parent: parent),
                );
              },
            ),
            (
              'GetFolder',
              (request) {
                expect(
                  request,
                  contains('DistinguishedFolderId Id="deleteditems"'),
                );
                return _deletedItems();
              },
            ),
          ]);
          final observed = _value(
            await fixture.provider().observeMembership(
              _identity('one'),
              lease: fixture.session.begin(),
            ),
          );
          expect(observed.kind, MailMembershipObservationKind.present);
          expect(observed.identity, _identity('one'));
          expect(observed.mailboxes, [
            MailMailboxId(parent, account: _account),
          ]);
          expect(
            observed.deletionMailbox,
            MailMailboxId('trash-id', account: _account),
          );
          expect(observed.isDeleted, parent == 'trash-id');
          expect(
            fixture.clients.single.requests.every((request) => !request.$3),
            isTrue,
          );
          expect(fixture.clients.single.mutationStarted, isFalse);
          expect(fixture.clients.single.aborted, isTrue);
          expect(fixture.clients.single.steps, isEmpty);
        },
      );
    }

    test(
      'original EWS item not found leaves replacement and destination unknown',
      () async {
        final fixture = _Fixture();
        fixture.scripts.add([
          (
            'GetItem',
            (_) => _response('GetItem', _error('GetItem', 'ErrorItemNotFound')),
          ),
        ]);
        final observed = _value(
          await fixture.provider().observeMembership(
            _identity('one'),
            lease: fixture.session.begin(),
          ),
        );
        expect(observed.kind, MailMembershipObservationKind.missing);
        expect(observed.identity, _identity('one'));
        expect(observed.mailboxes, isEmpty);
        expect(observed.isDeleted, isNull);
        expect(fixture.clients.single.requests.map((request) => request.$1), [
          'GetItem',
        ]);
        expect(fixture.clients.single.mutationStarted, isFalse);
      },
    );

    for (final (name, fields) in [
      ('omitted', ''),
      ('no ID', '<t:ParentFolderId/>'),
      ('empty ID', '<t:ParentFolderId Id=""/>'),
      (
        'duplicate parent',
        '<t:ParentFolderId Id="a"/><t:ParentFolderId Id="b"/>',
      ),
      ('wrong namespace', '<m:ParentFolderId Id="a"/>'),
      (
        'nested content',
        '<t:ParentFolderId Id="a"><t:Folder/></t:ParentFolderId>',
      ),
      ('oversized ID', '<t:ParentFolderId Id="${'x' * 1025}"/>'),
    ]) {
      test('$name parent is rejected before Deleted Items lookup', () async {
        final fixture = _Fixture();
        fixture.scripts.add([
          (
            'GetItem',
            (_) => _response(
              'GetItem',
              _success(
                'GetItem',
                '<m:Items><t:Message><t:ItemId Id="one" ChangeKey="key"/>$fields</t:Message></m:Items>',
              ),
            ),
          ),
        ]);
        final result = await fixture.provider().observeMembership(
          _identity('one'),
          lease: fixture.session.begin(),
        );
        _problem(result, MailProblemCode.providerFailure);
        expect(
          (result as MailFailure<MailMembershipObservation>)
              .problem
              .mutationMayHaveOccurred,
          isFalse,
        );
        expect(fixture.clients.single.requests, hasLength(1));
      });
    }

    test(
      'a different returned EWS ID cannot be rebound to the request',
      () async {
        final fixture = _Fixture();
        fixture.scripts.add([
          ('GetItem', (_) => _response('GetItem', _membershipItem('other'))),
        ]);
        _problem(
          await fixture.provider().observeMembership(
            _identity('one'),
            lease: fixture.session.begin(),
          ),
          MailProblemCode.providerFailure,
        );
        expect(fixture.clients.single.requests, hasLength(1));
      },
    );

    test('permission failure is not an absence observation', () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        (
          'GetItem',
          (_) => _response('GetItem', _error('GetItem', 'ErrorAccessDenied')),
        ),
      ]);
      _problem(
        await fixture.provider().observeMembership(
          _identity('one'),
          lease: fixture.session.begin(),
        ),
        MailProblemCode.permissionDenied,
      );
      expect(fixture.clients.single.mutationStarted, isFalse);
    });

    test(
      'unavailable Deleted Items cannot make a present original ID missing',
      () async {
        final fixture = _Fixture();
        fixture.scripts.add([
          ('GetItem', (_) => _response('GetItem', _membershipItem('one'))),
          (
            'GetFolder',
            (_) => _response(
              'GetFolder',
              _error('GetFolder', 'ErrorAccessDenied'),
            ),
          ),
        ]);
        _problem(
          await fixture.provider().observeMembership(
            _identity('one'),
            lease: fixture.session.begin(),
          ),
          MailProblemCode.permissionDenied,
        );
        expect(
          fixture.clients.single.requests.every((request) => !request.$3),
          isTrue,
        );
      },
    );

    for (final payload in [
      '',
      _folder('calendar', kind: 'IPF.Appointment'),
      _folder('a') + _folder('b'),
    ]) {
      test(
        'invalid Deleted Items collection (${payload.length}) fails the check',
        () async {
          final fixture = _Fixture();
          fixture.scripts.add([
            ('GetItem', (_) => _response('GetItem', _membershipItem('one'))),
            (
              'GetFolder',
              (_) => _response(
                'GetFolder',
                _success('GetFolder', '<m:Folders>$payload</m:Folders>'),
              ),
            ),
          ]);
          _problem(
            await fixture.provider().observeMembership(
              _identity('one'),
              lease: fixture.session.begin(),
            ),
            MailProblemCode.providerFailure,
          );
          expect(fixture.clients.single.mutationStarted, isFalse);
        },
      );
    }

    test(
      'scope and stale leases are rejected without credentials or requests',
      () async {
        final fixture = _Fixture();
        final provider = fixture.provider();
        final other = MailAccountId('other', profile: _account.profile);
        _problem(
          await provider.observeMembership(
            MailOpaqueIdentity(
              account: other,
              provider: MailProviderKind.ews,
              value: 'one',
            ),
            lease: fixture.session.begin(),
          ),
          MailProblemCode.invalidInput,
        );
        _problem(
          await provider.observeMembership(
            MailOpaqueIdentity(
              account: _account,
              provider: MailProviderKind.graph,
              value: 'one',
            ),
            lease: fixture.session.begin(),
          ),
          MailProblemCode.invalidInput,
        );
        _problem(
          await provider.observeMembership(
            _identity('one'),
            lease: MailAccountSession(other).begin(),
          ),
          MailProblemCode.invalidInput,
        );
        final stale = fixture.session.begin();
        fixture.session.invalidate();
        _problem(
          await provider.observeMembership(_identity('one'), lease: stale),
          MailProblemCode.staleOperation,
        );
        final cancellation = MailCancellationSource();
        final cancelled = fixture.session.begin(
          cancellation: cancellation.token,
        );
        cancellation.cancel();
        _problem(
          await provider.observeMembership(_identity('one'), lease: cancelled),
          MailProblemCode.cancelled,
        );
        expect(fixture.vault.loads, 0);
        expect(fixture.clients, isEmpty);
      },
    );

    for (final duringFolder in [false, true]) {
      test(
        'cancelling during ${duringFolder ? 'folder' : 'item'} read discards partial evidence',
        () async {
          final fixture = _Fixture();
          final started = Completer<void>();
          final release = Completer<String>();
          fixture.scripts.add([
            (
              'GetItem',
              (_) {
                if (!duringFolder) {
                  started.complete();
                  return release.future;
                }
                return _response('GetItem', _membershipItem('one'));
              },
            ),
            if (duringFolder)
              (
                'GetFolder',
                (_) {
                  started.complete();
                  return release.future;
                },
              ),
          ]);
          final cancellation = MailCancellationSource();
          final pending = fixture.provider().observeMembership(
            _identity('one'),
            lease: fixture.session.begin(cancellation: cancellation.token),
          );
          await started.future;
          cancellation.cancel();
          _problem(await pending, MailProblemCode.cancelled);
          release.complete(
            duringFolder
                ? _deletedItems()
                : _response('GetItem', _membershipItem('one')),
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            fixture.clients.single.requests,
            hasLength(duringFolder ? 2 : 1),
          );
          expect(fixture.clients.single.mutationStarted, isFalse);
        },
      );
    }
  });

  group('read-only flag observation', () {
    test(
      'reads exact current flags without envelope, MIME or mutation',
      () async {
        final fixture = _Fixture();
        fixture.scripts.add([
          (
            'GetItem',
            (request) {
              expect(request, contains('Id="one"'));
              expect(request, contains('FieldURI="message:IsRead"'));
              expect(request, contains('FieldURI="item:Flag"'));
              expect(request, isNot(contains('IncludeMimeContent')));
              expect(request, isNot(contains('item:Body')));
              expect(request, isNot(contains('item:Subject')));
              expect(request, isNot(contains('message:From')));
              return _response(
                'GetItem',
                _item('one', read: true, flagged: true),
              );
            },
          ),
        ]);
        final observed = _value(
          await fixture.provider().observeFlags(
            _identity('one'),
            lease: fixture.session.begin(),
          ),
        );
        expect(observed.kind, MailFlagObservationKind.present);
        expect(observed.identity, _identity('one'));
        expect(
          observed.flags,
          const MailMessageFlags(isRead: true, isFlagged: true),
        );
        expect(fixture.clients.single.requests.single.$3, isFalse);
        expect(fixture.clients.single.mutationStarted, isFalse);
        expect(fixture.clients.single.aborted, isTrue);
      },
    );

    test('explicit item-not-found is current absence only', () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        (
          'GetItem',
          (_) => _response('GetItem', _error('GetItem', 'ErrorItemNotFound')),
        ),
      ]);
      final observed = _value(
        await fixture.provider().observeFlags(
          _identity('gone'),
          lease: fixture.session.begin(),
        ),
      );
      expect(observed.kind, MailFlagObservationKind.missing);
      expect(observed.identity, _identity('gone'));
      expect(observed.flags, isNull);
      expect(fixture.clients.single.mutationStarted, isFalse);
    });

    for (final removed in [
      '<t:IsRead>false</t:IsRead>',
      '<t:IsDraft>false</t:IsDraft>',
      '<t:Flag><t:FlagStatus>NotFlagged</t:FlagStatus></t:Flag>',
    ]) {
      test('omitted $removed does not fabricate a known false', () async {
        final fixture = _Fixture();
        fixture.scripts.add([
          (
            'GetItem',
            (_) => _response('GetItem', _item('one').replaceFirst(removed, '')),
          ),
        ]);
        _problem(
          await fixture.provider().observeFlags(
            _identity('one'),
            lease: fixture.session.begin(),
          ),
          MailProblemCode.providerFailure,
        );
        expect(fixture.clients.single.mutationStarted, isFalse);
      });
    }

    test('wrong response identity and denied access are not missing', () async {
      final fixture = _Fixture();
      fixture.scripts.addAll([
        [('GetItem', (_) => _response('GetItem', _item('other')))],
        [
          (
            'GetItem',
            (_) => _response('GetItem', _error('GetItem', 'ErrorAccessDenied')),
          ),
        ],
      ]);
      final provider = fixture.provider();
      _problem(
        await provider.observeFlags(
          _identity('one'),
          lease: fixture.session.begin(),
        ),
        MailProblemCode.providerFailure,
      );
      _problem(
        await provider.observeFlags(
          _identity('one'),
          lease: fixture.session.begin(),
        ),
        MailProblemCode.permissionDenied,
      );
      expect(
        fixture.clients.every((client) => !client.mutationStarted),
        isTrue,
      );
    });

    test(
      'wrong provider/account and stale lease avoid credentials and IO',
      () async {
        final fixture = _Fixture();
        final provider = fixture.provider();
        _problem(
          await provider.observeFlags(
            MailOpaqueIdentity(
              account: _account,
              provider: MailProviderKind.gmail,
              value: 'one',
            ),
            lease: fixture.session.begin(),
          ),
          MailProblemCode.invalidInput,
        );
        final other = MailAccountId('other', profile: _account.profile);
        _problem(
          await provider.observeFlags(
            MailOpaqueIdentity(
              account: other,
              provider: MailProviderKind.ews,
              value: 'one',
            ),
            lease: fixture.session.begin(),
          ),
          MailProblemCode.invalidInput,
        );
        _problem(
          await provider.observeFlags(
            _identity('one'),
            lease: MailAccountSession(other).begin(),
          ),
          MailProblemCode.invalidInput,
        );
        final stale = fixture.session.begin();
        fixture.session.invalidate();
        _problem(
          await provider.observeFlags(_identity('one'), lease: stale),
          MailProblemCode.staleOperation,
        );
        expect(fixture.vault.loads, 0);
        expect(fixture.clients, isEmpty);
      },
    );

    test(
      'late observation cannot survive cancellation or account retirement',
      () async {
        final fixture = _Fixture();
        final started = Completer<void>();
        final released = Completer<String>();
        fixture.scripts.add([
          (
            'GetItem',
            (_) {
              started.complete();
              return released.future;
            },
          ),
        ]);
        final pending = fixture.provider().observeFlags(
          _identity('one'),
          lease: fixture.session.begin(),
        );
        await started.future;
        fixture.session.invalidate();
        _problem(await pending, MailProblemCode.staleOperation);
        released.complete(_response('GetItem', _item('one', read: true)));
        await Future<void>.delayed(Duration.zero);
        expect(fixture.clients.single.aborted, isTrue);
        expect(fixture.clients.single.mutationStarted, isFalse);
      },
    );
  });

  test(
    'bulk EWS reports acknowledged, definite, uncertain and untouched identities',
    () async {
      final fixture = _Fixture();
      fixture.scripts.addAll([
        [('GetItem', (_) => _response('GetItem', _item('one', read: true)))],
        [
          (
            'GetItem',
            (_) => _response('GetItem', _error('GetItem', 'ErrorItemNotFound')),
          ),
        ],
        [
          ('GetItem', (_) => _response('GetItem', _item('three'))),
          (
            'UpdateItem',
            (_) => throw const EwsException(MailProblemCode.unavailable),
          ),
        ],
      ]);
      final provider = fixture.provider();
      final report = await MailBulkFlagCoordinator().run(
        plan: MailBulkFlagPlan(
          id: 'ews-bulk',
          mailbox: _mailbox,
          provider: MailProviderKind.ews,
          action: MailBulkFlagAction.markRead,
          messages: [
            _identity('one'),
            _identity('two'),
            _identity('three'),
            _identity('four'),
          ],
        ),
        lease: fixture.session.begin(),
        apply: (operation, lease) async => MailBulkFlagAttempt.fromResult(
          await provider.apply(operation, lease),
        ),
        isScopeCurrent: () => true,
      );
      expect(report.items.map((result) => result.outcome), [
        MailBulkFlagOutcome.confirmed,
        MailBulkFlagOutcome.failed,
        MailBulkFlagOutcome.uncertain,
        MailBulkFlagOutcome.unattempted,
      ]);
      expect(report.items[1].problem?.mutationMayHaveOccurred, isFalse);
      expect(report.items[2].problem?.mutationMayHaveOccurred, isTrue);
      expect(fixture.clients, hasLength(3));
      expect(
        fixture.clients
            .expand((client) => client.requests)
            .where((request) => request.$3),
        hasLength(1),
      );
      expect(report.requiresRefresh, isTrue);
    },
  );

  test(
    'initial sync coalesces changes and loads complete headers once',
    () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        (
          'SyncFolderItems',
          (body) {
            expect(body, isNot(contains('<m:SyncState>')));
            expect(body, contains('<t:BaseShape>IdOnly</t:BaseShape>'));
            return _sync(
              'state-one',
              '${_change('Create', 'one')}'
                  '${_change('Update', 'one')}'
                  '${_change('Create', 'two')}'
                  '${_change('Delete', 'two')}'
                  '<t:ReadFlagChange><t:ItemId Id="three"/>'
                  '<t:IsRead>true</t:IsRead></t:ReadFlagChange>',
            );
          },
        ),
        (
          'GetItem',
          (body) {
            expect(body, contains('Id="one"'));
            expect(body, contains('Id="three"'));
            expect(body, isNot(contains('Id="two"')));
            expect(body, isNot(contains('IncludeMimeContent')));
            return _response(
              'GetItem',
              _item('one') + _item('three', read: true),
            );
          },
        ),
      ]);
      final page = _value(
        await fixture.provider().pullChanges(
          _mailbox,
          limit: 10,
          lease: fixture.session.begin(),
        ),
      );
      expect(page.resetRequired, isTrue);
      expect(page.hasMore, isFalse);
      expect(
        page.upserts.map((item) => (item.remote as MailOpaqueIdentity).value),
        ['one', 'three'],
      );
      expect(page.upserts.last.flags?.isRead, isTrue);
      expect(page.tombstones, [_identity('two')]);
      expect(page.next.value, contains('state-one'));
      expect(fixture.clients.single.aborted, isTrue);
    },
  );

  test('repeated empty SyncState advances durable revision', () async {
    final fixture = _Fixture();
    fixture.scripts.addAll([
      [('SyncFolderItems', (_) => _sync('unchanged', ''))],
      [('SyncFolderItems', (_) => _sync('unchanged', ''))],
    ]);
    final provider = fixture.provider();
    final first = _value(
      await provider.pullChanges(
        _mailbox,
        limit: 1,
        lease: fixture.session.begin(),
      ),
    );
    final second = _value(
      await provider.pullChanges(
        _mailbox,
        cursor: first.next,
        limit: 1,
        lease: fixture.session.begin(),
      ),
    );
    expect(first.next.value, isNot(second.next.value));
    expect(second.resetRequired, isFalse);
    expect(second.upserts, isEmpty);
  });

  test(
    'expired server state resets exactly once and retains revision',
    () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        (
          'SyncFolderItems',
          (_) => _response(
            'SyncFolderItems',
            _error('SyncFolderItems', 'ErrorInvalidSyncStateData'),
          ),
        ),
        (
          'SyncFolderItems',
          (body) {
            expect(body, isNot(contains('<m:SyncState>')));
            return _sync('new-state', '', last: false);
          },
        ),
      ]);
      final cursor = const EwsSyncCursor(
        state: 'expired',
        revision: 7,
      ).encode(_configuration(), _mailbox, const MailEwsLimits());
      final page = _value(
        await fixture.provider().pullChanges(
          _mailbox,
          cursor: cursor,
          limit: 1,
          lease: fixture.session.begin(),
        ),
      );
      expect(page.resetRequired, isTrue);
      expect(page.hasMore, isTrue);
      expect(
        EwsSyncCursor.decode(
          page.next,
          _configuration(),
          _mailbox,
          const MailEwsLimits(),
        )!.revision,
        8,
      );
    },
  );

  test('unrelated server conflict does not reset mailbox cache', () async {
    final fixture = _Fixture();
    fixture.scripts.add([
      (
        'SyncFolderItems',
        (_) => _response(
          'SyncFolderItems',
          _error('SyncFolderItems', 'ErrorIrresolvableConflict'),
        ),
      ),
    ]);
    final cursor = const EwsSyncCursor(
      state: 'valid-state',
      revision: 4,
    ).encode(_configuration(), _mailbox, const MailEwsLimits());
    _problem(
      await fixture.provider().pullChanges(
        _mailbox,
        cursor: cursor,
        limit: 1,
        lease: fixture.session.begin(),
      ),
      MailProblemCode.conflict,
    );
    expect(fixture.clients.single.requests, hasLength(1));
  });

  test('concurrent confirmed disappearance is a tombstone', () async {
    final fixture = _Fixture();
    fixture.scripts.add([
      ('SyncFolderItems', (_) => _sync('s1', _change('Create', 'gone'))),
      (
        'GetItem',
        (_) => _response('GetItem', _error('GetItem', 'ErrorItemNotFound')),
      ),
    ]);
    final page = _value(
      await fixture.provider().pullChanges(
        _mailbox,
        limit: 1,
        lease: fixture.session.begin(),
      ),
    );
    expect(page.upserts, isEmpty);
    expect(page.tombstones, [_identity('gone')]);
  });

  test(
    'omitted/mismatched GetItem results never become deletion success',
    () async {
      for (final response in ['', _item('unrequested')]) {
        final fixture = _Fixture();
        fixture.scripts.add([
          ('SyncFolderItems', (_) => _sync('s1', _change('Create', 'one'))),
          ('GetItem', (_) => _response('GetItem', response)),
        ]);
        _problem(
          await fixture.provider().pullChanges(
            _mailbox,
            limit: 1,
            lease: fixture.session.begin(),
          ),
          MailProblemCode.providerFailure,
        );
      }
    },
  );

  test(
    'cursor from another endpoint is rejected before vault access',
    () async {
      final fixture = _Fixture();
      final cursor = const EwsSyncCursor(state: 'state', revision: 1).encode(
        _configuration(host: 'other.example.test'),
        _mailbox,
        const MailEwsLimits(),
      );
      _problem(
        await fixture.provider().pullChanges(
          _mailbox,
          cursor: cursor,
          limit: 1,
          lease: fixture.session.begin(),
        ),
        MailProblemCode.invalidInput,
      );
      expect(fixture.vault.loads, 0);
    },
  );

  test(
    'revision exhaustion and invalid budgets fail before vault access',
    () async {
      final fixture = _Fixture();
      final provider = fixture.provider();
      final cursor = const EwsSyncCursor(
        state: 'state',
        revision: ewsMaxRevision,
      ).encode(_configuration(), _mailbox, const MailEwsLimits());
      _problem(
        await provider.pullChanges(
          _mailbox,
          cursor: cursor,
          limit: 1,
          lease: fixture.session.begin(),
        ),
        MailProblemCode.invalidInput,
      );
      _problem(
        await provider.pullChanges(
          _mailbox,
          limit: 513,
          lease: fixture.session.begin(),
        ),
        MailProblemCode.invalidInput,
      );
      expect(fixture.vault.loads, 0);
    },
  );

  test('FindFolder paginates and excludes non-mail folder classes', () async {
    final fixture = _Fixture();
    fixture.scripts.add([
      (
        'FindFolder',
        (_) => _response(
          'FindFolder',
          _success(
            'FindFolder',
            '<m:RootFolder IncludesLastItemInRange="false" IndexedPagingOffset="2"><t:Folders>${_folder('inbox')}${_folder('calendar', kind: 'IPF.Appointment')}</t:Folders></m:RootFolder>',
          ),
        ),
      ),
      (
        'FindFolder',
        (body) {
          expect(body, contains('Offset="2"'));
          return _response(
            'FindFolder',
            _success(
              'FindFolder',
              '<m:RootFolder IncludesLastItemInRange="true"><t:Folders>${_folder('archive')}</t:Folders></m:RootFolder>',
            ),
          );
        },
      ),
    ]);
    final folders = _value(
      await fixture.provider().listMailboxes(fixture.session.begin()),
    );
    expect(folders.map((folder) => folder.id.value), ['inbox', 'archive']);
  });

  test(
    'FindFolder duplicate page fails instead of looping/partial success',
    () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        (
          'FindFolder',
          (_) => _response(
            'FindFolder',
            _success(
              'FindFolder',
              '<m:RootFolder IncludesLastItemInRange="false" IndexedPagingOffset="0"><t:Folders>${_folder('inbox')}</t:Folders></m:RootFolder>',
            ),
          ),
        ),
      ]);
      _problem(
        await fixture.provider().listMailboxes(fixture.session.begin()),
        MailProblemCode.providerFailure,
      );
    },
  );

  test('header browsing has a separate continuation cursor', () async {
    final fixture = _Fixture();
    fixture.scripts.add([
      (
        'FindItem',
        (_) => _response(
          'FindItem',
          _success(
            'FindItem',
            '<m:RootFolder IncludesLastItemInRange="false" IndexedPagingOffset="1"><t:Items><t:Message><t:ItemId Id="one" ChangeKey="key"/></t:Message></t:Items></m:RootFolder>',
          ),
        ),
      ),
      ('GetItem', (_) => _response('GetItem', _item('one'))),
    ]);
    final page = _value(
      await fixture.provider().fetchHeaders(
        _mailbox,
        limit: 1,
        lease: fixture.session.begin(),
      ),
    );
    expect(page.messages, hasLength(1));
    expect(
      EwsHeaderCursor.decode(page.next, _configuration(), _mailbox).offset,
      1,
    );
    expect(
      () => EwsSyncCursor.decode(
        page.next,
        _configuration(),
        _mailbox,
        const MailEwsLimits(),
      ),
      throwsA(isA<EwsException>()),
    );
  });

  test(
    'MIME fetch preserves returned bytes and stable opaque identity',
    () async {
      final fixture = _Fixture();
      final raw = _prepared().wire.bytes;
      fixture.scripts.add([
        (
          'GetItem',
          (body) {
            expect(
              body,
              contains('<t:IncludeMimeContent>true</t:IncludeMimeContent>'),
            );
            return _response('GetItem', _item('one', mime: raw));
          },
        ),
      ]);
      final message = _value(
        await fixture.provider().fetchMessage(
          _identity('one'),
          budget: const MailReadBudget(),
          lease: fixture.session.begin(),
        ),
      );
      expect(message.raw.bytes, raw);
      expect(message.remoteIdentity, _identity('one'));
      expect(message.localId, ewsMessageId(_identity('one')));
      expect(message.body.plainText, contains('Hello.'));
    },
  );

  test('flag update uses fresh key and verifies observed flags', () async {
    final fixture = _Fixture();
    fixture.scripts.add([
      (
        'GetItem',
        (_) => _response('GetItem', _item('one', key: 'current-key')),
      ),
      (
        'UpdateItem',
        (body) {
          expect(body, contains('ChangeKey="current-key"'));
          expect(body, contains('ConflictResolution="NeverOverwrite"'));
          return _response(
            'UpdateItem',
            _success(
              'UpdateItem',
              '<m:Items><t:Message><t:ItemId Id="one" ChangeKey="new-key"/></t:Message></m:Items>',
            ),
          );
        },
      ),
      (
        'GetItem',
        (_) => _response('GetItem', _item('one', key: 'new-key', read: true)),
      ),
    ]);
    _value(
      await fixture.provider().apply(
        MailSetRead(id: 'read', message: _identity('one'), read: true),
        fixture.session.begin(),
      ),
    );
    expect(fixture.clients.single.requests.map((request) => request.$3), [
      false,
      true,
      false,
    ]);
  });

  test(
    'successful acknowledgment without changed flags requires reconciliation',
    () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        ('GetItem', (_) => _response('GetItem', _item('one'))),
        (
          'UpdateItem',
          (_) => _response(
            'UpdateItem',
            _success(
              'UpdateItem',
              '<m:Items><t:Message><t:ItemId Id="one" ChangeKey="new-key"/></t:Message></m:Items>',
            ),
          ),
        ),
        ('GetItem', (_) => _response('GetItem', _item('one'))),
      ]);
      _problem(
        await fixture.provider().apply(
          MailSetFlagged(id: 'flag', message: _identity('one'), flagged: true),
          fixture.session.begin(),
        ),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'delete moves to Deleted Items and confirms old identity absence',
    () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        ('GetItem', (_) => _response('GetItem', _item('one'))),
        (
          'DeleteItem',
          (body) {
            expect(body, contains('DeleteType="MoveToDeletedItems"'));
            expect(body, isNot(contains('HardDelete')));
            return _response('DeleteItem', _success('DeleteItem', ''));
          },
        ),
        (
          'GetItem',
          (_) => _response('GetItem', _error('GetItem', 'ErrorItemNotFound')),
        ),
      ]);
      _value(
        await fixture.provider().apply(
          MailDelete(id: 'delete', message: _identity('one')),
          fixture.session.begin(),
        ),
      );
    },
  );

  test('lost write response is conflict and is never replayed', () async {
    final fixture = _Fixture();
    fixture.scripts.add([
      ('GetItem', (_) => _response('GetItem', _item('one'))),
      (
        'DeleteItem',
        (_) => throw const EwsException(MailProblemCode.unavailable),
      ),
    ]);
    final result = await fixture.provider().apply(
      MailDelete(id: 'delete', message: _identity('one')),
      fixture.session.begin(),
    );
    _problem(result, MailProblemCode.conflict);
    expect((result as MailFailure<MailUnit>).problem.retryAfter, isNull);
    expect(fixture.clients.single.requests, hasLength(2));
  });

  test(
    'submission keeps hidden recipients separate and reports aggregate acceptance',
    () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        (
          'CreateItem',
          (body) {
            expect(body, contains('MessageDisposition="SendAndSaveCopy"'));
            expect(
              body,
              contains(
                '<t:BccRecipients><t:Mailbox><t:EmailAddress>hidden@example.test</t:EmailAddress>',
              ),
            );
            expect(
              body,
              contains(
                '<t:ToRecipients><t:Mailbox><t:EmailAddress>visible@example.test</t:EmailAddress>',
              ),
            );
            expect(body, contains(base64.encode(_prepared().wire.bytes)));
            return _response('CreateItem', _success('CreateItem', ''));
          },
        ),
      ]);
      final result = await fixture.provider().submit(
        _prepared(),
        attemptId: 'attempt-one',
        lease: fixture.session.begin(),
      );
      expect(result.outcome, MailSubmissionOutcome.accepted);
      expect(result.recipients, isEmpty);
      expect(
        result.submissionFor('hidden@example.test'),
        MailRecipientSubmission.unknown,
      );
    },
  );

  test(
    'submission refuses MIME/envelope mismatch before vault access',
    () async {
      final fixture = _Fixture();
      final result = await fixture.provider().submit(
        _prepared(recipients: ['wrong@example.test']),
        attemptId: 'attempt',
        lease: fixture.session.begin(),
      );
      expect(result.outcome, MailSubmissionOutcome.rejected);
      expect(result.problem?.code, MailProblemCode.invalidInput);
      expect(fixture.vault.loads, 0);
    },
  );

  test(
    'lost submission response is uncertain without retry hint or replay',
    () async {
      final fixture = _Fixture();
      fixture.scripts.add([
        (
          'CreateItem',
          (_) => throw const EwsException(MailProblemCode.unavailable),
        ),
      ]);
      final result = await fixture.provider().submit(
        _prepared(),
        attemptId: 'attempt',
        lease: fixture.session.begin(),
      );
      expect(result.outcome, MailSubmissionOutcome.uncertain);
      expect(result.problem?.retryAfter, isNull);
      expect(fixture.clients.single.requests, hasLength(1));
    },
  );

  test(
    'current vault credentials are loaded again for every operation',
    () async {
      final fixture = _Fixture();
      fixture.scripts.addAll([
        [('SyncFolderItems', (_) => _sync('one', ''))],
        [('SyncFolderItems', (_) => _sync('two', ''))],
      ]);
      final provider = fixture.provider();
      _value(
        await provider.pullChanges(
          _mailbox,
          limit: 1,
          lease: fixture.session.begin(),
        ),
      );
      fixture.vault.password = 'rotated-password';
      _value(
        await provider.pullChanges(
          _mailbox,
          limit: 1,
          lease: fixture.session.begin(),
        ),
      );
      expect(fixture.secrets, ['first-password', 'rotated-password']);
      fixture.vault.missing = true;
      _problem(
        await provider.pullChanges(
          _mailbox,
          limit: 1,
          lease: fixture.session.begin(),
        ),
        MailProblemCode.authenticationRequired,
      );
      expect(fixture.clients, hasLength(2));
    },
  );

  test('cancelled pending vault read cannot open a late connection', () async {
    final fixture = _Fixture();
    final gate = Completer<void>();
    fixture.vault.beforeLoad = () => gate.future;
    final cancellation = MailCancellationSource();
    final provider = fixture.provider(
      limits: const MailEwsLimits(
        cancellationPollInterval: Duration(milliseconds: 1),
      ),
    );
    final pending = provider.pullChanges(
      _mailbox,
      limit: 1,
      lease: fixture.session.begin(cancellation: cancellation.token),
    );
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    _problem(await pending, MailProblemCode.cancelled);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.clients, isEmpty);
    expect(fixture.secrets, isEmpty);
  });

  test(
    'timeout aborts pending request and provider accepts fresh work',
    () async {
      final fixture = _Fixture();
      final gate = Completer<String>();
      fixture.scripts.addAll([
        [('SyncFolderItems', (_) => gate.future)],
        [('SyncFolderItems', (_) => _sync('fresh', ''))],
      ]);
      final provider = fixture.provider(
        limits: const MailEwsLimits(
          operationTimeout: Duration(milliseconds: 30),
        ),
      );
      _problem(
        await provider.pullChanges(
          _mailbox,
          limit: 1,
          lease: fixture.session.begin(),
        ),
        MailProblemCode.unavailable,
      );
      expect(fixture.clients.first.aborted, isTrue);
      _value(
        await provider.pullChanges(
          _mailbox,
          limit: 1,
          lease: fixture.session.begin(),
        ),
      );
      gate.complete(_sync('late', ''));
      await Future<void>.delayed(Duration.zero);
      expect(fixture.clients, hasLength(2));
    },
  );
}
