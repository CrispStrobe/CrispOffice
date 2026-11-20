import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'studio_arabic_morph_host.dart';
import 'studio_download_catalog.dart';
import 'studio_download_strings.dart';
import 'studio_font_pack_host.dart';
import 'studio_font_pack_setup.dart';
import 'studio_hunspell_host.dart';
import 'studio_hunspell_setup.dart';
import 'studio_spacy_host.dart';
import 'studio_spacy_setup.dart';
import 'studio_strings.dart';

/// Reviews local language coverage and app-owned downloads. Opening or changing
/// a language never downloads data; Install opens the package review, where
/// the download remains an explicit action.
Future<void> showStudioDownloadsManager(
  BuildContext context, {
  Set<String> languages = const <String>{},
  StudioLanguage language = StudioLanguage.en,
  StudioFontPackHost? fontPacks,
}) {
  // Dialogs are pushed on the root navigator, above the workspace's own
  // Directionality; carry the caller's direction into the route.
  final direction =
      Directionality.maybeOf(context) ??
      (language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr);
  return showDialog<void>(
    context: context,
    builder: (_) => Directionality(
      textDirection: direction,
      child: StudioDownloadsManager(
        languages: languages,
        language: language,
        hunspell: studioHunspellHost,
        morphology: studioArabicMorphHost,
        spacy: studioSpacyHost,
        fontPacks: fontPacks ?? studioFontPackHost,
      ),
    ),
  );
}

/// The Language downloads overview: one uniform, full-width row per
/// downloadable package ([studioDownloadCatalog]), grouped by language, with
/// a sticky header and footer.
class StudioDownloadsManager extends StatefulWidget {
  const StudioDownloadsManager({
    super.key,
    required this.hunspell,
    required this.morphology,
    required this.spacy,
    this.languages = const <String>{},
    this.language = StudioLanguage.en,
    this.fontPacks,
    this.activity,
    this.openLicence,
  });
  final StudioHunspellHost hunspell;
  final StudioArabicMorphHost morphology;
  final StudioSpacyHost spacy;
  final Set<String> languages;

  /// Optional open font packs; null keeps the manager language-only (tests).
  final StudioFontPackHost? fontPacks;

  /// The UI language of the dialog's own text.
  final StudioLanguage language;

  /// Downloads started by the review dialogs; defaults to the process-wide
  /// [studioDownloadActivity].
  final StudioDownloadActivity? activity;

  /// Opens a licence page; defaults to the external browser.
  final Future<void> Function(Uri url)? openLicence;
  @override
  State<StudioDownloadsManager> createState() => _StudioDownloadsManagerState();
}

/// Rows at least this wide put status and actions in aligned columns;
/// narrower rows place them under the text.
const double studioDownloadWideRow = 560;

class _StudioDownloadsManagerState extends State<StudioDownloadsManager> {
  bool _busy = false;
  String? _error;
  final _scroll = ScrollController();

  StudioDownloadActivity get _activity =>
      widget.activity ?? studioDownloadActivity;

  @override
  void initState() {
    super.initState();
    widget.hunspell.addListener(_changed);
    widget.morphology.addListener(_changed);
    widget.spacy.addListener(_changed);
    widget.fontPacks?.addListener(_changed);
    _activity.addListener(_changed);
    unawaited(
      _run(() async {
        await Future.wait<void>(<Future<void>>[
          widget.hunspell.refresh(),
          widget.morphology.refresh(),
          widget.spacy.refresh(),
          if (widget.fontPacks case final packs?) packs.refresh(),
        ]);
      }),
    );
  }

