import 'package:flutter/material.dart';

import 'studio_credential_storage.dart';
import 'studio_productivity_accounts.dart';
import 'studio_strings.dart';

Future<void> showStudioConnections(
  BuildContext context, {
  StudioLanguage language = StudioLanguage.en,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ConnectionsDialog(language),
);

class _ConnectionsDialog extends StatefulWidget {
  const _ConnectionsDialog(this.language);
  final StudioLanguage language;

  @override
  State<_ConnectionsDialog> createState() => _ConnectionsDialogState();
}

class _ConnectionsDialogState extends State<_ConnectionsDialog> {
  final _storage = StudioCredentialStorage.instance;
  late var _accounts = _load();
  bool _saving = false;
  String? _error;

  Future<List<StudioProductivityAccount>> _load() async {
    final revision = _storage.revision;
    final vault = await _storage.storage;
    final accounts = await loadStudioProductivityAccounts(
      vault,
      groupByAddress: false,
    );
    if (_storage.revision != revision)
      throw StateError('Credential storage changed.');
    return accounts;
  }

  String _name(StudioProductivityService service) {
    final strings = StudioStrings(widget.language);
    return switch (service) {
      StudioProductivityService.mail => strings.mail,
      StudioProductivityService.tasks => strings.productivity('Tasks'),
      StudioProductivityService.calendar => switch (widget.language) {
        StudioLanguage.en => 'Calendar',
        StudioLanguage.de => 'Kalender',
        StudioLanguage.ar => 'التقويم',
      },
    };
  }

  Future<void> _edit(StudioProductivityAccount row) async {
    final id = row.id;
    if (_saving || id == null) return;
    final revision = _storage.revision;
    final selected = {...row.services};
    final request = await showDialog<Set<StudioProductivityService>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(row.label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final service in row.available)
                CheckboxListTile(
                  title: Text(_name(service)),
                  value: selected.contains(service),
                  onChanged: (use) => update(() {
                    if (use == true) {
                      selected.add(service);
                    } else {
                      selected.remove(service);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                StudioStrings(widget.language).productivity('Cancel'),
              ),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected),
              child: Text(StudioStrings(widget.language).save),
            ),
          ],
        ),
      ),
    );
    if (request == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final vault = await _storage.storage;
      if (revision != _storage.revision)
        throw StateError('Credential storage changed.');
      await saveStudioAccountServices(vault, id, request);
      if (mounted) setState(() => _accounts = _load());
    } on Object {
      if (mounted)
        setState(() => _error = 'The service settings could not be saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(StudioStrings(widget.language).productivity('Accounts')),
    content: SizedBox(
      width: 460,
      child: FutureBuilder<List<StudioProductivityAccount>>(
        future: _accounts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Saved connections could not be read.');
          }
          final rows = snapshot.data;
          if (rows == null) return const LinearProgressIndicator();
          if (rows.isEmpty) return const Text('No saved connections.');
          return ListView(
            shrinkWrap: true,
            children: [
              if (_error case final error?) Text(error),
              for (final row in rows)
                ListTile(
                  title: Text(row.label),
                  subtitle: Text(row.services.map(_name).join(' · ')),
                  trailing: row.id == null
                      ? null
                      : IconButton(
                          tooltip: 'Edit services',
                          onPressed: _saving ? null : () => _edit(row),
                          icon: const Icon(Icons.settings_outlined),
                        ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text(StudioStrings(widget.language).close),
      ),
    ],
  );
}
