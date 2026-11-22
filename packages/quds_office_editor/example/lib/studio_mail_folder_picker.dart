import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_saved_search_strings.dart';
import 'studio_strings.dart';

/// One observed local mailbox, or an explicitly missing saved membership.
/// Account and mailbox IDs are exact identities, never display-name matches.
final class StudioMailFolderOption {
  const StudioMailFolderOption({
    required this.folder,
    required this.accountLabel,
    required this.displayName,
    required this.available,
  });

  final MailSavedHeaderSearchFolder folder;
  final String accountLabel;
  final String displayName;
  final bool available;
}

/// A deliberate choice between all retained folders and an exact folder set.
/// Cancel returns null from showDialog and preserves the previous selection.
final class StudioMailFolderChoice {
  const StudioMailFolderChoice.all()
      : allFolders = true,
        folders = const [];

  StudioMailFolderChoice.exact(List<MailSavedHeaderSearchFolder> folders)
      : allFolders = false,
        folders = List.unmodifiable(folders);

  final bool allFolders;
  final List<MailSavedHeaderSearchFolder> folders;
}

/// Purely local folder selection. Never constructs a provider or credential
/// store, and never mutates a saved search until its parent explicitly saves.
class StudioMailFolderPickerDialog extends StatefulWidget {
  const StudioMailFolderPickerDialog({
    super.key,
    required this.strings,
    required this.accountIds,
    required this.options,
    required this.initialFolders,
  });

  final StudioStrings strings;
  final List<String> accountIds;
  final List<StudioMailFolderOption> options;
  final List<MailSavedHeaderSearchFolder>? initialFolders;

  @override
  State<StudioMailFolderPickerDialog> createState() =>
      _StudioMailFolderPickerDialogState();
}

class _StudioMailFolderPickerDialogState
    extends State<StudioMailFolderPickerDialog> {
  late final Set<MailSavedHeaderSearchFolder> _checked =
      widget.initialFolders == null
      ? {
          for (final option in widget.options)
            if (option.available) option.folder,
        }
      : widget.initialFolders!.toSet();

  bool get _valid {
    if (_checked.isEmpty ||
        _checked.length > MailSavedHeaderSearch.maxFolderScopes ||
        widget.accountIds.isEmpty) {
      return false;
    }
    final covered = {for (final folder in _checked) folder.accountId};
    if (widget.accountIds.any((id) => !covered.contains(id))) return false;
    final options = {
      for (final option in widget.options) option.folder: option,
    };
    return _checked.every((folder) => options[folder]?.available == true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.mailSavedSearchChooseFolders),
    content: SizedBox(
      width: 520,
      height: 420,
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(widget.strings.mailSavedSearchFolderScopeHelp),
          for (final option in widget.options)
            CheckboxListTile(
              key: ValueKey(
                'studio-mail-folder-' +
                    option.folder.accountId +
                    '-' +
                    option.folder.mailboxId,
              ),
              value: _checked.contains(option.folder),
              isThreeLine: true,
              title: Text(option.displayName),
              subtitle: Text(
                option.accountLabel +
                    '\n' +
                    (option.available
                        ? option.folder.mailboxId
                        : widget.strings.mailSavedSearchFolderMissing),
              ),
              onChanged: (selected) {
                if (selected == true && !option.available) return;
                setState(() {
                  if (selected == true) {
                    _checked.add(option.folder);
                  } else {
                    _checked.remove(option.folder);
                  }
                });
              },
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(widget.strings.cancel),
      ),
      TextButton(
        key: const ValueKey('studio-mail-folder-all'),
        onPressed: () =>
            Navigator.of(context).pop(const StudioMailFolderChoice.all()),
        child: Text(widget.strings.mailSavedSearchAllFolders),
      ),
      FilledButton(
        key: const ValueKey('studio-mail-folder-apply'),
        onPressed: !_valid
            ? null
            : () => Navigator.of(context).pop(
                StudioMailFolderChoice.exact([
                  for (final option in widget.options)
                    if (_checked.contains(option.folder)) option.folder,
                ]),
              ),
        child: Text(widget.strings.mailSavedSearchApplyFolders),
      ),
    ],
  );
}
