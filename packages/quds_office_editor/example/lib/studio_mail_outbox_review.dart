import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_outbox_content.dart';
import 'studio_mail_outbox_export.dart';
import 'studio_mail_outbox_strings.dart';
import 'studio_mail_rich_preview.dart';
import 'studio_mail_rich_preview_data.dart';
import 'studio_mail_strings.dart';
import 'studio_strings.dart';

/// Read-only local review. Links are inert and no HTML renderer, attachment
/// opener or provider port is present. Exact export remains available when
/// projection is refused.
class StudioMailOutboxReviewDialog extends StatefulWidget {
  const StudioMailOutboxReviewDialog({
    super.key,
    required this.entry,
    required this.strings,
    required this.isCurrent,
    this.embedded = false,
    this.exporter = exportStudioMailOutboxFile,
  });

  final MailOutboxEntry entry;
  final StudioStrings strings;
  final bool Function() isCurrent;
  final StudioMailOutboxExporter exporter;
  final bool embedded;

  @override
  State<StudioMailOutboxReviewDialog> createState() =>
      _StudioMailOutboxReviewDialogState();
}

class _StudioMailOutboxReviewDialogState
    extends State<StudioMailOutboxReviewDialog> {
  StudioMailOutboxContent? _content;
  final _cancellation = MailCancellationSource();
  bool _busy = false;
  String? _notice;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    try {
      _content = StudioMailOutboxContent.fromEntry(widget.entry);
    } on Object {
      // Export still uses the untouched wire/envelope; no approximate preview.
    }
  }

  @override
  void dispose() {
    _cancellation.cancel(MailCancellationReason.disposed);
    super.dispose();
  }

  bool get _current => mounted && widget.isCurrent();

  Future<void> _export({required bool envelope}) async {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _notice = null;
      _failed = false;
    });
    try {
      if (envelope) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(widget.strings.mailOutboxExportEnvelope),
            content: Text(widget.strings.mailOutboxExportPrivateExplanation),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(widget.strings.cancel),
              ),
              FilledButton(
                key: const ValueKey(
                  'studio-mail-outbox-export-private-confirm',
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(widget.strings.mailOutboxExportEnvelope),
              ),
            ],
          ),
        );
        if (confirm != true || !_current) return;
      }
      final result = await widget.exporter(
        envelope ? 'outbox-recipients.json' : 'outbox-message.eml',
        envelope
            ? studioMailOutboxEnvelopeBytes(widget.entry)
            : widget.entry.prepared.wire,
        cancellation: _cancellation.token,
        isCurrent: () => _current,
      );
      if (!_current) return;
      setState(() {
        switch (result) {
          case MailSuccess<bool>(value: true):
            _notice = widget.strings.mailOutboxExported;
          case MailSuccess<bool>(value: false):
            break;
          case MailFailure<bool>(:final problem):
            if (problem.code != MailProblemCode.cancelled) {
              _notice = widget.strings.mailOutboxExportFailed;
              _failed = true;
            }
        }
      });
    } on Object {
      if (_current) {
        setState(() {
          _notice = widget.strings.mailOutboxExportFailed;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String label, String text, {bool address = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        SelectableText(text, textDirection: address ? TextDirection.ltr : null),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final entry = widget.entry;
    final content = _content;
    final body = content?.draft.body ?? '';
    final plainPreview = studioMailPlainPreviewText(body);
    final preview = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.mailOutboxPreview,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (!widget.embedded)
                IconButton(
                  key: const ValueKey('studio-mail-outbox-review-close'),
                  tooltip: strings.close,
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_notice != null)
            Text(
              _notice!,
              style: _failed
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(strings.mailOutboxState(entry.state)),
                  Text(strings.mailOutboxAttempt(entry.attemptNumber)),
                  if (entry.state == MailOutboxState.closedUncertain)
                    Text(strings.mailOutboxClosedExplanation)
                  else if (entry.canBeginAcknowledgedAttempt)
                    Text(strings.mailOutboxUncertainExplanation),
                  const SizedBox(height: 12),
                  Text(strings.mailOutboxPreviewExplanation),
                  const SizedBox(height: 12),
                  _field(
                    strings.mailOutboxSender,
                    entry.prepared.envelope.sender,
                    address: true,
                  ),
                  if (content == null) ...[
                    _field(
                      strings.mailOutboxRecipients,
                      entry.prepared.envelope.recipients.join(', '),
                      address: true,
                    ),
                    Text(strings.mailOutboxPreviewUnavailable),
                  ] else ...[
                    _field(
                      strings.subject,
                      content.draft.subject.isEmpty
                          ? strings.mailOutboxNoSubject
                          : content.draft.subject,
                    ),
                    _field(strings.to, content.draft.to, address: true),
                    if (content.draft.cc.isNotEmpty)
                      _field(strings.mailCc, content.draft.cc, address: true),
                    if (content.draft.bcc.isNotEmpty)
                      _field(strings.mailBcc, content.draft.bcc, address: true),
                    if (content.message.envelope.messageId case final id?)
                      _field(strings.mailOutboxMessageId, id, address: true),
                    if (content.message.envelope.sentAt case final date?)
                      _field(
                        strings.mailOutboxMessageDate,
                        date.toUtc().toIso8601String(),
                        address: true,
                      ),
                    if (content.draft.richBody case final rich?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              strings.mailOutboxFormattedBody,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            StudioMailRichPreview(
                              body: rich,
                              truncationNotice: strings.mailOutboxBodyTruncated,
                            ),
                          ],
                        ),
                      )
                    else ...[
                      _field(strings.mailPlainTextBody, plainPreview.text),
                      if (plainPreview.truncated)
                        Text(strings.mailOutboxBodyTruncated),
                    ],
                    Text(
                      strings.mailAttachmentSummary(
                        content.draft.attachments.items.length,
                        content.draft.attachments.totalBytes,
                      ),
                    ),
                    for (final attachment in content.draft.attachments.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.attach_file),
                        title: Text(attachment.name),
                        subtitle: Text(
                          '${attachment.mediaType} · ${strings.mailAttachmentSize(attachment.length)}',
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Text(strings.mailOutboxExportExplanation),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('studio-mail-outbox-export-eml'),
                onPressed: _busy || !_current
                    ? null
                    : () => _export(envelope: false),
                icon: const Icon(Icons.download_outlined),
                label: Text(strings.mailOutboxExport),
              ),
              TextButton(
                key: const ValueKey('studio-mail-outbox-export-envelope'),
                onPressed: _busy || !_current
                    ? null
                    : () => _export(envelope: true),
                child: Text(strings.mailOutboxExportEnvelope),
              ),
            ],
          ),
        ],
      ),
    );
    if (widget.embedded) return preview;
    return PopScope(
      canPop: !_busy,
      child: Dialog(child: SizedBox(width: 760, height: 660, child: preview)),
    );
  }
}
