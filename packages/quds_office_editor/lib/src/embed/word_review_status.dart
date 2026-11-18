import 'package:flutter/material.dart';

import 'office_controller.dart';

/// Always-visible entry points and honest live-check status for Word review.
/// This is host chrome; it never edits the document or starts manual providers.
class WordReviewStatusBar extends StatelessWidget {
  const WordReviewStatusBar({super.key, required this.controller});

  final WordEditorController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final session = controller.proofing;
      final summary = session.summary;
      final arabic = controller.config.textDirection == TextDirection.rtl;
      final pending = controller.document.revisions
          .where((revision) => revision.accepted == null)
          .length;
      final String label;
      final IconData icon;
      if (summary.checking) {
        label = arabic ? 'جارٍ التدقيق…' : 'Checking…';
        icon = Icons.hourglass_top;
      } else if (summary.scheduled) {
        label = arabic ? 'بانتظار توقف الكتابة…' : 'Waiting to check…';
        icon = Icons.more_horiz;
      } else if (!session.enabled) {
        label = arabic ? 'التدقيق التلقائي متوقف' : 'Live checking paused';
        icon = Icons.pause_circle_outline;
      } else if (!summary.hasResults) {
        label = arabic ? 'لم يُدقّق بعد' : 'Not checked yet';
        icon = Icons.spellcheck;
      } else if (!summary.complete) {
        label = arabic
            ? '${summary.issues.length} ملاحظات · تدقيق جزئي'
            : '${summary.issues.length} issues · partial check';
        icon = Icons.info_outline;
      } else {
        label = summary.issues.isEmpty
            ? (arabic ? 'لا توجد ملاحظات' : 'No writing issues')
            : (arabic
                  ? '${summary.issues.length} ملاحظات'
                  : '${summary.issues.length} writing issues');
        icon = summary.issues.isEmpty
            ? Icons.check_circle_outline
            : Icons.spellcheck;
      }
      return Material(
        key: const ValueKey('word-review-status'),
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: summary.statusMessage,
                  child: TextButton.icon(
                    key: const ValueKey('word-review-writing-status'),
                    onPressed: () => controller.openReviewPane(),
                    icon: Icon(icon, size: 17),
                    label: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: TextButton.styleFrom(
                      alignment: AlignmentDirectional.centerStart,
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: arabic
                    ? 'مراجعة التغييرات المتعقبة'
                    : 'Review tracked changes',
                child: TextButton.icon(
                  key: const ValueKey('word-review-changes-status'),
                  onPressed: () =>
                      controller.openReviewPane(tab: WordReviewPaneTab.changes),
                  icon: Icon(
                    controller.document.trackRevisions
                        ? Icons.track_changes
                        : Icons.rate_review_outlined,
                    size: 17,
                  ),
                  label: Text(arabic ? '$pending تغييرات' : '$pending changes'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
