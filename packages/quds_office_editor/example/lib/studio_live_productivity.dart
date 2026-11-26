import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_engine/quds_productivity_automation.dart';
import 'package:quds_office_engine/quds_productivity_live.dart';

const studioLiveProductivityLabel = 'Live MCP access';

typedef StudioProductivityApproval = ({
  String label,
  String destination,
  Future<ProductivityApprovalOutcome> Function(
    ProductivityProposal,
    bool Function(),
  )
  apply,
});

/// One grant belongs to the mounted view and one exact scope. Its data source
/// follows the view's latest approved rows, including ordinary refreshes.
final class StudioLiveProductivityButton extends StatefulWidget {
  const StudioLiveProductivityButton({
    super.key,
    required this.kind,
    required this.scope,
    required this.scopeKey,
    required this.scopeIsCurrent,
    required this.readRows,
    this.openedMail,
    this.reviewProposal,
    this.approval,
    this.captureMailSelection,
    this.captureFolder,
    this.enabled = true,
  });

  final ProductivityKind kind;
  final String scope;
  final Object? scopeKey;
  final bool Function() scopeIsCurrent;
  final Iterable<Map<String, Object>> Function() readRows;
  final MailMessage? Function()? openedMail;
  final Future<void> Function(ProductivityProposal, bool Function())?
  reviewProposal;
  final StudioProductivityApproval? approval;
  final ProductivityMailSelection? Function()? captureMailSelection;
  final ProductivityFolderBrowser? Function(bool allowText)? captureFolder;
  final bool enabled;

  @override
  State<StudioLiveProductivityButton> createState() =>
      _StudioLiveProductivityButtonState();
}

