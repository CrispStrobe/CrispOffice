import 'package:flutter/material.dart';

import 'studio_mail_draft.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_drafts_strings.dart';
import 'studio_strings.dart';

/// Bounded metadata-only draft pages. The host opens the chosen draft's editor.
/// Nothing in this dialog invokes a transport or loads unselected attachments.
class StudioMailDraftsDialog extends StatefulWidget {
  const StudioMailDraftsDialog({
    super.key,
    required this.strings,
    required this.catalog,
    required this.isCurrent,
  });

  final StudioStrings strings;
  final StudioMailDraftCatalog catalog;
  final bool Function() isCurrent;

  @override
  State<StudioMailDraftsDialog> createState() => _StudioMailDraftsDialogState();
}

class _StudioMailDraftsDialogState extends State<StudioMailDraftsDialog> {
  List<StudioMailDraftSummary> _drafts = const [];
  final List<String?> _previousPages = [];
  String? _afterId;
  String? _nextAfterId;
  bool _busy = true;
  String? _error;

  bool get _current => mounted && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    if (!_current) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.strings.mailDraftListFailed;
        });
      }
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.catalog.listDrafts(afterId: _afterId);
      if (_current) {
        setState(() {
          _drafts = page.drafts;
          _nextAfterId = page.nextAfterId;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _error = widget.strings.mailDraftListFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(StudioMailDraftSummary? summary) async {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = summary == null
          ? await widget.catalog.createDraft(
              const StudioMailDraft(to: '', subject: '', body: ''),
            )
          : await widget.catalog.selectDraft(summary);
      if (mounted && widget.isCurrent()) Navigator.pop(context, draft);
    } on Object {
      if (mounted) {
        setState(() => _error = widget.strings.mailDraftListFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(StudioMailDraftSummary summary) async {
    if (_busy || !_current) return;
    setState(() => _busy = true);
    try {
      final strings = widget.strings;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.mailDraftDelete),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.subject.isEmpty
                    ? strings.mailDraftNoSubject
                    : summary.subject,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Text(strings.mailDraftDeleteExplanation),
              if (summary.submissionUncertain) ...[
                const SizedBox(height: 12),
                Text(strings.mailDraftDeleteUncertainExplanation),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const ValueKey('studio-mail-confirm-delete-draft'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.mailDraftDelete),
            ),
          ],
        ),
      );
      if (confirmed == true && _current) {
        await widget.catalog.discardDraft(summary);
      }
      if (_current) await _loadPage();
    } on Object {
      if (mounted) {
        setState(() => _error = widget.strings.mailDraftListFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (_busy || _nextAfterId == null || !_current) return;
    _previousPages.add(_afterId);
    _afterId = _nextAfterId;
    _loadPage();
  }

  void _previous() {
    if (_busy || _previousPages.isEmpty || !_current) return;
    _afterId = _previousPages.removeLast();
    _loadPage();
  }

  String _recipients(StudioMailDraftSummary draft) {
    final recipients = [
      draft.to,
      draft.cc,
      draft.bcc,
    ].where((value) => value.trim().isNotEmpty).join('; ');
    return recipients.isEmpty
        ? widget.strings.mailDraftNoRecipients
        : recipients;
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: SizedBox(
          width: 760,
          height: 620,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.mailDrafts,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: strings.refresh,
                      onPressed: _busy ? null : _loadPage,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(strings.mailDraftListExplanation),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    key: const ValueKey('studio-mail-new-draft'),
                    onPressed: _busy || !widget.isCurrent()
                        ? null
                        : () => _choose(null),
                    icon: const Icon(Icons.add),
                    label: Text(strings.mailNewDraft),
                  ),
                ),
                const SizedBox(height: 12),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _error!,
                      key: const ValueKey('studio-mail-drafts-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: _drafts.isEmpty
                      ? Center(child: Text(strings.mailDraftListEmpty))
                      : ListView.separated(
                          itemCount: _drafts.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final draft = _drafts[index];
                            return ListTile(
                              key: ValueKey('studio-mail-draft-${draft.id}'),
                              enabled: !_busy && widget.isCurrent(),
                              leading: Icon(
                                draft.submissionUncertain
                                    ? Icons.warning_amber_outlined
                                    : Icons.drafts_outlined,
                              ),
                              title: Text(
                                draft.subject.isEmpty
                                    ? strings.mailDraftNoSubject
                                    : draft.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _recipients(draft),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (draft.attachmentCount > 0)
                                    Text(
                                      strings.mailDraftAttachmentCount(
                                        draft.attachmentCount,
                                      ),
                                    ),
                                  if (draft.submissionUncertain)
                                    Text(strings.mailDraftUncertain),
                                ],
                              ),
                              onTap: _busy ? null : () => _choose(draft),
                              trailing: IconButton(
                                key: ValueKey(
                                  'studio-mail-delete-draft-${draft.id}',
                                ),
                                tooltip: strings.mailDraftDelete,
                                onPressed: _busy || !widget.isCurrent()
                                    ? null
                                    : () => _delete(draft),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            );
                          },
                        ),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('studio-mail-drafts-previous'),
                      onPressed: _busy || _previousPages.isEmpty
                          ? null
                          : _previous,
                      icon: const Icon(Icons.chevron_left),
                      label: Text(strings.mailDraftPrevious),
                    ),
                    TextButton.icon(
                      key: const ValueKey('studio-mail-drafts-next'),
                      onPressed: _busy || _nextAfterId == null ? null : _next,
                      icon: const Icon(Icons.chevron_right),
                      label: Text(strings.mailDraftNext),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
