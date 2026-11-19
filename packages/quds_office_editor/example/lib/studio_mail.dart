import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_strings.dart';

/// Session-only IMAP/SMTP client used by the Studio Mail module.
///
/// Credentials are never written to disk by this example. The account setup is
/// explicit, auto-discovery is followed by an SSL-only account, and every
/// network operation reports its own failure instead of presenting an empty
/// inbox.
class StudioMailDialog extends StatefulWidget {
  const StudioMailDialog({super.key, required this.strings});

  final StudioStrings strings;

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
  mail.MailAccount? _account;
  List<mail.Mailbox> _mailboxes = const <mail.Mailbox>[];
  mail.Mailbox? _mailbox;
  List<mail.MimeMessage> _messages = const <mail.MimeMessage>[];
  mail.MimeMessage? _selected;
  MailReaderController? _reader;
  bool _busy = false;
  bool _manual = false;
  bool _connecting = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _imapHost.dispose();
    _smtpHost.dispose();
    _search.dispose();
    _reader?.dispose();
    _client?.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
      _notice = null;
    });
    final email = _email.text.trim();
    final domain = email.contains('@') ? email.split('@').last : '';
    try {
      mail.MailAccount account;
      if (_manual) {
        account = mail.MailAccount.fromManualSettings(
          name: email,
          email: email,
          incomingHost: _imapHost.text.trim(),
          outgoingHost: _smtpHost.text.trim(),
          password: _password.text,
        );
      } else {
        final config = await mail.Discover.discover(email, isLogEnabled: false);
        if (config == null || config.isNotValid) {
          throw const FormatException(
            'Automatic discovery failed. Enter IMAP and SMTP hosts.',
          );
        }
        config.enforceSecureSockets();
        account = mail.MailAccount.fromDiscoveredSettings(
          name: email,
          email: email,
          password: _password.text,
          config: config,
          userName: email,
        );
      }
      final client = mail.MailClient(account, isLogEnabled: false);
      await client.connect();
      final boxes = await client.listMailboxes();
      final inbox =
          boxes.where((b) => b.isInbox).firstOrNull ??
          boxes.where((b) => !b.isNotSelectable).firstOrNull;
      if (inbox == null) {
        await client.disconnect();
        throw const FormatException('The account has no selectable mailbox.');
      }
      final messages = await client.fetchMessages(
        mailbox: inbox,
        count: 50,
        fetchPreference: mail.FetchPreference.envelope,
      );
      if (!mounted) return;
      setState(() {
        _client = client;
        _account = account;
        _mailboxes = boxes;
        _mailbox = inbox;
        _messages = messages;
        _selected = null;
        _reader?.dispose();
        _reader = null;
        _connecting = false;
        _notice = '${messages.length} messages';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = '$error';
        if (!_manual && domain.isNotEmpty) {
          _imapHost.text = 'imap.$domain';
          _smtpHost.text = 'smtp.$domain';
          _manual = true;
        }
      });
    }
  }

  Future<void> _selectMailbox(mail.Mailbox mailbox) async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _mailbox = mailbox;
      _selected = null;
      _reader?.dispose();
      _reader = null;
    });
    try {
      await client.selectMailbox(mailbox);
      final messages = await client.fetchMessages(
        mailbox: mailbox,
        count: 50,
        fetchPreference: mail.FetchPreference.envelope,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _busy = false;
        _notice = '${messages.length} messages';
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _openMessage(mail.MimeMessage message) async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final full = await client.fetchMessageContents(message);
      final raw = Uint8List.fromList(utf8.encode(full.renderMessage()));
      final reader = MailReaderController.fromBytes(
        raw,
        codec: const QudsMimeCodec(),
      );
      if (!mounted) {
        reader.dispose();
        return;
      }
      final previous = _reader;
      setState(() {
        _selected = full;
        _reader = reader;
        _busy = false;
      });
      previous?.dispose();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _compose() async {
    final client = _client;
    final account = _account;
    if (client == null || account == null) return;
    final draft = await showDialog<_MailDraft>(
      context: context,
      builder: (context) =>
          _ComposeDialog(strings: widget.strings, from: account.email),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = widget.strings.sending;
    });
    try {
      final builder =
          mail.MessageBuilder.prepareMultipartAlternativeMessage(
              plainText: draft.body,
              htmlText:
                  '<p>${_escapeHtml(draft.body).replaceAll('\n', '<br>')}</p>',
            )
            ..from = <mail.MailAddress>[mail.MailAddress('', account.email)]
            ..to = <mail.MailAddress>[mail.MailAddress('', draft.to)]
            ..subject = draft.subject;
      await client.sendMessage(builder.buildMimeMessage());
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = widget.strings.messageSent;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  void _disconnect() {
    _client?.disconnect();
    _reader?.dispose();
    _reader = null;
    setState(() {
      _client = null;
      _account = null;
      _mailboxes = const <mail.Mailbox>[];
      _mailbox = null;
      _messages = const <mail.MimeMessage>[];
      _selected = null;
      _error = null;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.mailTitle),
        actions: <Widget>[
          if (_client != null) ...<Widget>[
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
      body: _client == null ? _accountSetup(context) : _inbox(context),
    ),
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

  Widget _inbox(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _messages
        : _messages
              .where(
                (message) =>
                    (message.decodeSubject() ?? '').toLowerCase().contains(
                      query,
                    ) ||
                    (message.from?.first.email ?? '').toLowerCase().contains(
                      query,
                    ),
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
          child: Row(
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
                                    message.decodeSubject() ?? '(no subject)';
                                final from =
                                    message.from?.firstOrNull?.email ?? '';
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

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class _MailDraft {
  const _MailDraft(this.to, this.subject, this.body);
  final String to;
  final String subject;
  final String body;
}

class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog({required this.strings, required this.from});
  final StudioStrings strings;
  final String from;

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  final _to = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.compose),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _to,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: widget.strings.to),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _subject,
              decoration: InputDecoration(labelText: widget.strings.subject),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              minLines: 12,
              maxLines: 20,
              decoration: InputDecoration(
                labelText: widget.strings.messageBody,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.cancel),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(
          context,
          _MailDraft(_to.text.trim(), _subject.text.trim(), _body.text),
        ),
        icon: const Icon(Icons.send),
        label: Text(widget.strings.send),
      ),
    ],
  );
}
