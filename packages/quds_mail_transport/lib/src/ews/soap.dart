import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'configuration.dart';
import 'errors.dart';

part 'task_soap.dart';

const _soap = 'http://schemas.xmlsoap.org/soap/envelope/';
const _messages =
    'http://schemas.microsoft.com/exchange/services/2006/messages';
const _types = 'http://schemas.microsoft.com/exchange/services/2006/types';
const _errors = 'http://schemas.microsoft.com/exchange/services/2006/errors';

final class EwsItemId {
  const EwsItemId(this.id, this.changeKey);
  final String id;
  final String changeKey;
}

final class EwsItem {
  const EwsItem({
    required this.id,
    required this.changeKey,
    required this.envelope,
    required this.flags,
    this.mimeBytes,
    this.parentFolderId,
  });
  final String id;
  final String changeKey;
  final MailEnvelope envelope;
  final MailMessageFlags? flags;
  final Uint8List? mimeBytes;
  final String? parentFolderId;
}

final class EwsFolder {
  const EwsFolder({
    required this.id,
    required this.changeKey,
    required this.displayName,
    required this.folderClass,
    required this.isMailFolder,
  });
  final String id;
  final String changeKey;
  final String displayName;
  final String? folderClass;
  final bool isMailFolder;
}

final class EwsFolderPage {
  EwsFolderPage({
    required List<EwsFolder> folders,
    required this.lastPage,
    required this.nextOffset,
  }) : folders = List.unmodifiable(folders);
  final List<EwsFolder> folders;
  final bool lastPage;
  final int? nextOffset;
}

final class EwsItemIdPage {
  EwsItemIdPage({
    required List<EwsItemId> items,
    required this.lastPage,
    required this.nextOffset,
    this.totalCount,
  }) : items = List.unmodifiable(items);
  final List<EwsItemId> items;
  final bool lastPage;
  final int? nextOffset;
  final int? totalCount;
}

enum EwsChangeKind { create, update, delete, readFlagChange }

final class EwsSyncChange {
  const EwsSyncChange({
    required this.kind,
    required this.id,
    this.changeKey,
    this.isRead,
  });
  final EwsChangeKind kind;
  final String id;
  final String? changeKey;
  final bool? isRead;
}

final class EwsSyncChanges {
  EwsSyncChanges({
    required this.syncState,
    required this.includesLast,
    required List<EwsSyncChange> changes,
  }) : changes = List.unmodifiable(changes);
  final String syncState;
  final bool includesLast;
  final List<EwsSyncChange> changes;
}

/// Internal SOAP boundary. No server error text escapes the typed exception.
///
/// Requests deliberately use IdOnly before loading complete header properties
/// with GetItem: FindItem may truncate streamable properties. MIME retrieval
/// preserves the bytes returned by Exchange, not an alleged original SMTP wire.
final class EwsSoap {
  const EwsSoap({required this.configuration, required this.limits});

  final MailEwsConfiguration configuration;
  final MailEwsLimits limits;

