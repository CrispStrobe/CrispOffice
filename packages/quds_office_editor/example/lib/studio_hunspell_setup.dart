import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

import 'studio_arabic_morph_host.dart';
import 'studio_download_catalog.dart';
import 'studio_hunspell_host.dart';

String _short(String hash) =>
    hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;

String _megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Explicit setup for optional spelling dictionaries (first Arabic) and,
/// when [morphHost] is given, the Arabic morphology database: shows exactly
/// what would be downloaded (immutable source revision, size, SHA-256,
/// licence and attribution) and installs or removes only on request.
class StudioHunspellSetupDialog extends StatefulWidget {
  const StudioHunspellSetupDialog({
    super.key,
    required this.host,
    this.morphHost,
  });

  final StudioHunspellHost host;

  /// The Arabic morphology database host; null hides that section.
  final StudioArabicMorphHost? morphHost;

  @override
  State<StudioHunspellSetupDialog> createState() =>
      _StudioHunspellSetupDialogState();
}

class _StudioHunspellSetupDialogState extends State<StudioHunspellSetupDialog> {
  bool _loading = true;
  String? _working;
  double? _progress;
  String? _error;
  StudioHunspellCancellation? _cancellation;

  @override
  void initState() {
    super.initState();
    widget.host.addListener(_changed);
    widget.morphHost?.addListener(_changed);
    unawaited(
      _run(() async {
        await widget.host.refresh();
        // Loading the analyzer can take a second; the dialog need not wait.
        unawaited(widget.morphHost?.refresh().catchError((Object _) {}));
      }, loading: true),
    );
  }

