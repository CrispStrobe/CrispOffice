import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_cached_mail.dart';
import 'studio_mail_cached_search_dialog.dart';
import 'studio_mail_cached_search_strings.dart';
import 'studio_mail_cached_strings.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_local_accounts.dart';
import 'studio_mail_local_accounts_strings.dart';
import 'studio_mail_local_drafts.dart';
import 'studio_mail_strings.dart';
import 'studio_strings.dart';

/// A directory of verified local draft identities. Browsing, choosing and
/// removing entries never constructs a provider or touches credential storage.
class StudioMailLocalAccountsDialog extends StatefulWidget {
  const StudioMailLocalAccountsDialog({
    super.key,
    required this.strings,
    required this.store,
    required this.isCurrent,
    this.provider,
    this.draftStoreFactory,
  });

  final StudioStrings strings;
  final StudioMailLocalAccountStore store;
  final bool Function() isCurrent;
  final MailProviderKind? provider;
  final StudioMailDraftStoreFactory? draftStoreFactory;

  @override
  State<StudioMailLocalAccountsDialog> createState() =>
      _StudioMailLocalAccountsDialogState();
}

class _StudioMailLocalAccountsDialogState
    extends State<StudioMailLocalAccountsDialog> {
  List<MailLocalAccountRecord> _records = const [];
  bool _busy = true;
  bool _childOpen = false;
  String? _error;

  bool get _current => mounted && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!_current) return;
    setState(() {
      _busy = true;
      _error = null;
      _records = const [];
    });
    try {
      final rows = await widget.store.load();
      if (!_current) return;
      for (final row in rows) {
        studioMailLocalAccountIdentity(row);
      }
      setState(
        () => _records = [
          for (final row in rows)
            if (widget.provider == null || widget.provider == row.provider) row,
        ],
      );
    } on Object {
      if (_current) {
        setState(() => _error = widget.strings.mailLocalAccountsFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _providerName(MailProviderKind provider) => switch (provider) {
    MailProviderKind.imap => 'IMAP / SMTP',
    MailProviderKind.ews => widget.strings.ewsTitle,
    MailProviderKind.gmail => 'Gmail',
    MailProviderKind.graph => 'Microsoft 365 / Outlook',
    _ => provider.name,
  };

  String _description(MailLocalAccountRecord row) {
    var login = row.login;
    if (row.provider == MailProviderKind.ews ||
        row.provider == MailProviderKind.graph) {
      try {
        final Object? parts = jsonDecode(login);
        if (parts is List<Object?> && parts.every((part) => part is String)) {
          login = parts
              .cast<String>()
              .where((part) => part.isNotEmpty)
              .join(' · ');
        }
      } on Object {
        // Display the literal non-secret identity when it is not structured.
      }
    }
    return '${row.endpoint}\n$login';
  }

  Future<void> _open(
    MailLocalAccountRecord row, {
    bool cachedMail = false,
  }) async {
    if (!_current || _busy || _childOpen) return;
    setState(() => _childOpen = true);
    try {
      // Re-read before opening so a stale removed shortcut cannot acquire a
      // draft owner. Also verify the original scope before entering its store.
      final latest = await widget.store.load();
      if (!_current) return;
      final matches = latest.where(
        (entry) => entry.hasSameIdentity(row) && entry.revision == row.revision,
      );
      if (matches.length != 1) {
        throw const StudioMailDraftStoreException(MailProblemCode.conflict);
      }
      final identity = studioMailLocalAccountIdentity(matches.single);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => cachedMail
            ? StudioMailCachedMailDialog(
                strings: widget.strings,
                identity: identity,
                isCurrent: () => _current,
                draftStoreFactory: widget.draftStoreFactory,
              )
            : StudioMailLocalDraftsDialog(
                strings: widget.strings,
                identity: identity,
                sender: identity.sender,
                isCurrent: () => _current,
                draftStoreFactory: widget.draftStoreFactory,
              ),
      );
    } on Object {
      if (_current) {
        setState(() => _error = widget.strings.mailLocalAccountsFailed);
      }
    } finally {
      if (mounted) setState(() => _childOpen = false);
    }
  }

  Future<void> _forget(MailLocalAccountRecord row) async {
    if (!_current || _busy || _childOpen) return;
    setState(() => _childOpen = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.strings.mailLocalAccountRemove),
          content: Text(
            '${row.sender}\n${_description(row)}\n\n'
            '${widget.strings.mailLocalAccountRemoveHelp}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(widget.strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.strings.mailLocalAccountRemove),
            ),
          ],
        ),
      );
      if (!_current || confirmed != true) return;
      await widget.store.forget(row);
      if (_current) await _refresh();
    } on Object {
      if (_current) {
        setState(() => _error = widget.strings.mailLocalAccountsFailed);
      }
    } finally {
      if (mounted) setState(() => _childOpen = false);
    }
  }

  Future<void> _openSavedSearch() async {
    if (!_current || _busy || _childOpen) return;
    final directory = widget.store;
    final provider = widget.provider;
    final openStore = widget.draftStoreFactory;
    final strings = widget.strings;
    final parentIsCurrent = widget.isCurrent;
    bool entryIsCurrent() =>
        _current &&
        parentIsCurrent() &&
        identical(widget.store, directory) &&
        widget.provider == provider &&
        identical(widget.draftStoreFactory, openStore);
    setState(() => _childOpen = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Directionality(
          textDirection: strings.language == StudioLanguage.ar
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: StudioMailCachedSearchDialog(
            strings: strings,
            store: directory,
            isCurrent: entryIsCurrent,
            provider: provider,
            draftStoreFactory: openStore,
          ),
        ),
      );
    } on Object {
      if (entryIsCurrent()) {
        setState(() => _error = widget.strings.mailLocalAccountsFailed);
      }
    } finally {
      if (mounted) setState(() => _childOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_childOpen,
    child: AlertDialog(
      title: Text(widget.strings.mailLocalAccounts),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.strings.mailLocalAccountsHelp),
              const SizedBox(height: 8),
              Text(widget.strings.mailCachedAccountsHelp),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('studio-mail-search-saved'),
                  onPressed:
                      _busy ||
                          _childOpen ||
                          !_current ||
                          _records.isEmpty ||
                          _error != null
                      ? null
                      : _openSavedSearch,
                  icon: const Icon(Icons.manage_search),
                  label: Text(widget.strings.mailCachedSearch),
                ),
              ),
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(),
              if (_error case final error?) Text(error),
              if (!_busy && _error == null && _records.isEmpty)
                Text(widget.strings.mailLocalAccountsEmpty),
              for (final row in _records) ...[
                ListTile(
                  key: ValueKey('studio-mail-local-account-${row.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('${_providerName(row.provider)} · ${row.sender}'),
                  subtitle: Text(_description(row)),
                  onTap: _busy || _childOpen || !_current
                      ? null
                      : () => _open(row),
                  trailing: IconButton(
                    tooltip: widget.strings.mailLocalAccountRemove,
                    onPressed: _busy || _childOpen || !_current
                        ? null
                        : () => _forget(row),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: ValueKey('studio-mail-cached-account-${row.id}'),
                    onPressed: _busy || _childOpen || !_current
                        ? null
                        : () => _open(row, cachedMail: true),
                    icon: const Icon(Icons.offline_pin_outlined),
                    label: Text(widget.strings.mailCachedMail),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy || _childOpen || !_current ? null : _refresh,
          child: Text(widget.strings.refresh),
        ),
        TextButton(
          onPressed: _childOpen ? null : () => Navigator.pop(context),
          child: Text(widget.strings.close),
        ),
      ],
    ),
  );
}
