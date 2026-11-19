import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';
import 'studio_hunspell_host.dart';
import 'studio_arabic_morph_host.dart';
import 'studio_spacy_host.dart';
import 'studio_hunspell_setup.dart';
import 'studio_spacy_setup.dart';

/// Reviews local language coverage and app-owned downloads. Opening or changing
/// a language never downloads data; Install remains an explicit setup action.
Future<void> showStudioDownloadsManager(
  BuildContext context, {
  Set<String> languages = const <String>{},
}) => showDialog<void>(
  context: context,
  builder: (_) => StudioDownloadsManager(
    languages: languages,
    hunspell: studioHunspellHost,
    morphology: studioArabicMorphHost,
    spacy: studioSpacyHost,
  ),
);

class StudioDownloadsManager extends StatefulWidget {
  const StudioDownloadsManager({
    super.key,
    required this.hunspell,
    required this.morphology,
    required this.spacy,
    this.languages = const <String>{},
  });
  final StudioHunspellHost hunspell;
  final StudioArabicMorphHost morphology;
  final StudioSpacyHost spacy;
  final Set<String> languages;
  @override
  State<StudioDownloadsManager> createState() => _StudioDownloadsManagerState();
}

class _StudioDownloadsManagerState extends State<StudioDownloadsManager> {
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.hunspell.addListener(_changed);
    widget.morphology.addListener(_changed);
    widget.spacy.addListener(_changed);
    unawaited(
      _run(() async {
        await Future.wait<void>(<Future<void>>[
          widget.hunspell.refresh(),
          widget.morphology.refresh(),
          widget.spacy.refresh(),
        ]);
      }),
    );
  }

  @override
  void dispose() {
    widget.hunspell.removeListener(_changed);
    widget.morphology.removeListener(_changed);
    widget.spacy.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _size(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
  String _coverage(String language) {
    final primary = language
        .replaceAll('_', '-')
        .split('-')
        .first
        .toLowerCase();
    return switch (primary) {
      'en' =>
        '$language: English spelling and grammar use the bundled Harper checker. No dictionary download is required. The optional English spaCy model provides analysis, not grammar checking.',
      'de' =>
        '$language: German spelling and deterministic writing rules are included. German spaCy analysis and qualified manual grammar are optional downloads.',
      'ar' =>
        '$language: Arabic writing rules are included. Download the Arabic dictionary for spelling and the optional morphology database for additional rules.',
      'fr' =>
        '$language: Optional French analysis is available. Analysis does not provide a French spelling or grammar checker.',
      _ =>
        '$language: No spelling/grammar download is currently offered in the verified catalogue. Changing the document language does not install another language’s checker.',
    };
  }

  Widget _entry({
    required String title,
    required String detail,
    required bool installed,
    required VoidCallback manage,
    Future<void> Function()? remove,
    String? problem,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(
            problem != null
                ? 'Needs repair'
                : installed
                ? 'Installed'
                : 'Not installed',
          ),
          Text(detail),
          if (problem != null)
            Text(
              problem,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            spacing: 8,
            children: <Widget>[
              TextButton(
                onPressed: _busy ? null : manage,
                child: const Text('Review / install'),
              ),
              if (remove != null)
                TextButton(
                  onPressed: _busy ? null : () => _run(remove),
                  child: const Text('Remove downloaded data'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final spacy = widget.spacy.status;
    final morph = widget.morphology.status;
    void dictionaries() => showDialog<void>(
      context: context,
      builder: (_) => StudioHunspellSetupDialog(
        host: widget.hunspell,
        morphHost: widget.morphology,
      ),
    );
    void models() => showDialog<void>(
      context: context,
      builder: (_) => StudioSpacySetupDialog(host: widget.spacy),
    );
    return AlertDialog(
      title: const Text('Language downloads'),
      scrollable: true,
      content: SizedBox(
        width: 680,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Review support, size, source and licence before installing. Downloads start only when you choose Install in the package review. Removing downloaded data leaves your documents unchanged.',
            ),
            for (final language in (widget.languages.toList()..sort()))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_coverage(language)),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Included with the app'),
              subtitle: Text(
                'German spelling/writing rules, English Harper checker, Arabic writing rules, language detection and bundled thesaurus data. Bundled files are part of the application; downloaded packages below can be removed independently.',
              ),
            ),
            const Text('Download inventory — all languages'),
            for (final item in widget.hunspell.statuses)
              _entry(
                title: item.bundle.displayName,
                detail:
                    'Spelling dictionary · ${_size(item.bundle.totalBytes)} · ${item.bundle.license}\n${item.location ?? item.unavailableReason ?? "Optional download"}',
                installed: item.installed,
                manage: dictionaries,
                problem: item.problem,
                remove: item.installed || item.problem != null
                    ? () => widget.hunspell.remove(item.bundle)
                    : null,
              ),
            _entry(
              title: morph.bundle.displayName,
              detail:
                  'Arabic morphology data · ${_size(morph.bundle.totalBytes)} · ${morph.bundle.license}\n${morph.location ?? morph.unavailableReason ?? "Optional download"}',
              installed: morph.installed,
              manage: dictionaries,
              problem: morph.problem,
              remove: morph.installed || morph.problem != null
                  ? widget.morphology.remove
                  : null,
            ),
            _entry(
              title: 'German spaCy analysis package',
              detail:
                  'Analysis; manual grammar only for a qualified build. ${spacy.package == null ? "No package for this platform" : _size(spacy.package!.archiveBytes)}\n${spacy.installedDirectory ?? spacy.unavailableReason ?? "Optional download"}',
              installed: spacy.source == StudioSpacySource.installed,
              manage: models,
              problem: spacy.problem,
              remove: spacy.source == StudioSpacySource.installed
                  ? widget.spacy.remove
                  : null,
            ),
            if (spacyNerDownload case final ner?)
              _entry(
                title: 'German named-entity model (NER)',
                detail:
                    'Names and entities; not grammar. ${_size(ner.bytes)} · optional data model.',
                installed: spacy.nerInstalled,
                manage: models,
                problem: spacy.nerProblem,
                remove: spacy.nerInstalled || spacy.nerProblem != null
                    ? widget.spacy.removeNer
                    : null,
              ),
            for (final item in spacy.languages)
              _entry(
                title: '${item.language.displayName} spaCy analysis model',
                detail:
                    'Analysis only; not a spelling/grammar checker. ${_size(item.downloadBytes)} to download${item.runtimeInstalled ? "" : " including shared runtime"}\n${item.unavailableReason ?? "Data and weights; package review lists exact files and licences."}',
                installed: item.installed,
                manage: models,
                problem: item.problem,
                remove: item.installed || item.problem != null
                    ? () => widget.spacy.removeLanguage(item.language)
                    : null,
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.languages.isEmpty ? 'Close' : 'Not now'),
        ),
      ],
    );
  }
}
