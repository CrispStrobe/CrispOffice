import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_mail_draft.dart';
import 'studio_mail_strings.dart';
import 'studio_mail_threading.dart';
import 'studio_strings.dart';

export 'studio_mail_draft.dart';

/// Recipient/subject fields are host chrome. The body uses the shared Word
/// RenderBox surface, including its IME, selection, accessibility and undo.
class StudioMailComposeDialog extends StatefulWidget {
  const StudioMailComposeDialog({
    super.key,
    required this.strings,
    required this.from,
    this.initialDraft,
    this.previousSubmissionUncertain = false,
  });

  final StudioStrings strings;
  final String from;
  final StudioMailDraft? initialDraft;
  final bool previousSubmissionUncertain;

  @override
  State<StudioMailComposeDialog> createState() =>
      _StudioMailComposeDialogState();
}

class _StudioMailComposeDialogState extends State<StudioMailComposeDialog> {
  late final TextEditingController _to;
  late final TextEditingController _cc;
  late final TextEditingController _bcc;
  late final TextEditingController _subject;
  late final WordEditorController _body;
  final _bodyFocus = FocusNode();
  bool _retryAcknowledged = false;
  late bool _showCopies;
  StudioMailDraftProblem? _problem;

  @override
  void initState() {
    super.initState();
    _to = TextEditingController(text: widget.initialDraft?.to ?? '');
    _cc = TextEditingController(text: widget.initialDraft?.cc ?? '');
    _bcc = TextEditingController(text: widget.initialDraft?.bcc ?? '');
    _showCopies = _cc.text.isNotEmpty || _bcc.text.isNotEmpty;
    _subject = TextEditingController(text: widget.initialDraft?.subject ?? '');
    _body = WordEditorController(
      document: WmlDocument.empty(text: widget.initialDraft?.body ?? ''),
      config: const OfficeSurfaceConfig(showRulers: false),
      proofingService: OfficeProofingService(providers: const []),
    );
    _body.proofing.enabled = false;
  }

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _bcc.dispose();
    _subject.dispose();
    _bodyFocus.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.previousSubmissionUncertain && !_retryAcknowledged) return;
    _body.commitPendingEdits();
    final snapshot = StudioMailDraft(
      to: _to.text,
      cc: _cc.text,
      bcc: _bcc.text,
      subject: _subject.text,
      body: _body.document.paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n'),
      thread: widget.initialDraft?.thread ?? const StudioMailThread.empty(),
    );
    final problem = snapshot.problem;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context, snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final feedback = switch (_problem) {
      StudioMailDraftProblem.recipient => strings.mailInvalidRecipient,
      StudioMailDraftProblem.subject => strings.mailInvalidSubject,
      StudioMailDraftProblem.body => strings.mailInvalidBody,
      null => null,
    };
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 720,
        height: 680,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    strings.compose,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.from,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _to,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: strings.to,
                      helperText: strings.mailRecipientListHint,
                      helperMaxLines: 2,
                      suffixIcon: _showCopies
                          ? null
                          : TextButton(
                              onPressed: () =>
                                  setState(() => _showCopies = true),
                              child: Text(strings.mailCopyRecipients),
                            ),
                    ),
                  ),
                  if (_showCopies) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cc,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: strings.mailCc),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bcc,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: strings.mailBcc),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _subject,
                    decoration: InputDecoration(labelText: strings.subject),
                  ),
                  const SizedBox(height: 12),
                  Text(strings.mailPlainTextBody),
                  const SizedBox(height: 4),
                  SizedBox(
                    height:
                        (constraints.maxHeight -
                                (widget.previousSubmissionUncertain
                                    ? 436
                                    : 340) -
                                (_showCopies ? 128 : 0) -
                                (feedback == null ? 0 : 64))
                            .clamp(180.0, 440.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: QudsWordEditor(
                        key: const ValueKey<String>('studio-mail-compose-body'),
                        controller: _body,
                        focusNode: _bodyFocus,
                        enableLiveProofing: false,
                        showReviewStatus: false,
                        toolbarBuilder: (_, _) => const SizedBox.shrink(),
                        statusBarBuilder: (_, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  if (feedback != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        feedback,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (widget.previousSubmissionUncertain)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(strings.mailRetryAcknowledgement),
                      value: _retryAcknowledged,
                      onChanged: (value) =>
                          setState(() => _retryAcknowledged = value ?? false),
                    ),
                  const SizedBox(height: 8),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(strings.cancel),
                      ),
                      FilledButton.icon(
                        onPressed:
                            widget.previousSubmissionUncertain &&
                                !_retryAcknowledged
                            ? null
                            : _submit,
                        icon: const Icon(Icons.send),
                        label: Text(strings.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
