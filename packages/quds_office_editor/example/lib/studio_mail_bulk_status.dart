import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_strings.dart';

/// Foreground progress and an immutable, per-message command receipt.
///
/// Subjects are captured with the plan, so a later row refresh never relabels an
/// earlier result. Provider text and remote identifiers are not displayed.
class StudioMailBulkStatus extends StatelessWidget {
  const StudioMailBulkStatus({
    super.key,
    required this.strings,
    required this.report,
    required this.running,
    required this.subjects,
    this.onStop,
    this.onDismiss,
  });

  final StudioStrings strings;
  final MailBulkFlagReport report;
  final bool running;
  final Map<MailRemoteIdentity, String> subjects;
  final VoidCallback? onStop;
  final VoidCallback? onDismiss;

  String _text(String en, String de, String ar) => switch (strings.language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get _action => switch (report.plan.action) {
    MailBulkFlagAction.markRead => _text(
      'Mark read',
      'Als gelesen markieren',
      'تحديد كمقروءة',
    ),
    MailBulkFlagAction.markUnread => _text(
      'Mark unread',
      'Als ungelesen markieren',
      'تحديد كغير مقروءة',
    ),
    MailBulkFlagAction.flag => _text(
      'Flag messages',
      'Kennzeichnen',
      'تعليم الرسائل',
    ),
    MailBulkFlagAction.unflag => _text(
      'Unflag messages',
      'Kennzeichnung entfernen',
      'إزالة تعليم الرسائل',
    ),
  };

  String _outcome(MailBulkFlagOutcome value) => switch (value) {
    MailBulkFlagOutcome.confirmed => _text('Confirmed', 'Bestätigt', 'مؤكدة'),
    MailBulkFlagOutcome.failed => _text('Failed', 'Fehlgeschlagen', 'فشلت'),
    MailBulkFlagOutcome.uncertain => _text(
      'Uncertain',
      'Ungewiss',
      'غير مؤكدة',
    ),
    MailBulkFlagOutcome.unattempted => _text(
      'Not attempted',
      'Nicht versucht',
      'لم تُحاول',
    ),
  };

  String _explanation(MailBulkFlagOutcome value) => switch (value) {
    MailBulkFlagOutcome.confirmed => _text(
      'The server confirmed the requested state.',
      'Der Server hat den gewünschten Status bestätigt.',
      'أكد الخادم الحالة المطلوبة.',
    ),
    MailBulkFlagOutcome.failed => _text(
      'The request failed without changing this message.',
      'Die Anfrage ist fehlgeschlagen, ohne diese Nachricht zu ändern.',
      'فشل الطلب دون تغيير هذه الرسالة.',
    ),
    MailBulkFlagOutcome.uncertain => _text(
      'The server may have changed this message. Refresh before another change.',
      'Der Server könnte diese Nachricht geändert haben. Vor einer weiteren Änderung aktualisieren.',
      'ربما غيّر الخادم هذه الرسالة. حدّث القائمة قبل إجراء تغيير آخر.',
    ),
    MailBulkFlagOutcome.unattempted => _text(
      'No request was sent for this message.',
      'Für diese Nachricht wurde keine Anfrage gesendet.',
      'لم يُرسل أي طلب لهذه الرسالة.',
    ),
  };

  Future<void> _details(BuildContext context) async {
    final direction = Directionality.of(context);
    final media = MediaQuery.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: media,
          child: Dialog(
            key: const ValueKey('studio-mail-bulk-details-dialog'),
            insetPadding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _action,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: report.results.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final result = report.results[index];
                        final subject = subjects[result.message];
                        return Padding(
                          key: ValueKey('studio-mail-bulk-result-$index'),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subject == null || subject.isEmpty
                                    ? _text(
                                        '(No subject)',
                                        '(Kein Betreff)',
                                        '(بلا موضوع)',
                                      )
                                    : subject,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(_outcome(result.outcome)),
                              Text(_explanation(result.outcome)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        key: const ValueKey('studio-mail-bulk-details-close'),
                        onPressed: () => Navigator.pop(context),
                        child: Text(_text('Close', 'Schließen', 'إغلاق')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attempted = report.results.length - report.unattemptedCount;
    return Material(
      key: const ValueKey('studio-mail-bulk-status'),
      color: report.requiresRefresh
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_action, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final outcome in MailBulkFlagOutcome.values)
                  Text(
                    '${running && outcome == MailBulkFlagOutcome.unattempted ? _text('Pending', 'Ausstehend', 'قيد الانتظار') : _outcome(outcome)}: ${report.count(outcome)}',
                    key: ValueKey('studio-mail-bulk-count-${outcome.name}'),
                  ),
              ],
            ),
            if (running) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: attempted / report.results.length,
                semanticsLabel: _text(
                  'Messages completed',
                  'Abgeschlossene Nachrichten',
                  'الرسائل المكتملة',
                ),
              ),
            ],
            if (report.requiresRefresh) ...[
              const SizedBox(height: 8),
              Text(
                _text(
                  'Stopped after an uncertain result. Refresh the folder before another change.',
                  'Nach einem ungewissen Ergebnis angehalten. Aktualisieren Sie den Ordner vor einer weiteren Änderung.',
                  'توقفت العملية بعد نتيجة غير مؤكدة. حدّث المجلد قبل إجراء تغيير آخر.',
                ),
              ),
            ] else if (!running && report.stopProblem != null) ...[
              const SizedBox(height: 8),
              Text(
                _text(
                  'Stopped. Remaining messages were not attempted.',
                  'Angehalten. Verbleibende Nachrichten wurden nicht versucht.',
                  'توقفت العملية. لم تُحاول الرسائل المتبقية.',
                ),
              ),
            ],
            Wrap(
              spacing: 8,
              children: [
                if (running)
                  TextButton(
                    key: const ValueKey('studio-mail-bulk-stop'),
                    onPressed: onStop,
                    child: Text(
                      onStop == null
                          ? _text(
                              'Stopping after current message…',
                              'Wird nach der aktuellen Nachricht angehalten…',
                              'جارٍ التوقف بعد الرسالة الحالية…',
                            )
                          : _text(
                              'Stop after current message',
                              'Nach aktueller Nachricht anhalten',
                              'توقف بعد الرسالة الحالية',
                            ),
                    ),
                  ),
                TextButton(
                  key: const ValueKey('studio-mail-bulk-details'),
                  onPressed: running ? null : () => _details(context),
                  child: Text(_text('Details', 'Einzelheiten', 'التفاصيل')),
                ),
                if (!running && !report.requiresRefresh && onDismiss != null)
                  TextButton(
                    key: const ValueKey('studio-mail-bulk-dismiss'),
                    onPressed: onDismiss,
                    child: Text(_text('Dismiss', 'Ausblenden', 'إخفاء')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
