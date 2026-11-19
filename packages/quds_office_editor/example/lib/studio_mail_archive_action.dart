import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_archive_host.dart';
import 'studio_mail_archive_strings.dart';
import 'studio_strings.dart';

/// The writer owns any archive connection it opens. A successful result means
/// the original was committed; cleanup must not replace that result with failure.
typedef StudioMailArchiveWriter =
    Future<MailResult<MailArchiveImportResult>> Function(
      MailMessage message, {
      required MailArchiveOrigin origin,
      MailCancellationToken? cancellation,
    });

Future<MailResult<MailArchiveImportResult>> _writeOriginal(
  MailMessage message, {
  required MailArchiveOrigin origin,
  MailCancellationToken? cancellation,
}) => archiveStudioMailMessage(
  message,
  origin: origin,
  cancellation: cancellation,
);

/// Archives the selected immutable original without mutating its live mailbox.
/// A new selection invalidates feedback from the previous selection immediately.
class StudioArchiveMessageButton extends StatefulWidget {
  const StudioArchiveMessageButton({
    super.key,
    required this.strings,
    required this.message,
    required this.origin,
    this.writer,
  });

  final StudioStrings strings;
  final MailMessage? message;
  final MailArchiveOrigin origin;
  final StudioMailArchiveWriter? writer;

  @override
  State<StudioArchiveMessageButton> createState() =>
      _StudioArchiveMessageButtonState();
}

class _StudioArchiveMessageButtonState
    extends State<StudioArchiveMessageButton> {
  bool _pending = false;
  int _generation = 0;
  MailCancellationSource? _cancellation;

  @override
  void didUpdateWidget(StudioArchiveMessageButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.message, widget.message) ||
        !_sameOrigin(oldWidget.origin, widget.origin)) {
      _invalidate(MailCancellationReason.accountChanged);
    }
  }

  bool _sameOrigin(MailArchiveOrigin first, MailArchiveOrigin second) =>
      first.source == second.source &&
      first.folder == second.folder &&
      first.sourceMessageId == second.sourceMessageId;

  void _invalidate(MailCancellationReason reason) {
    _generation++;
    _cancellation?.cancel(reason);
    _cancellation = null;
    // didUpdateWidget is followed by build; dispose must never call setState.
    _pending = false;
  }

  @override
  void dispose() {
    _invalidate(MailCancellationReason.disposed);
    super.dispose();
  }

  Future<void> _archive() async {
    final message = widget.message;
    if (_pending || message == null) return;
    final origin = widget.origin;
    final writer = widget.writer ?? _writeOriginal;
    final generation = ++_generation;
    final cancellation = MailCancellationSource();
    _cancellation = cancellation;
    setState(() => _pending = true);

    final MailResult<MailArchiveImportResult> result;
    try {
      result = await writer(
        message,
        origin: origin,
        cancellation: cancellation.token,
      );
    } on MailCancelled {
      if (!mounted || generation != _generation) return;
      _complete(const MailFailure(MailProblem(MailProblemCode.cancelled)));
      return;
    } on Object {
      if (!mounted || generation != _generation) return;
      _complete(const MailFailure(MailProblem(MailProblemCode.storageFailure)));
      return;
    }
    if (!mounted || generation != _generation) return;
    _complete(result);
  }

  void _complete(MailResult<MailArchiveImportResult> result) {
    setState(() {
      _pending = false;
      _cancellation = null;
    });
    final strings = widget.strings;
    final feedback = switch (result) {
      MailSuccess(value: final value) =>
        value.duplicate
            ? strings.archiveMessageDuplicate
            : strings.archiveMessageStored,
      MailFailure(problem: final problem) => strings.archiveProblem(
        problem.code,
      ),
    };
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(feedback)));
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('archive-current-message'),
    tooltip: widget.strings.archiveCurrentMessage,
    onPressed: widget.message == null || _pending ? null : _archive,
    icon: _pending
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: widget.strings.archiveWorking,
            ),
          )
        : const Icon(Icons.archive_outlined),
  );
}
