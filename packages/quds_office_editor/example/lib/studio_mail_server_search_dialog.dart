import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_server_search.dart';
import 'studio_mail_server_search_strings.dart';
import 'studio_strings.dart';

typedef StudioMailServerSearchRunner =
    Future<StudioMailServerSearchResult> Function(
      StudioMailServerSearchField field,
      String query,
      MailCancellationToken cancellation,
    );

Future<mail.MimeMessage?> showStudioMailServerSearchDialog(
  BuildContext context, {
  required StudioStrings strings,
  required String mailboxName,
  required StudioMailServerSearchRunner search,
}) => showDialog<mail.MimeMessage>(
  context: context,
  builder: (_) => _StudioMailServerSearchDialog(
    strings: strings,
    mailboxName: mailboxName,
    search: search,
  ),
);

class _StudioMailServerSearchDialog extends StatefulWidget {
  const _StudioMailServerSearchDialog({
    required this.strings,
    required this.mailboxName,
    required this.search,
  });

  final StudioStrings strings;
  final String mailboxName;
  final StudioMailServerSearchRunner search;

  @override
  State<_StudioMailServerSearchDialog> createState() =>
      _StudioMailServerSearchDialogState();
}

class _StudioMailServerSearchDialogState
    extends State<_StudioMailServerSearchDialog> {
  final _query = TextEditingController();
  StudioMailServerSearchField _field = StudioMailServerSearchField.body;
  MailCancellationSource? _source;
  StudioMailServerSearchResult? _result;
  bool _running = false;
  bool _stopping = false;
  String? _error;

  @override
  void dispose() {
    _source?.cancel(MailCancellationReason.disposed);
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    final text = _query.text.trim();
    if (text.isEmpty ||
        text.length > 512 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      setState(() => _error = widget.strings.mailServerSearchInvalid);
      return;
    }
    final source = MailCancellationSource();
    final field = _field;
    setState(() {
      _source = source;
      _running = true;
      _stopping = false;
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.search(field, text, source.token);
      if (!mounted || !identical(source, _source)) return;
      if (source.token.isCancelled) {
        setState(() {
          _running = false;
          _stopping = false;
        });
        return;
      }
      setState(() {
        _running = false;
        _stopping = false;
        _result = result;
      });
    } on MailCancelled {
      if (!mounted || !identical(source, _source)) return;
      setState(() {
        _running = false;
        _stopping = false;
      });
    } on FormatException {
      if (!mounted || !identical(source, _source)) return;
      setState(() {
        _running = false;
        _stopping = false;
        _error = widget.strings.mailServerSearchInvalid;
      });
    } on Object {
      if (!mounted || !identical(source, _source)) return;
      setState(() {
        _running = false;
        _stopping = false;
        _error = widget.strings.mailServerSearchFailed;
      });
    }
  }

  void _stop() {
    final source = _source;
    if (!_running || source == null || _stopping) return;
    setState(() => _stopping = true);
    source.cancel();
  }

  void _close() {
    _source?.cancel(MailCancellationReason.user);
    Navigator.pop(context);
  }

  String? _fieldLabel(
    StudioStrings strings,
    StudioMailServerSearchField field,
  ) => switch (field) {
    StudioMailServerSearchField.body => strings.mailServerSearchBody,
    StudioMailServerSearchField.subject => strings.mailServerSearchSubject,
    StudioMailServerSearchField.from => strings.mailServerSearchFrom,
    StudioMailServerSearchField.to => strings.mailServerSearchTo,
  };

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final result = _result;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.manage_search),
          const SizedBox(width: 8),
          Expanded(child: Text(strings.mailServerSearch)),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.mailServerSearchHelp),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<StudioMailServerSearchField>(
                    key: const ValueKey('studio-mail-server-field'),
                    initialValue: _field,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: strings.mailServerSearchField,
                    ),
                    items: [
                      for (final field in StudioMailServerSearchField.values)
                        DropdownMenuItem(
                          value: field,
                          child: Text(_fieldLabel(strings, field) ?? ''),
                        ),
                    ],
                    onChanged: _running
                        ? null
                        : (field) {
                            if (field != null) setState(() => _field = field);
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const ValueKey('studio-mail-server-query'),
                    controller: _query,
                    maxLength: 512,
                    enabled: !_running,
                    decoration: InputDecoration(
                      labelText: strings.mailServerSearchQuery,
                      counterText: '',
                    ),
                    onSubmitted: (_) => _run(),
                  ),
                ),
              ],
            ),
            if (_running) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                key: const ValueKey('studio-mail-server-progress'),
              ),
              const SizedBox(height: 6),
              Text(
                _stopping
                    ? strings.mailServerSearchStopping
                    : strings.mailServerSearchRunning,
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                key: const ValueKey('studio-mail-server-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 8),
              Text(
                strings.mailServerSearchCount(
                  result.totalMatches,
                  result.messages.length,
                ),
                key: const ValueKey('studio-mail-server-count'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (result.truncated)
                Text(
                  strings.mailServerSearchTruncated,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              Expanded(
                child: result.isEmpty
                    ? Center(child: Text(strings.mailServerSearchEmpty))
                    : ListView.separated(
                        itemCount: result.messages.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final message = result.messages[index];
                          final from = message.from
                              ?.map(
                                (address) =>
                                    address.personalName?.isNotEmpty == true
                                    ? '${address.personalName} <${address.email}>'
                                    : address.email,
                              )
                              .join(', ');
                          return ListTile(
                            key: ValueKey(
                              'studio-mail-server-result-${message.uid}',
                            ),
                            title: Text(
                              message.decodeSubject() ?? '(no subject)',
                            ),
                            subtitle: Text(
                              [
                                if (from != null && from.isNotEmpty) from,
                                ?message.decodeDate()?.toLocal().toString(),
                              ].join('\n'),
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.open_in_new, size: 18),
                            onTap: _running
                                ? null
                                : () => Navigator.pop(context, message),
                          );
                        },
                      ),
              ),
            ] else if (!_running && _error == null)
              const Spacer(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
        if (_running)
          OutlinedButton(
            key: const ValueKey('studio-mail-server-stop'),
            onPressed: _stopping ? null : _stop,
            child: Text(strings.mailServerSearchStop),
          ),
        FilledButton.icon(
          key: const ValueKey('studio-mail-server-run'),
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.search),
          label: Text(strings.mailServerSearchRun),
        ),
      ],
    );
  }
}
