import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_compose.dart';
import 'studio_mail_compose_tools.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_draft_store_native.dart';
import 'studio_mail_drafts_dialog.dart';
import 'studio_mail_drafts_strings.dart';
import 'studio_mail_mailbox_store.dart';
import 'studio_mail_strings.dart';
import 'studio_strings.dart';

/// An owned, local-only draft workspace for one previously resolved account.
/// It never constructs a provider, discovers an endpoint, queues or sends mail.
/// The surrounding host supplies an account-lifetime guard and must await the
/// dialog result before acquiring another owner of the same native profile.
class StudioMailLocalDraftsDialog extends StatefulWidget {
  const StudioMailLocalDraftsDialog({
    super.key,
    required this.strings,
    required this.identity,
    required this.sender,
    required this.isCurrent,
    this.draftStoreFactory,
  });

  final StudioStrings strings;
  final StudioMailDraftAccount identity;
  final String sender;
  final bool Function() isCurrent;
  final StudioMailDraftStoreFactory? draftStoreFactory;

  @override
  State<StudioMailLocalDraftsDialog> createState() =>
      _StudioMailLocalDraftsDialogState();
}

class _StudioMailLocalDraftsDialogState
    extends State<StudioMailLocalDraftsDialog> {
  StudioMailDraftStore? _store;
  StudioMailDraftCatalog? _catalog;
  late final Future<void> _opening;
  Future<void>? _storeClosing;
  bool _loaded = false;
  bool _browsing = false;
  bool _closeRequested = false;
  bool _closingNavigation = false;
  bool _allowPop = false;
  String? _error;

  bool get _current =>
      mounted &&
      !_closeRequested &&
      widget.isCurrent() &&
      _catalog?.account == widget.identity.account &&
      _store != null;

  @override
  void initState() {
    super.initState();
    _opening = _openStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_browseWhenReady());
    });
  }

  @override
  void dispose() {
    _closeRequested = true;
    // An opener completing after route disposal still owns a native lease.
    // Release it when available; ordinary user close awaits this same cleanup.
    unawaited(_closeAfterDisposal());
    super.dispose();
  }

  Future<void> _closeAfterDisposal() async {
    await _opening;
    try {
      await _releaseStore();
    } on Object {
      // The route no longer has a surface for a content-redacted close error.
    }
  }

  Future<void> _openStore() async {
    try {
      if (!widget.isCurrent() ||
          !StudioMailDraft.isSupportedAddress(widget.sender)) {
        throw const StudioMailDraftStoreException(MailProblemCode.unavailable);
      }
      final candidate =
          await (widget.draftStoreFactory ?? openStudioMailDraftStore)(
            widget.identity,
          );
      _store = candidate;
      final catalog = switch (candidate) {
        StudioMailDraftCatalog value => value,
        _ => null,
      };
      if (catalog == null || catalog.account != widget.identity.account) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.permissionDenied,
        );
      }
      if (candidate case StudioMailMailboxStoreOwner(:final mailboxStore)) {
        if (mailboxStore.account != widget.identity.account) {
          throw const StudioMailDraftStoreException(
            MailProblemCode.permissionDenied,
          );
        }
      }
      _catalog = catalog;
      if (!_current) {
        await _releaseStore();
        if (mounted && !_closeRequested) {
          setState(() => _error = widget.strings.mailDraftStorageFailed);
        }
        return;
      }
      await candidate.load();
      if (!_current) {
        await _releaseStore();
        if (mounted && !_closeRequested) {
          setState(() => _error = widget.strings.mailDraftStorageFailed);
        }
        return;
      }
      setState(() => _loaded = true);
    } on Object {
      var closeFailed = false;
      try {
        await _releaseStore();
      } on Object {
        closeFailed = true;
      }
      if (mounted && !_closeRequested) {
        setState(() {
          _error = closeFailed
              ? widget.strings.mailDraftCloseFailed
              : widget.strings.mailDraftStorageFailed;
        });
      }
    }
  }

  Future<void> _browseWhenReady() async {
    await _opening;
    if (_loaded && _current) await _browseDrafts();
  }

  Future<void> _browseDrafts() async {
    if (!_loaded || !_current || _browsing) return;
    final store = _store!;
    final catalog = _catalog!;
    setState(() => _browsing = true);
    var leave = true;
    try {
      while (_current && identical(store, _store)) {
        if (!mounted) break;
        final selected = await showDialog<StudioMailStoredDraft>(
          context: context,
          barrierDismissible: false,
          builder: (_) => StudioMailDraftsDialog(
            strings: widget.strings,
            catalog: catalog,
            isCurrent: () => _current && identical(store, _store),
          ),
        );
        if (!mounted ||
            selected == null ||
            !_current ||
            !identical(store, _store)) {
          break;
        }
        final draftId = catalog.selectedDraftId;
        final epoch = catalog.selectionEpoch;
        final mailbox = switch (store) {
          StudioMailMailboxStoreOwner value => value.mailboxStore,
          _ => null,
        };
        bool currentDraft() =>
            _current &&
            identical(store, _store) &&
            catalog.selectedDraftId == draftId &&
            catalog.selectionEpoch == epoch;
        await showDialog<StudioMailDraft>(
          context: context,
          barrierDismissible: false,
          builder: (_) => StudioMailComposeDialog(
            strings: widget.strings,
            from: widget.sender,
            initialDraft: selected.draft,
            previousSubmissionUncertain: selected.submissionUncertain,
            canSend: false,
            composeToolsStore: switch (store) {
              StudioMailComposeToolsStore value => value,
              _ => null,
            },
            isComposeToolsCurrent: currentDraft,
            onClearMailCache: mailbox == null
                ? null
                : () async {
                    if (!currentDraft()) {
                      throw const StudioMailDraftStoreException(
                        MailProblemCode.unavailable,
                      );
                    }
                    return mailbox.clearCache();
                  },
            onSaveDraft: (snapshot) async {
              if (!currentDraft()) {
                throw const StudioMailDraftStoreException(
                  MailProblemCode.unavailable,
                );
              }
              await store.save(
                snapshot,
                submissionUncertain: selected.submissionUncertain,
              );
            },
          ),
        );
      }
    } on Object {
      leave = false;
      if (mounted) {
        setState(() => _error = widget.strings.mailDraftStorageFailed);
      }
    } finally {
      if (mounted) setState(() => _browsing = false);
      if (leave) await _closeAndPop();
    }
  }

  Future<void> _releaseStore() {
    final pending = _storeClosing;
    if (pending != null) return pending;
    final store = _store;
    if (store == null) return Future<void>.value();
    final closing = Future<void>.sync(store.close).then((_) {
      if (identical(store, _store)) {
        _store = null;
        _catalog = null;
      }
    });
    final result = closing.whenComplete(() => _storeClosing = null);
    _storeClosing = result;
    return result;
  }

  Future<void> _closeAndPop() async {
    if (_closingNavigation) return;
    _closeRequested = true;
    if (mounted) setState(() => _closingNavigation = true);
    await _opening;
    try {
      await _releaseStore();
    } on Object {
      if (mounted) {
        setState(() {
          _closingNavigation = false;
          _error = widget.strings.mailDraftCloseFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_browsing) unawaited(_closeAndPop());
    },
    child: AlertDialog(
      title: Text(widget.strings.mailLocalDrafts),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.sender),
            const SizedBox(height: 12),
            Text(widget.strings.mailLocalDraftsExplanation),
            if (!_loaded && _error == null || _closingNavigation) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                key: const ValueKey('studio-mail-local-drafts-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_loaded && !_closeRequested)
          TextButton(
            onPressed: _browsing ? null : _browseDrafts,
            child: Text(widget.strings.mailDrafts),
          ),
        TextButton(
          key: const ValueKey('studio-mail-local-drafts-close'),
          onPressed: _closingNavigation || _browsing ? null : _closeAndPop,
          child: Text(widget.strings.close),
        ),
      ],
    ),
  );
}
