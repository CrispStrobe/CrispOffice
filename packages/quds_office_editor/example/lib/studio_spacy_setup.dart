import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

import 'studio_spacy_host.dart';

String _short(String hash) =>
    hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;

String _megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Explicit setup for optional local German analysis: shows exactly what
/// would be downloaded (immutable source, size, SHA-256, licenses), installs
/// only on request, and exposes the default-off manual grammar opt-in with
/// the qualification of the exact native build.
class StudioSpacySetupDialog extends StatefulWidget {
  const StudioSpacySetupDialog({super.key, required this.host});

  final StudioSpacyHost host;

  @override
  State<StudioSpacySetupDialog> createState() => _StudioSpacySetupDialogState();
}

class _StudioSpacySetupDialogState extends State<StudioSpacySetupDialog> {
  bool _loading = true;
  bool _working = false;
  double? _progress;
  String? _error;
  StudioSpacyInstallCancellation? _cancellation;

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
  }) async {
    setState(() {
      _error = null;
      _working = !loading;
      _loading = loading;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _loading = false;
          _progress = null;
          _cancellation = null;
        });
      }
    }
  }

  Future<void> _install() async {
    final cancellation = StudioSpacyInstallCancellation();
    setState(() {
      _cancellation = cancellation;
      _progress = 0;
    });
    await _run(
      () => widget.host.install(
        cancellation: cancellation,
        onProgress: (received, total) {
          if (mounted) setState(() => _progress = received / total);
        },
      ),
    );
  }

  Future<void> _installLanguage(SpacyLanguage language) async {
    final cancellation = StudioSpacyInstallCancellation();
    setState(() {
      _cancellation = cancellation;
      _progress = 0;
    });
    await _run(
      () => widget.host.installLanguage(
        language,
        cancellation: cancellation,
        onProgress: (received, total) {
          if (mounted) setState(() => _progress = received / total);
        },
      ),
    );
  }

  /// English and French: separately downloaded bundles opened by a
  /// v2-capable native package. Analysis only; no grammar is offered.
  List<Widget> _languageSection(StudioSpacyStatus status, ThemeData theme) {
    if (status.languages.isEmpty) return const [];
    final widgets = <Widget>[
      const SizedBox(height: 16),
      Text('More analysis languages', style: theme.textTheme.titleSmall),
      const Text(
        'Tokens, lemmas, part of speech, morphology, dependencies, sentences '
        'and named entities. Analysis only: no grammar suggestions are '
        'offered for these languages.',
      ),
    ];
    for (final item in status.languages) {
      final download = item.download;
      final runtime = item.runtime;
      final name = item.language.displayName;
      widgets.add(const SizedBox(height: 8));
      if (!item.offered || download == null || runtime == null) {
        widgets.add(
          Text(
            '$name: ${item.unavailableReason ?? 'not available here.'}',
            key: Key('spacy-language-${item.language.code}-unavailable'),
          ),
        );
        continue;
      }
      final files = download.files
          .map(
            (file) =>
                '${file.file} ${_megabytes(file.bytes)} · SHA-256 ${file.sha256}',
          )
          .join('\n');
      widgets.addAll([
        Text(
          '$name (${download.bundle.modelName} ${download.bundle.modelVersion})'
          '${item.installed ? ' · installed and verified' : ''}',
          style: theme.textTheme.labelLarge,
        ),
        if (item.problem != null)
          Text(item.problem!, style: TextStyle(color: theme.colorScheme.error)),
        ExpansionTile(
          key: Key('spacy-language-${item.language.code}-details'),
          tilePadding: EdgeInsets.zero,
          title: Text(
            'Source, files and license (${_megabytes(download.totalBytes)})',
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                'Source: https://huggingface.co/${download.repository} at '
                'revision ${download.revision}\n$files\n'
                '${item.runtimeInstalled ? 'Native package already installed' : 'Also downloads the native package ${runtime.url} (${_megabytes(runtime.archiveBytes)} · SHA-256 ${runtime.archiveSha256})'}.\n'
                'Every file is checked against its compiled-in digest before use.\n\n'
                'License: ${download.license}\n\n'
                'Qualification: ${download.qualification}',
                key: Key('spacy-language-${item.language.code}-source'),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            if (!item.installed)
              FilledButton.tonal(
                key: Key('spacy-language-${item.language.code}-install'),
                onPressed: _working
                    ? null
                    : () => _installLanguage(item.language),
                child: Text(
                  'Download $name (${_megabytes(item.downloadBytes)})',
                ),
              ),
            if (item.installed || item.problem != null)
              TextButton(
                key: Key('spacy-language-${item.language.code}-remove'),
                onPressed: _working
                    ? null
                    : () =>
                          _run(() => widget.host.removeLanguage(item.language)),
                child: Text('Remove $name'),
              ),
          ],
        ),
      ]);
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.host.status;
    final theme = Theme.of(context);
    final package = status.package;
    final children = <Widget>[
      Text('This device: ${status.platformLabel}'),
      const SizedBox(height: 8),
      const Text(
        'German (Germany) tokens, lemmas, part of speech, morphology, '
        'dependencies and sentences, computed on this device with the '
        'de_core_news_sm 3.8.0 model. Text never leaves the device and '
        'analysis never downloads anything.',
      ),
      const SizedBox(height: 12),
    ];
    if (_loading) {
      children.add(const LinearProgressIndicator());
    } else if (status.source == StudioSpacySource.developer) {
      children.addAll([
        Text('Developer configuration', style: theme.textTheme.titleSmall),
        Text(
          'Environment variables select the model bundle and native library '
          '(${_short(status.librarySha256 ?? '')}).',
        ),
      ]);
    } else if (!status.configured) {
      if (package == null) {
        children.add(
          Text(
            status.unavailableReason ?? 'Not available on this platform.',
            key: const Key('spacy-setup-unavailable'),
          ),
        );
      } else {
        children.addAll([
          Text('Download', style: theme.textTheme.titleSmall),
          SelectableText(
            'Source: ${package.url}\n'
            'Size: ${_megabytes(package.archiveBytes)} · '
            'SHA-256 ${package.archiveSha256}\n'
            'Every byte is checked against this digest before anything is '
            'unpacked; the native library and model are then verified '
            'individually and installed atomically.',
            key: const Key('spacy-setup-source'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Licenses: spaCy model de_core_news_sm (MIT; source data notices '
            'included), CrispEmbed and ggml (MIT), PCRE2 (BSD), Unicode data '
            'notice. Full texts are installed with the files.',
          ),
          if (package.systemRequirements.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Requires: ${package.systemRequirements.join('; ')}.'),
          ],
        ]);
      }
    } else {
      children.addAll([
        Text(
          status.problem == null ? 'Installed and verified' : 'Needs attention',
          style: theme.textTheme.titleSmall,
        ),
        if (status.problem != null)
          Text(
            status.problem!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (status.librarySha256 != null)
          Text('Native build ${_short(status.librarySha256!)}'),
      ]);
    }
    if (!_loading && status.configured && status.problem == null) {
      final qualification = status.qualification;
      children.addAll([
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('spacy-setup-analysis'),
          contentPadding: EdgeInsets.zero,
          title: const Text('German text analysis view'),
          value: status.analysisEnabled,
          onChanged: _working || status.source == StudioSpacySource.developer
              ? null
              : (value) => _run(() => widget.host.setAnalysisEnabled(value)),
        ),
        SwitchListTile(
          key: const Key('spacy-setup-grammar'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Manual German grammar suggestions'),
          subtitle: Text(
            status.grammarOffered
                ? 'Off by default. Runs only for “Check document”, never while '
                      'typing; every suggestion is reviewed before it changes text.'
                : 'Not available: this exact native build has no recorded '
                      'grammar qualification.',
          ),
          value: status.grammarEnabled,
          onChanged: _working || !status.grammarOffered
              ? null
              : (value) => _run(() => widget.host.setGrammarEnabled(value)),
        ),
        if (status.nerOffered)
          SwitchListTile(
            key: const Key('spacy-setup-ner'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Named entities (optional download)'),
            subtitle: const Text(
              'Shows people, places and organizations in the analysis view. '
              'Not used for grammar suggestions.',
            ),
            value: status.nerEnabled,
            onChanged: _working
                ? null
                : (value) => _run(() => widget.host.setNerEnabled(value)),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('What this build is qualified for'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                qualification == null
                    ? 'No recorded qualification for this exact build.'
                    : 'Analysis: ${qualification.analysis}\n\n'
                          'Grammar: ${qualification.grammar ?? 'not qualified for this build.'}'
                          '${qualification.limitations.isEmpty ? '' : '\n\nLimits: ${qualification.limitations.join(' ')}'}',
                key: const Key('spacy-setup-qualification'),
              ),
            ),
          ],
        ),
      ]);
    }
    if (!_loading) children.addAll(_languageSection(status, theme));
    if (_progress != null) {
      children.addAll([
        const SizedBox(height: 12),
        LinearProgressIndicator(value: _progress),
      ]);
    }
    if (_error != null) {
      children.addAll([
        const SizedBox(height: 12),
        Text(
          _error!,
          key: const Key('spacy-setup-error'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ]);
    }
    return AlertDialog(
      title: const Text('Local text analysis'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
      actions: [
        if (_cancellation != null)
          TextButton(
            onPressed: () => _cancellation?.cancel(),
            child: const Text('Cancel download'),
          ),
        if (!_loading &&
            status.source == StudioSpacySource.none &&
            package != null)
          FilledButton(
            key: const Key('spacy-setup-install'),
            onPressed: _working ? null : _install,
            child: Text(
              'Download and install (${_megabytes(package.archiveBytes)})',
            ),
          ),
        if (!_loading && status.source == StudioSpacySource.installed)
          TextButton(
            key: const Key('spacy-setup-remove'),
            onPressed: _working ? null : () => _run(widget.host.remove),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Opens the setup dialog.
Future<void> showStudioSpacySetup(
  BuildContext context, {
  StudioSpacyHost? host,
}) => showDialog<void>(
  context: context,
  builder: (_) => StudioSpacySetupDialog(host: host ?? studioSpacyHost),
);