  String _request(
    String action,
    void Function(XmlBuilder) body, {
    Map<String, String> attributes = const {},
  }) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="utf-8"');
    builder.element(
      's:Envelope',
      attributes: const {
        'xmlns:s': _soap,
        'xmlns:m': _messages,
        'xmlns:t': _types,
      },
      nest: () {
        builder.element(
          's:Header',
          nest: () {
            builder.element(
              't:RequestServerVersion',
              attributes: {'Version': configuration.serverVersion.wireValue},
            );
          },
        );
        builder.element(
          's:Body',
          nest: () {
            builder.element(
              'm:$action',
              attributes: attributes,
              nest: () => body(builder),
            );
          },
        );
      },
    );
    return builder.buildDocument().toXmlString();
  }

  void _folderId(XmlBuilder builder, String id, {bool distinguished = false}) {
    builder.element(
      distinguished ? 't:DistinguishedFolderId' : 't:FolderId',
      attributes: {'Id': id},
      nest: () {
        if (configuration.mailboxAddress case final address?
            when distinguished) {
          builder.element(
            't:Mailbox',
            nest: () {
              builder.element('t:EmailAddress', nest: address);
            },
          );
        }
      },
    );
  }

  void _itemId(XmlBuilder builder, String id, [String? changeKey]) => builder
      .element('t:ItemId', attributes: {'Id': id, 'ChangeKey': ?changeKey});

  void _folderShape(XmlBuilder builder) {
    builder.element(
      'm:FolderShape',
      nest: () {
        builder.element('t:BaseShape', nest: 'IdOnly');
        builder.element(
          't:AdditionalProperties',
          nest: () {
            for (final name in ['folder:DisplayName', 'folder:FolderClass']) {
              builder.element('t:FieldURI', attributes: {'FieldURI': name});
            }
          },
        );
      },
    );
  }

  String getFolder(String id, {bool distinguished = false}) =>
      _request('GetFolder', (builder) {
        _folderShape(builder);
        builder.element(
          'm:FolderIds',
          nest: () {
            _folderId(builder, id, distinguished: distinguished);
          },
        );
      });

  String findFolders({
    required int offset,
    required int limit,
    bool taskFolders = false,
  }) => _request('FindFolder', (builder) {
    _folderShape(builder);
    builder.element(
      'm:IndexedPageFolderView',
      attributes: {
        'MaxEntriesReturned': '$limit',
        'Offset': '$offset',
        'BasePoint': 'Beginning',
      },
    );
    if (taskFolders) {
      builder.element(
        'm:Restriction',
        nest: () {
          builder.element(
            't:IsEqualTo',
            nest: () {
              builder.element(
                't:FieldURI',
                attributes: {'FieldURI': 'folder:FolderClass'},
              );
              builder.element(
                't:FieldURIOrConstant',
                nest: () {
                  builder.element(
                    't:Constant',
                    attributes: {'Value': 'IPF.Task'},
                  );
                },
              );
            },
          );
        },
      );
    }
    builder.element(
      'm:ParentFolderIds',
      nest: () {
        _folderId(builder, 'msgfolderroot', distinguished: true);
      },
    );
  }, attributes: const {'Traversal': 'Deep'});

  String findItems(
    String folderId, {
    required int offset,
    required int limit,
    MailProviderSearchRequest? search,
  }) => _request('FindItem', (builder) {
    builder.element(
      'm:ItemShape',
      nest: () {
        builder.element('t:BaseShape', nest: 'IdOnly');
      },
    );
    builder.element(
      'm:IndexedPageItemView',
      attributes: {
        'MaxEntriesReturned': '$limit',
        'Offset': '$offset',
        'BasePoint': 'Beginning',
      },
    );
    if (search != null) {
      if (!search.isValid || search.mailbox.value != folderId) {
        throw const EwsException(MailProblemCode.invalidInput);
      }
      final field = switch (search.field) {
        MailProviderSearchField.body => 'item:Body',
        MailProviderSearchField.subject => 'item:Subject',
        _ => throw const EwsException(MailProblemCode.unsupported),
      };
      void conditions() {
        builder.element(
          't:Contains',
          attributes: const {
            'ContainmentMode': 'Substring',
            'ContainmentComparison': 'IgnoreCase',
          },
          nest: () {
            builder.element('t:FieldURI', attributes: {'FieldURI': field});
            builder.element('t:Constant', attributes: {'Value': search.query});
          },
        );
        void dateCondition(String comparison, DateTime value) {
          builder.element(
            't:$comparison',
            nest: () {
              builder.element(
                't:FieldURI',
                attributes: const {'FieldURI': 'item:DateTimeReceived'},
              );
              builder.element(
                't:FieldURIOrConstant',
                nest: () => builder.element(
                  't:Constant',
                  attributes: {'Value': value.toIso8601String()},
                ),
              );
            },
          );
        }

        if (search.receivedAfter case final date?) {
          dateCondition('IsGreaterThanOrEqualTo', date);
        }
        if (search.receivedBefore case final date?) {
          dateCondition('IsLessThan', date);
        }
      }

      builder.element(
        'm:Restriction',
        nest: () {
          if (search.receivedAfter != null || search.receivedBefore != null) {
            builder.element('t:And', nest: conditions);
          } else {
            conditions();
          }
        },
      );
    }
    builder.element(
      'm:SortOrder',
      nest: () {
        builder.element(
          't:FieldOrder',
          attributes: {'Order': 'Descending'},
          nest: () {
            builder.element(
              't:FieldURI',
              attributes: {'FieldURI': 'item:DateTimeReceived'},
            );
          },
        );
      },
    );
    builder.element(
      'm:ParentFolderIds',
      nest: () {
        _folderId(builder, folderId);
      },
    );
  }, attributes: const {'Traversal': 'Shallow'});

  String syncFolderItems(
    String folderId, {
    String? syncState,
    required int limit,
  }) => _request('SyncFolderItems', (builder) {
    builder.element(
      'm:ItemShape',
      nest: () {
        builder.element('t:BaseShape', nest: 'IdOnly');
      },
    );
    builder.element(
      'm:SyncFolderId',
      nest: () {
        _folderId(builder, folderId);
      },
    );
    if (syncState != null) builder.element('m:SyncState', nest: syncState);
    builder.element('m:MaxChangesReturned', nest: '$limit');
    builder.element('m:SyncScope', nest: 'NormalItems');
  });

  String getItems(
    List<String> ids, {
    bool mime = false,
    bool flagsOnly = false,
    bool membershipOnly = false,
    bool includeMembership = false,
  }) => _request('GetItem', (builder) {
    builder.element(
      'm:ItemShape',
      nest: () {
        builder.element('t:BaseShape', nest: 'IdOnly');
        if (mime) builder.element('t:IncludeMimeContent', nest: 'true');
        builder.element(
          't:AdditionalProperties',
          nest: () {
            for (final field in [
              if (membershipOnly || includeMembership) 'item:ParentFolderId',
              if (!flagsOnly && !membershipOnly) ...const [
                'item:Subject',
                'item:DateTimeSent',
                'item:InReplyTo',
                'message:From',
                'message:ToRecipients',
                'message:CcRecipients',
                'message:BccRecipients',
                'message:ReplyTo',
                'message:InternetMessageId',
                'message:References',
              ],
              if (!membershipOnly) ...const [
                'item:IsDraft',
                'item:Flag',
                'message:IsRead',
              ],
            ]) {
              builder.element('t:FieldURI', attributes: {'FieldURI': field});
            }
            if (!membershipOnly) {
              builder.element(
                't:ExtendedFieldURI',
                attributes: {
                  'PropertyTag': '0x1081',
                  'PropertyType': 'Integer',
                },
              );
            }
          },
        );
      },
    );
    builder.element(
      'm:ItemIds',
      nest: () {
        for (final id in ids) {
          _itemId(builder, id);
        }
      },
    );
  });

  String _update(
    String id,
    String changeKey,
    String field,
    void Function(XmlBuilder) value,
  ) => _request(
    'UpdateItem',
    (builder) {
      builder.element(
        'm:ItemChanges',
        nest: () {
          builder.element(
            't:ItemChange',
            nest: () {
              _itemId(builder, id, changeKey);
              builder.element(
                't:Updates',
                nest: () {
                  builder.element(
                    't:SetItemField',
                    nest: () {
                      builder.element(
                        't:FieldURI',
                        attributes: {'FieldURI': field},
                      );
                      builder.element('t:Message', nest: () => value(builder));
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
    attributes: const {
      'ConflictResolution': 'NeverOverwrite',
      'MessageDisposition': 'SaveOnly',
      'SuppressReadReceipts': 'true',
    },
  );

  String updateRead(String id, String changeKey, bool read) =>
      _update(id, changeKey, 'message:IsRead', (builder) {
        builder.element('t:IsRead', nest: '$read');
      });

  String updateFlagged(String id, String changeKey, bool flagged) =>
      _update(id, changeKey, 'item:Flag', (builder) {
        builder.element(
          't:Flag',
          nest: () {
            builder.element(
              't:FlagStatus',
              nest: flagged ? 'Flagged' : 'NotFlagged',
            );
          },
        );
      });

  String moveItem(String id, String changeKey, String folderId) =>
      _request('MoveItem', (builder) {
        builder.element(
          'm:ToFolderId',
          nest: () {
            _folderId(builder, folderId);
          },
        );
        builder.element(
          'm:ItemIds',
          nest: () {
            _itemId(builder, id, changeKey);
          },
        );
        builder.element('m:ReturnNewItemIds', nest: 'true');
      });

  String deleteItem(String id, String changeKey) => _request(
    'DeleteItem',
    (builder) {
      builder.element(
        'm:ItemIds',
        nest: () {
          _itemId(builder, id, changeKey);
        },
      );
    },
    attributes: const {
      'DeleteType': 'MoveToDeletedItems',
      'SuppressReadReceipts': 'true',
    },
  );

  /// MIME is supplied by the host's canonical composer. Explicit recipients
  /// preserve envelope-only Bcc addresses without adding Bcc to the wire data.
  String createMessage({
    required Uint8List mime,
    required String sender,
    required List<MailAddress> to,
    required List<MailAddress> cc,
    required List<String> bcc,
  }) => _request('CreateItem', (builder) {
    builder.element(
      'm:SavedItemFolderId',
      nest: () {
        _folderId(builder, 'sentitems', distinguished: true);
      },
    );
    builder.element(
      'm:Items',
      nest: () {
        builder.element(
          't:Message',
          nest: () {
            builder.element('t:MimeContent', nest: base64.encode(mime));
            void recipients(String name, List<MailAddress> addresses) {
              if (addresses.isEmpty) return;
              builder.element(
                't:$name',
                nest: () {
                  for (final address in addresses) {
                    builder.element(
                      't:Mailbox',
                      nest: () {
                        if (address.displayName case final display?) {
                          builder.element('t:Name', nest: display);
                        }
                        builder.element(
                          't:EmailAddress',
                          nest: address.address,
                        );
                      },
                    );
                  }
                },
              );
            }

            // Message extends Item: MIME precedes To/Cc/Bcc; From follows them.
            recipients('ToRecipients', to);
            recipients('CcRecipients', cc);
            recipients('BccRecipients', bcc.map(MailAddress.new).toList());
            recipients('From', [MailAddress(sender)]);
          },
        );
      },
    );
  }, attributes: const {'MessageDisposition': 'SendAndSaveCopy'});

  EwsFolderPage folders(String xml, String action) => _guard(() {
    if (action != 'FindFolder' && action != 'GetFolder') _invalid();
    final responses = _responses(xml, action);
    if (responses.length != 1) _invalid();
    final response = responses.single!;
    final root = action == 'FindFolder'
        ? _one(response, 'RootFolder', _messages)
        : response;
    final container = _one(
      root,
      'Folders',
      action == 'FindFolder' ? _types : _messages,
    );
    final result = <EwsFolder>[];
    final ids = <String>{};
    for (final folder in container.childElements) {
      if (folder.namespaceUri != _types ||
          !const {
            'Folder',
            'CalendarFolder',
            'ContactsFolder',
            'TasksFolder',
            'SearchFolder',
          }.contains(folder.name.local)) {
        _invalid();
      }
      final id = _id(_one(folder, 'FolderId', _types));
      if (!ids.add(id.id)) _invalid();
      final budget = _HeaderBudget(limits.maxHeaderBytes);
      final folderClass = _optionalText(folder, 'FolderClass', budget);
      result.add(
        EwsFolder(
          id: id.id,
          changeKey: id.changeKey,
          displayName: _text(_one(folder, 'DisplayName', _types), budget),
          folderClass: folderClass,
          // Search folders cannot be consumed by SyncFolderItems; the strongly
          // typed calendar/contact/task folders are separate provider features.
          isMailFolder:
              folder.name.local == 'Folder' &&
              (folderClass == null ||
                  folderClass == 'IPF.Note' ||
                  folderClass.startsWith('IPF.Note.')),
        ),
      );
      if (result.length > limits.maxPageSize) _quota();
    }
    final page = action == 'FindFolder' ? _page(root) : (true, null);
    return EwsFolderPage(
      folders: result,
      lastPage: page.$1,
      nextOffset: page.$2,
    );
  });

  EwsItemIdPage itemIdsPage(String xml) => _guard(() {
    final responses = _responses(xml, 'FindItem');
    if (responses.length != 1) _invalid();
    final root = _one(responses.single!, 'RootFolder', _messages);
    final container = _one(root, 'Items', _types);
    final result = <EwsItemId>[];
    final ids = <String>{};
    for (final item in container.childElements) {
      _mailItem(item);
      final id = _id(_one(item, 'ItemId', _types));
      if (!ids.add(id.id)) _invalid();
      result.add(id);
      if (result.length > limits.maxPageSize) _quota();
    }
    final page = _page(root);
    final rawCount = root.getAttribute('TotalItemsInView');
    final totalCount = rawCount == null ? null : int.tryParse(rawCount);
    if (rawCount != null &&
        (totalCount == null ||
            !RegExp(r'^\d+$').hasMatch(rawCount) ||
            totalCount < result.length ||
            totalCount > 0x1fffffffffffff)) {
      _invalid();
    }
    return EwsItemIdPage(
      items: result,
      lastPage: page.$1,
      nextOffset: page.$2,
      totalCount: totalCount,
    );
  });

  EwsSyncChanges sync(String xml, {bool tasks = false}) => _guard(() {
    final responses = _responses(xml, 'SyncFolderItems');
    if (responses.length != 1) _invalid();
    final response = responses.single!;
    final state = _text(
      _one(response, 'SyncState', _messages),
      _HeaderBudget(limits.maxSyncStateBytes),
    );
    if (state.isEmpty) _invalid();
    final last = _boolean(_one(response, 'IncludesLastItemInRange', _messages));
    final changes = <EwsSyncChange>[];
    for (final change in _one(response, 'Changes', _messages).childElements) {
      if (change.namespaceUri != _types) _invalid();
      final kind = switch (change.name.local) {
        'Create' => EwsChangeKind.create,
        'Update' => EwsChangeKind.update,
        'Delete' => EwsChangeKind.delete,
        'ReadFlagChange' => EwsChangeKind.readFlagChange,
        _ => _invalid(),
      };
      final XmlElement id;
      bool? read;
      if (kind == EwsChangeKind.create || kind == EwsChangeKind.update) {
        final items = change.childElements.toList();
        if (items.length != 1) _invalid();
        if (tasks) {
          _taskItem(items.single);
        } else {
          _mailItem(items.single);
        }
        id = _one(items.single, 'ItemId', _types);
      } else {
        id = _one(change, 'ItemId', _types);
        if (kind == EwsChangeKind.readFlagChange) {
          read = _boolean(_one(change, 'IsRead', _types));
        }
      }
      changes.add(
        EwsSyncChange(
          kind: kind,
          id: _identifier(id.getAttribute('Id')),
          changeKey: _optionalIdentifier(id.getAttribute('ChangeKey')),
          isRead: read,
        ),
      );
      if (changes.length > limits.maxPageSize) _quota();
    }
    return EwsSyncChanges(
      syncState: state,
      includesLast: last,
      changes: changes,
    );
  });

  /// A null slot is permitted only for an explicit ErrorItemNotFound response.
  /// Callers correlate slots with the requested IDs before creating tombstones.
  List<EwsItem?> items(
    String xml, {
    bool mime = false,
    int? maxMimeBytes,
    bool allowMissing = false,
    bool requireFlags = false,
    bool requireMembership = false,
  }) => _guard(() {
    final responses = _responses(xml, 'GetItem', allowMissing: allowMissing);
    final result = <EwsItem?>[];
    final ids = <String>{};
    for (final response in responses) {
      if (response == null) {
        result.add(null);
        continue;
      }
      final children = _one(
        response,
        'Items',
        _messages,
      ).childElements.toList();
      if (children.length != 1) _invalid();
      final item = children.single;
      _mailItem(item);
      final id = _id(_one(item, 'ItemId', _types));
      if (!ids.add(id.id)) _invalid();
      final parentElement = _optional(item, 'ParentFolderId', _types);
      if (parentElement != null && parentElement.childElements.isNotEmpty) {
        _invalid();
      }
      final parentFolderId = parentElement == null
          ? null
          : _identifier(parentElement.getAttribute('Id'));
      if (requireMembership && parentFolderId == null) _invalid();
      final budget = _HeaderBudget(limits.maxHeaderBytes);
      final sent = _optionalText(item, 'DateTimeSent', budget);
      final date = sent == null ? null : DateTime.tryParse(sent);
      if (sent != null && date == null) _invalid();
      final references = _optionalText(item, 'References', budget);
      final envelope = MailEnvelope(
        subject: _optionalText(item, 'Subject', budget) ?? '',
        from: _addresses(item, 'From', budget),
        to: _addresses(item, 'ToRecipients', budget),
        cc: _addresses(item, 'CcRecipients', budget),
        bcc: _addresses(item, 'BccRecipients', budget),
        replyTo: _addresses(item, 'ReplyTo', budget),
        sentAt: date,
        messageId: _optionalText(item, 'InternetMessageId', budget),
        inReplyTo: _optionalText(item, 'InReplyTo', budget),
        references: references == null || references.trim().isEmpty
            ? const []
            : references.trim().split(RegExp(r'\s+')),
      );
      final readElement = _optional(item, 'IsRead', _types);
      final draftElement = _optional(item, 'IsDraft', _types);
      final flagElement = _optional(item, 'Flag', _types);
      final flag = flagElement == null
          ? null
          : _text(_one(flagElement, 'FlagStatus', _types), budget);
      if (requireFlags &&
          (readElement == null || draftElement == null || flag == null)) {
        _invalid();
      }
      if (flag != null &&
          !const {'Flagged', 'NotFlagged', 'Complete'}.contains(flag)) {
        _invalid();
      }
      int? lastVerb;
      for (final extended in item.findElements(
        'ExtendedProperty',
        namespaceUri: _types,
      )) {
        final field = _one(extended, 'ExtendedFieldURI', _types);
        final tag = field.getAttribute('PropertyTag');
        if (tag == '0x1081' || tag == '4225') {
          if (lastVerb != null ||
              field.getAttribute('PropertyType') != 'Integer') {
            _invalid();
          }
          lastVerb = int.tryParse(
            _text(_one(extended, 'Value', _types), budget),
          );
          if (lastVerb == null) _invalid();
        }
      }
      final read = readElement == null ? null : _boolean(readElement);
      final draft = draftElement == null ? null : _boolean(draftElement);
      final flags = read == null || draft == null
          ? null
          : MailMessageFlags(
              isRead: read,
              isDraft: draft,
              isFlagged: flag == 'Flagged',
              isAnswered: lastVerb == 102 || lastVerb == 103,
            );
      Uint8List? bytes;
      if (mime) {
        if (maxMimeBytes == null || maxMimeBytes < 1) _invalid();
        final content = _one(item, 'MimeContent', _types);
        if (content.childElements.isNotEmpty) _invalid();
        final encoded = content.innerText.replaceAll(RegExp(r'[\t\r\n ]'), '');
        if (encoded.length > ((maxMimeBytes + 2) ~/ 3) * 4) _quota();
        // Require the standard padded alphabet. Percent escapes, URL-safe
        // aliases and unpadded/partially decoded content are not MIME content.
        if (encoded.isEmpty ||
            encoded.length % 4 != 0 ||
            !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(encoded)) {
          _invalid();
        }
        bytes = base64.decode(encoded);
        if (bytes.length > maxMimeBytes) _quota();
      }
      result.add(
        EwsItem(
          id: id.id,
          changeKey: id.changeKey,
          envelope: envelope,
          flags: flags,
          mimeBytes: bytes,
          parentFolderId: parentFolderId,
        ),
      );
    }
    return List.unmodifiable(result);
  });

  /// Checks every response before exposing mutation acknowledgment or new IDs.
  List<EwsItemId> mutation(String xml, String action) => _guard(() {
    if (!const {
      'UpdateItem',
      'MoveItem',
      'DeleteItem',
      'CreateItem',
    }.contains(action)) {
      _invalid();
    }
    final responses = _responses(xml, action);
    if (responses.length != 1) _invalid();
    final response = responses.single!;
    final container = _optional(response, 'Items', _messages);
    final result = <EwsItemId>[];
    if (container != null) {
      for (final item in container.childElements) {
        _mailItem(item);
        result.add(_id(_one(item, 'ItemId', _types)));
      }
    }
    if (action == 'DeleteItem' || action == 'CreateItem') {
      if (result.isNotEmpty) _invalid();
    } else if (action == 'MoveItem' ? result.length > 1 : result.length != 1) {
      _invalid();
    }
    return List.unmodifiable(result);
  });

  List<XmlElement?> _responses(
    String xml,
    String action, {
    bool allowMissing = false,
    bool taskMutation = false,
  }) {
    if (xml.length > limits.maxResponseBytes ||
        utf8.encode(xml).length > limits.maxResponseBytes) {
      _quota();
    }
    var depth = 0;
    var nodes = 0;
    // Pull parsing bounds nesting and node work before allocating a DOM. The
    // XML package validates namespaces and document form; duplicate expanded
    // attribute names are rejected here rather than relying on DOM lookup order.
    for (final event in parseEvents(
      xml,
      validateNesting: true,
      validateNamespace: true,
      validateDocument: true,
      withNamespace: true,
    )) {
      if (++nodes > limits.maxXmlNodes) _quota();
      if (event is XmlDoctypeEvent) _invalid();
      if (event is XmlStartElementEvent) {
        final attributes = <(String?, String)>{};
        for (final attribute in event.attributes) {
          if (++nodes > limits.maxXmlNodes) _quota();
          if (!attributes.add((attribute.namespaceUri, attribute.localName))) {
            _invalid();
          }
        }
        if (depth + 1 > limits.maxXmlDepth) _quota();
        if (!event.isSelfClosing) depth++;
      } else if (event is XmlEndElementEvent) {
        depth--;
      }
    }
    if (depth != 0) _invalid();
    final root = XmlDocument.parse(xml).rootElement;
    if (root.name.local != 'Envelope' || root.namespaceUri != _soap) _invalid();
    final body = _one(root, 'Body', _soap);
    if (_optional(body, 'Fault', _soap) case final fault?) {
      final detail = _optional(fault, 'detail', null);
      final codeElement = detail == null
          ? null
          : _optional(detail, 'ResponseCode', _errors) ??
                _optional(detail, 'ResponseCode', _messages);
      final code = codeElement == null
          ? null
          : _text(codeElement, _HeaderBudget(256));
      throw EwsException(
        _errorCode(code),
        retryAfter: detail == null ? null : _retryAfter(detail),
        invalidSyncState:
            action == 'SyncFolderItems' && code == 'ErrorInvalidSyncStateData',
      );
    }
    final bodies = body.childElements.toList();
    if (bodies.length != 1 ||
        bodies.single.name.local != '${action}Response' ||
        bodies.single.namespaceUri != _messages) {
      _invalid();
    }
    final responseMessages = _one(bodies.single, 'ResponseMessages', _messages);
    final result = <XmlElement?>[];
    for (final response in responseMessages.childElements) {
      if (response.name.local != '${action}ResponseMessage' ||
          response.namespaceUri != _messages) {
        _invalid();
      }
      final code = _text(
        _one(response, 'ResponseCode', _messages),
        _HeaderBudget(256),
      );
      final responseClass = response.getAttribute('ResponseClass');
      if (responseClass != 'Success' || code != 'NoError') {
        if (responseClass == 'Error' &&
            code == 'ErrorItemNotFound' &&
            allowMissing &&
            action == 'GetItem') {
          result.add(null);
        } else {
          throw EwsException(
            _errorCode(code),
            retryAfter: _retryAfter(response),
            confirmedRejection:
                taskMutation &&
                responseClass == 'Error' &&
                responseMessages.childElements.length == 1 &&
                const {
                  'ErrorAccessDenied',
                  'ErrorInvalidChangeKey',
                  'ErrorStaleObject',
                  'ErrorIrresolvableConflict',
                  'ErrorItemNotFound',
                  'ErrorCannotCreateTaskInNonTaskFolder',
                }.contains(code),
            invalidSyncState:
                responseClass == 'Error' &&
                action == 'SyncFolderItems' &&
                code == 'ErrorInvalidSyncStateData',
          );
        }
      } else {
        result.add(response);
      }
      if (result.length > limits.maxPageSize) _quota();
    }
    if (result.isEmpty) _invalid();
    return result;
  }

  Duration? _retryAfter(XmlElement response) {
    final messageXml =
        _optional(response, 'MessageXml', _messages) ??
        _optional(response, 'MessageXml', _types);
    if (messageXml == null) return null;
    Duration? result;
    for (final value in messageXml.childElements) {
      if (value.name.local == 'Value' &&
          value.namespaceUri == _types &&
          value.getAttribute('Name') == 'BackOffMilliseconds') {
        final milliseconds = int.tryParse(value.innerText);
        if (result != null ||
            milliseconds == null ||
            milliseconds < 0 ||
            milliseconds > 86400000) {
          _invalid();
        }
        result = Duration(milliseconds: milliseconds);
      }
    }
    return result;
  }

  static MailProblemCode _errorCode(String? code) => switch (code) {
    'ErrorAccessDenied' ||
    'ErrorImpersonateUserDenied' ||
    'ErrorDelegateNoUser' ||
    'ErrorAccountDisabled' => MailProblemCode.permissionDenied,
    'ErrorInvalidClientSecurityContext' ||
    'ErrorInvalidUserSid' ||
    'ErrorInvalidExchangeImpersonationHeaderData' =>
      MailProblemCode.authenticationRequired,
    'ErrorInvalidSyncStateData' ||
    'ErrorSyncFolderNotFound' ||
    'ErrorIrresolvableConflict' ||
    'ErrorChangeKeyRequiredForWriteOperations' ||
    'ErrorInvalidChangeKey' ||
    'ErrorStaleObject' => MailProblemCode.conflict,
    'ErrorItemNotFound' ||
    'ErrorFolderNotFound' ||
    'ErrorServerBusy' ||
    'ErrorInternalServerTransientError' ||
    'ErrorTimeoutExpired' ||
    'ErrorMailboxMoveInProgress' ||
    'ErrorMailboxStoreUnavailable' => MailProblemCode.unavailable,
    'ErrorQuotaExceeded' ||
    'ErrorExceededConnectionCount' ||
    'ErrorExceededSubscriptionCount' ||
    'ErrorExceededFindCountLimit' => MailProblemCode.quotaExceeded,
    'ErrorInvalidServerVersion' ||
    'ErrorInvalidRequest' ||
    'ErrorNotSupported' ||
    'ErrorUnsupportedPathForQuery' ||
    'ErrorPropertyRequestFailed' => MailProblemCode.unsupported,
    'ErrorInvalidIdMalformed' ||
    'ErrorInvalidIdEmpty' ||
    'ErrorInvalidPropertyRequest' ||
    'ErrorInvalidPropertySet' => MailProblemCode.invalidInput,
    _ => MailProblemCode.providerFailure,
  };

  static (bool, int?) _page(XmlElement root) {
    final last = _parseBoolean(root.getAttribute('IncludesLastItemInRange'));
    final offset = root.getAttribute('IndexedPagingOffset');
    final next = offset == null ? null : int.tryParse(offset);
    if (offset != null && (next == null || next < 0 || next > 0x7fffffff) ||
        !last && next == null) {
      _invalid();
    }
    return (last, next);
  }

  static List<MailAddress> _addresses(
    XmlElement item,
    String name,
    _HeaderBudget budget,
  ) {
    final container = _optional(item, name, _types);
    if (container == null) return const [];
    final result = <MailAddress>[];
    for (final address in container.childElements) {
      if (address.name.local != 'Mailbox' || address.namespaceUri != _types) {
        _invalid();
      }
      final value = _optionalText(address, 'EmailAddress', budget);
      if (value == null || value.isEmpty) _invalid();
      result.add(
        MailAddress(value, displayName: _optionalText(address, 'Name', budget)),
      );
    }
    return result;
  }

  static void _mailItem(XmlElement element) {
    if (element.namespaceUri != _types) _invalid();
    if (!const {
      'Message',
      'MeetingMessage',
      'MeetingRequest',
      'MeetingResponse',
      'MeetingCancellation',
    }.contains(element.name.local)) {
      throw const EwsException(MailProblemCode.unsupported);
    }
  }

  static EwsItemId _id(XmlElement element) => EwsItemId(
    _identifier(element.getAttribute('Id')),
    _identifier(element.getAttribute('ChangeKey')),
  );

  static String _identifier(String? value) {
    if (value == null ||
        value.isEmpty ||
        value.length > 1024 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      _invalid();
    }
    return value;
  }

  static String? _optionalIdentifier(String? value) =>
      value == null ? null : _identifier(value);

  static XmlElement _one(XmlElement parent, String name, String? namespace) =>
      _optional(parent, name, namespace) ?? _invalid();

  static XmlElement? _optional(
    XmlElement parent,
    String name,
    String? namespace,
  ) {
    final values = parent.childElements
        .where(
          (element) =>
              element.name.local == name && element.namespaceUri == namespace,
        )
        .toList();
    if (values.length > 1) _invalid();
    return values.isEmpty ? null : values.single;
  }

  static String _text(XmlElement element, _HeaderBudget budget) {
    if (element.childElements.isNotEmpty) _invalid();
    final value = element.innerText;
    budget.add(value);
    return value;
  }

  static String? _optionalText(
    XmlElement parent,
    String name,
    _HeaderBudget budget,
  ) {
    final element = _optional(parent, name, _types);
    return element == null ? null : _text(element, budget);
  }

  static bool _boolean(XmlElement element) {
    if (element.childElements.isNotEmpty) _invalid();
    return _parseBoolean(element.innerText);
  }

  static bool _parseBoolean(String? text) => switch (text) {
    'true' || '1' => true,
    'false' || '0' => false,
    _ => _invalid(),
  };

  static T _guard<T>(T Function() action) {
    try {
      return action();
    } on EwsException {
      rethrow;
    } on Object {
      throw const EwsException(MailProblemCode.providerFailure);
    }
  }

  static Never _invalid() =>
      throw const EwsException(MailProblemCode.providerFailure);
  static Never _quota() =>
      throw const EwsException(MailProblemCode.quotaExceeded);
}

final class _HeaderBudget {
  _HeaderBudget(this.limit);
  final int limit;
  int used = 0;
  void add(String value) {
    used += utf8.encode(value).length;
    if (used > limit) throw const EwsException(MailProblemCode.quotaExceeded);
  }
}
