import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_compose.dart';
import 'studio_mail_operation.dart';
import 'studio_mail_reply.dart';
import 'studio_mail_strings.dart';
import 'studio_mail_submission.dart';
import 'studio_strings.dart';

typedef StudioEwsProviderFactory =
    MailEwsProvider Function(
      MailEwsConfiguration configuration,
      MailCredentialStore credentials,
    );

/// Explicit, foreground Exchange Server host. This example retains credentials,
/// downloaded messages and unsent drafts only for the current dialog session.
class StudioMailEwsDialog extends StatefulWidget {
  const StudioMailEwsDialog({
    super.key,
    required this.strings,
    this.providerFactory,
  });

  final StudioStrings strings;

  /// Tests inject the provider boundary, not sockets or authenticated clients.
  final StudioEwsProviderFactory? providerFactory;

  @override
  State<StudioMailEwsDialog> createState() => _StudioMailEwsDialogState();
}

class _StudioMailEwsDialogState extends State<StudioMailEwsDialog> {
  static const _pageSize = 50;
  static const _maxHeaders = 1000;
  final _endpoint = TextEditingController();
  final _email = TextEditingController();
  final _login = TextEditingController();
  final _domain = TextEditingController();
  final _password = TextEditingController();
  final _search = TextEditingController();
  MailEwsAuthentication _authentication = MailEwsAuthentication.ntlm;
  MailEwsProvider? _provider;
  MailAccountSession? _session;
  _SessionCredentials? _credentials;
  MailCapabilities _capabilities = const MailCapabilities.none();
  List<MailMailbox> _mailboxes = const [];
  MailMailbox? _mailbox;
  List<MailHeaderRecord> _headers = const [];
  MailCursor? _next;
  MailHeaderRecord? _selected;
  MailReaderController? _reader;
  StudioMailDraft? _draft;
  bool _submissionUncertain = false;
  bool _connected = false;
  bool _busy = false;
  bool _dialogOpen = false;
  bool _showMessage = false;
  bool _needsRefresh = false;
  String? _error;
  String? _notice;
  String _sender = '';
  int _serial = 0;

  bool get _blocked => _busy || _dialogOpen;
  bool get _canSend => _capabilities.supports(MailCapability.send);
  bool _current(MailEwsProvider provider, MailOperationLease lease) =>
      mounted && identical(_provider, provider) && lease.isCurrent;

  T _value<T>(MailResult<T> result) => switch (result) {
    MailSuccess<T>(:final value) => value,
    MailFailure<T>(:final problem) => throw _EwsUiFailure(problem),
  };

  String _problem(MailProblem problem, String fallback) =>
      switch (problem.code) {
        MailProblemCode.authenticationRequired =>
          widget.strings.ewsAuthenticationFailed,
        MailProblemCode.permissionDenied => widget.strings.ewsAccessFailed,
        MailProblemCode.unsupported => widget.strings.ewsUnsupported,
        MailProblemCode.quotaExceeded => widget.strings.ewsBudgetExceeded,
        _ => fallback,
      };