  @override
  void dispose() {
    widget.hunspell.removeListener(_changed);
    widget.morphology.removeListener(_changed);
    widget.spacy.removeListener(_changed);
    widget.fontPacks?.removeListener(_changed);
    _activity.removeListener(_changed);
    _scroll.dispose();
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

  Future<void> _review(StudioDownloadItem item) {
    final fontHost = widget.fontPacks;
    final fontStatus = item.review == StudioDownloadReview.fontPack
        ? fontHost?.statuses
              .where((candidate) => candidate.pack.id == item.id)
              .firstOrNull
        : null;
    // The host can refresh its inventory after a row was rendered.
    if (item.review == StudioDownloadReview.fontPack &&
        (fontHost == null || fontStatus == null)) {
      return Future<void>.value();
    }
    final direction = Directionality.of(context);
    return showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: direction,
        child: switch (item.review) {
          StudioDownloadReview.dictionaries => StudioHunspellSetupDialog(
            host: widget.hunspell,
            morphHost: widget.morphology,
          ),
          StudioDownloadReview.analysis => StudioSpacySetupDialog(
            host: widget.spacy,
          ),
          StudioDownloadReview.fontPack => StudioFontPackSetupDialog(
            status: fontStatus!,
            host: fontHost!,
          ),
        },
      ),
    );
  }

  Future<void> _openLicence(Uri url) async {
    final open = widget.openLicence;
    if (open != null) return open(url);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Widget _section(String title, {Key? key}) {
    final theme = Theme.of(context);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: <Widget>[
          Flexible(
            flex: 3,
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
        ],
      ),
    );
  }

  Widget _banner(String text) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // The space the dialog route offers, not the window: correct in split
    // views and in tests that resize only the surface.
    builder: (context, constraints) => _dialog(
      context,
      Size(
        constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width,
        constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height,
      ),
    ),
  );

  Widget _dialog(BuildContext context, Size screen) {
    final theme = Theme.of(context);
    final strings = StudioDownloadStrings(widget.language);
    final items = studioDownloadCatalog(
      hunspell: widget.hunspell,
      morphology: widget.morphology,
      spacy: widget.spacy,
      fontPacks: widget.fontPacks,
      activity: _activity,
    );
    final titles = <String, String>{
      for (final item in items) item.id: item.title,
    };
    final offered = items
        .where((item) => item.state != StudioDownloadState.unavailable)
        .toList();
    final installed = items
        .where((item) => item.state == StudioDownloadState.installed)
        .toList();
    final installedBytes = installed
        .where((item) => item.exactSizeOnDisk)
        .fold<int>(0, (sum, item) => sum + item.bytes);
    final groups = <String, List<StudioDownloadItem>>{};
    for (final item in items) {
      (groups[item.language] ??= <StudioDownloadItem>[]).add(item);
    }
    int rank(String code) {
      if (code == studioFontGroup) {
        return studioDownloadLanguageOrder.length + 1;
      }
      final index = studioDownloadLanguageOrder.indexOf(code);
      return index < 0 ? studioDownloadLanguageOrder.length : index;
    }

    final languages = groups.keys.toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });

    final compact = screen.width < 600;
    final inset = compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 16)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
    final sidePadding = compact ? 16.0 : 24.0;
    final contentWidth = math.max(
      200.0,
      math.min(880.0, screen.width - inset.horizontal - 2 * sidePadding),
    );

    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final included = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final label in strings.includedItems)
          Chip(
            avatar: Icon(
              Icons.check_circle_outline,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            label: Text(label),
            labelStyle: theme.textTheme.labelMedium,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
    final children = <Widget>[
      Text(strings.intro, style: muted),
      if (widget.languages.isNotEmpty) ...<Widget>[
        _section(strings.forThisDocument),
        for (final language in (widget.languages.toList()..sort()))
          _banner(strings.coverage(language)),
      ],
      if (compact)
        // Phones: a collapsed panel keeps the package rows near the top.
        ExpansionTile(
          key: const ValueKey('downloads-included'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            strings.included,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(strings.includedNote, style: muted),
          children: <Widget>[included],
        )
      else ...<Widget>[
        _section(strings.included, key: const ValueKey('downloads-included')),
        included,
        const SizedBox(height: 6),
        Text(strings.includedNote, style: muted),
      ],
      if (items.isEmpty) ...<Widget>[
        _section(strings.available),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: <Widget>[
              Icon(
                Icons.cloud_off_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(strings.empty, textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
      for (final language in languages) ...<Widget>[
        _section(
          strings.languageName(language),
          key: ValueKey('downloads-section-$language'),
        ),
        for (final item in groups[language]!)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StudioDownloadTile(
              item: item,
              strings: strings,
              requiredTitle: titles[item.requires],
              enabled:
                  !_busy &&
                  (item.kind != StudioDownloadKind.fonts ||
                      !(widget.fontPacks?.busy ?? false)),
              onReview: () => _review(item),
              onRemove: item.remove == null ? null : () => _run(item.remove!),
              onLicence: () => _openLicence(item.licenceUrl),
            ),
          ),
      ],
      if (widget.fontPacks case final packs?
          when packs.statuses.isEmpty) ...<Widget>[
        _section(strings.languageName(studioFontGroup)),
        Text(packs.error ?? strings.fontsUnavailable, style: muted),
      ],
      if (widget.fontPacks case final packs?
          when packs.statuses.isNotEmpty && packs.error != null)
        Text(
          packs.error!,
          style: muted?.copyWith(color: theme.colorScheme.error),
        ),
    ];

    return AlertDialog(
      insetPadding: inset,
      titlePadding: EdgeInsets.fromLTRB(sidePadding, 20, sidePadding, 12),
      contentPadding: EdgeInsets.symmetric(horizontal: sidePadding),
      actionsPadding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 12),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.download_for_offline_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(strings.title)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            strings.summary(
              installed.length,
              offered.length,
              _isolate(context, _megabytes(installedBytes)),
            ),
            key: const ValueKey('downloads-summary'),
            style: muted,
          ),
          if (_busy || (widget.fontPacks?.busy ?? false)) ...<Widget>[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      content: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SizedBox(
          width: contentWidth,
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              key: const ValueKey('downloads-scroll'),
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FocusTraversalGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'CrispOffice'),
          child: Text(strings.licences),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            widget.languages.isEmpty ? strings.close : strings.notNow,
          ),
        ),
      ],
    );
  }
}

