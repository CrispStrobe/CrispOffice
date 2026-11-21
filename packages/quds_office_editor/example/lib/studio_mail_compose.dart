import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart'
    show MailCacheCleanupReport;
import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_mail_attachment_loader.dart';
import 'studio_mail_cached_strings.dart';
import 'studio_mail_compose_tools.dart';
import 'studio_mail_compose_tools_dialog.dart';
import 'studio_mail_compose_tools_strings.dart';
import 'studio_mail_draft.dart';
import 'studio_mail_drafts_strings.dart';
import 'studio_mail_outbox_strings.dart';
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
    this.onSaveDraft,
    this.onQueueDraft,
    this.onClearMailCache,
    this.canSend = true,
    this.composeToolsStore,
    this.isComposeToolsCurrent,
  });

  final StudioStrings strings;
  final String from;
  final StudioMailDraft? initialDraft;
  final bool previousSubmissionUncertain;

  /// Local-only workspaces save drafts without producing a transport request.
  /// The finish handler also checks this, so a retained callback cannot send
  /// after the host has disabled submission.
  final bool canSend;

  /// Account-owned writing tools, independent of the draft's immutable text.
  final StudioMailComposeToolsStore? composeToolsStore;
  final bool Function()? isComposeToolsCurrent;

  /// Persists an immutable editor snapshot, including unfinished recipients.
  /// A failed save keeps the composer open and prevents submission.
  final Future<void> Function(StudioMailDraft draft)? onSaveDraft;

  /// Atomically transfers the saved draft to the account's local Outbox.
  final Future<void> Function(StudioMailDraft draft)? onQueueDraft;

  /// Releases one bounded batch of expendable account cache after confirmation.
  /// Offered only after a failed save; the live draft stays open and is retried
  /// after cleanup. This callback must never submit or queue outgoing mail.
  final Future<MailCacheCleanupReport> Function()? onClearMailCache;

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
  late StudioMailAttachments _attachments;
  StudioMailAttachmentLoader? _attachmentLoader;
  bool _pickingAttachments = false;
  bool _attachmentFailed = false;
  StudioMailDraftProblem? _problem;
  Timer? _autosave;
  Future<bool>? _pendingSave;
  StudioMailDraft? _lastObserved;
  int _editRevision = 0;
  int _savedRevision = 0;
  bool _saveFailed = false;
  bool _queueFailed = false;
  bool _recoveringCache = false;
  bool _cacheClearFailed = false;
  MailCacheCleanupReport? _cacheCleanupReport;
  bool _finishing = false;
  bool _allowPop = false;
  StudioMailComposeToolsStore? _toolsOwner;
  MailAccountId? _toolsAccount;
  MailComposeSettings? _composeSettings;
  int _toolsEpoch = 0;
  bool _loadingTools = false;
  bool _initialToolsPending = false;
  bool _editingTools = false;
  bool _toolsLoadFailed = false;
  bool _toolsInsertionFailed = false;
  bool _toolsSelectionFailed = false;

  @override
  void initState() {
    super.initState();
    _to = TextEditingController(text: widget.initialDraft?.to ?? '');
    _cc = TextEditingController(text: widget.initialDraft?.cc ?? '');
    _bcc = TextEditingController(text: widget.initialDraft?.bcc ?? '');
    _showCopies = _cc.text.isNotEmpty || _bcc.text.isNotEmpty;
    _attachments =
        widget.initialDraft?.attachments ?? const StudioMailAttachments.empty();
    _subject = TextEditingController(text: widget.initialDraft?.subject ?? '');
    final document = WmlDocument.empty(text: widget.initialDraft?.body ?? '');
    for (final section in document.sections) {
      section.margins = const WmlPageMargins(
        top: 12,
        bottom: 12,
        left: 12,
        right: 12,
        header: 0,
        footer: 0,
      );
    }
    final arabic = widget.strings.language == StudioLanguage.ar;
    _body = WordEditorController(
      document: document,
      config: OfficeSurfaceConfig(
        showRulers: false,
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        strings: switch (widget.strings.language) {
          StudioLanguage.en => OfficeStrings.english,
          StudioLanguage.de => OfficeStrings.german,
          StudioLanguage.ar => OfficeStrings.arabic,
        },
      ),
      proofingService: OfficeProofingService(providers: const []),
    );
    _body.proofing.enabled = false;
    _lastObserved = _snapshot();
    for (final controller in [_to, _cc, _bcc, _subject, _body]) {
      controller.addListener(_edited);
    }
    _toolsOwner = widget.composeToolsStore;
    _toolsAccount = _toolsOwner?.account;
    _initialToolsPending = _toolsOwner != null && widget.initialDraft == null;
    if (_toolsOwner != null) unawaited(_loadComposeTools());
    // A new reply/forward is already meaningful work before the first edit.
    if (widget.onSaveDraft != null && widget.initialDraft != null) {
      _editRevision++;
      _autosave = Timer(const Duration(milliseconds: 500), _saveInBackground);
    }
  }

  @override
  void dispose() {
    _toolsEpoch++;
    _autosave?.cancel();
    _attachmentLoader?.cancel();
    for (final controller in [_to, _cc, _bcc, _subject, _body]) {
      controller.removeListener(_edited);
    }
    _to.dispose();
    _cc.dispose();
    _bcc.dispose();
    _subject.dispose();
    _bodyFocus.dispose();
    _body.dispose();
    super.dispose();
  }

  StudioMailDraft _snapshot() => StudioMailDraft(
    to: _to.text,
    cc: _cc.text,
    bcc: _bcc.text,
    subject: _subject.text,
    body: _body.document.paragraphs
        .map((paragraph) => paragraph.text)
        .join('\n'),
    thread: widget.initialDraft?.thread ?? const StudioMailThread.empty(),
    attachments: _attachments,
  );

  void _edited() {
    if (!mounted) return;
    final next = _snapshot();
    final previous = _lastObserved;
    if (previous != null &&
        next.to == previous.to &&
        next.cc == previous.cc &&
        next.bcc == previous.bcc &&
        next.subject == previous.subject &&
        next.body == previous.body &&
        identical(next.attachments, previous.attachments)) {
      return;
    }
    _lastObserved = next;
    _editRevision++;
    if (widget.onSaveDraft == null) return;
    _autosave?.cancel();
    // A late IME/editor notification remains part of the next immutable save,
    // but cannot start a write while cleanup owns the recovery flow.
    if (_recoveringCache) return;
    _autosave = Timer(const Duration(milliseconds: 500), _saveInBackground);
    setState(() => _saveFailed = false);
  }

  void _saveInBackground() => unawaited(_save());

  Future<bool> _save({bool fromCacheRecovery = false}) {
    _autosave?.cancel();
    if (_recoveringCache && !fromCacheRecovery) {
      return _pendingSave ?? Future<bool>.value(false);
    }
    final save = widget.onSaveDraft;
    if (save == null) return Future.value(true);
    final pending = _pendingSave;
    if (pending != null) return pending;
    if (_savedRevision == _editRevision) return Future.value(true);
    final future = _saveLatest(save);
    _pendingSave = future;
    if (mounted) setState(() {});
    return future;
  }

  Future<bool> _saveLatest(Future<void> Function(StudioMailDraft) save) async {
    try {
      // Install _pendingSave before an injected saver can throw synchronously.
      await Future<void>.value();
      // An edit arriving during a write gets its own later immutable revision.
      while (mounted && _savedRevision != _editRevision) {
        final revision = _editRevision;
        final snapshot = _snapshot();
        await save(snapshot);
        _savedRevision = revision;
      }
      if (!mounted) return false;
      _saveFailed = false;
      return true;
    } on Object {
      _saveFailed = true;
      return false;
    } finally {
      _pendingSave = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _finish({required bool send, bool queue = false}) async {
    if ((send || queue) && !widget.canSend) return;
    if (_finishing ||
        _recoveringCache ||
        _initialToolsPending ||
        _editingTools ||
        (send && _pickingAttachments)) {
      return;
    }
    if (send && widget.previousSubmissionUncertain && !_retryAcknowledged) {
      return;
    }
    if (!send) _attachmentLoader?.cancel();
    _body.commitPendingEdits();
    _edited();
    FocusScope.of(context).unfocus();
    final snapshot = _snapshot();
    if (send) {
      final problem = snapshot.problem;
      if (problem != null) {
        setState(() => _problem = problem);
        return;
      }
    }
    if (widget.onSaveDraft == null && !queue) {
      Navigator.pop(context, send ? snapshot : null);
      return;
    }
    setState(() {
      _finishing = true;
      _queueFailed = false;
    });
    final saved = await _save();
    if (!mounted) return;
    if (!saved) {
      setState(() => _finishing = false);
      return;
    }
    if ((send || queue) && !widget.canSend) {
      setState(() => _finishing = false);
      return;
    }
    final finalSnapshot = _snapshot();
    if (send && finalSnapshot.problem != null) {
      setState(() {
        _problem = finalSnapshot.problem;
        _finishing = false;
      });
      return;
    }
    if (queue) {
      try {
        await widget.onQueueDraft!(finalSnapshot);
      } on Object {
        if (mounted) {
          setState(() {
            _finishing = false;
            _queueFailed = true;
          });
        }
        return;
      }
      if (!mounted) return;
    }
    setState(() => _allowPop = true);
    // An explicit pop follows the completed save; only a send returns a draft.
    Navigator.pop(context, send && !queue ? finalSnapshot : null);
  }

  Future<void> _closeWithoutSaving() async {
    if (_finishing || _recoveringCache || _pendingSave != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.mailDraftCloseUnsaved),
        content: Text(widget.strings.mailDraftCloseUnsavedExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings.mailDraftCloseUnsaved),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _autosave?.cancel();
    _attachmentLoader?.cancel();
    setState(() => _allowPop = true);
    Navigator.pop(context);
  }

  Future<void> _clearMailCache() async {
    if (!mounted ||
        !_saveFailed ||
        _finishing ||
        _recoveringCache ||
        widget.onSaveDraft == null ||
        widget.onClearMailCache == null) {
      return;
    }
    setState(() => _recoveringCache = true);
    _autosave?.cancel();
    _body.commitPendingEdits();
    _edited();
    FocusScope.of(context).unfocus();
    final direction = Directionality.of(context);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: direction,
          child: AlertDialog(
            title: Text(widget.strings.mailCacheClear),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.strings.mailCacheClearHelp),
                  const SizedBox(height: 12),
                  Text(widget.strings.mailCacheDraftClearHelp),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(widget.strings.cancel),
              ),
              FilledButton(
                key: const ValueKey('studio-mail-compose-clear-cache-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(widget.strings.mailCacheClear),
              ),
            ],
          ),
        ),
      );
      if (!mounted || confirmed != true) return;
      // A retry that began before confirmation owns its existing write. Never
      // run cleanup concurrently with it, or clear after it already saved all
      // current edits successfully.
      await _pendingSave;
      if (!mounted || (!_saveFailed && _savedRevision == _editRevision)) return;
      final clear = widget.onClearMailCache;
      if (clear == null) return;
      setState(() => _cacheClearFailed = false);
      final report = await clear();
      if (!mounted) return;
      setState(() => _cacheCleanupReport = report);
      // Exactly one cleanup step, then a local save of the latest live edits.
      // A previous Send/Queue/Close failure does not retain its finish intent.
      await _save(fromCacheRecovery: true);
    } on Object {
      if (mounted) setState(() => _cacheClearFailed = true);
    } finally {
      if (mounted) {
        setState(() => _recoveringCache = false);
        if (!_saveFailed && _savedRevision != _editRevision) {
          _autosave = Timer(
            const Duration(milliseconds: 500),
            _saveInBackground,
          );
        }
      }
    }
  }

  Future<void> _pickAttachments() async {
    if (_pickingAttachments || _recoveringCache) return;
    final loader = StudioMailAttachmentLoader();
    setState(() {
      _attachmentLoader = loader;
      _pickingAttachments = true;
      _attachmentFailed = false;
    });
    try {
      final selection = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        withReadStream: true,
      );
      if (!mounted || selection == null) return;
      final next = await loader.read(selection.files, existing: _attachments);
      if (!mounted || !identical(_attachmentLoader, loader)) return;
      setState(() => _attachments = next);
      _edited();
    } on StudioMailAttachmentReadCancelled {
      // Closing the dialog invalidates its outstanding selection.
    } on Object {
      if (mounted && identical(_attachmentLoader, loader)) {
        setState(() => _attachmentFailed = true);
      }
    } finally {
      loader.cancel();
      if (mounted && identical(_attachmentLoader, loader)) {
        setState(() {
          _attachmentLoader = null;
          _pickingAttachments = false;
        });
      }
    }
  }

  void _removeAttachment(int index) {
    if (_pickingAttachments || _recoveringCache) return;
    setState(() {
      _attachments = StudioMailAttachments.from([
        for (var i = 0; i < _attachments.items.length; i++)
          if (i != index) _attachments.items[i],
      ]);
      _attachmentFailed = false;
    });
    _edited();
  }

  bool get _toolsCurrent =>
      mounted &&
      identical(_toolsOwner, widget.composeToolsStore) &&
      _toolsOwner != null &&
      _toolsOwner!.account == _toolsAccount &&
      (widget.isComposeToolsCurrent?.call() ?? true);

  bool get _canUseTools =>
      _toolsCurrent &&
      !_loadingTools &&
      !_editingTools &&
      !_finishing &&
      !_recoveringCache;

  Future<void> _loadComposeTools() async {
    final owner = _toolsOwner;
    if (!_toolsCurrent || owner == null) {
      if (mounted) {
        setState(() {
          _initialToolsPending = false;
          _loadingTools = false;
          _toolsLoadFailed = true;
        });
      }
      return;
    }
    final epoch = ++_toolsEpoch;
    setState(() {
      _loadingTools = true;
      _toolsLoadFailed = false;
      _composeSettings = null;
    });
    try {
      final settings = await owner.loadComposeSettings();
      if (!_toolsCurrent || epoch != _toolsEpoch) return;
      if (settings.account != _toolsAccount || !settings.isValid) {
        throw const StudioMailComposeToolsException();
      }
      setState(() {
        _composeSettings = settings;
        _loadingTools = false;
      });
      // The primary Compose route initially has no saved draft. Catalog-created
      // messages and replies already received defaults before being persisted.
      // Resuming a draft, editing an Outbox copy, or reloading tools never
      // changes saved text or adds another automatic signature.
      if (_initialToolsPending && _editRevision == 0) {
        final prepared = applyStudioMailDefaultSignature(
          _snapshot(),
          settings,
          replyOrForward: false,
        );
        if (prepared.body != _snapshot().body) {
          _insertComposeText(prepared.body, requestFocus: false);
          _body.jumpToParagraph(0);
        }
      }
    } on Object {
      if (_toolsCurrent && epoch == _toolsEpoch) {
        setState(() {
          _composeSettings = null;
          _toolsLoadFailed = true;
        });
      }
    } finally {
      if (mounted && epoch == _toolsEpoch) {
        setState(() {
          _loadingTools = false;
          _initialToolsPending = false;
        });
      }
    }
  }

  Future<void> _manageComposeTools() async {
    final settings = _composeSettings;
    final owner = _toolsOwner;
    if (!_canUseTools || settings == null || owner == null) return;
    final epoch = _toolsEpoch;
    _body.commitPendingEdits();
    _edited();
    FocusScope.of(context).unfocus();
    setState(() => _editingTools = true);
    bool current() =>
        _toolsCurrent &&
        epoch == _toolsEpoch &&
        identical(owner, _toolsOwner) &&
        settings.account == _toolsAccount;
    try {
      await showDialog<MailComposeSettings>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Directionality(
          textDirection: widget.strings.language == StudioLanguage.ar
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: StudioMailComposeToolsDialog(
            strings: widget.strings,
            initialSettings: settings,
            isCurrent: current,
            onSave: (next) async {
              if (!current() || next.account != _toolsAccount) {
                throw const StudioMailComposeToolsException();
              }
              return owner.saveComposeSettings(next);
            },
          ),
        ),
      );
      // A failed/uncertain write must be read back before another edit. Settings
      // only affect later drafts; this draft changes through explicit insertion.
      if (current()) await _loadComposeTools();
    } finally {
      if (mounted) setState(() => _editingTools = false);
    }
  }

  void _insertComposeText(String value, {bool requestFocus = true}) {
    if (!_canUseTools) return;
    final text = studioMailComposeText(value);
    if (text.isEmpty) return;
    _body.commitPendingEdits();
    final paragraphs = _body.document.paragraphs.toList();
    final range = _body.caret.normalizedRange;
    if (range.startPara < 0 ||
        range.endPara >= paragraphs.length ||
        range.startIdx < 0 ||
        range.endIdx < 0 ||
        range.startIdx > paragraphs[range.startPara].text.length ||
        range.endIdx > paragraphs[range.endPara].text.length) {
      return;
    }
    final wholeMessage =
        range.startPara == 0 &&
        range.startIdx == 0 &&
        range.endPara == paragraphs.length - 1 &&
        range.endIdx == paragraphs.last.text.length;
    if (range.startPara != range.endPara && !wholeMessage) {
      setState(() {
        _toolsInsertionFailed = false;
        _toolsSelectionFailed = true;
      });
      return;
    }
    var start = range.startIdx;
    var end = range.endIdx;
    for (var i = 0; i < range.endPara; i++) {
      final length = paragraphs[i].text.length + 1;
      end += length;
      if (i < range.startPara) start += length;
    }
    final body = _snapshot().body;
    // These supported selection shapes match the Word insertion contract.
    // Partial cross-paragraph ranges were refused above without changing text.
    final next = body.replaceRange(start, end, text);
    if (next.length > StudioMailDraft.maxBodyBytes ||
        utf8.encode(next).length > StudioMailDraft.maxBodyBytes) {
      setState(() {
        _toolsInsertionFailed = true;
        _toolsSelectionFailed = false;
      });
      return;
    }
    try {
      if (!_body.insertPlainText(text)) {
        setState(() {
          _toolsInsertionFailed = false;
          _toolsSelectionFailed = true;
        });
        return;
      }
    } on Object {
      setState(() {
        _toolsInsertionFailed = false;
        _toolsSelectionFailed = true;
      });
      return;
    }
    _edited();
    setState(() {
      _toolsInsertionFailed = false;
      _toolsSelectionFailed = false;
    });
    if (requestFocus) _bodyFocus.requestFocus();
  }

  Widget _composeToolsToolbar() {
    final strings = widget.strings;
    final settings = _composeSettings;
    final epoch = _toolsEpoch;
    final available = _canUseTools && settings != null;
    bool currentMenu() =>
        _canUseTools &&
        epoch == _toolsEpoch &&
        identical(settings, _composeSettings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              key: const ValueKey('studio-mail-compose-tools'),
              onPressed: available ? _manageComposeTools : null,
              icon: const Icon(Icons.edit_note),
              label: Text(strings.mailComposeTools),
            ),
            TextButton.icon(
              key: const ValueKey('studio-mail-insert-signature'),
              onPressed: available && settings.signature.isNotEmpty
                  ? () {
                      if (currentMenu()) {
                        _insertComposeText(
                          studioMailSignatureText(settings.signature),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.draw_outlined),
              label: Text(strings.mailComposeInsertSignature),
            ),
            PopupMenuButton<MailQuickText>(
              key: const ValueKey('studio-mail-insert-quick-text'),
              enabled: available && settings.quickTexts.isNotEmpty,
              tooltip: strings.mailComposeInsertQuickText,
              onSelected: (item) {
                if (settings != null &&
                    currentMenu() &&
                    settings.quickTexts.contains(item)) {
                  _insertComposeText(item.text);
                }
              },
              itemBuilder: (_) => [
                for (final item in settings?.quickTexts ?? <MailQuickText>[])
                  PopupMenuItem(
                    value: item,
                    child: Text(item.name, maxLines: 2),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(strings.mailComposeInsertQuickText),
              ),
            ),
          ],
        ),
        if (_loadingTools)
          Semantics(
            liveRegion: true,
            child: Text(strings.mailComposeToolsLoading),
          ),
        if (_toolsLoadFailed) ...[
          Text(
            strings.mailComposeToolsLoadFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('studio-mail-reload-compose-tools'),
              onPressed: _canUseTools ? _loadComposeTools : null,
              child: Text(strings.mailComposeToolsReload),
            ),
          ),
        ],
        if (_toolsSelectionFailed)
          Text(
            strings.mailComposeToolsSelectionFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_toolsInsertionFailed)
          Text(
            strings.mailComposeToolsInsertionFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  void _fitBodyToWidth(double width) {
    // The shared Word canvas reserves 64 logical pixels on each side and a
    // 14-pixel scrollbar. Reflow this disposable plain-text mail document at
    // normal zoom instead of shrinking a full paper page (or hiding RTL text
    // beyond the viewport). Resizing must not replace the controller, source
    // paragraphs, input connection, selection or undo history.
    const pointsToPixels = 96 / 72;
    final pageWidth = ((width - 2 * 64 - 14) / pointsToPixels).clamp(
      48.0,
      double.infinity,
    );
    var changed = false;
    for (final section in _body.document.sections) {
      if (section.pageSize.width != pageWidth) {
        section.pageSize = section.pageSize.copyWith(width: pageWidth);
        changed = true;
      }
    }
    // relayout does not notify during layout or create an editing command.
    if (changed) _body.relayout();
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
    return PopScope<StudioMailDraft>(
      canPop:
          !_recoveringCache &&
          !_initialToolsPending &&
          !_editingTools &&
          (widget.onSaveDraft == null || _allowPop),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_finish(send: false));
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: AbsorbPointer(
          absorbing: _finishing || _recoveringCache || _initialToolsPending,
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
                          decoration: InputDecoration(
                            labelText: strings.mailCc,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _bcc,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: strings.mailBcc,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: _subject,
                        decoration: InputDecoration(labelText: strings.subject),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey('studio-mail-add-attachments'),
                          onPressed: _pickingAttachments
                              ? null
                              : _pickAttachments,
                          icon: _pickingAttachments
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.attach_file),
                          label: Text(
                            _pickingAttachments
                                ? strings.mailReadingAttachments
                                : strings.mailAddAttachments,
                          ),
                        ),
                      ),
                      Text(
                        strings.mailAttachmentSummary(
                          _attachments.items.length,
                          _attachments.totalBytes,
                        ),
                        textDirection: TextDirection.ltr,
                        textAlign:
                            Directionality.of(context) == TextDirection.rtl
                            ? TextAlign.right
                            : TextAlign.left,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      for (
                        var index = 0;
                        index < _attachments.items.length;
                        index++
                      )
                        Row(
                          children: [
                            const Icon(
                              Icons.insert_drive_file_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _attachments.items[index].name,
                                textDirection: TextDirection.ltr,
                                textAlign:
                                    Directionality.of(context) ==
                                        TextDirection.rtl
                                    ? TextAlign.right
                                    : TextAlign.left,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              strings.mailAttachmentSize(
                                _attachments.items[index].length,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                            IconButton(
                              key: ValueKey(
                                'studio-mail-remove-attachment-$index',
                              ),
                              tooltip: strings.mailRemoveAttachment(
                                _attachments.items[index].name,
                              ),
                              onPressed: _pickingAttachments
                                  ? null
                                  : () => _removeAttachment(index),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      if (_attachmentFailed)
                        Text(
                          strings.mailAttachmentFailed,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (_toolsOwner != null) ...[
                        _composeToolsToolbar(),
                        const SizedBox(height: 8),
                      ],
                      Text(strings.mailPlainTextBody),
                      const SizedBox(height: 4),
                      SizedBox(
                        height:
                            (constraints.maxHeight -
                                    (widget.previousSubmissionUncertain
                                        ? 436
                                        : 340) -
                                    88 -
                                    (_attachments.items.length * 48) -
                                    (_attachmentFailed ? 72 : 0) -
                                    (_showCopies ? 128 : 0) -
                                    (feedback == null ? 0 : 64))
                                .clamp(180.0, 440.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, bodyConstraints) {
                              _fitBodyToWidth(bodyConstraints.maxWidth);
                              return QudsWordEditor(
                                key: const ValueKey<String>(
                                  'studio-mail-compose-body',
                                ),
                                controller: _body,
                                focusNode: _bodyFocus,
                                enableLiveProofing: false,
                                showReviewStatus: false,
                                toolbarBuilder: (_, _) =>
                                    const SizedBox.shrink(),
                                statusBarBuilder: (_, _) =>
                                    const SizedBox.shrink(),
                              );
                            },
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
                          onChanged: (value) => setState(
                            () => _retryAcknowledged = value ?? false,
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (widget.onSaveDraft != null)
                        Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _recoveringCache
                                      ? strings.mailCacheClearing
                                      : _saveFailed
                                      ? strings.mailDraftSaveFailed
                                      : _pendingSave != null ||
                                            _savedRevision != _editRevision
                                      ? strings.mailDraftSaving
                                      : _savedRevision == 0 &&
                                            widget.initialDraft == null
                                      ? strings.mailDraftAutosave
                                      : strings.mailDraftSaved,
                                  key: const ValueKey(
                                    'studio-mail-draft-status',
                                  ),
                                  style: _saveFailed
                                      ? TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            if (_saveFailed)
                              TextButton(
                                onPressed: _finishing || _recoveringCache
                                    ? null
                                    : _saveInBackground,
                                child: Text(strings.mailDraftRetrySave),
                              ),
                          ],
                        ),
                      if (_recoveringCache) const LinearProgressIndicator(),
                      if (_saveFailed && widget.onClearMailCache != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: const ValueKey(
                              'studio-mail-compose-clear-cache',
                            ),
                            onPressed: _finishing || _recoveringCache
                                ? null
                                : _clearMailCache,
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: Text(strings.mailCacheClear),
                          ),
                        ),
                      if (_cacheClearFailed)
                        Text(
                          strings.mailCacheDraftClearFailed,
                          key: const ValueKey(
                            'studio-mail-compose-cache-error',
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (_cacheCleanupReport case final report?)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              strings.mailCacheCleared(
                                report.removedViews,
                                report.evictedBodies,
                                report.removedHeaders,
                              ),
                              key: const ValueKey(
                                'studio-mail-compose-cache-cleared',
                              ),
                            ),
                            if (report.hasMore)
                              Text(strings.mailCacheDraftClearMore),
                            if (report.retainedBodies > 0)
                              Text(
                                strings.mailCacheProtected(
                                  report.retainedBodies,
                                ),
                              ),
                          ],
                        ),
                      if (_queueFailed)
                        Text(
                          strings.mailQueueFailed,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (!widget.canSend)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(strings.mailDraftConnectToSend),
                        ),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        children: <Widget>[
                          if (_saveFailed)
                            TextButton(
                              onPressed:
                                  _finishing ||
                                      _recoveringCache ||
                                      _pendingSave != null
                                  ? null
                                  : _closeWithoutSaving,
                              child: Text(strings.mailDraftCloseUnsaved),
                            ),
                          TextButton(
                            onPressed: _finishing || _recoveringCache
                                ? null
                                : () => _finish(send: false),
                            child: Text(
                              widget.onSaveDraft == null
                                  ? strings.cancel
                                  : strings.mailDraftSaveClose,
                            ),
                          ),
                          if (widget.onQueueDraft != null)
                            TextButton.icon(
                              key: const ValueKey('studio-mail-queue'),
                              onPressed:
                                  !widget.canSend ||
                                      _finishing ||
                                      _recoveringCache ||
                                      _pickingAttachments ||
                                      (widget.previousSubmissionUncertain &&
                                          !_retryAcknowledged)
                                  ? null
                                  : () => _finish(send: true, queue: true),
                              icon: const Icon(Icons.outbox_outlined),
                              label: Text(strings.mailQueue),
                            ),
                          FilledButton.icon(
                            onPressed:
                                !widget.canSend ||
                                    _finishing ||
                                    _recoveringCache ||
                                    _pickingAttachments ||
                                    (widget.previousSubmissionUncertain &&
                                        !_retryAcknowledged)
                                ? null
                                : () => _finish(send: true),
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
        ),
      ),
    );
  }
}
