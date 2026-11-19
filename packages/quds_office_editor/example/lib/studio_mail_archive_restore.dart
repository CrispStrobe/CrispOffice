import 'package:flutter/material.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_archive_restore_strings.dart';
import 'studio_mail_archive_strings.dart';
import 'studio_strings.dart';

final class StudioMailArchiveRestoreOptions {
  const StudioMailArchiveRestoreOptions({
    required this.indexAttachmentText,
    this.resume = false,
  });

  final bool indexAttachmentText;
  final bool resume;
}

/// Preview is informational until the user explicitly starts restoration.
class StudioMailArchiveRestoreDialog extends StatefulWidget {
  const StudioMailArchiveRestoreDialog({
    super.key,
    required this.strings,
    required this.plan,
    this.indexAttachmentText = false,
  });

  final StudioStrings strings;
  final MailArchiveRestorePlan plan;
  final bool indexAttachmentText;

  @override
  State<StudioMailArchiveRestoreDialog> createState() =>
      _StudioMailArchiveRestoreDialogState();
}

class _StudioMailArchiveRestoreDialogState
    extends State<StudioMailArchiveRestoreDialog> {
  late bool _attachments = widget.indexAttachmentText;
  late bool _resume = (widget.plan.checkpoint?.completedMessages ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final plan = widget.plan;
    final createdAt = plan.createdAt
        .toUtc()
        .toIso8601String()
        .split('.')
        .first
        .replaceFirst('T', ' ');
    return Directionality(
      textDirection: s.language == StudioLanguage.ar
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: AlertDialog(
        scrollable: true,
        title: Text(s.archiveRestoreExport),
        content: SizedBox(
          width: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.archiveRestoreSelection(
                  plan.messageCount,
                  plan.originCount,
                  plan.totalBytes,
                ),
                key: const ValueKey('archive-restore-selection'),
              ),
              const SizedBox(height: 12),
              Text(
                s.archiveRestoreSourceProfile(
                  plan.sourceProfile.hostId,
                  plan.sourceProfile.value,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              Text(s.archiveRestoreCreatedAt('\u2066$createdAt UTC\u2069')),
              Text(
                s.archiveRestoreExportId(plan.manifestSha256.substring(0, 16)),
                key: const ValueKey('archive-restore-export-id'),
              ),
              const SizedBox(height: 8),
              SelectableText(
                plan.directoryPath,
                key: const ValueKey('archive-restore-directory'),
                textDirection: TextDirection.ltr,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              Text(s.archiveRestoreTrust),
              const SizedBox(height: 8),
              Text(s.archiveRestoreHelp),
              if (plan.checkpoint case final checkpoint?) ...[
                const SizedBox(height: 12),
                Text(
                  s.archiveRestoreRecorded(
                    checkpoint.completedMessages,
                    checkpoint.planned,
                    checkpoint.completedBytes,
                  ),
                  key: const ValueKey('archive-restore-recorded'),
                ),
                if (checkpoint.completedMessages > 0)
                  CheckboxListTile(
                    key: const ValueKey('archive-restore-resume'),
                    contentPadding: EdgeInsets.zero,
                    value: _resume,
                    title: Text(s.archiveRestoreResume),
                    subtitle: Text(s.archiveRestoreResumeHelp),
                    onChanged: (value) =>
                        setState(() => _resume = value ?? false),
                  ),
              ],
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey('archive-restore-attachments'),
                contentPadding: EdgeInsets.zero,
                value: _attachments,
                title: Text(s.archiveIndexAttachmentText),
                subtitle: Text(s.archiveAttachmentHelp),
                onChanged: (value) =>
                    setState(() => _attachments = value ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('archive-restore-dismiss'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.archiveCancel),
          ),
          FilledButton(
            key: const ValueKey('archive-restore-confirm'),
            onPressed: () => Navigator.of(context).pop(
              StudioMailArchiveRestoreOptions(
                indexAttachmentText: _attachments,
                resume: _resume,
              ),
            ),
            child: Text(
              _resume ? s.archiveRestoreResumeStart : s.archiveRestoreStart,
            ),
          ),
        ],
      ),
    );
  }
}
