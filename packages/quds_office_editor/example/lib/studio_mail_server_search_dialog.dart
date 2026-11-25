import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_server_search.dart';
import 'studio_mail_provider_search.dart';
import 'studio_mail_server_search_strings.dart';
import 'studio_strings.dart';

typedef StudioMailServerSearchRunner =
    Future<StudioMailServerSearchResult> Function(
      StudioMailServerSearchField field,
      StudioMailServerSearchRange range,
      String query,
      MailCancellationToken cancellation,
    );

/// Typed cloud/Exchange search without coupling provider results to IMAP MIME.
typedef StudioMailProviderSearchRunner =
    Future<MailProviderSearchResult> Function(
      MailProviderSearchField field,
      StudioMailServerSearchRange range,
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
  builder: (_) => _StudioMailServerSearchDialog<mail.MimeMessage>(
    strings: strings,
    mailboxName: mailboxName,
    fields: StudioMailServerSearchField.values,
    help: strings.mailServerSearchHelp,
    search: (field, range, query, cancellation) async {
      final result = await search(field, range, query, cancellation);
      return _SearchPage(
        totalMatches: result.totalMatches,
        precision: MailSearchCountPrecision.exact,
        hasMore: result.truncated,
        rows: [
          for (final message in result.messages)
            _SearchRow(
              value: message,
              id: '${message.uid}',
              subject: message.decodeSubject() ?? '',
              from:
                  message.from
                      ?.map(
                        (address) => address.personalName?.isNotEmpty == true
                            ? '${address.personalName} <${address.email}>'
                            : address.email,
                      )
                      .join(', ') ??
                  '',
              date: message.decodeDate(),
            ),
        ],
      );
    },
  ),
);

Future<MailHeaderRecord?> showStudioMailProviderSearchDialog(
  BuildContext context, {
  required StudioStrings strings,
  required String mailboxName,
  required Set<MailProviderSearchField> fields,
  required StudioMailProviderSearchRunner search,
}) {
  if (fields.isEmpty) throw ArgumentError.value(fields, 'fields');
  final available = [
    for (final field in StudioMailServerSearchField.values)
      if (fields.any((supported) => supported.name == field.name)) field,
  ];
  return showDialog<MailHeaderRecord>(
    context: context,
    builder: (_) => _StudioMailServerSearchDialog<MailHeaderRecord>(
      strings: strings,
      mailboxName: mailboxName,
      fields: available,
      help: strings.mailProviderSearchHelp,
      search: (field, range, query, cancellation) async {
        final result = await search(
          MailProviderSearchField.values.byName(field.name),
          range,
          query,
          cancellation,
        );
        return _SearchPage(
          totalMatches: result.totalCount,
          precision: result.countPrecision,
          hasMore: result.hasMore,
          rows: [
            for (final header in result.messages)
              _SearchRow(
                value: header,
                id: header.id.value,
                subject: header.envelope.subject,
                from: header.envelope.from
                    .map(
                      (address) => address.displayName?.isNotEmpty == true
                          ? '${address.displayName} <${address.address}>'
                          : address.address,
                    )
                    .join(', '),
                date: header.envelope.sentAt,
              ),
          ],
        );
      },
    ),
  );
}

final class _SearchRow<T> {
  const _SearchRow({
    required this.value,
    required this.id,
    required this.subject,
    required this.from,
    this.date,
  });
  final T value;
  final String id;
  final String subject;
  final String from;
  final DateTime? date;
}

final class _SearchPage<T> {
  const _SearchPage({
    required this.rows,
    required this.precision,
    required this.hasMore,
    this.totalMatches,
  });
  final List<_SearchRow<T>> rows;
  final int? totalMatches;
  final MailSearchCountPrecision precision;
  final bool hasMore;
}

class _StudioMailServerSearchDialog<T> extends StatefulWidget {
  const _StudioMailServerSearchDialog({
    required this.strings,
    required this.mailboxName,
    required this.fields,
    required this.help,
    required this.search,
  });

  final StudioStrings strings;
  final String mailboxName;
  final List<StudioMailServerSearchField> fields;
  final String help;
  final Future<_SearchPage<T>> Function(
    StudioMailServerSearchField,
    StudioMailServerSearchRange,
    String,
    MailCancellationToken,
  )
  search;

