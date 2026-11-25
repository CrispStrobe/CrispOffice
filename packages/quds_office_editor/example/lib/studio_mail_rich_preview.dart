import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_rich_preview_data.dart';

/// Read-only rendering of the canonical authoring model, without an HTML
/// renderer, gesture recognizers, resource callbacks or link launching.
class StudioMailRichPreview extends StatelessWidget {
  const StudioMailRichPreview({
    super.key,
    required this.body,
    required this.truncationNotice,
  });

  final MailComposeBody body;
  final String truncationNotice;

  @override
  Widget build(BuildContext context) {
    final preview = StudioMailRichPreviewData(body);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < preview.paragraphs.length; index++)
          SelectableText.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                for (final run in preview.paragraphs[index].runs)
                  TextSpan(
                    text: run.text,
                    style: TextStyle(
                      fontWeight: run.bold
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontStyle: run.italic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: run.link == null
                          ? null
                          : theme.colorScheme.primary,
                      decoration: TextDecoration.combine([
                        if (run.underline) TextDecoration.underline,
                        if (run.strike) TextDecoration.lineThrough,
                      ]),
                    ),
                  ),
              ],
            ),
            key: ValueKey('studio-mail-rich-preview-paragraph-$index'),
            minLines: 1,
            textAlign: switch (preview.paragraphs[index].alignment) {
              MailComposeAlignment.left => TextAlign.left,
              MailComposeAlignment.center => TextAlign.center,
              MailComposeAlignment.right => TextAlign.right,
              MailComposeAlignment.justify => TextAlign.justify,
            },
            textDirection: switch (preview.paragraphs[index].rightToLeft) {
              true => TextDirection.rtl,
              false => TextDirection.ltr,
              null => null,
            },
          ),
        if (preview.truncated)
          Text(
            truncationNotice,
            key: const ValueKey('studio-mail-rich-preview-truncated'),
          ),
      ],
    );
  }
}
