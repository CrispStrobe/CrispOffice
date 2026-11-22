import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_mutation_strings.dart';
import 'studio_strings.dart';

/// Review a frozen selection and choose an exact same-account destination.
/// Selecting a folder only changes this dialog; the caller owns all commands.
Future<MailMailboxId?> showStudioMailMoveSelection(
  BuildContext context, {
  required StudioStrings strings,
  required int count,
  required String accountLabel,
  required MailMailbox source,
  required List<MailMailbox> destinations,
}) async {
  if (count < 1 || count > MailBulkFlagPlan.maxMessages) return null;
  final candidates = List<MailMailbox>.unmodifiable(
    destinations.where(
      (folder) =>
          folder.id.account == source.id.account && folder.id != source.id,
    ),
  );
  if (candidates.map((folder) => folder.id).toSet().length !=
      candidates.length) {
    return null;
  }
  MailMailboxId? selected;
  return showDialog<MailMailboxId>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Directionality(
        textDirection: strings.language == StudioLanguage.ar
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: AlertDialog(
          key: const ValueKey('studio-mail-move-selection-dialog'),
          scrollable: true,
          title: Text(strings.mailMoveSelection),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SelectionScope(
                  strings: strings,
                  count: count,
                  accountLabel: accountLabel,
                  source: source,
                ),
                const SizedBox(height: 12),
                Text(strings.mailOrganizationMoveExplanation),
                const SizedBox(height: 16),
                Text(strings.mailOrganizationDestination),
                if (candidates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(strings.mailOrganizationNoDestination),
                  ),
                for (var index = 0; index < candidates.length; index++)
                  ListTile(
                    key: ValueKey('studio-mail-move-destination-$index'),
                    contentPadding: EdgeInsets.zero,
                    selected: selected == candidates[index].id,
                    title: Text(candidates[index].displayName),
                    subtitle: Text(
                      candidates[index].id.value,
                      textDirection: TextDirection.ltr,
                    ),
                    leading: Icon(
                      selected == candidates[index].id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: () =>
                        setState(() => selected = candidates[index].id),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('studio-mail-organization-cancel'),
              onPressed: () => Navigator.pop(context),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const ValueKey('studio-mail-move-apply'),
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, selected),
              child: Text(strings.mailOrganizationApplyMove),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Confirm provider-specific trash or IMAP deletion-marker semantics.
/// This dialog never performs a provider or repository operation.
Future<bool> confirmStudioMailDeleteSelection(
  BuildContext context, {
  required StudioStrings strings,
  required int count,
  required String accountLabel,
  required MailMailbox source,
  required MailProviderKind provider,
}) async {
  if (count < 1 || count > MailBulkFlagPlan.maxMessages) return false;
  return await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: strings.language == StudioLanguage.ar
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: AlertDialog(
            key: const ValueKey('studio-mail-delete-selection-dialog'),
            scrollable: true,
            title: Text(strings.mailDeleteAction(provider)),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SelectionScope(
                    strings: strings,
                    count: count,
                    accountLabel: accountLabel,
                    source: source,
                  ),
                  const SizedBox(height: 12),
                  Text(strings.mailOrganizationDeleteExplanation(provider)),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('studio-mail-organization-cancel'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                key: const ValueKey('studio-mail-delete-apply'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.mailDeleteAction(provider)),
              ),
            ],
          ),
        ),
      ) ??
      false;
}

class _SelectionScope extends StatelessWidget {
  const _SelectionScope({
    required this.strings,
    required this.count,
    required this.accountLabel,
    required this.source,
  });

  final StudioStrings strings;
  final int count;
  final String accountLabel;
  final MailMailbox source;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        strings.mailOrganizationCount(count),
        key: const ValueKey('studio-mail-organization-count'),
      ),
      const SizedBox(height: 12),
      Text(strings.account),
      Text(
        accountLabel,
        key: const ValueKey('studio-mail-organization-account'),
        textDirection: TextDirection.ltr,
      ),
      const SizedBox(height: 12),
      Text(strings.mailOrganizationSource),
      Text(source.displayName),
      Text(
        source.id.value,
        key: const ValueKey('studio-mail-organization-source'),
        textDirection: TextDirection.ltr,
      ),
    ],
  );
}
