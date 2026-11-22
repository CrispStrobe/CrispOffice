import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/src/ews/configuration.dart';
import 'package:quds_mail_transport/src/ews/errors.dart';
import 'package:quds_mail_transport/src/ews/soap.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _s = 'http://schemas.xmlsoap.org/soap/envelope/';
const _m = 'http://schemas.microsoft.com/exchange/services/2006/messages';
const _t = 'http://schemas.microsoft.com/exchange/services/2006/types';

MailEwsConfiguration _configuration({String? mailboxAddress}) {
  final profile = MailProfileId('profile', hostId: 'ews-soap-test');
  final account = MailAccountId('account', profile: profile);
  return MailEwsConfiguration(
    account: account,
    endpoint: Uri.parse('https://exchange.example.test/EWS/Exchange.asmx'),
    username: r'EXAMPLE\user',
    credential: MailCredentialReference(
      account: account,
      key: 'vault-reference',
    ),
    mailboxAddress: mailboxAddress,
  );
}

EwsSoap _codec([MailEwsLimits limits = const MailEwsLimits()]) =>
    EwsSoap(configuration: _configuration(), limits: limits);

String _envelope(String body) =>
    '<s:Envelope xmlns:s="$_s" xmlns:m="$_m" xmlns:t="$_t">'
    '<s:Body>$body</s:Body></s:Envelope>';

String _response(String action, String responses) => _envelope(
  '<m:${action}Response><m:ResponseMessages>$responses'
  '</m:ResponseMessages></m:${action}Response>',
);

String _success(String action, String body) =>
    '<m:${action}ResponseMessage ResponseClass="Success">'
    '<m:ResponseCode>NoError</m:ResponseCode>$body'
    '</m:${action}ResponseMessage>';

String _error(String action, String code, {String extra = ''}) =>
    '<m:${action}ResponseMessage ResponseClass="Error">'
    '<m:ResponseCode>$code</m:ResponseCode>'
    '<m:MessageText>secret-server-text</m:MessageText>$extra'
    '</m:${action}ResponseMessage>';

String _item(String id, {String fields = '', String type = 'Message'}) =>
    '<t:$type><t:ItemId Id="$id" ChangeKey="change-$id"/>'
    '$fields</t:$type>';

String _itemResponse(
  String id, {
  String fields = '',
  String type = 'Message',
}) => _success(
  'GetItem',
  '<m:Items>${_item(id, fields: fields, type: type)}</m:Items>',
);

Matcher _failure(MailProblemCode code) =>
    throwsA(isA<EwsException>().having((error) => error.code, 'code', code));

XmlElement _element(String xml, String name, String namespace) =>
    XmlDocument.parse(
      xml,
    ).findAllElements(name, namespaceUri: namespace).single;

