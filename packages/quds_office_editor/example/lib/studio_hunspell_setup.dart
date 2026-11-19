import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

import 'studio_hunspell_host.dart';

String _short(String hash) =>
    hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;

String _megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Explicit setup for optional spelling dictionaries (first Arabic): shows
/// exactly what would be downloaded (immutable source revision, size,
/// SHA-256, licence) and installs or removes only on request.
class StudioHunspellSetupDialog extends StatefulWidget {
  const StudioHunspellSetupDialog({super.key, required this.host});

  final StudioHunspellHost host;

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
    unawaited(_run(widget.host.refresh, loading: true));
  }

  @override
  void dispose() {
    widget.host.removeListener(_changed);
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
    await _run(
      () => widget.host.install(
        bundle,
        cancellation: cancellation,
        onProgress: (received, total) {
          if (mounted) setState(() => _progress = received / total);
        },
      ),
      working: bundle.id,
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
      const Text(
        'Optional spelling dictionaries are downloaded on request and checked '
        'on this device. The spelling engine (Hunspell 1.7.2, MPL 1.1) is part '
        'of the app; only dictionary data is downloaded.',
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
    }
    if (_error != null) {
      children.add(
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      );
    }
    return AlertDialog(
      title: const Text('Spelling dictionaries'),
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
}) => showDialog<void>(
  context: context,
  builder: (_) => StudioHunspellSetupDialog(host: host ?? studioHunspellHost),
);
