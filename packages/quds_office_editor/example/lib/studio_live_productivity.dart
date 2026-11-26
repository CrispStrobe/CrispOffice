import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_engine/quds_productivity_automation.dart';
import 'package:quds_office_engine/quds_productivity_live.dart';

const studioLiveProductivityLabel = 'Live MCP access';

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
    this.enabled = true,
  });

  final ProductivityKind kind;
  final String scope;
  final Object? scopeKey;
  final bool Function() scopeIsCurrent;
  final Iterable<Map<String, Object>> Function() readRows;
  final MailMessage? Function()? openedMail;
  final bool enabled;

  @override
  State<StudioLiveProductivityButton> createState() =>
      _StudioLiveProductivityButtonState();
}

final class _StudioLiveProductivityButtonState
    extends State<StudioLiveProductivityButton> {
  ProductivityGrant? _grant;
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
    setState(() => _opening = true);
    try {
      final allowed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Grant live read access'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share display fields from $scope for up to 10 minutes. '
                  'The MCP client can copy the returned data.',
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
      final grant = await ProductivityGrant.open(
        session: ProductivityMcp.live(
          kind: kind,
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
      setState(() => _grant = grant);
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
    final revoke = await showDialog<bool>(
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
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke access'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Done'),
          ),
          FilledButton(
            onPressed: () async {
              if (!grant.isActive) return;
              await Clipboard.setData(
                ClipboardData(text: grant.ticket.relayCredential),
              );
              if (context.mounted) Navigator.pop(context, false);
            },
            child: const Text('Copy grant'),
          ),
        ],
      ),
    );
    if (revoke == true && mounted && identical(_grant, grant)) {
      setState(_revoke);
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
