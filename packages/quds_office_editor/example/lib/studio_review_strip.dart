import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_strings.dart';

/// Writing, language and tracked-change actions of the Studio footer.
///
/// It listens to the session's coalesced [WordProofingSession.status] and
/// rebuilds for controller changes only when a shown value changes, so
/// typing and proofing progress do not repaint the footer per keystroke. The
/// workspace keeps one instance per controller, language and layout, so its
/// own rebuilds do not rebuild this strip either.
class StudioReviewStrip extends StatefulWidget {
  const StudioReviewStrip({
    super.key,
    required this.controller,
    required this.language,
    required this.compact,
  });

  final WordEditorController controller;
  final StudioLanguage language;
  final bool compact;

  @override
  State<StudioReviewStrip> createState() => _StudioReviewStripState();
}

typedef _StripChrome = ({int pending, String? language, bool hasResults});

class _StudioReviewStripState extends State<StudioReviewStrip> {
  WordEditorController get _word => widget.controller;
  WordProofingSession? _session;
  late _StripChrome _chrome;
  int _pendingRevision = -1;
  int _pending = 0;

  String _t(String en, String de, String ar) => switch (widget.language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(StudioReviewStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, _word)) {
      oldWidget.controller.removeListener(_onController);
      _session?.status.removeListener(_onStatus);
      _pendingRevision = -1;
      _attach();
    }
  }

  void _attach() {
    _word.addListener(_onController);
    _session = _word.proofing..status.addListener(_onStatus);
    _chrome = _read();
  }

  @override
  void dispose() {
    _word.removeListener(_onController);
    _session?.status.removeListener(_onStatus);
    super.dispose();
  }

  _StripChrome _read() {
    final revision = _word.contentRevision;
    if (revision != _pendingRevision) {
      _pendingRevision = revision;
      _pending = _word.document.revisions
          .where((revision) => revision.accepted == null)
          .length;
    }
    final phase = _word.proofing.status.value.phase;
    return (
      pending: _pending,
      language: _word.textProofingTarget?.language,
      hasResults:
          phase == WordProofingPhase.partial ||
          phase == WordProofingPhase.complete,
    );
  }

  void _onController() {
    if (!mounted) return;
    final session = _word.proofing;
    if (!identical(session, _session)) {
      _session?.status.removeListener(_onStatus);
      _session = session..status.addListener(_onStatus);
    }
    final next = _read();
    if (next != _chrome) setState(() => _chrome = next);
  }

  void _onStatus() {
    if (!mounted) return;
    setState(() => _chrome = _read());
  }

  @override
  Widget build(BuildContext context) {
    final session = _word.proofing;
    final status = session.status.value;
    final pending = _chrome.pending;
    final language =
        _chrome.language ??
        (_chrome.hasResults ? _t('Mixed', 'Gemischt', 'مختلط') : '');
    final count = status.issueCount;
    final String issues;
    final IconData issuesIcon;
    switch (status.phase) {
      case WordProofingPhase.checking:
        issues = _t('Checking…', 'Prüfung läuft …', 'جارٍ التدقيق…');
        issuesIcon = Icons.hourglass_top;
      case WordProofingPhase.waiting:
        issues = _t(
          'Waiting to check…',
          'Warten auf Prüfung …',
          'بانتظار توقف الكتابة…',
        );
        issuesIcon = Icons.more_horiz;
      case WordProofingPhase.paused:
        issues = _t(
          'Live checking paused',
          'Automatische Prüfung pausiert',
          'التدقيق التلقائي متوقف',
        );
        issuesIcon = Icons.pause_circle_outline;
      case WordProofingPhase.notChecked:
        issues = _t('Not checked yet', 'Noch nicht geprüft', 'لم يُدقّق بعد');
        issuesIcon = Icons.spellcheck;
      case WordProofingPhase.partial:
        issues = _t(
          '${count == 1 ? '1 issue' : '$count issues'} · partial check',
          '${count == 1 ? '1 Hinweis' : '$count Hinweise'} · teilweise geprüft',
          '$count ملاحظات · تدقيق جزئي',
        );
        issuesIcon = Icons.info_outline;
      case WordProofingPhase.complete:
        issues = count == 0
            ? _t(
                'No writing issues',
                'Keine Schreibhinweise',
                'لا توجد ملاحظات',
              )
            : count == 1
            ? _t('1 writing issue', '1 Schreibhinweis', 'ملاحظة واحدة')
            : _t(
                '$count writing issues',
                '$count Schreibhinweise',
                '$count ملاحظات',
              );
        issuesIcon = count == 0 ? Icons.check_circle_outline : Icons.spellcheck;
    }
    final changes = pending == 1
        ? _t('1 change', '1 Änderung', 'تغيير واحد')
        : _t('$pending changes', '$pending Änderungen', '$pending تغييرات');
    final compact = widget.compact;
    Widget action(
      IconData icon,
      String label,
      String tooltip,
      VoidCallback? onTap,
    ) {
      final button = compact
          ? IconButton(
              onPressed: onTap,
              tooltip: tooltip,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              icon: Icon(icon, size: 14, color: Colors.white),
            )
          : TextButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 14, color: Colors.white),
              label: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
      return compact ? button : Tooltip(message: tooltip, child: button);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: action(
            issuesIcon,
            issues,
            status.message.isEmpty || status.message == issues
                ? issues
                : '$issues\n${status.message}',
            _word.openReviewPane,
          ),
        ),
        if (language.isNotEmpty)
          Flexible(
            child: action(
              Icons.language,
              language,
              _t(
                'Language and checking',
                'Sprache und Prüfung',
                'اللغة والتدقيق',
              ),
              _word.showTextProofingOptions,
            ),
          ),
        Flexible(
          child: action(
            Icons.track_changes,
            changes,
            _t(
              'Review tracked changes',
              'Nachverfolgte Änderungen prüfen',
              'مراجعة التغييرات المتعقبة',
            ),
            () => _word.openReviewPane(tab: WordReviewPaneTab.changes),
          ),
        ),
      ],
    );
  }
}
