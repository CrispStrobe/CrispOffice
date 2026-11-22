import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_account_navigation_strings.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_local_accounts.dart';
import 'studio_mail_strings.dart';
import 'studio_strings.dart';

/// A selected, non-secret account route. It grants no connection or provider
/// authority; hosts must request sign-in and preserve the selected identity.
final class StudioMailAccountNavigationTarget {
  factory StudioMailAccountNavigationTarget.fromRecord(
    MailLocalAccountRecord record,
  ) {
    final identity = studioMailLocalAccountIdentity(record);
    final endpoint = Uri.parse(identity.endpoint);
    if (!_usableEndpoint(endpoint)) _invalid();
    String? domain;
    String? login;
    String? tenant;
    switch (identity.provider) {
      case MailProviderKind.imap:
        if ((endpoint.scheme != 'imap' && endpoint.scheme != 'imaps') ||
            endpoint.path.isNotEmpty ||
            // The native account namespace records its actual socket port.
            // Uri folds :0 into a missing port for these non-default schemes;
            // neither representation can identify a reconnectable route.
            endpoint.port <= 0 ||
            endpoint.port > 65535) {
          _invalid();
        }
      case MailProviderKind.ews:
        if (endpoint.scheme != 'https') _invalid();
        final parts = _loginParts(identity.login);
        domain = parts.$1;
        login = parts.$2;
        if (login.isEmpty) _invalid();
      case MailProviderKind.gmail:
        if (identity.endpoint != 'https://gmail.googleapis.com/gmail/v1' ||
            identity.login != identity.sender) {
          _invalid();
        }
      case MailProviderKind.graph:
        if (identity.endpoint != 'https://graph.microsoft.com/v1.0') _invalid();
        final parts = _loginParts(identity.login);
        tenant = parts.$1;
        if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9.-]{0,253}$').hasMatch(tenant) ||
            tenant.contains('..') ||
            parts.$2 != identity.sender) {
          _invalid();
        }
      default:
        _invalid();
    }
    return StudioMailAccountNavigationTarget._(
      record,
      identity,
      domain,
      login,
      tenant,
    );
  }

  const StudioMailAccountNavigationTarget._(
    this.record,
    this.identity,
    this.ewsDomain,
    this.ewsLogin,
    this.graphTenant,
  );

  final MailLocalAccountRecord record;
  final StudioMailDraftAccount identity;
  final String? ewsDomain;
  final String? ewsLogin;
  final String? graphTenant;

  MailProviderKind get provider => identity.provider;

  String providerLabel(StudioStrings strings) => switch (provider) {
    MailProviderKind.imap => 'IMAP / SMTP',
    MailProviderKind.ews => strings.ewsTitle,
    MailProviderKind.gmail => 'Gmail',
    MailProviderKind.graph => 'Microsoft 365 / Outlook',
    _ => throw const StudioMailDraftStoreException(
      MailProblemCode.invalidInput,
    ),
  };

  /// Full non-secret routing details, without the internal account fingerprint.
  String get description {
    final login = switch (provider) {
      MailProviderKind.ews => [
        if (ewsDomain!.isNotEmpty) ewsDomain!,
        ewsLogin!,
      ].join(' · '),
      MailProviderKind.graph => '$graphTenant · ${identity.sender}',
      _ => identity.login,
    };
    return '${identity.endpoint}\n$login';
  }

  /// Prevents edited setup or a different provider route from silently
  /// reconnecting another account after this target has been selected.
  void requireMatches(StudioMailDraftAccount actual) {
    if (actual.account != identity.account ||
        actual.provider != identity.provider ||
        actual.endpoint != identity.endpoint ||
        actual.login != identity.login ||
        actual.sender != identity.sender) {
      throw const StudioMailDraftStoreException(
        MailProblemCode.permissionDenied,
      );
    }
  }

  /// Revalidates the whole bounded catalog before admitting this exact record.
  /// A removed/replaced record, duplicate, or malformed sibling fails closed.
  Future<void> validateCurrent(StudioMailLocalAccountStore store) async {
    final targets = _targets(await store.load());
    final current = targets.where((target) => target.record.id == record.id);
    if (current.length != 1 ||
        !current.single.record.hasSameIdentity(record) ||
        current.single.record.revision != record.revision) {
      throw const StudioMailDraftStoreException(MailProblemCode.conflict);
    }
  }

  /// Refreshes a fulfilled sign-in only if its selected shortcut still exists
  /// unchanged. Older/custom directories without an atomic refresh capability
  /// keep their existing metadata; a read followed by an unconditional remember
  /// could otherwise recreate a shortcut removed during sign-in.
  Future<void> rememberConnection(
    StudioMailLocalAccountStore store,
    StudioMailDraftAccount actual, {
    required bool Function() isCurrent,
  }) async {
    requireMatches(actual);
    void checkCurrent() {
      if (!isCurrent()) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.staleOperation,
        );
      }
    }

    checkCurrent();
    await validateCurrent(store);
    checkCurrent();
    if (store is StudioMailLocalAccountReconnectStore) {
      await (store as StudioMailLocalAccountReconnectStore).rememberSelected(
        actual,
        expectedRecord: record,
      );
    }
    checkCurrent();
  }

  static Never _invalid() =>
      throw const StudioMailDraftStoreException(MailProblemCode.invalidInput);

  static bool _usableEndpoint(Uri uri) =>
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      !RegExp(r'[\s%/@?#\\]').hasMatch(uri.host) &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (!uri.hasPort || uri.port > 0 && uri.port <= 65535);

  static (String, String) _loginParts(String value) {
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      _invalid();
    }
    if (decoded is! List<Object?> ||
        decoded.length != 2 ||
        decoded.any((part) => part is! String)) {
      _invalid();
    }
    final first = decoded[0]! as String;
    final second = decoded[1]! as String;
    for (final part in [first, second]) {
      if (part != part.trim() || RegExp(r'[\x00-\x1f\x7f]').hasMatch(part)) {
        _invalid();
      }
    }
    return (first, second);
  }

  static List<StudioMailAccountNavigationTarget> _targets(
    List<MailLocalAccountRecord> records,
  ) {
    if (records.length > 100) {
      throw const StudioMailDraftStoreException(MailProblemCode.quotaExceeded);
    }
    final ids = <String>{};
    final targets = <StudioMailAccountNavigationTarget>[];
    for (final record in records) {
      if (!ids.add(record.id)) {
        throw const StudioMailDraftStoreException(MailProblemCode.conflict);
      }
      targets.add(StudioMailAccountNavigationTarget.fromRecord(record));
    }
    return List.unmodifiable(targets);
  }

  @override
  String toString() => 'StudioMailAccountNavigationTarget(redacted)';
}