  void _retire(MailReaderController? reader) {
    if (reader != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    _credentials?.clear();
    _reader?.dispose();
    _reader = null;
    _draft = null;
    _headers = const [];
    _password.clear();
    for (final controller in [
      _endpoint,
      _email,
      _login,
      _domain,
      _password,
      _search,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() => runStudioMailOperation(() async {
    if (_blocked || _connected) return;
    final sender = _email.text.trim();
    MailEwsConfiguration configuration;
    try {
      if (!StudioMailDraft.isSupportedAddress(sender) ||
          _password.text.isEmpty) {
        throw const FormatException();
      }
      final profile = MailProfileId('studio-ews', hostId: 'quds-office-studio');
      final account = MailAccountId(
        '${DateTime.now().microsecondsSinceEpoch}-${++_serial}',
        profile: profile,
      );
      configuration = MailEwsConfiguration(
        account: account,
        endpoint: Uri.parse(_endpoint.text.trim()),
        username: _login.text.trim().isEmpty ? sender : _login.text.trim(),
        domain: _domain.text.trim(),
        mailboxAddress: sender,
        authentication: _authentication,
        credential: MailCredentialReference(
          account: account,
          key: 'session-password',
        ),
      );
    } on Object {
      setState(() => _error = widget.strings.ewsInvalidSettings);
      return;
    }
    final credentials = _SessionCredentials(
      MailCredentialRecord(
        reference: configuration.credential,
        opaqueData: MailBytes(utf8.encode(_password.text)),
      ),
    );
    final session = MailAccountSession(configuration.account);
    MailEwsProvider provider;
    try {
      provider =
          widget.providerFactory?.call(configuration, credentials) ??
          createMailEwsProvider(
            configuration: configuration,
            credentialStore: credentials,
          );
      if (provider.account != configuration.account) {
        throw const FormatException();
      }
    } on Object {
      credentials.clear();
      session.dispose();
      setState(() => _error = widget.strings.mailConnectionFailed);
      return;
    }
    final lease = session.begin();
    setState(() {
      _provider = provider;
      _session = session;
      _credentials = credentials;
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final capabilities = await provider.capabilities(lease);
      if (!_current(provider, lease)) return;
      final supported = _value(capabilities);
      if (!supported.supports(MailCapability.mail)) {
        throw const _EwsUiFailure(MailProblem(MailProblemCode.unsupported));
      }
      final folders = await provider.listMailboxes(lease);
      if (!_current(provider, lease)) return;
      final boxes = _value(folders);
      if (boxes.isEmpty) {
        throw const _EwsUiFailure(MailProblem(MailProblemCode.unavailable));
      }
      final inbox =
          boxes
              .where(
                (box) => const {
                  'inbox',
                  'posteingang',
                  'علبة الوارد',
                }.contains(box.displayName.toLowerCase()),
              )
              .firstOrNull ??
          boxes.first;
      final response = await provider.fetchHeaders(
        inbox.id,
        limit: _pageSize,
        lease: lease,
      );
      if (!_current(provider, lease)) return;
      final page = _value(response);
      setState(() {
        _connected = true;
        _capabilities = supported;
        _busy = false;
        _sender = sender;
        _mailboxes = boxes;
        _mailbox = inbox;
        _headers = page.messages;
        _next = page.next;
        _password.clear();
      });
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      session.dispose();
      credentials.clear();
      setState(() {
        _provider = null;
        _session = null;
        _credentials = null;
        _busy = false;
        _error = error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.mailConnectionFailed)
            : widget.strings.mailConnectionFailed;
      });
    }
  });

  void _disconnect() {
    _session?.dispose();
    _credentials?.clear();
    final old = _reader;
    setState(() {
      _session = null;
      _provider = null;
      _credentials = null;
      _capabilities = const MailCapabilities.none();
      _connected = false;
      _busy = false;
      _dialogOpen = false;
      _mailboxes = const [];
      _mailbox = null;
      _headers = const [];
      _next = null;
      _selected = null;
      _reader = null;
      _draft = null;
      _submissionUncertain = false;
      _showMessage = false;
      _needsRefresh = false;
      _password.clear();
      _search.clear();
      _error = null;
      _notice = null;
      _sender = '';
    });
    _retire(old);
  }

  Future<void> _loadHeaders(MailMailbox mailbox, {bool more = false}) async {
    final provider = _provider;
    final session = _session;
    if (provider == null ||
        session == null ||
        _blocked ||
        more &&
            (_needsRefresh ||
                _next == null ||
                _headers.length >= _maxHeaders)) {
      return;
    }
    final lease = session.begin();
    final old = more ? null : _reader;
    final cursor = more ? _next : null;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      if (!more) {
        _mailbox = mailbox;
        _selected = null;
        _reader = null;
        _headers = const [];
        _next = null;
        _showMessage = false;
      }
    });
    _retire(old);
    try {
      final response = await provider.fetchHeaders(
        mailbox.id,
        cursor: cursor,
        limit: _pageSize,
        lease: lease,
      );
      if (!_current(provider, lease)) return;
      final page = _value(response);
      final byId = <MailRemoteIdentity, MailHeaderRecord>{
        if (more)
          for (final header in _headers) header.remote: header,
        for (final header in page.messages) header.remote: header,
      };
      setState(() {
        _headers = byId.values.take(_maxHeaders).toList();
        _next = page.next;
        _busy = false;
        if (!more) _needsRefresh = false;
        if (_headers.length >= _maxHeaders && _next != null) {
          _notice = widget.strings.ewsHeaderLimit;
        }
      });
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      setState(() {
        _busy = false;
        _error = error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.mailMailboxFailed)
            : widget.strings.mailMailboxFailed;
      });
    }
  }

  Future<void> _openMessage(MailHeaderRecord header) async {
    final provider = _provider;
    final session = _session;
    if (provider == null || session == null || _blocked) return;
    final lease = session.begin();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await provider.fetchMessage(
        header.remote,
        budget: const MailReadBudget(),
        lease: lease,
      );
      if (!_current(provider, lease)) return;
      final message = _value(result);
      final next = MailReaderController(
        result: MailParseResult(
          status: MailParseStatus.complete,
          message: message,
        ),
      );
      final old = _reader;
      setState(() {
        _reader = next;
        _selected = header;
        _showMessage = true;
        _busy = false;
      });
      _retire(old);
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      setState(() {
        _busy = false;
        _error = error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.mailMessageFailed)
            : widget.strings.mailMessageFailed;
      });
    }
  }

  Future<void> _apply(MailOperation command) async {
    final provider = _provider;
    final session = _session;
    final selected = _selected;
    if (provider == null ||
        session == null ||
        selected == null ||
        _blocked ||
        _needsRefresh ||
        command.message != selected.remote ||
        command is MailMove && !_capabilities.supports(MailCapability.move)) {
      return;
    }
    final lease = session.begin();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await provider.apply(command, lease);
      if (!_current(provider, lease)) return;
      _value(result);
      MailReaderController? old;
      setState(() {
        if (command is MailMove || command is MailDelete) {
          _headers = _headers
              .where((header) => header.remote != selected.remote)
              .toList();
          old = _reader;
          _reader = null;
          _selected = null;
          _showMessage = false;
          // Removing a row shifts FindItem offsets. The next page must start
          // from a refreshed folder rather than reusing that earlier cursor.
          _next = null;
        } else {
          final flags = selected.flags;
          final updated = MailHeaderRecord(
            id: selected.id,
            remote: selected.remote,
            envelope: selected.envelope,
            flags: flags == null
                ? null
                : MailMessageFlags(
                    isRead: command is MailSetRead
                        ? command.read
                        : flags.isRead,
                    isFlagged: command is MailSetFlagged
                        ? command.flagged
                        : flags.isFlagged,
                    isAnswered: flags.isAnswered,
                    isDraft: flags.isDraft,
                    isDeleted: flags.isDeleted,
                  ),
          );
          _selected = updated;
          _headers = [
            for (final header in _headers)
              header.remote == updated.remote ? updated : header,
          ];
        }
        _busy = false;
        _notice = command is MailMove || command is MailDelete
            ? widget.strings.ewsFolderChanged
            : widget.strings.ewsActionConfirmed;
      });
      _retire(old);
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      setState(() {
        _busy = false;
        // Even a failed confirmation can follow an accepted write. Require a
        // fresh mailbox observation before another mutation in this session.
        _needsRefresh = true;
        _error = error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.ewsMutationFailed)
            : widget.strings.ewsMutationFailed;
      });
    }
  }

  Future<void> _delete() async {
    final provider = _provider;
    final session = _session;
    final selected = _selected;
    if (provider == null ||
        session == null ||
        selected == null ||
        _blocked ||
        _needsRefresh) {
      return;
    }
    final lease = session.begin();
    setState(() => _dialogOpen = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.ewsDelete),
        content: Text(widget.strings.ewsDeleteExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings.ewsDelete),
          ),
        ],
      ),
    );
    if (!_current(provider, lease)) return;
    setState(() => _dialogOpen = false);
    if (confirmed == true && identical(_selected, selected)) {
      await _apply(
        MailDelete(id: 'delete-${++_serial}', message: selected.remote),
      );
    }
  }

  Future<void> _compose([StudioMailDraft? initial]) =>
      runStudioMailOperation(() async {
        final provider = _provider;
        final session = _session;
        if (provider == null ||
            session == null ||
            !_connected ||
            !_canSend ||
            _blocked) {
          return;
        }
        if (initial != null && _draft != null) {
          setState(() => _error = widget.strings.mailRetainedDraft);
          return;
        }
        final lease = session.begin();
        setState(() => _dialogOpen = true);
        final draft = await showDialog<StudioMailDraft>(
          context: context,
          builder: (context) => StudioMailComposeDialog(
            strings: widget.strings,
            from: _sender,
            initialDraft: initial ?? _draft,
            previousSubmissionUncertain: _submissionUncertain,
          ),
        );
        if (!_current(provider, lease)) return;
        setState(() => _dialogOpen = false);
        if (draft == null) return;
        setState(() {
          _draft = draft;
          _busy = true;
          _error = null;
          _notice = widget.strings.sending;
        });
        var attempted = false;
        try {
          final wire = buildStudioMailMessage(draft, _sender).renderMessage();
          final attempt = 'ews-send-${++_serial}';
          final message = MailPreparedMessage(
            account: provider.account,
            draftId: 'session-draft',
            draftRevision: _serial,
            wire: MailBytes(utf8.encode(wire)),
            envelope: MailTransportEnvelope(
              sender: _sender,
              recipients: [draft.to],
            ),
          );
          lease.checkCurrent();
          attempted = true;
          final result = await provider.submit(
            message,
            attemptId: attempt,
            lease: lease,
          );
          if (!_current(provider, lease)) return;
          final outcome = result.attemptId == attempt
              ? result.outcome
              : MailSubmissionOutcome.uncertain;
          setState(() {
            _busy = false;
            _notice = null;
            _submissionUncertain = outcome == MailSubmissionOutcome.uncertain;
            if (outcome == MailSubmissionOutcome.accepted) {
              _draft = null;
              _notice = widget.strings.ewsSubmissionAccepted;
            } else {
              _error = _submissionUncertain
                  ? widget.strings.mailSubmissionUncertain
                  : widget.strings.ewsSubmissionRejected;
            }
          });
        } on Object {
          if (!_current(provider, lease)) return;
          setState(() {
            _busy = false;
            _notice = null;
            _submissionUncertain = _submissionUncertain || attempted;
            _error = _submissionUncertain
                ? widget.strings.mailSubmissionUncertain
                : widget.strings.ewsSubmissionRejected;
          });
        }
      });

  Future<void> _reply({required bool forward}) async {
    final message = _reader?.result.message;
    if (message == null || !_canSend || _blocked) return;
    try {
      await _compose(
        buildStudioMailReplyDraft(
          message,
          forward: forward,
          truncationNotice: widget.strings.mailQuotedTextTruncated,
          forwardNotice: widget.strings.mailTextOnlyForward,
        ),
      );
    } on StudioMailReplyUnavailable {
      if (mounted) {
        setState(() => _error = widget.strings.mailPlainTextUnavailable);
      }
    }
  }

  Future<void> _discardDraft() async {
    final provider = _provider;
    final session = _session;
    if (provider == null || session == null || _draft == null || _blocked) {
      return;
    }
    final lease = session.begin();
    setState(() => _dialogOpen = true);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.mailDiscardDraft),
        content: Text(widget.strings.mailDiscardDraftExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings.mailDiscardDraft),
          ),
        ],
      ),
    );
    if (!_current(provider, lease)) return;
    setState(() {
      _dialogOpen = false;
      if (discard == true) {
        _draft = null;
        _submissionUncertain = false;
        _error = null;
        _notice = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.ewsTitle, overflow: TextOverflow.ellipsis),
        actions: [
          if (_connected) ...[
            IconButton(
              tooltip: widget.strings.compose,
              icon: const Icon(Icons.edit_outlined),
              onPressed: _blocked || !_canSend ? null : () => _compose(),
            ),
            IconButton(
              tooltip: widget.strings.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: _blocked || _mailbox == null
                  ? null
                  : () => _loadHeaders(_mailbox!),
            ),
            if (_draft != null)
              IconButton(
                tooltip: widget.strings.mailDiscardDraft,
                icon: const Icon(Icons.delete_outline),
                onPressed: _blocked ? null : _discardDraft,
              ),
          ],
          if (_session != null)
            IconButton(
              tooltip: widget.strings.disconnect,
              icon: const Icon(Icons.logout),
              onPressed: _dialogOpen ? null : _disconnect,
            ),
          IconButton(
            tooltip: widget.strings.close,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: _connected ? _inbox() : _setup(),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String key,
    String label, {
    String? hint,
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: ValueKey(key),
      controller: controller,
      enabled: !_busy,
      obscureText: secret,
      enableSuggestions: !secret,
      enableIMEPersonalizedLearning: !secret,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _setup() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.dns_outlined, size: 44),
            const SizedBox(height: 12),
            Text(widget.strings.ewsSetupHelp, textAlign: TextAlign.center),
            _field(
              _endpoint,
              'ews-endpoint',
              widget.strings.ewsEndpoint,
              hint: 'https://mail.example.com/EWS/Exchange.asmx',
            ),
            _field(
              _email,
              'ews-mailbox',
              widget.strings.emailAddress,
              hint: 'user@example.com',
            ),
            _field(
              _login,
              'ews-login',
              widget.strings.ewsLogin,
              hint: r'DOMAIN\user or user@example.com',
            ),
            _field(_domain, 'ews-domain', widget.strings.ewsDomain),
            _field(
              _password,
              'ews-password',
              widget.strings.password,
              secret: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MailEwsAuthentication>(
              initialValue: _authentication,
              decoration: InputDecoration(
                labelText: widget.strings.ewsAuthentication,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: MailEwsAuthentication.ntlm,
                  child: Text(widget.strings.ewsNtlm),
                ),
                DropdownMenuItem(
                  value: MailEwsAuthentication.basic,
                  child: Text(widget.strings.ewsBasic),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _authentication = value);
                      }
                    },
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              key: const ValueKey('ews-connect'),
              onPressed: _busy ? null : _connect,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(widget.strings.connect),
            ),
            const SizedBox(height: 12),
            Text(
              widget.strings.ewsSessionNotice,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _inbox() => Column(
    children: [
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (_error != null || _notice != null)
        Material(
          color: _error == null
              ? Theme.of(context).colorScheme.secondaryContainer
              : Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [Expanded(child: Text(_error ?? _notice!))]),
          ),
        ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1000;
            if (compact && _reader != null && _showMessage) {
              return Column(
                children: [
                  _actions(compact: true),
                  Expanded(child: MailMessageView(controller: _reader!)),
                ],
              );
            }
            return Row(
              children: [
                if (!compact)
                  SizedBox(
                    width: 190,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _sender,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final box in _mailboxes)
                                ListTile(
                                  dense: true,
                                  selected: box.id == _mailbox?.id,
                                  leading: const Icon(
                                    Icons.folder_outlined,
                                    size: 18,
                                  ),
                                  title: Text(
                                    box.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: _blocked
                                      ? null
                                      : () => _loadHeaders(box),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!compact) const VerticalDivider(width: 1),
                if (compact)
                  Expanded(child: _messageList(compact: true))
                else
                  SizedBox(width: 330, child: _messageList(compact: false)),
                if (!compact) ...[
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _reader == null
                        ? Center(child: Text(widget.strings.noMessage))
                        : Column(
                            children: [
                              _actions(compact: false),
                              Expanded(
                                child: MailMessageView(controller: _reader!),
                              ),
                            ],
                          ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ],
  );

  Widget _messageList({required bool compact}) {
    final query = _search.text.trim().toLowerCase();
    final visible = _headers
        .where(
          (header) =>
              query.isEmpty ||
              header.envelope.subject.toLowerCase().contains(query) ||
              header.envelope.from.any(
                (address) => address.address.toLowerCase().contains(query),
              ),
        )
        .toList();
    return Column(
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButton<MailMailboxId>(
              isExpanded: true,
              value: _mailbox?.id,
              items: [
                for (final box in _mailboxes)
                  DropdownMenuItem(
                    value: box.id,
                    child: Text(
                      box.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _blocked
                  ? null
                  : (id) {
                      if (id != null) {
                        unawaited(
                          _loadHeaders(
                            _mailboxes.firstWhere((box) => box.id == id),
                          ),
                        );
                      }
                    },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: widget.strings.ewsSearchLoaded,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(widget.strings.noMessages))
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final header = visible[index];
                    return ListTile(
                      key: ValueKey('ews-message-${header.id.value}'),
                      selected: header.remote == _selected?.remote,
                      leading: header.flags?.isFlagged == true
                          ? const Icon(Icons.flag, size: 18)
                          : null,
                      title: Text(
                        header.envelope.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: header.flags?.isRead == false
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        header.envelope.from.firstOrNull?.address ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: _blocked ? null : () => _openMessage(header),
                    );
                  },
                ),
        ),
        if (_next != null && _headers.length < _maxHeaders)
          TextButton.icon(
            key: const ValueKey('ews-load-more'),
            onPressed: _blocked || _needsRefresh || _mailbox == null
                ? null
                : () => _loadHeaders(_mailbox!, more: true),
            icon: const Icon(Icons.expand_more),
            label: Text(widget.strings.ewsLoadMore),
          ),
      ],
    );
  }

  Widget _actions({required bool compact}) {
    final selected = _selected;
    final canChange = selected != null && !_blocked && !_needsRefresh;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Wrap(
        children: [
          if (compact)
            IconButton(
              tooltip: widget.strings.backToMessages,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _showMessage = false),
            ),
          IconButton(
            tooltip: widget.strings.reply,
            icon: const Icon(Icons.reply_outlined),
            onPressed: _blocked || !_canSend
                ? null
                : () => _reply(forward: false),
          ),
          IconButton(
            tooltip: widget.strings.forward,
            icon: const Icon(Icons.forward_outlined),
            onPressed: _blocked || !_canSend
                ? null
                : () => _reply(forward: true),
          ),
          IconButton(
            tooltip: selected?.flags?.isRead == true
                ? widget.strings.ewsMarkUnread
                : widget.strings.markRead,
            icon: Icon(
              selected?.flags?.isRead == true
                  ? Icons.mark_email_unread_outlined
                  : Icons.mark_email_read_outlined,
            ),
            onPressed: !canChange
                ? null
                : () => _apply(
                    MailSetRead(
                      id: 'read-${++_serial}',
                      message: selected.remote,
                      read: selected.flags?.isRead != true,
                    ),
                  ),
          ),
          IconButton(
            tooltip: selected?.flags?.isFlagged == true
                ? widget.strings.ewsUnflag
                : widget.strings.ewsFlag,
            icon: Icon(
              selected?.flags?.isFlagged == true
                  ? Icons.flag
                  : Icons.outlined_flag,
            ),
            onPressed: !canChange
                ? null
                : () => _apply(
                    MailSetFlagged(
                      id: 'flag-${++_serial}',
                      message: selected.remote,
                      flagged: selected.flags?.isFlagged != true,
                    ),
                  ),
          ),
          PopupMenuButton<MailMailbox>(
            tooltip: widget.strings.ewsMove,
            enabled: canChange && _capabilities.supports(MailCapability.move),
            icon: const Icon(Icons.drive_file_move_outline),
            itemBuilder: (context) => [
              for (final box in _mailboxes)
                if (box.id != _mailbox?.id)
                  PopupMenuItem(value: box, child: Text(box.displayName)),
            ],
            onSelected: (box) {
              if (selected != null) {
                unawaited(
                  _apply(
                    MailMove(
                      id: 'move-${++_serial}',
                      message: selected.remote,
                      destination: box.id,
                    ),
                  ),
                );
              }
            },
          ),
          IconButton(
            tooltip: widget.strings.ewsDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: canChange ? _delete : null,
          ),
        ],
      ),
    );
  }
}

final class _EwsUiFailure implements Exception {
  const _EwsUiFailure(this.problem);
  final MailProblem problem;
}

/// Session-scoped vault implementation. No preferences, files or logs are used.
final class _SessionCredentials implements MailCredentialStore {
  _SessionCredentials(MailCredentialRecord record)
    : _record = record,
      _reference = record.reference;
  final MailCredentialReference _reference;
  MailCredentialRecord? _record;
  bool _closed = false;
  void clear() {
    _closed = true;
    _record = null;
  }

  bool _matches(MailCredentialReference reference) =>
      reference.account == _reference.account &&
      reference.key == _reference.key;

  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  ) async => MailSuccess(!_closed && _matches(reference) ? _record : null);
  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async {
    if (_closed || !_matches(record.reference)) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    _record = record;
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> delete(MailCredentialReference reference) async {
    if (_matches(reference)) clear();
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async {
    if (account == _reference.account) clear();
    return const MailSuccess(MailUnit.value);
  }
}