void main() {
  group('EWS SOAP requests', () {
    test('escapes opaque identifiers and binds the schema and mailbox', () {
      final codec = EwsSoap(
        configuration: _configuration(
          mailboxAddress: 'shared&team@example.test',
        ),
        limits: const MailEwsLimits(),
      );
      const id = 'opaque&<"\'id';
      final item = codec.getItems([id]);
      expect(_element(item, 'ItemId', _t).getAttribute('Id'), id);
      expect(
        _element(item, 'RequestServerVersion', _t).getAttribute('Version'),
        'Exchange2013_SP1',
      );
      final folder = codec.getFolder('inbox', distinguished: true);
      expect(
        _element(folder, 'EmailAddress', _t).innerText,
        'shared&team@example.test',
      );
      expect(folder, isNot(contains('vault-reference')));
      expect(folder, isNot(contains(r'EXAMPLE\user')));
    });

    test('folder and item paging are bounded and initially IdOnly', () {
      final codec = _codec();
      final folders = codec.findFolders(offset: 23, limit: 17);
      final view = _element(folders, 'IndexedPageFolderView', _m);
      expect(view.getAttribute('Offset'), '23');
      expect(view.getAttribute('MaxEntriesReturned'), '17');
      expect(
        _element(folders, 'FindFolder', _m).getAttribute('Traversal'),
        'Deep',
      );
      expect(
        _element(folders, 'DistinguishedFolderId', _t).getAttribute('Id'),
        'msgfolderroot',
      );
      final items = codec.findItems('folder', offset: 12, limit: 3);
      expect(_element(items, 'BaseShape', _t).innerText, 'IdOnly');
      expect(
        _element(items, 'IndexedPageItemView', _m).getAttribute('Offset'),
        '12',
      );
      expect(items, isNot(contains('IncludeMimeContent')));
    });

    test('GetItem loads full headers and actual Exchange flag properties', () {
      final xml = _codec().getItems(['a']);
      final fields = XmlDocument.parse(xml)
          .findAllElements('FieldURI', namespaceUri: _t)
          .map((element) => element.getAttribute('FieldURI'));
      expect(
        fields,
        containsAll(['message:IsRead', 'item:IsDraft', 'item:Flag']),
      );
      expect(fields, isNot(contains('message:IsDraft')));
      expect(fields, isNot(contains('item:Body')));
      expect(
        _element(xml, 'ExtendedFieldURI', _t).getAttribute('PropertyTag'),
        '0x1081',
      );
      expect(xml, isNot(contains('IncludeMimeContent')));
      expect(
        _element(
          _codec().getItems(['a'], mime: true),
          'IncludeMimeContent',
          _t,
        ).innerText,
        'true',
      );
    });

    test('membership projection requests only the exact parent folder', () {
      final xml = _codec().getItems(['one'], membershipOnly: true);
      final fields = XmlDocument.parse(xml)
          .findAllElements('FieldURI', namespaceUri: _t)
          .map((element) => element.getAttribute('FieldURI'));
      expect(fields, ['item:ParentFolderId']);
      expect(xml, isNot(contains('IncludeMimeContent')));
      expect(xml, isNot(contains('ExtendedFieldURI')));
      expect(_element(xml, 'ItemId', _t).getAttribute('Id'), 'one');
      final item = _codec()
          .items(
            _response(
              'GetItem',
              _itemResponse('one', fields: '<t:ParentFolderId Id="parent"/>'),
            ),
            requireMembership: true,
          )
          .single!;
      expect(item.parentFolderId, 'parent');
      expect(item.flags, isNull);
      expect(item.mimeBytes, isNull);
    });

    test('sync state is omitted on first sync and escaped on continuation', () {
      final codec = _codec();
      expect(
        codec.syncFolderItems('folder', limit: 2),
        isNot(contains('<m:SyncState')),
      );
      final xml = codec.syncFolderItems(
        'folder',
        syncState: 'state&<next>',
        limit: 2,
      );
      expect(_element(xml, 'SyncState', _m).innerText, 'state&<next>');
      expect(_element(xml, 'MaxChangesReturned', _m).innerText, '2');
      expect(_element(xml, 'SyncScope', _m).innerText, 'NormalItems');
    });

    test('updates use current ChangeKey and suppress read receipts', () {
      final xml = _codec().updateRead('item', 'latest-key', true);
      final update = _element(xml, 'UpdateItem', _m);
      expect(update.getAttribute('ConflictResolution'), 'NeverOverwrite');
      expect(update.getAttribute('MessageDisposition'), 'SaveOnly');
      expect(update.getAttribute('SuppressReadReceipts'), 'true');
      expect(
        _element(xml, 'ItemId', _t).getAttribute('ChangeKey'),
        'latest-key',
      );
      expect(_element(xml, 'IsRead', _t).innerText, 'true');
      final flag = _codec().updateFlagged('item', 'latest-key', false);
      expect(_element(flag, 'FlagStatus', _t).innerText, 'NotFlagged');
      final deletion = _codec().deleteItem('item', 'latest-key');
      expect(
        _element(deletion, 'DeleteItem', _m).getAttribute('DeleteType'),
        'MoveToDeletedItems',
      );
      expect(deletion, isNot(contains('HardDelete')));
    });

    test(
      'submission preserves MIME and supplies Bcc only as an EWS recipient',
      () {
        final mime = Uint8List.fromList([65, 13, 10, 0xff]);
        final xml = _codec().createMessage(
          mime: mime,
          sender: 'from@example.test',
          to: [const MailAddress('to@example.test', displayName: 'A & B')],
          cc: [const MailAddress('cc@example.test')],
          bcc: ['hidden@example.test'],
        );
        expect(
          _element(xml, 'CreateItem', _m).getAttribute('MessageDisposition'),
          'SendAndSaveCopy',
        );
        expect(base64.decode(_element(xml, 'MimeContent', _t).innerText), mime);
        expect(
          _element(xml, 'BccRecipients', _t).innerText,
          'hidden@example.test',
        );
        expect(
          _element(xml, 'Message', _t).childElements.map((e) => e.name.local),
          [
            'MimeContent',
            'ToRecipients',
            'CcRecipients',
            'BccRecipients',
            'From',
          ],
        );
      },
    );
  });

  group('EWS response projection', () {
    test('parses namespaces by URI and bounded folder continuation', () {
      final xml = _response(
        'FindFolder',
        _success(
          'FindFolder',
          '<m:RootFolder IncludesLastItemInRange="false" IndexedPagingOffset="7">'
              '<t:Folders><t:Folder><t:FolderId Id="folder" ChangeKey="key"/>'
              '<t:DisplayName>Team &amp; Support</t:DisplayName>'
              '<t:FolderClass>IPF.Note</t:FolderClass></t:Folder></t:Folders>'
              '</m:RootFolder>',
        ),
      ).replaceAll('t:', 'different:').replaceAll('xmlns:t=', 'xmlns:different=');
      final page = _codec().folders(xml, 'FindFolder');
      expect(page.lastPage, isFalse);
      expect(page.nextOffset, 7);
      expect(page.folders.single.displayName, 'Team & Support');
      expect(page.folders.single.folderClass, 'IPF.Note');
    });

    test('paged folder results require continuation and reject duplicates', () {
      String folders(String attrs, String content) => _response(
        'FindFolder',
        _success(
          'FindFolder',
          '<m:RootFolder $attrs><t:Folders>$content'
              '</t:Folders></m:RootFolder>',
        ),
      );
      const folder =
          '<t:Folder><t:FolderId Id="f" ChangeKey="c"/>'
          '<t:DisplayName>Inbox</t:DisplayName></t:Folder>';
      expect(
        () => _codec().folders(
          folders('IncludesLastItemInRange="false"', folder),
          'FindFolder',
        ),
        _failure(MailProblemCode.providerFailure),
      );
      expect(
        () => _codec().folders(
          folders('IncludesLastItemInRange="true"', '$folder$folder'),
          'FindFolder',
        ),
        _failure(MailProblemCode.providerFailure),
      );
    });

    test('search and strongly typed nonmail folders are not sync mailboxes', () {
      final folders = [
        '<t:Folder><t:FolderId Id="mail" ChangeKey="c"/>'
            '<t:DisplayName>Mail</t:DisplayName><t:FolderClass>IPF.Note.Custom</t:FolderClass>'
            '</t:Folder>',
        '<t:SearchFolder><t:FolderId Id="search" ChangeKey="c"/>'
            '<t:DisplayName>Unread</t:DisplayName><t:FolderClass>IPF.Note</t:FolderClass>'
            '</t:SearchFolder>',
        '<t:CalendarFolder><t:FolderId Id="calendar" ChangeKey="c"/>'
            '<t:DisplayName>Calendar</t:DisplayName></t:CalendarFolder>',
      ].join();
      final result = _codec().folders(
        _response(
          'FindFolder',
          _success(
            'FindFolder',
            '<m:RootFolder IncludesLastItemInRange="true">'
                '<t:Folders>$folders</t:Folders></m:RootFolder>',
          ),
        ),
        'FindFolder',
      );
      expect(result.folders.map((folder) => folder.isMailFolder), [
        true,
        false,
        false,
      ]);
    });

    test('sync retains ordered create/update/delete/read-state changes', () {
      final xml = _response(
        'SyncFolderItems',
        _success(
          'SyncFolderItems',
          '<m:SyncState>state+/=</m:SyncState>'
              '<m:IncludesLastItemInRange>false</m:IncludesLastItemInRange>'
              '<m:Changes><t:Create>${_item('a')}</t:Create>'
              '<t:Update>${_item('b', type: 'MeetingRequest')}</t:Update>'
              '<t:Delete><t:ItemId Id="c"/></t:Delete>'
              '<t:ReadFlagChange><t:ItemId Id="a"/><t:IsRead>true</t:IsRead>'
              '</t:ReadFlagChange></m:Changes>',
        ),
      );
      final page = _codec().sync(xml);
      expect(page.syncState, 'state+/=');
      expect(page.includesLast, isFalse);
      expect(page.changes.map((change) => change.kind), EwsChangeKind.values);
      expect(page.changes.last.id, 'a');
      expect(page.changes.last.isRead, isTrue);
      expect(page.changes[2].changeKey, isNull);
    });

    test(
      'sync rejects missing state, unknown changes and excessive page counts',
      () {
        String sync(String changes, {String state = 'valid'}) => _response(
          'SyncFolderItems',
          _success(
            'SyncFolderItems',
            '<m:SyncState>$state</m:SyncState>'
                '<m:IncludesLastItemInRange>true</m:IncludesLastItemInRange>'
                '<m:Changes>$changes</m:Changes>',
          ),
        );
        expect(
          () => _codec().sync(sync('', state: '')),
          _failure(MailProblemCode.providerFailure),
        );
        expect(
          () => _codec().sync(sync('<t:Surprise/>')),
          _failure(MailProblemCode.providerFailure),
        );
        final changes =
            '<t:Create>${_item('a')}</t:Create>'
            '<t:Create>${_item('b')}</t:Create>';
        expect(
          () => _codec(const MailEwsLimits(maxPageSize: 1)).sync(sync(changes)),
          _failure(MailProblemCode.quotaExceeded),
        );
      },
    );

    test('projects complete GetItem headers and observed flags', () {
      final xml = _response(
        'GetItem',
        _itemResponse(
          'a',
          fields:
              '<t:Subject>R&amp;D</t:Subject><t:DateTimeSent>2026-11-19T10:00:00Z</t:DateTimeSent>'
              '<t:From><t:Mailbox><t:Name>Sender</t:Name>'
              '<t:EmailAddress>from@example.test</t:EmailAddress></t:Mailbox></t:From>'
              '<t:ToRecipients><t:Mailbox><t:EmailAddress>to@example.test</t:EmailAddress>'
              '</t:Mailbox></t:ToRecipients>'
              '<t:References>&lt;one@example.test&gt; &lt;two@example.test&gt;</t:References>'
              '<t:IsRead>true</t:IsRead><t:IsDraft>false</t:IsDraft>'
              '<t:Flag><t:FlagStatus>Flagged</t:FlagStatus></t:Flag>'
              '<t:ExtendedProperty><t:ExtendedFieldURI PropertyTag="0x1081" '
              'PropertyType="Integer"/><t:Value>103</t:Value></t:ExtendedProperty>',
        ),
      );
      final item = _codec().items(xml).single!;
      expect(item.envelope.subject, 'R&D');
      expect(item.envelope.from.single.displayName, 'Sender');
      expect(item.envelope.to.single.address, 'to@example.test');
      expect(item.envelope.references, [
        '<one@example.test>',
        '<two@example.test>',
      ]);
      expect(
        item.flags,
        const MailMessageFlags(isRead: true, isFlagged: true, isAnswered: true),
      );
      expect(
        _codec().items(_response('GetItem', _itemResponse('a'))).single!.flags,
        isNull,
      );
    });

    test(
      'missing GetItem slots remain correlated and errors reject the batch',
      () {
        final xml = _response(
          'GetItem',
          _itemResponse('a') +
              _error('GetItem', 'ErrorItemNotFound') +
              _itemResponse('c'),
        );
        final items = _codec().items(xml, allowMissing: true);
        expect(items.map((item) => item?.id), ['a', null, 'c']);
        expect(
          () => _codec().items(xml),
          _failure(MailProblemCode.unavailable),
        );
        expect(
          () => _codec().items(
            _response(
              'GetItem',
              _itemResponse('a') + _error('GetItem', 'ErrorAccessDenied'),
            ),
            allowMissing: true,
          ),
          _failure(MailProblemCode.permissionDenied),
        );
      },
    );

    test('MIME bytes are exact and malformed or oversized base64 fails', () {
      final bytes = Uint8List.fromList([0, 1, 2, 0xff, 0xfe, 13, 10]);
      final encoded = base64.encode(bytes);
      String mime(String value) => _response(
        'GetItem',
        _itemResponse('a', fields: '<t:MimeContent>$value</t:MimeContent>'),
      );
      final item = _codec()
          .items(
            mime(
              '${encoded.substring(0, 4)}\r\n'
              '${encoded.substring(4)}',
            ),
            mime: true,
            maxMimeBytes: 7,
          )
          .single!;
      expect(item.mimeBytes, bytes);
      expect(
        () => _codec().items(mime(encoded), mime: true, maxMimeBytes: 6),
        _failure(MailProblemCode.quotaExceeded),
      );
      for (final malformed in ['AA', 'AA%3D%3D', 'AA-_', 'AA==AAAA', '!!!=']) {
        expect(
          () => _codec().items(mime(malformed), mime: true, maxMimeBytes: 20),
          _failure(MailProblemCode.providerFailure),
        );
      }
    });

    test('mutation responses require the expected count and item identity', () {
      final xml = _response(
        'MoveItem',
        _success('MoveItem', '<m:Items>${_item('new')}</m:Items>'),
      );
      expect(_codec().mutation(xml, 'MoveItem').single.id, 'new');
      expect(
        _codec().mutation(
          _response('DeleteItem', _success('DeleteItem', '')),
          'DeleteItem',
        ),
        isEmpty,
      );
      expect(
        _codec().mutation(
          _response('CreateItem', _success('CreateItem', '')),
          'CreateItem',
        ),
        isEmpty,
      );
      expect(
        () => _codec().mutation(
          _response('UpdateItem', _success('UpdateItem', '<m:Items/>')),
          'UpdateItem',
        ),
        _failure(MailProblemCode.providerFailure),
      );
    });
  });

  group('EWS response rejection and budgets', () {
    test('server errors are redacted and throttling duration is preserved', () {
      final xml = _response(
        'GetItem',
        _error(
          'GetItem',
          'ErrorServerBusy',
          extra:
              '<m:MessageXml><t:Value Name="BackOffMilliseconds">2300</t:Value>'
              '</m:MessageXml>',
        ),
      );
      try {
        _codec().items(xml);
        fail('Expected an EWS error.');
      } on EwsException catch (error) {
        expect(error.code, MailProblemCode.unavailable);
        expect(error.retryAfter, const Duration(milliseconds: 2300));
        expect(error.toString(), isNot(contains('secret-server-text')));
      }
      expect(
        () => _codec().sync(
          _response(
            'SyncFolderItems',
            _error('SyncFolderItems', 'ErrorInvalidSyncStateData'),
          ),
        ),
        _failure(MailProblemCode.conflict),
      );
    });

    test('a success class does not hide a failing response code', () {
      final xml = _response(
        'GetItem',
        _error('GetItem', 'ErrorAccessDenied'),
      ).replaceAll('ResponseClass="Error"', 'ResponseClass="Success"');
      expect(
        () => _codec().items(xml),
        _failure(MailProblemCode.permissionDenied),
      );
    });

    test(
      'only an explicit sync state rejection authorizes a mailbox reset',
      () {
        for (final code in [
          'ErrorInvalidSyncStateData',
          'ErrorInvalidChangeKey',
          'ErrorIrresolvableConflict',
          'ErrorSyncFolderNotFound',
        ]) {
          try {
            _codec().sync(
              _response('SyncFolderItems', _error('SyncFolderItems', code)),
            );
            fail('Expected an EWS error.');
          } on EwsException catch (error) {
            expect(error.invalidSyncState, code == 'ErrorInvalidSyncStateData');
          }
        }
        try {
          _codec().items(
            _response(
              'GetItem',
              _error('GetItem', 'ErrorInvalidSyncStateData'),
            ),
          );
          fail('Expected an EWS error.');
        } on EwsException catch (error) {
          expect(error.invalidSyncState, isFalse);
        }
        try {
          _codec().sync(
            _response(
              'SyncFolderItems',
              _error('SyncFolderItems', 'ErrorInvalidSyncStateData'),
            ).replaceAll('ResponseClass="Error"', 'ResponseClass="Success"'),
          );
          fail('Expected an EWS error.');
        } on EwsException catch (error) {
          expect(error.invalidSyncState, isFalse);
        }
      },
    );

    test('wrong namespaces, actions, duplicate required fields and DTD fail', () {
      final valid = _response('GetItem', _itemResponse('a'));
      for (final xml in [
        valid.replaceAll(_m, 'https://attacker.invalid/messages'),
        valid.replaceAll('GetItemResponse', 'FindItemResponse'),
        valid.replaceAll(
          '<m:ResponseCode>NoError</m:ResponseCode>',
          '<m:ResponseCode>NoError</m:ResponseCode><m:ResponseCode>NoError</m:ResponseCode>',
        ),
        '<!DOCTYPE example [<!ENTITY secret "private">]>$valid',
        valid.replaceFirst('Id="a"', 'Id="a" Id="duplicate"'),
        valid.substring(0, valid.length - 2),
      ]) {
        expect(
          () => _codec().items(xml),
          _failure(MailProblemCode.providerFailure),
        );
      }
    });

    test('SOAP faults cannot become empty successful operations', () {
      final xml = _envelope(
        '<s:Fault><faultcode>s:Server</faultcode>'
        '<faultstring>secret-server-text</faultstring></s:Fault>',
      );
      expect(
        () => _codec().mutation(xml, 'DeleteItem'),
        _failure(MailProblemCode.providerFailure),
      );
    });

    test('SOAP server-busy fault retains the typed backoff hint', () {
      final xml = _envelope(
        '<s:Fault><faultcode>s:Server</faultcode>'
        '<faultstring>secret-server-text</faultstring><detail>'
        '<e:ResponseCode xmlns:e="http://schemas.microsoft.com/exchange/services/2006/errors">'
        'ErrorServerBusy</e:ResponseCode><t:MessageXml>'
        '<t:Value Name="BackOffMilliseconds">3000</t:Value></t:MessageXml>'
        '</detail></s:Fault>',
      );
      expect(
        () => _codec().items(xml),
        throwsA(
          isA<EwsException>()
              .having(
                (error) => error.code,
                'code',
                MailProblemCode.unavailable,
              )
              .having(
                (error) => error.retryAfter,
                'retryAfter',
                const Duration(seconds: 3),
              )
              .having(
                (error) => error.toString(),
                'redaction',
                isNot(contains('secret-server-text')),
              ),
        ),
      );
    });

    test('bounds XML depth, total nodes, headers and sync state', () {
      final deep = _response(
        'GetItem',
        _itemResponse('a', fields: '${'<t:N>' * 65}${'</t:N>' * 65}'),
      );
      expect(
        () => _codec().items(deep),
        _failure(MailProblemCode.quotaExceeded),
      );
      final xml = _response('GetItem', _itemResponse('a'));
      expect(
        () => _codec(const MailEwsLimits(maxXmlNodes: 4)).items(xml),
        _failure(MailProblemCode.quotaExceeded),
      );
      expect(
        () => _codec(const MailEwsLimits(maxHeaderBytes: 2)).items(
          _response(
            'GetItem',
            _itemResponse('a', fields: '<t:Subject>four</t:Subject>'),
          ),
        ),
        _failure(MailProblemCode.quotaExceeded),
      );
      expect(
        () => _codec(const MailEwsLimits(maxSyncStateBytes: 2)).sync(
          _response(
            'SyncFolderItems',
            _success(
              'SyncFolderItems',
              '<m:SyncState>four</m:SyncState>'
                  '<m:IncludesLastItemInRange>true</m:IncludesLastItemInRange>'
                  '<m:Changes/>',
            ),
          ),
        ),
        _failure(MailProblemCode.quotaExceeded),
      );
    });

    test('invalid boolean and nested scalar data are rejected', () {
      for (final fields in [
        '<t:IsRead>yes</t:IsRead>',
        '<t:Subject><t:Injected>subject</t:Injected></t:Subject>',
        '<t:IsRead>false</t:IsRead><t:IsDraft>true</t:IsDraft>'
            '<t:Flag><t:FlagStatus>unexpected</t:FlagStatus></t:Flag>',
      ]) {
        expect(
          () => _codec().items(
            _response('GetItem', _itemResponse('a', fields: fields)),
          ),
          _failure(MailProblemCode.providerFailure),
        );
      }
    });
  });
}