/// Choosing or refreshing an account only reads local metadata. The caller
/// owns the subsequent draft-safe transition and explicit provider sign-in.
Future<StudioMailAccountNavigationTarget?> showStudioMailAccountNavigation({
  required BuildContext context,
  required StudioStrings strings,
  required StudioMailLocalAccountStore store,
  required bool Function() isCurrent,
  StudioMailDraftAccount? currentAccount,
}) async {
  if (!context.mounted || !isCurrent()) return null;
  final target = await showDialog<StudioMailAccountNavigationTarget>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Directionality(
      textDirection: strings.language == StudioLanguage.ar
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: _StudioMailAccountNavigationDialog(
        strings: strings,
        store: store,
        isCurrent: isCurrent,
        currentAccount: currentAccount,
      ),
    ),
  );
  return context.mounted && isCurrent() ? target : null;
}

class _StudioMailAccountNavigationDialog extends StatefulWidget {
  const _StudioMailAccountNavigationDialog({
    required this.strings,
    required this.store,
    required this.isCurrent,
    required this.currentAccount,
  });

  final StudioStrings strings;
  final StudioMailLocalAccountStore store;
  final bool Function() isCurrent;
  final StudioMailDraftAccount? currentAccount;

  @override
  State<_StudioMailAccountNavigationDialog> createState() =>
      _StudioMailAccountNavigationDialogState();
}

class _StudioMailAccountNavigationDialogState
    extends State<_StudioMailAccountNavigationDialog> {
  List<StudioMailAccountNavigationTarget> _targets = const [];
  StudioMailAccountNavigationTarget? _selected;
  bool _busy = true;
  String? _error;
  int _generation = 0;

  bool get _current => mounted && widget.isCurrent();
  bool _isCurrent(int generation) => _current && generation == _generation;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!_current) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _targets = const [];
      _selected = null;
    });
    try {
      final targets = StudioMailAccountNavigationTarget._targets(
        await widget.store.load(),
      );
      if (!_isCurrent(generation)) return;
      setState(() => _targets = targets);
    } on Object {
      if (_isCurrent(generation)) {
        setState(() => _error = widget.strings.mailAccountNavigationFailed);
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _continue() async {
    final selected = _selected;
    if (!_current ||
        _busy ||
        _error != null ||
        selected == null ||
        selected.identity.account == widget.currentAccount?.account) {
      return;
    }
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      await selected.validateCurrent(widget.store);
      if (!mounted ||
          !_isCurrent(generation) ||
          !identical(_selected, selected)) {
        return;
      }
      Navigator.pop(context, selected);
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _selected = null;
        _error =
            error is StudioMailDraftStoreException &&
                error.code == MailProblemCode.conflict
            ? widget.strings.mailAccountNavigationChanged
            : widget.strings.mailAccountNavigationFailed;
      });
    } finally {
      if (_isCurrent(generation)) setState(() => _busy = false);
    }
  }

  void _cancel() {
    _generation++;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.mailAccountNavigationTitle),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.strings.mailAccountNavigationHelp),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!_busy && _error == null && _targets.isEmpty)
              Text(widget.strings.mailAccountNavigationEmpty),
            for (final target in _targets) _accountTile(target),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        key: const ValueKey('studio-mail-account-navigation-refresh'),
        onPressed: _busy || !_current ? null : _refresh,
        icon: const Icon(Icons.refresh),
        label: Text(widget.strings.mailAccountNavigationRefresh),
      ),
      TextButton(
        key: const ValueKey('studio-mail-account-navigation-cancel'),
        onPressed: _cancel,
        child: Text(widget.strings.cancel),
      ),
      FilledButton(
        key: const ValueKey('studio-mail-account-navigation-continue'),
        onPressed: _busy || _selected == null || _error != null || !_current
            ? null
            : _continue,
        child: Text(widget.strings.mailAccountNavigationContinue),
      ),
    ],
  );

  Widget _accountTile(StudioMailAccountNavigationTarget target) {
    final current = target.identity.account == widget.currentAccount?.account;
    return Tooltip(
      message: '${target.identity.sender}\n${target.description}',
      child: ListTile(
        key: ValueKey('studio-mail-navigation-account-${target.record.id}'),
        contentPadding: EdgeInsets.zero,
        enabled: !_busy && _error == null && _current && !current,
        selected: identical(_selected, target),
        leading: Icon(
          current
              ? Icons.account_circle
              : identical(_selected, target)
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
        ),
        title: Text(
          '${target.providerLabel(widget.strings)} · ${target.identity.sender}',
        ),
        subtitle: Text(
          [
            if (current) widget.strings.mailAccountNavigationCurrent,
            target.description,
          ].join('\n'),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: _busy || _error != null || !_current || current
            ? null
            : () => setState(() => _selected = target),
      ),
    );
  }
}