String _megabytes(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

/// Brackets Latin package names and sizes with left-to-right marks inside
/// right-to-left text, so a trailing `)` and `7.0 MB` keep their order.
/// (Marks rather than isolates: the text engine applies them reliably.)
String _isolate(BuildContext context, String text) =>
    Directionality.of(context) == TextDirection.rtl
    ? '\u200E$text\u200E'
    : text;

/// One package row. Every row fills the list width; at [studioDownloadWideRow]
/// and wider the status chip and actions sit in fixed-width trailing columns
/// so they line up from row to row.
class StudioDownloadTile extends StatelessWidget {
  const StudioDownloadTile({
    super.key,
    required this.item,
    required this.strings,
    required this.onReview,
    required this.onLicence,
    this.onRemove,
    this.requiredTitle,
    this.enabled = true,
  });

  final StudioDownloadItem item;
  final StudioDownloadStrings strings;
  final VoidCallback onReview;
  final VoidCallback onLicence;
  final VoidCallback? onRemove;
  final String? requiredTitle;
  final bool enabled;

  static const double statusWidth = 184;
  static const double actionsWidth = 208;

  /// The Studio theme stretches outlined buttons to the full width.
  static final ButtonStyle _outlined = OutlinedButton.styleFrom(
    minimumSize: const Size(88, 40),
    alignment: Alignment.center,
  );
  static final ButtonStyle _filled = FilledButton.styleFrom(
    minimumSize: const Size(88, 40),
  );

  IconData get _icon => switch (item.kind) {
    StudioDownloadKind.spelling => Icons.spellcheck,
    StudioDownloadKind.morphology => Icons.account_tree_outlined,
    StudioDownloadKind.contextModel => Icons.hub_outlined,
    StudioDownloadKind.analysis => Icons.manage_search,
    StudioDownloadKind.entities => Icons.label_outline,
    StudioDownloadKind.fonts => Icons.font_download_outlined,
  };

  Widget _leading(ColorScheme scheme) {
    final installed = item.state == StudioDownloadState.installed;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: 20,
        backgroundColor: installed
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        foregroundColor: installed
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant,
        child: Icon(_icon, size: 20),
      ),
    );
  }

  Widget _status(BuildContext context, ThemeData theme) {
    final scheme = theme.colorScheme;
    final (
      Color background,
      Color foreground,
      IconData icon,
    ) = switch (item.state) {
      StudioDownloadState.installed => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle,
      ),
      StudioDownloadState.downloading => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.downloading,
      ),
      StudioDownloadState.needsRepair => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      StudioDownloadState.needsPrerequisite => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.link,
      ),
      StudioDownloadState.unavailable => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.block,
      ),
      StudioDownloadState.notInstalled => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.cloud_download_outlined,
      ),
    };
    return Container(
      key: ValueKey('download-${item.id}-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              strings.state(item, _isolate(context, _megabytes(item.bytes))),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions() {
    final review = enabled ? onReview : null;
    return switch (item.state) {
      StudioDownloadState.downloading => <Widget>[
        Tooltip(
          message: strings.cancelLabel(item.title),
          child: OutlinedButton(
            style: _outlined,
            key: ValueKey('download-${item.id}-cancel'),
            onPressed: item.cancel,
            child: Text(strings.cancel),
          ),
        ),
      ],
      StudioDownloadState.installed => <Widget>[
        if (item.kind == StudioDownloadKind.fonts)
          Tooltip(
            message: strings.details,
            child: FilledButton.tonal(
              style: _filled,
              key: ValueKey('download-${item.id}-review'),
              onPressed: review,
              child: Text(strings.details),
            ),
          ),
        Tooltip(
          message: strings.removeLabel(item.title),
          child: OutlinedButton(
            style: _outlined,
            key: ValueKey('download-${item.id}-remove'),
            onPressed: enabled ? onRemove : null,
            child: Text(strings.remove),
          ),
        ),
      ],
      StudioDownloadState.needsRepair => <Widget>[
        Tooltip(
          message: strings.installLabel(item.title),
          child: FilledButton.tonal(
            style: _filled,
            key: ValueKey('download-${item.id}-install'),
            onPressed: review,
            child: Text(strings.repair),
          ),
        ),
        if (onRemove != null)
          Tooltip(
            message: strings.removeLabel(item.title),
            child: OutlinedButton(
              style: _outlined,
              key: ValueKey('download-${item.id}-remove'),
              onPressed: enabled ? onRemove : null,
              child: Text(strings.remove),
            ),
          ),
      ],
      StudioDownloadState.notInstalled ||
      StudioDownloadState.needsPrerequisite => <Widget>[
        Tooltip(
          message: strings.installLabel(item.title),
          child: FilledButton.tonal(
            style: _filled,
            key: ValueKey('download-${item.id}-install'),
            onPressed: review,
            child: Text(strings.install),
          ),
        ),
      ],
      StudioDownloadState.unavailable => const <Widget>[],
    };
  }

  Widget _details(BuildContext context, ThemeData theme) {
    final scheme = theme.colorScheme;
    final size = _isolate(context, _megabytes(item.bytes));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final link = theme.textTheme.bodySmall?.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    );
    final requires = requiredTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _isolate(context, item.title),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: muted,
            children: <InlineSpan>[
              TextSpan(text: '${strings.kind(item.kind)} · $size · '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Tooltip(
                  message: item.licenceUrl.toString(),
                  child: Semantics(
                    container: true,
                    link: true,
                    label: strings.licenceLabel(item.licence),
                    child: InkWell(
                      key: ValueKey('download-${item.id}-licence'),
                      onTap: onLicence,
                      borderRadius: BorderRadius.circular(4),
                      child: ExcludeSemantics(
                        child: Text(item.licence, style: link),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (item.description case final description?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(description, style: muted),
          ),
        if (item.note case final note?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(strings.note(note), style: muted),
          ),
        if (item.state == StudioDownloadState.needsPrerequisite &&
            requires != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            // The Latin title is its own left-to-right run, so its
            // brackets stay in order inside Arabic text.
            child: Text.rich(
              TextSpan(
                style: muted,
                children: <InlineSpan>[
                  TextSpan(text: '${strings.requires} '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: Text(
                      requires,
                      key: ValueKey('download-${item.id}-requires'),
                      textDirection: TextDirection.ltr,
                      style: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (item.state == StudioDownloadState.unavailable &&
            item.unavailableReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(item.unavailableReason!, style: muted),
          ),
        if (item.problem case final problem?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              problem,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        if (item.state == StudioDownloadState.downloading)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(value: item.progress),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = _actions();
    return Semantics(
      container: true,
      label: '${item.title}, ${strings.state(item, _megabytes(item.bytes))}',
      child: Card.outlined(
        key: ValueKey('download-${item.id}'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= studioDownloadWideRow) {
                return Row(
                  children: <Widget>[
                    _leading(theme.colorScheme),
                    const SizedBox(width: 12),
                    Expanded(child: _details(context, theme)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: statusWidth,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _status(context, theme),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: actionsWidth,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 4,
                        children: actions,
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _leading(theme.colorScheme),
                      const SizedBox(width: 12),
                      Expanded(child: _details(context, theme)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Phones: status and actions under the text; actions
                  // move to their own line when they do not fit beside it.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _status(context, theme),
                      if (actions.isNotEmpty)
                        Wrap(spacing: 8, runSpacing: 4, children: actions),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
