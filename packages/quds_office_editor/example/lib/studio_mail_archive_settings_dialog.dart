import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_archive_destination.dart';
import 'studio_mail_archive_settings_store.dart';
import 'studio_mail_archive_settings_strings.dart';
import 'studio_mail_mutation_strings.dart';
import 'studio_strings.dart';

/// Account settings remain available without a selected message or nonempty
/// folder. Only local routing preferences are written here, never mail commands.
Future<bool> showStudioMailArchiveSettings(
  BuildContext context, {
  required StudioStrings strings,
  required String accountLabel,
  required MailAccountId providerAccount,
  required StudioMailArchiveSettingsStore store,
  required Future<List<MailMailbox>> Function() loadFolders,
  required bool Function() isCurrent,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ArchiveSettingsDialog(
        strings: strings,
        accountLabel: accountLabel,
        providerAccount: providerAccount,
        store: store,
        loadFolders: loadFolders,
        isCurrent: isCurrent,
      ),
    ) ??
    false;

class _ArchiveSettingsDialog extends StatefulWidget {
  const _ArchiveSettingsDialog({
    required this.strings,
    required this.accountLabel,
    required this.providerAccount,
    required this.store,
    required this.loadFolders,
    required this.isCurrent,
  });

  final StudioStrings strings;
  final String accountLabel;
  final MailAccountId providerAccount;
  final StudioMailArchiveSettingsStore store;
  final Future<List<MailMailbox>> Function() loadFolders;
  final bool Function() isCurrent;

  @override
  State<_ArchiveSettingsDialog> createState() => _ArchiveSettingsDialogState();
}

class _ArchiveSettingsDialogState extends State<_ArchiveSettingsDialog> {
  late final MailAccountId _owner = widget.store.account;
  MailArchiveDestinationSettings? _settings;
  List<MailMailbox> _folders = const [];
  MailMailboxId? _selected;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _catalogReady = false;
  bool _requiresReload = false;
  int _generation = 0;

  bool get _current =>
      mounted && widget.isCurrent() && widget.store.account == _owner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_saving) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _catalogReady = false;
      _requiresReload = false;
      _settings = null;
      _selected = null;
      _folders = const [];
      _error = null;
    });
    try {
      final settings = await readStudioMailArchiveSettings(
        widget.store,
        isCurrent: () => _current,
      );
      if (!_current || generation != _generation) return;
      setState(() => _settings = settings);
      final observed = await widget.loadFolders();
      if (!_current || generation != _generation) return;
      final folders = studioMailArchiveDestinations(
        observed,
        widget.providerAccount,
      );
      final saved = settings.destination?.value;
      final matching = folders.where((folder) => folder.id.value == saved);
      setState(() {
        _folders = folders;
        _catalogReady = true;
        _selected = matching.isEmpty ? null : matching.single.id;
      });
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _error = widget.strings.mailArchiveSettingsLoadFailed);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save({required bool clear}) async {
    final settings = _settings;
    final selected = _selected;
    if (!_current ||
        _loading ||
        _saving ||
        _requiresReload ||
        settings == null ||
        (!clear &&
            (!_catalogReady ||
                selected == null ||
                !_folders.any((folder) => folder.id == selected))) ||
        (clear && settings.destination == null)) {
      return;
    }
    final updated = MailArchiveDestinationSettings(
      account: _owner,
      revision: settings.revision,
      destination: clear
          ? null
          : MailMailboxId(selected!.value, account: _owner),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.store.saveArchiveSettings(
        updated,
        expectedRevision: settings.revision,
      );
      if (!_current) return;
      if (!saved.isValid ||
          saved.account != _owner ||
          saved.revision != settings.revision + 1 ||
          saved.destination != updated.destination) {
        throw const StudioMailArchiveDestinationException(
          StudioMailArchiveDestinationFailure.changed,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (mounted) {
        setState(() {
          _requiresReload = true;
          _error = widget.strings.mailArchiveSettingsSaveFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final saved = _settings?.destination;
    final missing =
        saved != null &&
        _catalogReady &&
        !_folders.any((folder) => folder.id.value == saved.value);
    final blocked = _loading || _saving || _requiresReload || !_current;
    return PopScope(
      canPop: !_saving,
      child: Directionality(
        textDirection: s.language == StudioLanguage.ar
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: AlertDialog(
          key: const ValueKey('studio-mail-archive-settings-dialog'),
          scrollable: true,
          title: Text(s.mailArchiveSettingsTitle),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.accountLabel, textDirection: TextDirection.ltr),
                const SizedBox(height: 12),
                Text(s.mailArchiveSettingsHelp),
                const SizedBox(height: 12),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_settings != null) ...[
                  if (saved == null)
                    Text(s.mailArchiveSettingsDefault)
                  else ...[
                    Text(s.mailArchiveSettingsSavedDestination),
                    Text(
                      saved.value,
                      key: const ValueKey('studio-mail-archive-settings-saved'),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                  if (missing)
                    Text(
                      s.mailArchiveSettingsMissing,
                      key: const ValueKey(
                        'studio-mail-archive-settings-missing',
                      ),
                    ),
                  if (_catalogReady) ...[
                    const SizedBox(height: 12),
                    Text(s.mailOrganizationDestination),
                    if (_folders.isEmpty)
                      Text(s.mailOrganizationNoDestination)
                    else
                      SizedBox(
                        height: 220,
                        child: ListView.builder(
                          key: const ValueKey(
                            'studio-mail-archive-settings-folders',
                          ),
                          itemCount: _folders.length,
                          itemBuilder: (context, index) {
                            final folder = _folders[index];
                            final selected = folder.id == _selected;
                            return ListTile(
                              key: ValueKey(
                                'studio-mail-archive-settings-folder-$index',
                              ),
                              selected: selected,
                              title: Text(folder.displayName),
                              subtitle: Text(
                                folder.id.value,
                                textDirection: TextDirection.ltr,
                              ),
                              leading: Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                              ),
                              onTap: blocked
                                  ? null
                                  : () => setState(() => _selected = folder.id),
                            );
                          },
                        ),
                      ),
                  ],
                ],
                if (_error != null || !_current)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      !_current
                          ? s.mailArchiveDestinationFailure(
                              StudioMailArchiveDestinationFailure.stale,
                            )
                          : _error!,
                      key: const ValueKey('studio-mail-archive-settings-error'),
                    ),
                  ),
                TextButton.icon(
                  key: const ValueKey('studio-mail-archive-settings-reload'),
                  onPressed: _loading || _saving || !_current ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: Text(s.mailArchiveSettingsReload),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('studio-mail-archive-settings-cancel'),
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: Text(s.cancel),
            ),
            if (saved != null)
              TextButton(
                key: const ValueKey('studio-mail-archive-settings-clear'),
                onPressed: blocked ? null : () => _save(clear: true),
                child: Text(s.mailArchiveSettingsClear),
              ),
            FilledButton(
              key: const ValueKey('studio-mail-archive-settings-save'),
              onPressed: blocked || !_catalogReady || _selected == null
                  ? null
                  : () => _save(clear: false),
              child: Text(s.mailArchiveSettingsSave),
            ),
          ],
        ),
      ),
    );
  }
}
