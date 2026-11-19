import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_cloud.dart';
import 'studio_mail_compose.dart';
import 'studio_mail_credentials.dart';
import 'studio_mail_ews.dart';
import 'studio_mail_message_loader.dart';
import 'studio_mail_operation.dart';
import 'studio_mail_presets.dart';
import 'studio_mail_reply.dart';
import 'studio_mail_strings.dart';
import 'studio_mail_submission.dart';
import 'studio_saved_mail.dart';
import 'studio_strings.dart';

/// IMAP/SMTP client with optional platform-keychain account persistence.
///
/// Account setup is explicit; remembered credentials use the platform keychain.
/// Discovery and provider presets require verified encrypted transports. Every
/// network operation reports its own failure instead of presenting an empty
/// inbox.
class StudioMailDialog extends StatefulWidget {
  const StudioMailDialog({
    super.key,
    required this.strings,
    this.clientFactory,
    this.messageLoaderFactory,
    this.accountDiscovery,
    this.credentialStore,
  });

  final StudioStrings strings;

  /// Tests supply the keychain boundary without reading a platform credential.
  final StudioMailCredentialStore? credentialStore;

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
  final _primaryLogin = TextEditingController();
  StudioMailImapPreset? _preset;
  bool _icloudFullAddressLogin = false;
  late final StudioMailCredentialStore _credentials;
  bool _remember = true;
  bool _startTls = false;
  bool _hasSavedCredentials = false;
  bool _credentialPending = false;
  int _settingsRevision = 0;
  int _credentialGeneration = 0;

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
  bool _dialogOpen = false;
  bool _manual = false;
  bool _connecting = false;
  bool _showSavedMessages = false;
  bool _savedMessagesVisited = false;
  bool _showCompactMessage = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _credentials = widget.credentialStore ?? StudioMailCredentialStore();
    for (final controller in [
      _email,
      _password,
      _imapHost,
      _smtpHost,
      _primaryLogin,
    ]) {
      controller.addListener(_settingsEdited);
    }
    unawaited(_loadCredentials());
  }

  void _settingsEdited() => _settingsRevision++;

  Future<void> _loadCredentials() async {
    final generation = _sessionGeneration;
    final settings = _settingsRevision;
    final credentialGeneration = _credentialGeneration;
    StudioMailCredentials? saved;
    try {
      saved = await _credentials.load();
    } on Object {
      // Missing or locked keychains do not prevent explicit account setup.
      return;
    }
    if (!_currentAttempt(generation) ||
        saved == null ||
        _connecting ||
        _client != null ||
        settings != _settingsRevision ||
        credentialGeneration != _credentialGeneration) {
      return;
    }
    setState(() {
      _email.text = saved!.email;
      _password.text = saved.password;
      _imapHost.text = saved.imapHost;
      _smtpHost.text = saved.smtpHost;
      _manual = saved.manual;
      _startTls = saved.startTls;
      _preset = saved.preset;
      _primaryLogin.text = saved.primaryLogin;
      _icloudFullAddressLogin = saved.icloudFullAddressLogin;
      _hasSavedCredentials = true;
    });
  }

  Future<void> _persistCredentials(
    mail.MailClient client,
    int sessionGeneration,
    StudioMailCredentials credentials,
    bool remember,
  ) async {
    if (!_currentSession(client, sessionGeneration)) return;
    final generation = ++_credentialGeneration;
    setState(() => _credentialPending = true);
    bool success;
    try {
      success = remember
          ? await _credentials.save(credentials)
          : await _credentials.clear();
    } on Object {
      success = false;
    }
    if (!mounted || generation != _credentialGeneration) return;
    setState(() {
      _credentialPending = false;
      if (success) {
        _hasSavedCredentials = remember;
      } else if (_currentSession(client, sessionGeneration)) {
        _notice = remember
            ? widget.strings.mailKeychainSaveFailed
            : widget.strings.mailKeychainClearFailed;
      }
    });
  }

  Future<void> _forgetCredentials() async {
    if (_connecting) return;
    final generation = ++_credentialGeneration;
    final session = _sessionGeneration;
    final settings = _settingsRevision;
    setState(() => _credentialPending = true);
    bool success;
    try {
      success = await _credentials.clear();
    } on Object {
      success = false;
    }
    if (!mounted || generation != _credentialGeneration) return;
    setState(() {
      _credentialPending = false;
      if (success) {
        _hasSavedCredentials = false;
        if (_error == widget.strings.mailKeychainClearFailed) _error = null;
        if (session == _sessionGeneration && settings == _settingsRevision) {
          _password.clear();
        }
      } else if (session == _sessionGeneration &&
          settings == _settingsRevision) {
        _error = widget.strings.mailKeychainClearFailed;
      }
    });
  }

  @override
  void dispose() {
    _sessionGeneration++;
    _credentialGeneration++;
    _email.dispose();
    _password.dispose();
    _imapHost.dispose();
    _smtpHost.dispose();
    _search.dispose();
    _primaryLogin.dispose();
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
    Future<void> settle(Future<void> Function() close) async {
      try {
        await close();
      } on Object {
        // Each owned transport must still close if another shutdown fails.
        // Cleanup must not replace the operation's fixed, localized feedback.
      }
    }

    await Future.wait<void>(<Future<void>>[
      // Disconnect can queue behind an in-flight command. Abort both owned
      // transports independently, including while initial connection is pending.
      settle(() => client.lowLevelIncomingMailClient.abort()),
      settle(() => client.lowLevelOutgoingMailClient.abort()),
      settle(client.disconnect),
    ]);
  });

  void _retireReader(MailReaderController? reader) {
    if (reader == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
  }

  Future<void> _connect() => runStudioMailOperation(() async {
    if (_connecting || _client != null) return;
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
    final startTls = _startTls;
    final remember = _remember;
    final preset = _preset;
    final primaryLogin = _primaryLogin.text.trim();
    final icloudFullAddressLogin = _icloudFullAddressLogin;
    final imapHost = _imapHost.text.trim();
    final smtpHost = _smtpHost.text.trim();
    mail.MailClient? candidate;
    StudioMailMessageLoader? candidateLoader;
    bool adopted = false;
    try {
      mail.MailAccount account;
      if (preset != null) {
        account = createStudioMailPresetAccount(
          preset: preset,
          email: email,
          password: password,
          primaryLogin: primaryLogin,
          icloudFullAddressLogin: icloudFullAddressLogin,
        );
      } else if (manual) {
        account = mail.MailAccount.fromManualSettings(
          name: email,
          email: email,
          incomingHost: imapHost,
          outgoingHost: smtpHost,
          password: password,
          incomingPort: startTls ? 143 : 993,
          outgoingPort: startTls ? 587 : 465,
          incomingSocketType: startTls
              ? mail.SocketType.starttls
              : mail.SocketType.ssl,
          outgoingSocketType: startTls
              ? mail.SocketType.starttls
              : mail.SocketType.ssl,
        );
      } else if (domain.toLowerCase() == 'mailbox.org') {
        account = mail.MailAccount.fromManualSettings(
          name: email,
          email: email,
          incomingHost: 'imap.mailbox.org',
          outgoingHost: 'smtp.mailbox.org',
          password: password,
          incomingPort: 143,
          outgoingPort: 587,
          incomingSocketType: mail.SocketType.starttls,
          outgoingSocketType: mail.SocketType.starttls,
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
          boxes.where((b) => b.isInbox && !b.isNotSelectable).firstOrNull ??
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
        _pendingClient = null;
        _messageLoader = loader;
        _pendingLoader = null;
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
      await _persistCredentials(
        client,
        generation,
        StudioMailCredentials(
          email: email,
          password: password,
          imapHost: account.incoming.serverConfig.hostname,
          smtpHost: account.outgoing.serverConfig.hostname,
          manual:
              manual || preset == null && domain.toLowerCase() == 'mailbox.org',
          startTls:
              account.incoming.serverConfig.socketType ==
              mail.SocketType.starttls,
          preset: preset,
          primaryLogin: primaryLogin,
          icloudFullAddressLogin: icloudFullAddressLogin,
        ),
        remember,
      );
    } on Object {
      if (!_currentAttempt(generation)) return;
      setState(() {
        _connecting = false;
        _error = widget.strings.mailConnectionFailed;
        if (preset == null && !manual && domain.isNotEmpty) {
          _imapHost.text = 'imap.$domain';
          _smtpHost.text = 'smtp.$domain';
          _manual = true;
          if (domain.toLowerCase() == 'mailbox.org') _startTls = true;
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
        if (client == null || _busy || _dialogOpen) return;
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

  Future<void> _openMessage(mail.MimeMessage message) =>
      runStudioMailOperation(() async {
        final client = _client;
        final loader = _messageLoader;
        final mailbox = _messageMailbox;
        if (client == null ||
            loader == null ||
            mailbox == null ||
            _busy ||
            _dialogOpen) {
          return;
        }
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
      });

  Future<void> _compose() => _openComposer(null);

  Future<void> _openComposer(
    StudioMailDraft? initial,
  ) => runStudioMailOperation(() async {
    final client = _client;
    final account = _account;
    if (client == null || account == null || _busy || _dialogOpen) return;
    if (initial != null && _draft != null) {
      setState(() {
        _error = widget.strings.mailRetainedDraft;
        _notice = null;
      });
      return;
    }
    if (!StudioMailDraft.isSupportedAddress(account.email)) {
      setState(() => _error = widget.strings.mailInvalidSender);
      return;
    }
    final generation = _sessionGeneration;
    StudioMailDraft? draft;
    setState(() => _dialogOpen = true);
    try {
      draft = await showDialog<StudioMailDraft>(
        context: context,
        builder: (context) => StudioMailComposeDialog(
          strings: widget.strings,
          from: account.email,
          initialDraft: initial ?? _draft,
          previousSubmissionUncertain: _submissionUncertain,
        ),
      );
    } finally {
      if (_currentSession(client, generation)) {
        setState(() => _dialogOpen = false);
      }
    }
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
    } on mail.MailSendPostSubmissionException catch (error) {
      if (_currentSession(client, generation)) {
        setState(() {
          _busy = false;
          if (identical(error.mailClient, client)) {
            // SMTP acceptance is final for this draft even when subsequent
            // connection cleanup fails. Retrying would duplicate submission.
            _draft = null;
            _submissionUncertain = false;
            _error = null;
            _notice = widget.strings.mailSubmissionFollowUpFailed;
          } else {
            // An outcome from another client cannot confirm this submission.
            _notice = null;
            _submissionUncertain = attempted;
            _error = widget.strings.mailSubmissionUncertain;
          }
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

  Future<void> _reply() => _composeFromMessage(forward: false);

  Future<void> _forward() => _composeFromMessage(forward: true);

  Future<void> _composeFromMessage({required bool forward}) =>
      runStudioMailOperation(() async {
        if (_busy || _dialogOpen || _client == null) return;
        if (_draft != null) {
          setState(() {
            _error = widget.strings.mailRetainedDraft;
            _notice = null;
          });
          return;
        }
        // The list item contains only an envelope. Quote the authoritative
        // bounded raw-message parse, never the reader's header presentation.
        final message = _reader?.result.message;
        if (message == null) return;
        try {
          final draft = buildStudioMailReplyDraft(
            message,
            forward: forward,
            truncationNotice: widget.strings.mailQuotedTextTruncated,
            forwardNotice: widget.strings.mailTextOnlyForward,
          );
          await _openComposer(draft);
        } on StudioMailReplyUnavailable {
          setState(() {
            _error = widget.strings.mailPlainTextUnavailable;
            _notice = null;
          });
        }
      });

  Future<void> _discardDraft() async {
    final client = _client;
    final retained = _draft;
    if (client == null || retained == null || _busy || _dialogOpen) return;
    final generation = _sessionGeneration;
    bool? discard;
    setState(() => _dialogOpen = true);
    try {
      discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.strings.mailDiscardDraft),
          content: Text(widget.strings.mailDiscardDraftExplanation),
          actions: <Widget>[
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
    } finally {
      if (_currentSession(client, generation)) {
        setState(() => _dialogOpen = false);
      }
    }
    if (discard != true ||
        !_currentSession(client, generation) ||
        !identical(_draft, retained)) {
      return;
    }
    setState(() {
      _draft = null;
      _submissionUncertain = false;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _markRead() => runStudioMailOperation(() async {
    final client = _client;
    final loader = _messageLoader;
    final mailbox = _messageMailbox;
    final message = _selected;
    if (client == null ||
        loader == null ||
        mailbox == null ||
        message == null ||
        message.isSeen ||
        _busy ||
        _dialogOpen) {
      return;
    }
    final generation = _sessionGeneration;
    final uid = message.uid;
    final uidValidity = mailbox.uidValidity;
    final mailboxPath = mailbox.path;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await loader.markRead(mailbox, message);
      if (_currentSession(client, generation)) {
        setState(() {
          if (identical(_selected, message) &&
              identical(_messageLoader, loader) &&
              identical(_messageMailbox, mailbox) &&
              message.uid == uid &&
              mailbox.uidValidity == uidValidity &&
              mailbox.path == mailboxPath) {
            message.setFlag(mail.MessageFlags.seen, true);
            _error = null;
          } else {
            _error = widget.strings.mailMarkReadFailed;
          }
          _busy = false;
        });
      }
    } on Object {
      if (_currentSession(client, generation)) {
        setState(() {
          _busy = false;
          _error = widget.strings.mailMarkReadFailed;
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
      _dialogOpen = false;
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
              if (_draft != null)
                IconButton(
                  onPressed: _busy || _dialogOpen ? null : _discardDraft,
                  tooltip: widget.strings.mailDiscardDraft,
                  icon: const Icon(Icons.delete_outline),
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
                for (final service in MailCloudService.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      key: ValueKey('studio-mail-open-${service.name}'),
                      onPressed: _connecting
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              builder: (_) => StudioMailCloudDialog(
                                strings: widget.strings,
                                service: service,
                              ),
                            ),
                      icon: const Icon(Icons.cloud_outlined),
                      label: Text(
                        service == MailCloudService.gmail
                            ? 'Gmail'
                            : 'Microsoft 365 / Outlook',
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('studio-mail-open-ews'),
                  onPressed: _connecting
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              StudioMailEwsDialog(strings: widget.strings),
                        ),
                  icon: const Icon(Icons.dns_outlined),
                  label: Text(widget.strings.ewsTitle),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: const ValueKey('studio-mail-provider-preset'),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_preset?.name ?? 'other'),
                    initialValue: _preset?.name ?? 'other',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: widget.strings.mailProvider,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'other',
                        child: Text(widget.strings.mailOtherProvider),
                      ),
                      for (final preset in StudioMailImapPreset.values)
                        DropdownMenuItem(
                          value: preset.name,
                          child: Text(preset.label),
                        ),
                    ],
                    onChanged: _connecting
                        ? null
                        : (value) => setState(() {
                            _settingsEdited();
                            _preset = StudioMailImapPreset.values
                                .where((entry) => entry.name == value)
                                .firstOrNull;
                            _manual = false;
                            _password.clear();
                            _primaryLogin.clear();
                            _icloudFullAddressLogin = false;
                            _error = null;
                          }),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _preset == null
                      ? widget.strings.mailSetupHelp
                      : widget.strings.mailPresetPasswordHelp,
                  textAlign: TextAlign.center,
                ),
                if (_preset case final preset?) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${preset.imapHost}:993 TLS\n${preset.smtpHost}:${preset.smtpPort} ${preset == StudioMailImapPreset.icloud ? 'STARTTLS' : 'TLS'}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
                    labelText: _preset == null
                        ? widget.strings.password
                        : widget.strings.mailAppPassword,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                if (_preset != null) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('studio-mail-primary-login'),
                    controller: _primaryLogin,
                    enabled: !_connecting,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: widget.strings.mailPrimaryLogin,
                    ),
                  ),
                ],
                if (_preset == StudioMailImapPreset.icloud)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    key: const ValueKey('studio-mail-icloud-full-login'),
                    value: _icloudFullAddressLogin,
                    title: Text(widget.strings.mailIcloudFullLogin),
                    onChanged: _connecting
                        ? null
                        : (value) => setState(() {
                            _settingsEdited();
                            _icloudFullAddressLogin = value ?? false;
                          }),
                  ),
                const SizedBox(height: 8),
                if (_preset == null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.strings.manualServers),
                    value: _manual,
                    onChanged: _connecting
                        ? null
                        : (value) => setState(() {
                            _settingsEdited();
                            _manual = value;
                          }),
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
                  SwitchListTile(
                    key: const ValueKey('studio-mail-starttls'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.strings.useStartTls),
                    value: _startTls,
                    onChanged: _connecting
                        ? null
                        : (value) => setState(() {
                            _settingsEdited();
                            _startTls = value;
                          }),
                  ),
                  const SizedBox(height: 12),
                ],
                SwitchListTile(
                  key: const ValueKey('studio-mail-remember'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.strings.rememberAccount),
                  value: _remember,
                  onChanged: _connecting
                      ? null
                      : (value) => setState(() {
                          _settingsEdited();
                          _remember = value;
                        }),
                ),
                TextButton.icon(
                  key: const ValueKey('studio-mail-forget'),
                  onPressed: _connecting ? null : _forgetCredentials,
                  icon: Icon(
                    _credentialPending
                        ? Icons.hourglass_empty
                        : _hasSavedCredentials
                        ? Icons.key_off_outlined
                        : Icons.delete_outline,
                    size: 18,
                  ),
                  label: Text(widget.strings.forgetAccount),
                ),
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
                          : Column(
                              children: <Widget>[
                                _messageActions(),
                                Expanded(
                                  child: MailMessageView(controller: _reader!),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _messageActions() => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          onPressed: _busy ? null : _reply,
          tooltip: widget.strings.reply,
          icon: const Icon(Icons.reply_outlined),
        ),
        IconButton(
          onPressed: _busy ? null : _forward,
          tooltip: widget.strings.forward,
          icon: const Icon(Icons.forward_outlined),
        ),
        IconButton(
          onPressed: _busy || (_selected?.isSeen ?? true) ? null : _markRead,
          tooltip: widget.strings.markRead,
          icon: const Icon(Icons.mark_email_read_outlined),
        ),
        const SizedBox(width: 8),
      ],
    ),
  );

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
          _messageActions(),
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
