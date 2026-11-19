import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_archive_restore_strings.dart';
import 'studio_mail_archive_strings.dart';
import 'studio_strings.dart';

/// Manage only durable restore receipts. Forgetting one never deletes mail.
class StudioMailArchiveRestoreProgressDialog extends StatefulWidget {
  const StudioMailArchiveRestoreProgressDialog({
    super.key,
    required this.strings,
    required this.checkpoints,
    required this.onForget,
  });

  final StudioStrings strings;
  final List<MailArchiveRestoreCheckpoint> checkpoints;
  final Future<MailResult<MailUnit>> Function(String manifestSha256) onForget;

  @override
  State<StudioMailArchiveRestoreProgressDialog> createState() =>
      _StudioMailArchiveRestoreProgressDialogState();
}

class _StudioMailArchiveRestoreProgressDialogState
    extends State<StudioMailArchiveRestoreProgressDialog> {
  late final _checkpoints = [...widget.checkpoints];
  bool _forgetting = false;
  String? _error;

  Future<void> _forget(MailArchiveRestoreCheckpoint checkpoint) async {
    if (_forgetting) return;
    final s = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: s.language == StudioLanguage.ar
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: AlertDialog(
          scrollable: true,
          title: Text(s.archiveRestoreForget),
          content: SizedBox(
            width: 440,
            child: Text(
              s.archiveRestoreForgetConfirmation(
                checkpoint.manifestSha256.substring(0, 16),
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('archive-restore-forget-dismiss'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.archiveCancel),
            ),
            FilledButton(
              key: const ValueKey('archive-restore-forget-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.archiveRestoreForget),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _forgetting = true;
      _error = null;
    });
    MailResult<MailUnit> result;
    try {
      result = await widget.onForget(checkpoint.manifestSha256);
    } on Object {
      result = const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
    if (!mounted) return;
    setState(() {
      _forgetting = false;
      switch (result) {
        case MailSuccess():
          _checkpoints.removeWhere(
            (entry) => entry.manifestSha256 == checkpoint.manifestSha256,
          );
        case MailFailure(:final problem):
          _error = s.archiveProblem(problem.code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Directionality(
      textDirection: s.language == StudioLanguage.ar
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: PopScope(
        canPop: !_forgetting,
        child: AlertDialog(
          key: const ValueKey('archive-restore-progress-dialog'),
          scrollable: true,
          title: Text(s.archiveRestoreProgress),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.archiveRestoreProgressHelp),
                const SizedBox(height: 12),
                if (_checkpoints.isEmpty)
                  Text(
                    s.archiveRestoreProgressEmpty,
                    key: const ValueKey('archive-restore-progress-empty'),
                  )
                else
                  SizedBox(
                    height:
                        (MediaQuery.textScalerOf(context).scale(144) *
                                _checkpoints.length)
                            .clamp(0, MediaQuery.sizeOf(context).height * .4),
                    child: ListView.separated(
                      key: const ValueKey('archive-restore-checkpoints'),
                      shrinkWrap: true,
                      itemCount: _checkpoints.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final checkpoint = _checkpoints[index];
                        return Column(
                          key: ValueKey(
                            'archive-restore-checkpoint-${checkpoint.manifestSha256}',
                          ),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: checkpoint.manifestSha256,
                              child: Text(
                                s.archiveRestoreExportId(
                                  checkpoint.manifestSha256.substring(0, 16),
                                ),
                              ),
                            ),
                            Text(
                              s.archiveRestoreRecorded(
                                checkpoint.completedMessages,
                                checkpoint.planned,
                                checkpoint.completedBytes,
                              ),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                key: ValueKey('archive-restore-forget-$index'),
                                onPressed: _forgetting
                                    ? null
                                    : () => _forget(checkpoint),
                                icon: const Icon(Icons.delete_outline),
                                label: Text(s.archiveRestoreForget),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                if (_forgetting) const LinearProgressIndicator(),
                if (_error case final error?)
                  Text(
                    error,
                    key: const ValueKey('archive-restore-progress-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('archive-restore-progress-close'),
              onPressed: _forgetting ? null : () => Navigator.of(context).pop(),
              child: Text(s.close),
            ),
          ],
        ),
      ),
    );
  }
}
