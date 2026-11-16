import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../proofing/word_proofing.dart';
import 'office_controller.dart';

/// Commits active editor drafts before starting a document-wide review.
Future<void> showWordProofingDialog(
  BuildContext context, {
  required WordEditorController controller,
}) {
  controller.commitPendingEdits();
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) =>
        WordProofingDialog(controller: controller),
  );
}

/// Reviews proofing results across the document and its additional stories.
/// The controller owns the session, vocabulary, and undoable corrections.
class WordProofingDialog extends StatefulWidget {
  const WordProofingDialog({super.key, required this.controller});

  final WordEditorController controller;

  @override
  State<WordProofingDialog> createState() => _WordProofingDialogState();
}

class _WordProofingDialogState extends State<WordProofingDialog> {
  static const Map<String, String> _languages = <String, String>{
    'de-DE': 'Deutsch (Deutschland)',
    'de-AT': 'Deutsch (Österreich)',
    'de-CH': 'Deutsch (Schweiz)',
    'en-US': 'English (United States)',
    'en-GB': 'English (United Kingdom)',
  };

  String? _notice;

  WordEditorController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check());
    });
  }

  Future<void> _check() async {
    try {
      await _controller.checkDocumentProofing();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'The document check could not finish. Try again.',
        );
      }
    }
  }

  void _apply(WordProofingIssue issue, String replacement) {
    final bool applied = _controller.applyProofingSuggestion(
      issue,
      replacement,
    );
    setState(() {
      _notice = applied
          ? 'Correction applied. You can undo this change.'
          : 'This result can no longer be changed. Check the document again.';
    });
    unawaited(_check());
  }

  void _show(WordProofingIssue issue) {
    if (_controller.revealProofingIssue(issue)) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _notice =
            'This result cannot be selected in the current document view.';
      });
    }
  }

  void _ignoreWord(WordProofingIssue issue) {
    _controller.proofing.ignoreWord(issue);
    unawaited(_check());
  }

  void _addWord(WordProofingIssue issue) {
    _controller.proofing.addWord(issue);
    setState(() => _notice = 'Word added to your personal dictionary.');
    unawaited(_check());
  }

  void _ignoreRule(WordProofingIssue issue) {
    _controller.proofing.ignoreRule(issue.finding.ruleId);
    unawaited(_check());
  }

  void _ignoreOnce(WordProofingIssue issue) {
    _controller.proofing.ignoreOnce(issue);
    unawaited(_check());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (BuildContext context, Widget? child) {
      final WordProofingSession session = _controller.proofing;
      final WordProofingSummary summary = session.summary;
      final double height = math.min(
        720.0,
        math.max(240.0, MediaQuery.sizeOf(context).height - 48),
      );
      return Directionality(
        textDirection: _controller.config.textDirection,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 720,
            height: height,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Spelling and grammar',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close proofing',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                if (session.checking)
                  const LinearProgressIndicator(
                    key: ValueKey<String>('proofing-progress'),
                    semanticsLabel: 'Checking the document',
                  )
                else
                  const Divider(height: 4),
                Expanded(
                  child: CustomScrollView(
                    slivers: <Widget>[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _settings(session),
                              const SizedBox(height: 16),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  summary.statusMessage,
                                  key: const ValueKey<String>(
                                    'proofing-status',
                                  ),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              if (summary.hasResults) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  '${summary.checkedParagraphCount} of '
                                  '${summary.paragraphCount} paragraphs checked'
                                  '${summary.skippedContentCount == 0 ? '' : ' · ${summary.skippedContentCount} content item(s) skipped'}',
                                ),
                              ],
                              _providerStatus(summary),
                              if (_notice != null) ...<Widget>[
                                const SizedBox(height: 8),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(_notice!),
                                ),
                              ],
                              if (!_controller
                                  .canApplyProofingSuggestions) ...<Widget>[
                                const SizedBox(height: 8),
                                const Text(
                                  'Suggestions can be applied when the document is '
                                  'editable and text composition has finished.',
                                ),
                              ],
                              if (summary.issues.isEmpty) ...<Widget>[
                                const SizedBox(height: 16),
                                Text(
                                  session.checking
                                      ? 'Checking the document…'
                                      : summary.complete && summary.hasResults
                                      ? 'No issues found in the checked text.'
                                      : summary.hasResults
                                      ? 'Results are incomplete. Review the checker status above.'
                                      : 'Run a check to review this document.',
                                  key: const ValueKey<String>('proofing-empty'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList.builder(
                          itemCount: summary.issues.length,
                          itemBuilder: (BuildContext context, int index) =>
                              _issue(summary.issues[index], session.checking),
                        ),
                      ),
                      SliverToBoxAdapter(child: _personalWords(session)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 8,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                      FilledButton.icon(
                        key: const ValueKey<String>('proofing-check-document'),
                        onPressed: session.checking
                            ? null
                            : () => unawaited(_check()),
                        icon: const Icon(Icons.spellcheck),
                        label: const Text('Check entire document'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _providerStatus(WordProofingSummary summary) {
    final Map<String, OfficeProofingResult> statuses =
        <String, OfficeProofingResult>{};
    for (final OfficeProofingReport report in summary.reports) {
      for (final OfficeProofingResult result in report.results) {
        statuses.putIfAbsent(
          '${result.providerId}/${result.request.language}/${result.status.name}',
          () => result,
        );
      }
    }
    if (statuses.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      key: const ValueKey<String>('proofing-provider-status'),
      tilePadding: EdgeInsets.zero,
      title: const Text('Checker status'),
      initiallyExpanded: !summary.complete,
      children: <Widget>[
        for (final OfficeProofingResult result in statuses.values)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              result.status == OfficeProofingStatus.success
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
            ),
            title: Text(
              '${result.providerId} · ${result.request.language} · '
              '${switch (result.status) {
                OfficeProofingStatus.success => 'Checked',
                OfficeProofingStatus.unsupported => 'Unsupported language',
                OfficeProofingStatus.unavailable => 'Unavailable',
                OfficeProofingStatus.failed => 'Check failed',
              }}',
            ),
            subtitle: result.message == null ? null : Text(result.message!),
          ),
      ],
    );
  }

  Widget _settings(WordProofingSession session) {
    final bool editable = _controller.config.allowsMutation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Document language',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey<String>('proofing-language'),
              value: session.language,
              isExpanded: true,
              items: <DropdownMenuItem<String>>[
                for (final MapEntry<String, String> language
                    in _languages.entries)
                  DropdownMenuItem<String>(
                    value: language.key,
                    child: Text(language.value),
                  ),
                if (!_languages.containsKey(session.language))
                  DropdownMenuItem<String>(
                    value: session.language,
                    child: Text(session.language),
                  ),
              ],
              onChanged: !editable
                  ? null
                  : (String? value) {
                      if (value == null) return;
                      _controller.setProofingLanguage(value);
                      unawaited(_check());
                    },
            ),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          key: const ValueKey<String>('proofing-background'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Check while typing'),
          value: session.enabled,
          onChanged: (bool value) => session.enabled = value,
        ),
        SwitchListTile.adaptive(
          key: const ValueKey<String>('proofing-hyphenation'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Automatic hyphenation'),
          subtitle: const Text(
            'Uses the document and text languages. Hyphens at line breaks '
            'do not change the original text.',
          ),
          value: _controller.document.autoHyphenation,
          onChanged: editable ? _controller.setAutomaticHyphenation : null,
        ),
      ],
    );
  }

  Widget _issue(WordProofingIssue issue, bool checking) {
    final OfficeProofingFinding finding = issue.finding;
    final bool canApply = !checking && _controller.canApplyProofingIssue(issue);
    final bool spelling =
        finding.category == OfficeProofingCategory.spelling &&
        finding.originalText.trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              finding.originalText.isEmpty
                  ? 'Suggested insertion'
                  : finding.originalText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(finding.message),
            const SizedBox(height: 4),
            Text(
              '${switch (finding.category) {
                OfficeProofingCategory.spelling => 'Spelling',
                OfficeProofingCategory.grammar => 'Grammar',
                OfficeProofingCategory.style => 'Writing style',
              }} · ${issue.story} · ${issue.language}',
            ),
            const SizedBox(height: 4),
            Text(
              issue.sourceText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String replacement in finding.replacements)
                  OutlinedButton(
                    onPressed: canApply
                        ? () => _apply(issue, replacement)
                        : null,
                    child: Text(replacement.isEmpty ? 'Delete' : replacement),
                  ),
                TextButton(
                  onPressed: checking ? null : () => _show(issue),
                  child: const Text('Show in document'),
                ),
                TextButton(
                  onPressed: checking ? null : () => _ignoreOnce(issue),
                  child: const Text('Ignore once'),
                ),
                if (spelling) ...<Widget>[
                  TextButton(
                    onPressed: checking ? null : () => _ignoreWord(issue),
                    child: const Text('Ignore word'),
                  ),
                  TextButton(
                    onPressed: checking ? null : () => _addWord(issue),
                    child: const Text('Add to dictionary'),
                  ),
                ] else
                  TextButton(
                    onPressed: checking ? null : () => _ignoreRule(issue),
                    child: const Text('Ignore rule'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _personalWords(WordProofingSession session) {
    final List<String> words =
        session.vocabulary.wordsFor(session.language).toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ExpansionTile(
        key: const ValueKey<String>('proofing-personal-words'),
        title: Text('Personal dictionary (${words.length})'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Added words belong to your current app profile. Keeping them '
            'between sessions depends on whether the app saves your dictionary.',
          ),
          if (words.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No personal words for this language.'),
            ),
          for (final String word in words)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(word),
              trailing: IconButton(
                tooltip: 'Remove $word from dictionary',
                onPressed: () {
                  session.vocabulary.removeWord(
                    word,
                    language: session.language,
                  );
                  session.onVocabularyChanged?.call(
                    session.vocabulary.toJson(),
                  );
                  session.refresh();
                  unawaited(_check());
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    );
  }
}