final class _StudioLiveProductivityButtonState
    extends State<StudioLiveProductivityButton> {
  ProductivityGrant? _grant;
  ProductivityProposals? _proposals;
  bool _opening = false;

  @override
  void didUpdateWidget(StudioLiveProductivityButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scopeKey != oldWidget.scopeKey || !widget.scopeIsCurrent()) {
      _revoke();
    }
  }

  void _revoke() {
    final grant = _grant;
    _grant = null;
    _proposals = null;
    if (grant != null) unawaited(grant.revoke());
  }

  @override
  void dispose() {
    _revoke();
    super.dispose();
  }

  Future<void> _manage() async {
    if (_grant case final grant? when grant.isActive) {
      await _showTicket(grant);
      return;
    }
    _revoke();
    final scope = widget.scope;
    final key = widget.scopeKey;
    final scopeIsCurrent = widget.scopeIsCurrent;
    bool isCurrent() => mounted && key == widget.scopeKey && scopeIsCurrent();
    final message = widget.openedMail?.call();
    var includeText = false;
    var allowProposals = false;
    var includeMailboxText = false;
    var browseFolder = false;
    var browseText = false;
    final mailbox = widget.captureMailSelection?.call();
    setState(() => _opening = true);
    try {
      final allowed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Grant live read access'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share display fields from $scope for up to 10 minutes. '
                  'The MCP client can copy the returned data.',
                ),
                if (widget.reviewProposal != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow suggestions for review'),
                    subtitle: const Text(
                      'Suggestions wait here for you to review.',
                    ),
                    value: allowProposals,
                    onChanged: (value) =>
                        update(() => allowProposals = value ?? false),
                  ),
                if (widget.captureFolder != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Browse the selected folder on the server',
                    ),
                    subtitle: const Text(
                      'Includes older messages outside this view.',
                    ),
                    value: browseFolder,
                    onChanged: (value) =>
                        update(() => browseFolder = value ?? false),
                  ),
                if (browseFolder)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Include plain text from browsed messages',
                    ),
                    value: browseText,
                    onChanged: (value) =>
                        update(() => browseText = value ?? false),
                  ),
                if (mailbox != null && mailbox.subjects.isNotEmpty)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Include plain text from loaded messages',
                    ),
                    subtitle: Text(
                      '${mailbox.subjects.length} messages currently loaded in this folder.',
                    ),
                    value: includeMailboxText,
                    onChanged: (value) =>
                        update(() => includeMailboxText = value ?? false),
                  ),
                if (message?.body.plainText?.isNotEmpty == true)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeText,
                    title: const Text(
                      'Include plain text from this open email',
                    ),
                    subtitle: Text(message!.envelope.subject),
                    onChanged: (value) =>
                        update(() => includeText = value ?? false),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Grant read access'),
              ),
            ],
          ),
        ),
      );
      if (allowed != true || !isCurrent()) return;
      final kind = widget.kind;
      final proposals = allowProposals && widget.reviewProposal != null
          ? ProductivityProposals(kind)
          : null;
      final grant = await ProductivityGrant.open(
        session: ProductivityMcp.live(
          kind: kind,
          proposals: proposals,
          folderBrowser: browseFolder
              ? widget.captureFolder?.call(browseText)
              : null,
          mailSelection: includeMailboxText ? mailbox : null,
          isCurrent: () => isCurrent() && _grant?.isActive == true,
          read: () => ProductivitySnapshot.capture(
            kind: kind,
            capturedAt: DateTime.now(),
            rows: widget.readRows(),
          ),
          readOpenedMail: includeText && message != null
              ? () {
                  if (!identical(widget.openedMail?.call(), message)) {
                    return null;
                  }
                  return ProductivityMailText(
                    subject: message.envelope.subject,
                    text: message.body.plainText!,
                  );
                }
              : null,
        ),
        isCurrent: isCurrent,
      );
      if (!isCurrent()) {
        await grant.revoke();
        return;
      }
      setState(() {
        _grant = grant;
        _proposals = proposals;
      });
      await _showTicket(grant);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Live MCP access could not be started.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _showTicket(ProductivityGrant grant) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Live MCP access'),
        content: Text(
          'Copy the grant into the CRISPOFFICE_MCP_GRANT environment setting '
          'of your trusted local productivity MCP client. The grant expires '
          'after 10 minutes and is withdrawn when you leave this scope.\n\n'
          'Successful reads so far: ${grant.successfulReads}',
        ),
        actions: [
          if (_proposals?.pending != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'review'),
              child: const Text('Review suggestion'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'revoke'),
            child: const Text('Revoke access'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          FilledButton(
            onPressed: () async {
              if (!grant.isActive) return;
              await Clipboard.setData(
                ClipboardData(text: grant.ticket.relayCredential),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copy grant'),
          ),
        ],
      ),
    );
    if (!mounted || !identical(_grant, grant)) return;
    if (action == 'revoke') setState(_revoke);
    if (action == 'review') await _review(grant);
  }

  Future<void> _review(ProductivityGrant grant) async {
    final proposals = _proposals;
    final pending = proposals?.pending;
    if (proposals == null || pending == null || !grant.isActive) return;
    final approval = widget.approval;
    final review = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review MCP suggestion'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scope: ${widget.scope}'),
            if (approval != null) Text('Destination: ${approval.destination}'),
            Text(pending.title),
            if (pending.start case final start?)
              Text(
                '${start.toIso8601String()} – ${pending.end!.toIso8601String()}',
              ),
            if (pending.text.isNotEmpty) Text(pending.text),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'dismiss'),
            child: const Text('Dismiss suggestion'),
          ),
          if (approval != null)
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, 'apply'),
              child: Text(approval.label),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'editor'),
            child: const Text('Open in editor'),
          ),
        ],
      ),
    );
    bool current() => mounted && identical(_grant, grant) && grant.isActive;
    final open = widget.reviewProposal;
    if (review == null || !current()) return;
    if (review == 'apply' && approval != null) {
      await proposals.apply(pending, () => approval.apply(pending, current));
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(switch (proposals.status['status']) {
              'saved' => 'Suggestion saved.',
              'queued' => 'Task added locally. Sync will run separately.',
              'rejected' => 'Suggestion could not be saved in this scope.',
              _ =>
                'Save outcome could not be confirmed. Refresh before you retry.',
            }),
          ),
        );
      }
    } else if (review == 'editor' && open != null) {
      if (proposals.resolve(pending, review: true)) {
        await open(pending, current);
      }
    } else if (review == 'dismiss') {
      proposals.resolve(pending, review: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _grant?.isActive == true;
    return IconButton(
      tooltip: studioLiveProductivityLabel,
      icon: Icon(active ? Icons.lock_open_outlined : Icons.lock_outline),
      onPressed:
          _opening || (!active && (!widget.enabled || widget.scopeKey == null))
          ? null
          : _manage,
    );
  }
}
