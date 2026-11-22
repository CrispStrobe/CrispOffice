import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_cached_search.dart';
import 'studio_mail_search_folder_strings.dart';
import 'studio_strings.dart';

/// A cancelled dialog returns no object. A null [folders] value here means
/// the user explicitly chose every folder within the captured account scope.
final class StudioMailSearchFolderSelection {
  StudioMailSearchFolderSelection(List<MailSavedHeaderSearchFolder>? folders)
    : folders = folders == null ? null : List.unmodifiable(folders);

  final List<MailSavedHeaderSearchFolder>? folders;
}

/// Local folder selection. Labels are presentation only; account/mailbox IDs
/// keep identically named folders and unavailable selections independent.
class StudioMailSearchFolderPicker extends StatefulWidget {
  const StudioMailSearchFolderPicker({
    super.key,
    required this.strings,
    required this.catalog,
    this.selectedFolders,
  });

  final StudioStrings strings;
  final List<StudioMailCachedSearchFolderCatalog> catalog;
  final List<MailSavedHeaderSearchFolder>? selectedFolders;

  @override
  State<StudioMailSearchFolderPicker> createState() =>
      _StudioMailSearchFolderPickerState();
}

final class _FolderPickerRow {
  const _FolderPickerRow(this.catalog, [this.folder, this.available = false]);
  final StudioMailCachedSearchFolderCatalog catalog;
  final MailSavedHeaderSearchFolder? folder;
  final bool available;
}

class _StudioMailSearchFolderPickerState
    extends State<StudioMailSearchFolderPicker> {
  late bool _allFolders;
  final _selected =
      <MailSavedHeaderSearchFolder, MailSavedHeaderSearchFolder>{};
  final _rows = <_FolderPickerRow>[];

  @override
  void initState() {
    super.initState();
    _allFolders = widget.selectedFolders == null;
    for (final folder
        in widget.selectedFolders ?? const <MailSavedHeaderSearchFolder>[]) {
      _selected[folder] = folder;
    }
    for (final account in widget.catalog) {
      _rows.add(_FolderPickerRow(account));
      final known = <String>{};
      for (final mailbox in account.folders) {
        known.add(mailbox.id.value);
        final folder = MailSavedHeaderSearchFolder(
          accountId: account.account.id,
          mailboxId: mailbox.id.value,
          displayName: mailbox.displayName,
        );
        // Refresh a renamed folder's label without changing its identity.
        if (_selected.containsKey(folder)) _selected[folder] = folder;
        _rows.add(_FolderPickerRow(account, folder, true));
      }
      for (final folder in _selected.values.where(
        (folder) =>
            folder.accountId == account.account.id &&
            !known.contains(folder.mailboxId),
      )) {
        _rows.add(_FolderPickerRow(account, folder));
      }
    }
  }

  bool get _valid =>
      _allFolders ||
      (_selected.isNotEmpty &&
          _selected.length <= MailSavedHeaderSearch.maxFolders &&
          _selected.values.every((folder) => folder.isValid));

  void _apply() {
    if (!_valid) return;
    final folders = _allFolders ? null : _selected.values.toList();
    folders?.sort((left, right) {
      final account = left.accountId.compareTo(right.accountId);
      return account == 0 ? left.mailboxId.compareTo(right.mailboxId) : account;
    });
    Navigator.of(context).pop(StudioMailSearchFolderSelection(folders));
  }

  Widget _row(_FolderPickerRow row) {
    final folder = row.folder;
    if (folder == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.catalog.account.sender,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              row.catalog.account.endpoint,
              textDirection: TextDirection.ltr,
            ),
            if (row.catalog.problem != null)
              Text(widget.strings.mailSearchFolderUnchecked)
            else if (row.catalog.folders.isEmpty)
              Text(widget.strings.mailSearchFolderNone),
          ],
        ),
      );
    }
    final name = folder.displayName;
    return CheckboxListTile(
      key: ValueKey(
        'studio-mail-folder-${jsonEncode([folder.accountId, folder.mailboxId])}',
      ),
      value: !_allFolders && _selected.containsKey(folder),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(name == null || name.isEmpty ? folder.mailboxId : name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (name != folder.mailboxId)
            Text(folder.mailboxId, textDirection: TextDirection.ltr),
          if (!row.available)
            Text(
              row.catalog.problem != null
                  ? widget.strings.mailSearchFolderUnchecked
                  : widget.strings.mailSearchFolderUnavailable,
            ),
        ],
      ),
      onChanged: _allFolders
          ? null
          : (value) => setState(() {
              if (value == true) {
                _selected[folder] = folder;
              } else {
                _selected.remove(folder);
              }
            }),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('studio-mail-folder-picker'),
    insetPadding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 680,
      height: 660,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              widget.strings.mailSearchFolderTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _rows.length + 1,
              itemBuilder: (context, index) => index == 0
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(widget.strings.mailSearchFolderAbout),
                          SwitchListTile.adaptive(
                            key: const ValueKey('studio-mail-folder-all'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(widget.strings.mailSearchFolderAll),
                            value: _allFolders,
                            onChanged: (value) =>
                                setState(() => _allFolders = value),
                          ),
                          if (!_allFolders)
                            Text(
                              widget.strings.mailSearchFolderCount(
                                _selected.length,
                              ),
                            ),
                          if (!_allFolders && _selected.isEmpty)
                            Text(widget.strings.mailSearchFolderRequired),
                          if (!_allFolders &&
                              _selected.length >
                                  MailSavedHeaderSearch.maxFolders)
                            Text(
                              widget.strings.mailSearchFolderLimit(
                                MailSavedHeaderSearch.maxFolders,
                              ),
                            ),
                        ],
                      ),
                    )
                  : _row(_rows[index - 1]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('studio-mail-folder-cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(widget.strings.cancel),
                ),
                FilledButton(
                  key: const ValueKey('studio-mail-folder-apply'),
                  onPressed: _valid ? _apply : null,
                  child: Text(widget.strings.mailSearchFolderApply),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
