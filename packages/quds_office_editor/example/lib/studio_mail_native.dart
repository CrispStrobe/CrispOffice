import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_compose.dart';
import 'studio_mail_message_loader.dart';
import 'studio_mail_operation.dart';
import 'studio_mail_strings.dart';
import 'studio_mail_submission.dart';
import 'studio_saved_mail.dart';
import 'studio_strings.dart';

/// Session-only IMAP/SMTP client used by the Studio Mail module.
///
/// Credentials are never written to disk by this example. The account setup is
/// explicit, auto-discovery is followed by an SSL-only account, and every
/// network operation reports its own failure instead of presenting an empty
/// inbox.
class StudioMailDialog extends StatefulWidget {
  const StudioMailDialog({
    super.key,
    required this.strings,
    this.clientFactory,
    this.messageLoaderFactory,
    this.accountDiscovery,
  });

  final StudioStrings strings;

  /// Creates a fresh client for each connection attempt. Tests use this seam
  /// to control network completions without contacting an external account.
  final mail.MailClient Function(mail.MailAccount account)? clientFactory;

  /// Resolves endpoint settings only; credentials are supplied after the
  /// discovery origin and IMAP/SMTP server types have been checked.
  final Future<mail.ClientConfig?> Function(String email)? accountDiscovery;

  /// Owns exact, bounded UID reads for this foreground account session.
  final StudioMailMessageLoader Function(mail.MailAccount account)?
  messageLoaderFactory;

  @override
  State<StudioMailDialog> createState() => _StudioMailDialogState();
}