  @override
  State<_StudioMailServerSearchDialog<T>> createState() =>
      _StudioMailServerSearchDialogState<T>();
}

class _StudioMailServerSearchDialogState<T>
    extends State<_StudioMailServerSearchDialog<T>> {
  final _query = TextEditingController();
  late StudioMailServerSearchField _field;
  StudioMailServerSearchRange _range = StudioMailServerSearchRange.anyTime;
  MailCancellationSource? _source;
  _SearchPage<T>? _result;
  bool _running = false;
  bool _stopping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _field = widget.fields.first;
  }

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
    final range = _range;
    setState(() {
      _source = source;
      _running = true;
      _stopping = false;
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.search(field, range, text, source.token);
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
    } on StudioMailProviderSearchFailure catch (error) {
      if (!mounted || !identical(source, _source)) return;
      setState(() {
        _running = false;
        _stopping = false;
        _error = switch (error.code) {
          MailProblemCode.invalidInput =>
            widget.strings.mailServerSearchInvalid,
          MailProblemCode.unsupported =>
            widget.strings.mailServerSearchUnsupported,
          MailProblemCode.authenticationRequired ||
          MailProblemCode.permissionDenied =>
            widget.strings.mailServerSearchAuthorization,
          MailProblemCode.cancelled || MailProblemCode.staleOperation => null,
          _ => widget.strings.mailServerSearchFailed,
        };
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

  String _rangeLabel(
    StudioStrings strings,
    StudioMailServerSearchRange range,
  ) => switch (range) {
    StudioMailServerSearchRange.anyTime => strings.mailServerSearchAnyTime,
    StudioMailServerSearchRange.last7Days => strings.mailServerSearchLast7,
    StudioMailServerSearchRange.last30Days => strings.mailServerSearchLast30,
    StudioMailServerSearchRange.last90Days => strings.mailServerSearchLast90,
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
            Text(widget.help),
            const SizedBox(height: 4),
            Text(
              strings.mailServerSearchFolder(widget.mailboxName),
              key: const ValueKey('studio-mail-server-folder'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
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
                      for (final field in widget.fields)
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
                  flex: 2,
                  child: DropdownButtonFormField<StudioMailServerSearchRange>(
                    key: const ValueKey('studio-mail-server-range'),
                    initialValue: _range,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: strings.mailServerSearchRange,
                    ),
                    items: [
                      for (final range in StudioMailServerSearchRange.values)
                        DropdownMenuItem(
                          value: range,
                          child: Text(_rangeLabel(strings, range)),
                        ),
                    ],
                    onChanged: _running
                        ? null
                        : (range) {
                            if (range != null) setState(() => _range = range);
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
                switch (result.precision) {
                  MailSearchCountPrecision.exact =>
                    strings.mailServerSearchCount(
                      result.totalMatches!,
                      result.rows.length,
                    ),
                  MailSearchCountPrecision.estimate =>
                    strings.mailServerSearchEstimate(
                      result.totalMatches!,
                      result.rows.length,
                    ),
                  MailSearchCountPrecision.unknown =>
                    strings.mailServerSearchUnknown(result.rows.length),
                },
                key: const ValueKey('studio-mail-server-count'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (result.hasMore)
                Text(
                  result.precision == MailSearchCountPrecision.exact
                      ? strings.mailServerSearchTruncated
                      : strings.mailServerSearchMorePossible,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              Expanded(
                child: result.rows.isEmpty
                    ? Center(child: Text(strings.mailServerSearchEmpty))
                    : ListView.separated(
                        itemCount: result.rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final message = result.rows[index];
                          return ListTile(
                            key: ValueKey(
                              'studio-mail-server-result-${message.id}',
                            ),
                            title: Text(
                              message.subject.isEmpty
                                  ? strings.mailServerSearchNoSubject
                                  : message.subject,
                            ),
                            subtitle: Text(
                              [
                                if (message.from.isNotEmpty) message.from,
                                ?message.date?.toLocal().toString(),
                              ].join('\n'),
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.open_in_new, size: 18),
                            onTap: _running
                                ? null
                                : () => Navigator.pop(context, message.value),
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