  @override
  void dispose() {
    widget.host.removeListener(_changed);
    widget.morphHost?.removeListener(_changed);
    _cancellation?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool loading = false,
    String? working,
  }) async {
    setState(() {
      _error = null;
      _loading = loading;
      _working = working;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _working = null;
          _progress = null;
          _cancellation = null;
        });
      }
    }
  }

  Future<void> _install(HunspellBundleDownload bundle) async {
    final cancellation = StudioHunspellCancellation();
    setState(() {
      _cancellation = cancellation;
      _progress = 0;
    });
    await studioDownloadActivity.track(
      bundle.id,
      cancel: cancellation.cancel,
      download: (report) => _run(
        () => widget.host.install(
          bundle,
          cancellation: cancellation,
          onProgress: (received, total) {
            report(received, total);
            if (mounted) setState(() => _progress = received / total);
          },
        ),
        working: bundle.id,
      ),
    );
  }

  Future<void> _installMorph(StudioArabicMorphHost host) async {
    final cancellation = StudioHunspellCancellation();
    setState(() {
      _cancellation = cancellation;
      _progress = 0;
    });
    await studioDownloadActivity.track(
      host.status.bundle.id,
      cancel: cancellation.cancel,
      download: (report) => _run(
        () => host.install(
          cancellation: cancellation,
          onProgress: (received, total) {
            report(received, total);
            if (mounted) setState(() => _progress = received / total);
          },
        ),
        working: host.status.bundle.id,
      ),
    );
  }

  Future<void> _installModel(StudioArabicMorphHost host) async {
    final cancellation = StudioHunspellCancellation();
    setState(() {
      _cancellation = cancellation;
      _progress = 0;
    });
    await studioDownloadActivity.track(
      host.modelStatus.bundle.id,
      cancel: cancellation.cancel,
      download: (report) => _run(
        () => host.installModel(
          cancellation: cancellation,
          onProgress: (received, total) {
            report(received, total);
            if (mounted) setState(() => _progress = received / total);
          },
        ),
        working: host.modelStatus.bundle.id,
      ),
    );
  }

  /// The optional context model: a second download that needs the database.
  Widget _modelEntry(StudioArabicMorphHost host, ThemeData theme) {
    final status = host.modelStatus;
    final bundle = status.bundle;
    final busy = _working == bundle.id;
    final ready = host.status.installed && host.status.loaded;
    return Column(
      key: const ValueKey('arabic-morph-model'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bundle.displayName, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(
          'Optional context model for the Arabic grammar rules: it ranks '
          'the analyses of each word in its sentence, so a rule can rely on '
          'the clearly most likely reading instead of staying silent '
          'whenever any reading would fit. Needs the morphology data above.\n'
          'Source: ${bundle.browseUrl}\n'
          'Format: ${bundle.sourceUrl}\n'
          'Licence: CC BY-SA 4.0 (${bundle.licenseUrl})\n'
          'Attribution: ${bundle.attribution}\n'
          'Download: ${_megabytes(bundle.totalBytes)}, every file checked '
          'against its pinned SHA-256 (manifest.json '
          '${_short(bundle.manifest.sha256)}, model '
          '${_short(bundle.database.sha256)}).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (!status.offered)
          Text(status.unavailableReason!)
        else if (status.installed && status.loaded)
          const Text(
            'Installed, verified and loaded. Grammar rules use readings in '
            'context.',
            key: ValueKey('arabic-morph-model-loaded'),
          )
        else if (status.installed && status.problem == null)
          const Text(
            'Installed and verified; it loads with the morphology data.',
            key: ValueKey('arabic-morph-model-installed'),
          )
        else if (!status.installed)
          Text(
            ready
                ? 'Not installed. Nothing is downloaded until you ask.'
                : 'Install the morphology data first.',
          ),
        if (status.problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              status.problem!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (busy) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _progress),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (status.offered && !status.installed && !busy)
              FilledButton(
                key: const ValueKey('arabic-morph-model-install'),
                onPressed: _working == null && ready
                    ? () => _installModel(host)
                    : null,
                child: const Text('Download'),
              ),
            if (busy)
              TextButton(
                onPressed: () => _cancellation?.cancel(),
                child: const Text('Cancel'),
              ),
            if (status.installed && !busy)
              TextButton(
                key: const ValueKey('arabic-morph-model-remove'),
                onPressed: _working == null
                    ? () => _run(host.removeModel, working: bundle.id)
                    : null,
                child: const Text('Remove'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _morphEntry(StudioArabicMorphHost host, ThemeData theme) {
    final status = host.status;
    final bundle = status.bundle;
    final busy = _working == bundle.id;
    return Column(
      key: const ValueKey('arabic-morph'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bundle.displayName, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(
          'Grammar data for Arabic rules: every possible analysis of each '
          'word (lemma, part of speech, gender, number, clitics).\n'
          'Source: ${bundle.browseUrl}\n'
          'Data project: ${bundle.sourceUrl}\n'
          'Licence: CC BY 4.0 (${bundle.licenseUrl})\n'
          'Attribution: ${bundle.attribution}\n'
          'Download: ${_megabytes(bundle.totalBytes)}, every file checked '
          'against its pinned SHA-256 (manifest.json '
          '${_short(bundle.manifest.sha256)}, database '
          '${_short(bundle.database.sha256)}). The analyzer needs about '
          '15 MB of memory while loaded'
          '${kIsWeb ? ' (about 20 MB in this browser tab)' : ''}.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (!status.offered)
          Text(status.unavailableReason!)
        else if (status.installed && status.loaded)
          const Text(
            'Installed, verified and loaded. Arabic grammar rules can use it.',
            key: ValueKey('arabic-morph-loaded'),
          )
        else if (status.installed && status.problem == null)
          const Text(
            'Installed and verified; loading the analyzer…',
            key: ValueKey('arabic-morph-loading'),
          )
        else if (!status.installed)
          const Text('Not installed. Nothing is downloaded until you ask.'),
        if (status.problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              status.problem!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (busy) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _progress),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (status.offered && !status.installed && !busy)
              FilledButton(
                key: const ValueKey('arabic-morph-install'),
                onPressed: _working == null ? () => _installMorph(host) : null,
                child: const Text('Download'),
              ),
            if (busy)
              TextButton(
                onPressed: () => _cancellation?.cancel(),
                child: const Text('Cancel'),
              ),
            if (status.installed && !busy)
              TextButton(
                key: const ValueKey('arabic-morph-remove'),
                onPressed: _working == null
                    ? () => _run(host.remove, working: bundle.id)
                    : null,
                child: const Text('Remove'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _entry(StudioHunspellStatus status, ThemeData theme) {
    final bundle = status.bundle;
    final busy = _working == bundle.id;
    return Column(
      key: ValueKey('hunspell-${bundle.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bundle.displayName, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(
          'Source: ${status.sourceUri}\n'
          'Licence: ${bundle.license}\n'
          'Download: ${_megabytes(bundle.totalBytes)}, every file checked '
          'against its pinned SHA-256 (ar.aff ${_short(bundle.aff.sha256)}, '
          'ar.dic ${_short(bundle.dic.sha256)}).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (!status.offered)
          Text(status.unavailableReason!)
        else if (status.installed)
          Text(
            'Installed and verified. Spelling is checked for '
            '${bundle.languages.join(', ')} paragraphs.',
            key: ValueKey('hunspell-${bundle.id}-installed'),
          )
        else
          const Text('Not installed. Nothing is downloaded until you ask.'),
        if (status.problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              status.problem!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (busy) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _progress),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (status.offered && !status.installed && !busy)
              FilledButton(
                key: ValueKey('hunspell-${bundle.id}-install'),
                onPressed: _working == null ? () => _install(bundle) : null,
                child: const Text('Download'),
              ),
            if (busy)
              TextButton(
                onPressed: () => _cancellation?.cancel(),
                child: const Text('Cancel'),
              ),
            if (status.installed && !busy)
              TextButton(
                key: ValueKey('hunspell-${bundle.id}-remove'),
                onPressed: _working == null
                    ? () => _run(
                        () => widget.host.remove(bundle),
                        working: bundle.id,
                      )
                    : null,
                child: const Text('Remove'),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[
      Text(
        'Optional spelling dictionaries are downloaded on request and checked '
        'on this device. The spelling engine (Hunspell 1.7.2, MPL 1.1) is part '
        'of the app; only dictionary data is downloaded.'
        '${widget.morphHost == null ? '' : ' The same applies to the Arabic morphology database: the analyzer (MIT) is part of the app, only its data is downloaded.'}',
      ),
      const SizedBox(height: 16),
    ];
    if (_loading) {
      children.add(const LinearProgressIndicator());
    } else {
      for (final status in widget.host.statuses) {
        children
          ..add(_entry(status, theme))
          ..add(const SizedBox(height: 16));
      }
      final morphHost = widget.morphHost;
      if (morphHost != null) {
        children
          ..add(const Divider())
          ..add(const SizedBox(height: 8))
          ..add(_morphEntry(morphHost, theme))
          ..add(const SizedBox(height: 16))
          ..add(_modelEntry(morphHost, theme))
          ..add(const SizedBox(height: 16));
      }
    }
    if (_error != null) {
      children.add(
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      );
    }
    return AlertDialog(
      title: Text(
        widget.morphHost == null
            ? 'Spelling dictionaries'
            : 'Dictionaries and language data',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'CrispOffice'),
          child: const Text('Licences'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

Future<void> showStudioHunspellSetup(
  BuildContext context, {
  StudioHunspellHost? host,
  StudioArabicMorphHost? morphHost,
}) => showDialog<void>(
  context: context,
  builder: (_) => StudioHunspellSetupDialog(
    host: host ?? studioHunspellHost,
    morphHost: morphHost ?? studioArabicMorphHost,
  ),
);