class _StudioMailDialogState extends State<StudioMailDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _imapHost = TextEditingController();
  final _smtpHost = TextEditingController();
  final _search = TextEditingController();

  mail.MailClient? _client;
  mail.MailClient? _pendingClient;
  StudioMailMessageLoader? _messageLoader;
  StudioMailMessageLoader? _pendingLoader;
  mail.Mailbox? _messageMailbox;
  int _sessionGeneration = 0;
  mail.MailAccount? _account;
  List<mail.Mailbox> _mailboxes = const <mail.Mailbox>[];
  mail.Mailbox? _mailbox;
  List<mail.MimeMessage> _messages = const <mail.MimeMessage>[];
  mail.MimeMessage? _selected;
  MailReaderController? _reader;
  StudioMailDraft? _draft;
  bool _submissionUncertain = false;
  bool _busy = false;
  bool _manual = false;
  bool _connecting = false;
  bool _showSavedMessages = false;
  bool _savedMessagesVisited = false;
  bool _showCompactMessage = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _sessionGeneration++;
    _email.dispose();
    _password.dispose();
    _imapHost.dispose();
    _smtpHost.dispose();
    _search.dispose();
    _reader?.dispose();
    _messageLoader?.dispose();
    _pendingLoader?.dispose();
    unawaited(_disconnectQuietly(_client));
    unawaited(_disconnectQuietly(_pendingClient));
    super.dispose();
  }

  bool _currentAttempt(int generation) =>
      mounted && generation == _sessionGeneration;

  bool _currentSession(mail.MailClient client, int generation) =>
      _currentAttempt(generation) && identical(client, _client);

  Future<void> _disconnectQuietly(
    mail.MailClient? client,
  ) => runStudioMailOperation(() async {
    if (client == null) return;
    try {
      await client.disconnect();
    } on Object {
      // Cleanup must not create an unhandled asynchronous error, especially
      // after the dialog has gone away. Operation failures retain their own UI.
    }
  });

  void _retireReader(MailReaderController? reader) {
    if (reader == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
  }

  Future<void> _connect() => runStudioMailOperation(() async {
    if (_connecting) return;
    final generation = ++_sessionGeneration;
    setState(() {
      _connecting = true;
      _error = null;
      _notice = null;
    });
    final email = _email.text.trim();
    final domain = email.contains('@') ? email.split('@').last : '';
    final password = _password.text;
    final manual = _manual;
    final imapHost = _imapHost.text.trim();
    final smtpHost = _smtpHost.text.trim();
    mail.MailClient? candidate;
    StudioMailMessageLoader? candidateLoader;
    bool adopted = false;
    try {
      mail.MailAccount account;
      if (manual) {
        account = mail.MailAccount.fromManualSettings(
          name: email,
          email: email,
          incomingHost: imapHost,
          outgoingHost: smtpHost,
          password: password,
        );
      } else {
        final config =
            await (widget.accountDiscovery?.call(email) ??
                mail.Discover.discover(email, isLogEnabled: false));
        if (!_currentAttempt(generation)) return;
        if (config == null ||
            config.isNotValid ||
            config.isFromInsecureSource ||
            config.preferredIncomingImapServer?.type != mail.ServerType.imap ||
            config.preferredOutgoingServer?.type != mail.ServerType.smtp) {
          throw const FormatException(
            'Authenticated IMAP and SMTP discovery is required.',
          );
        }
        config.enforceSecureSockets();
        account = mail.MailAccount.fromDiscoveredSettings(
          name: email,
          email: email,
          password: password,
          config: config,
          userName: email,
        );
      }
      final client =
          widget.clientFactory?.call(account) ??
          mail.MailClient(account, isLogEnabled: false);
      candidate = client;
      _pendingClient = client;
      final loader =
          widget.messageLoaderFactory?.call(account) ??
          NativeStudioMailMessageLoader(account);
      candidateLoader = loader;
      _pendingLoader = loader;
      await client.connect();
      if (!_currentAttempt(generation)) return;
      final boxes = await client.listMailboxes();
      if (!_currentAttempt(generation)) return;
      final inbox =
          boxes.where((b) => b.isInbox).firstOrNull ??
          boxes.where((b) => !b.isNotSelectable).firstOrNull;
      if (inbox == null) {
        throw const FormatException('The account has no selectable mailbox.');
      }
      final messages = await client.fetchMessages(
        mailbox: inbox,
        count: 50,
        fetchPreference: mail.FetchPreference.envelope,
      );
      if (!_currentAttempt(generation)) return;
      final previous = _reader;
      setState(() {
        _client = client;
        _messageLoader = loader;
        _messageMailbox = (client.selectedMailbox ?? inbox).copyWith();
        _account = account;
        _mailboxes = boxes;
        _mailbox = inbox;
        _messages = messages;
        _selected = null;
        _reader = null;
        _connecting = false;
        _notice = '${messages.length} messages';
      });
      adopted = true;
      _retireReader(previous);
    } on Object {
      if (!_currentAttempt(generation)) return;
      setState(() {
        _connecting = false;
        _error = widget.strings.mailConnectionFailed;
        if (!manual && domain.isNotEmpty) {
          _imapHost.text = 'imap.$domain';
          _smtpHost.text = 'smtp.$domain';
          _manual = true;
        }
      });
    } finally {
      if (identical(_pendingClient, candidate)) _pendingClient = null;
      if (identical(_pendingLoader, candidateLoader)) _pendingLoader = null;
      if (!adopted) {
        candidateLoader?.dispose();
        await _disconnectQuietly(candidate);
      }
    }
  });

  Future<void> _selectMailbox(mail.Mailbox mailbox) =>
      runStudioMailOperation(() async {
        final client = _client;
        if (client == null || _busy) return;
        final generation = _sessionGeneration;
        final previous = _reader;
        setState(() {
          _busy = true;
          _error = null;
          _notice = null;
          _mailbox = mailbox;
          _messageMailbox = null;
          _selected = null;
          _messages = const <mail.MimeMessage>[];
          _reader = null;
          _showCompactMessage = false;
        });
        _retireReader(previous);
        try {
          await client.selectMailbox(mailbox);
          if (!_currentSession(client, generation)) return;
          final messages = await client.fetchMessages(
            mailbox: mailbox,
            count: 50,
            fetchPreference: mail.FetchPreference.envelope,
          );
          if (!_currentSession(client, generation)) return;
          setState(() {
            _messages = messages;
            _messageMailbox = (client.selectedMailbox ?? mailbox).copyWith();
            _busy = false;
            _notice = '${messages.length} messages';
          });
        } on Object {
          if (_currentSession(client, generation)) {
            setState(() {
              _busy = false;
              _error = widget.strings.mailMailboxFailed;
            });
          }
        }
      });

  Future<void> _openMessage(mail.MimeMessage message) => runStudioMailOperation(
    () async {
      final client = _client;
      final loader = _messageLoader;
      final mailbox = _messageMailbox;
      if (client == null || loader == null || mailbox == null || _busy) return;
      final generation = _sessionGeneration;
      setState(() {
        _busy = true;
        _error = null;
        _notice = null;
      });
      try {
        final raw = await loader.fetch(mailbox, message);
        if (!_currentSession(client, generation)) return;
        final reader = MailReaderController.fromBytes(
          raw,
          codec: const QudsMimeCodec(),
        );
        final previous = _reader;
        setState(() {
          _selected = message;
          _reader = reader;
          _busy = false;
          _showCompactMessage = true;
        });
        _retireReader(previous);
      } on Object {
        if (_currentSession(client, generation)) {
          setState(() {
            _busy = false;
            _error = widget.strings.mailMessageFailed;
          });
        }
      }
    },
  );

  Future<void> _compose() => runStudioMailOperation(() async {
    final client = _client;
    final account = _account;
    if (client == null || account == null || _busy) return;
    if (!StudioMailDraft.isSupportedAddress(account.email)) {
      setState(() => _error = widget.strings.mailInvalidSender);
      return;
    }
    final generation = _sessionGeneration;
    final draft = await showDialog<StudioMailDraft>(
      context: context,
      builder: (context) => StudioMailComposeDialog(
        strings: widget.strings,
        from: account.email,
        initialDraft: _draft,
        previousSubmissionUncertain: _submissionUncertain,
      ),
    );
    if (draft == null || !_currentSession(client, generation)) return;
    // Preserve the immutable draft before handing anything to the transport.
    // An uncertain attempt is never automatically retried.
    setState(() {
      _draft = draft;
      _busy = true;
      _error = null;
      _notice = widget.strings.sending;
    });
    var attempted = false;
    try {
      final message = buildStudioMailMessage(draft, account.email);
      attempted = true;
      await client.sendMessage(
        message,
        appendToSent: false,
        recipients: <mail.MailAddress>[mail.MailAddress('', draft.to)],
      );
      if (_currentSession(client, generation)) {
        setState(() {
          _busy = false;
          _draft = null;
          _submissionUncertain = false;
          _notice = widget.strings.mailSubmissionAccepted;
        });
      }
    } on mail.MailSendPostSubmissionException {
      // SMTP already accepted this message. A later cleanup failure must not
      // retain the submitted draft or offer it for another submission.
      if (_currentSession(client, generation)) {
        setState(() {
          _busy = false;
          _draft = null;
          _submissionUncertain = false;
          _notice = widget.strings.mailSubmissionAccepted;
        });
      }
    } on Object {
      if (_currentSession(client, generation)) {
        setState(() {
          _busy = false;
          _notice = null;
          _submissionUncertain = attempted;
          _error = attempted
              ? widget.strings.mailSubmissionUncertain
              : widget.strings.mailInvalidSender;
        });
      }
    }
  });

  void _disconnect() {
    _sessionGeneration++;
    final client = _client;
    final pending = _pendingClient;
    final loader = _messageLoader;
    final pendingLoader = _pendingLoader;
    final previous = _reader;
    setState(() {
      _client = null;
      _pendingClient = null;
      _messageLoader = null;
      _pendingLoader = null;
      _messageMailbox = null;
      _reader = null;
      _busy = false;
      _connecting = false;
      _account = null;
      _draft = null;
      _submissionUncertain = false;
      _password.clear();
      _mailboxes = const <mail.Mailbox>[];
      _mailbox = null;
      _messages = const <mail.MimeMessage>[];
      _selected = null;
      _showCompactMessage = false;
      _error = null;
      _notice = null;
    });
    _retireReader(previous);
    loader?.dispose();
    pendingLoader?.dispose();
    unawaited(_disconnectQuietly(client));
    unawaited(_disconnectQuietly(pending));
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: LayoutBuilder(
      builder: (context, constraints) => IndexedStack(
        index: _showSavedMessages ? 1 : 0,
        children: <Widget>[
          _accountView(context, compact: constraints.maxWidth < 800),
          if (_savedMessagesVisited)
            StudioSavedMailView(
              strings: widget.strings,
              onAccounts: () => setState(() => _showSavedMessages = false),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    ),
  );

  Widget _accountView(BuildContext context, {required bool compact}) =>
      Scaffold(
        appBar: AppBar(
          title: Text(
            widget.strings.mailTitle,
            overflow: TextOverflow.ellipsis,
          ),
          actions: <Widget>[
            IconButton(
              onPressed: _busy || _connecting
                  ? null
                  : () => setState(() {
                      _savedMessagesVisited = true;
                      _showSavedMessages = true;
                    }),
              tooltip: widget.strings.savedMessages,
              icon: const Icon(Icons.folder_open_outlined),
            ),
            if (_client != null) ...<Widget>[
              if (compact)
                IconButton(
                  onPressed: _busy ? null : _compose,
                  tooltip: widget.strings.compose,
                  icon: const Icon(Icons.edit_outlined),
                )
              else
                TextButton.icon(
                  onPressed: _busy ? null : _compose,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(widget.strings.compose),
                ),
              IconButton(
                onPressed: _busy || _mailbox == null
                    ? null
                    : () => _selectMailbox(_mailbox!),
                tooltip: widget.strings.refresh,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                onPressed: _disconnect,
                tooltip: widget.strings.disconnect,
                icon: const Icon(Icons.logout),
              ),
            ],
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: widget.strings.close,
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _client == null
            ? _accountSetup(context)
            : _inbox(context, compact: compact),
      );

  Widget _accountSetup(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.mail_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.strings.mailTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(widget.strings.mailSetupHelp, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: widget.strings.emailAddress,
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const <String>[AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: widget.strings.password,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.strings.manualServers),
                  value: _manual,
                  onChanged: _connecting
                      ? null
                      : (value) => setState(() => _manual = value),
                ),
                if (_manual) ...<Widget>[
                  TextField(
                    controller: _imapHost,
                    decoration: InputDecoration(
                      labelText: widget.strings.imapHost,
                      hintText: 'imap.example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpHost,
                    decoration: InputDecoration(
                      labelText: widget.strings.smtpHost,
                      hintText: 'smtp.example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _connecting ? null : _connect,
                  icon: _connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(widget.strings.connect),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.strings.mailSessionNotice,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _inbox(BuildContext context, {required bool compact}) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _messages
        : _messages
              .where(
                (message) =>
                    (message.decodeSubject() ?? '').toLowerCase().contains(
                      query,
                    ) ||
                    (message.from?.firstOrNull?.email ?? '')
                        .toLowerCase()
                        .contains(query),
              )
              .toList();
    return Column(
      children: <Widget>[
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null || _notice != null)
          Material(
            color: _error == null
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SelectableText(_error ?? _notice ?? '', maxLines: 2),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: compact
              ? _compactInbox(context, visible)
              : Row(
                  children: <Widget>[
                    SizedBox(
                      width: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _account?.email ?? '',
                              style: Theme.of(context).textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView(
                              children: <Widget>[
                                for (final box in _mailboxes)
                                  ListTile(
                                    dense: true,
                                    selected: box.path == _mailbox?.path,
                                    leading: Icon(
                                      box.isInbox
                                          ? Icons.inbox_outlined
                                          : box.isSent
                                          ? Icons.send_outlined
                                          : box.isDrafts
                                          ? Icons.edit_note
                                          : box.isJunk
                                          ? Icons.report_gmailerrorred_outlined
                                          : box.isTrash
                                          ? Icons.delete_outline
                                          : Icons.folder_outlined,
                                      size: 18,
                                    ),
                                    title: Text(
                                      box.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: !box.isNotSelectable
                                        ? () => _selectMailbox(box)
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 360,
                      child: Column(
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: TextField(
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                isDense: true,
                                prefixIcon: const Icon(Icons.search, size: 18),
                                hintText: widget.strings.searchMail,
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
                                      final message = visible[index];
                                      final subject =
                                          message.decodeSubject() ??
                                          '(no subject)';
                                      final from =
                                          message.from?.firstOrNull?.email ??
                                          '';
                                      final date = message.decodeDate();
                                      return ListTile(
                                        selected: identical(message, _selected),
                                        title: Text(
                                          subject,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: message.isSeen
                                                ? FontWeight.w400
                                                : FontWeight.w700,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '$from${date == null ? '' : '\n${date.toLocal()}'}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: _busy
                                            ? null
                                            : () => _openMessage(message),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _reader == null
                          ? Center(child: Text(widget.strings.noMessage))
                          : MailMessageView(controller: _reader!),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _compactInbox(BuildContext context, List<mail.MimeMessage> visible) {
    if (_reader != null && _showCompactMessage) {
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: () => setState(() => _showCompactMessage = false),
                tooltip: widget.strings.backToMessages,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  _selected?.decodeSubject() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Expanded(child: MailMessageView(controller: _reader!)),
        ],
      );
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<String>(
            isExpanded: true,
            value: _mailbox?.path,
            items: <DropdownMenuItem<String>>[
              for (final box in _mailboxes)
                if (!box.isNotSelectable)
                  DropdownMenuItem<String>(
                    value: box.path,
                    child: Text(
                      box.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ],
            onChanged: _busy
                ? null
                : (path) {
                    if (path == null) return;
                    final box = _mailboxes.firstWhere(
                      (item) => item.path == path,
                    );
                    unawaited(_selectMailbox(box));
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
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: widget.strings.searchMail,
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
                    final message = visible[index];
                    return ListTile(
                      selected: identical(message, _selected),
                      title: Text(
                        message.decodeSubject() ?? '(no subject)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: message.isSeen
                              ? FontWeight.w400
                              : FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        message.from?.firstOrNull?.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: _busy ? null : () => _openMessage(message),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
