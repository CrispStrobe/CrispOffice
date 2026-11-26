import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_window.dart';

/// Measures a chrome label at the user's text scale, including Arabic metrics.
double studioChromeLineHeight(BuildContext context, double fontSize) {
  // Material supplies bodyMedium below the host's build context. Match that
  // style here as well, including its line height, before measuring a label.
  final style = Theme.of(context).textTheme.bodyMedium!;
  final painter = TextPainter(
    text: TextSpan(
      text: 'Agالعربية',
      style: style.copyWith(fontSize: fontSize),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Ribbon presentation is local to its subtree; dialogs and other workspaces
/// cannot accidentally change one another's command labels.
class StudioRibbonStyle extends InheritedWidget {
  const StudioRibbonStyle({
    super.key,
    required super.child,
    this.compact = true,
    this.showCommandLabels = true,
    this.showGroupLabels = false,
  });

  final bool compact;
  final bool showCommandLabels;
  final bool showGroupLabels;

  static StudioRibbonStyle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioRibbonStyle>();

  @override
  bool updateShouldNotify(StudioRibbonStyle oldWidget) =>
      compact != oldWidget.compact ||
      showCommandLabels != oldWidget.showCommandLabels ||
      showGroupLabels != oldWidget.showGroupLabels;
}

/// Compact Office-style command used only in the example host chrome.
class StudioCmd extends StatelessWidget {
  const StudioCmd({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.foreground,
    this.onPressed,
    this.selected = false,
    this.tooltip,
    this.isMenu = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Color foreground;
  final VoidCallback? onPressed;
  final bool selected;
  final String? tooltip;
  final bool isMenu;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final style = StudioRibbonStyle.maybeOf(context);
    final compact = style?.compact ?? true;
    final showLabel = (style?.showCommandLabels ?? true) && label.isNotEmpty;
    final color = enabled ? (selected ? accent : foreground) : Colors.grey;
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      selected: selected,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip ?? label,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            width: showLabel
                ? (compact ? 68 : 86)
                : (compact ? 36 : 44) + (isMenu ? 12 : 0),
            constraints: BoxConstraints(minHeight: compact ? 32 : 40),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 6,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      icon,
                      size: compact ? 18 : 21,
                      color: enabled ? accent : Colors.grey,
                    ),
                    if (isMenu)
                      Icon(Icons.arrow_drop_down, size: 14, color: color),
                  ],
                ),
                if (showLabel)
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: color),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact ribbon entry that reveals full, readable commands on demand.
class StudioCommandMenu extends StatelessWidget {
  const StudioCommandMenu({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.foreground,
    required this.commands,
    this.currentValue,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Color foreground;
  final List<StudioCmd> commands;
  final String? currentValue;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = commands.indexWhere(
      (command) => command.selected && command.onPressed != null,
    );
    final firstEnabled = selectedIndex >= 0
        ? selectedIndex
        : commands.indexWhere((command) => command.onPressed != null);
    return MenuAnchor(
      // Switching ribbon controls should dismiss this menu and perform the
      // clicked action in the same gesture.
      consumeOutsideTap: false,
      menuChildren: <Widget>[
        for (var index = 0; index < commands.length; index++)
          Tooltip(
            message: commands[index].tooltip ?? commands[index].label,
            child: Semantics(
              selected: commands[index].selected,
              child: MenuItemButton(
                // Move keyboard focus into the submenu so its Escape and arrow-key
                // shortcuts take precedence over document/workspace shortcuts.
                autofocus: index == firstEnabled,
                leadingIcon: Icon(commands[index].icon, size: 19),
                trailingIcon: commands[index].selected
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onPressed: commands[index].onPressed,
                child: Text(commands[index].label),
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => StudioCmd(
        icon: icon,
        label: label,
        tooltip: currentValue == null ? label : '$label: $currentValue',
        accent: accent,
        foreground: foreground,
        isMenu: true,
        onPressed: commands.any((command) => command.onPressed != null)
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
      ),
    );
  }
}

/// Icon-only ribbon button, matching the dense Office Home toolbar.
class StudioIconCmd extends StatelessWidget {
  const StudioIconCmd({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.accent,
    this.foreground = const Color(0xFF333333),
    this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final Color accent;
  final Color foreground;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final side = StudioRibbonStyle.maybeOf(context)?.compact == false
        ? 40.0
        : 32.0;
    return Semantics(
      label: tooltip,
      button: true,
      enabled: enabled,
      selected: selected,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              size: 18,
              color: enabled ? (selected ? accent : foreground) : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paste button with an Office-style options menu.
class StudioPasteCmd extends StatelessWidget {
  const StudioPasteCmd({
    super.key,
    required this.accent,
    required this.foreground,
    required this.pasteLabel,
    required this.keepSourceLabel,
    required this.mergeLabel,
    required this.textOnlyLabel,
    this.onPaste,
    this.onKeepSource,
    this.onMerge,
    this.onTextOnly,
  });

  final Color accent;
  final Color foreground;
  final String pasteLabel;
  final String keepSourceLabel;
  final String mergeLabel;
  final String textOnlyLabel;
  final VoidCallback? onPaste;
  final VoidCallback? onKeepSource;
  final VoidCallback? onMerge;
  final VoidCallback? onTextOnly;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPaste != null;
    return Tooltip(
      message: '$pasteLabel (Ctrl+V)',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            onTap: onPaste,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.content_paste,
                    size: 18,
                    color: enabled ? accent : Colors.grey,
                  ),
                  if (StudioRibbonStyle.maybeOf(context)?.showCommandLabels ??
                      true)
                    Text(
                      pasteLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: enabled ? foreground : Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ),
          PopupMenuButton<OfficePasteMode>(
            enabled: enabled,
            tooltip: pasteLabel,
            padding: EdgeInsets.zero,
            onSelected: (OfficePasteMode mode) {
              switch (mode) {
                case OfficePasteMode.keepSource:
                  (onKeepSource ?? onPaste)?.call();
                case OfficePasteMode.mergeFormatting:
                  (onMerge ?? onPaste)?.call();
                case OfficePasteMode.keepTextOnly:
                  (onTextOnly ?? onPaste)?.call();
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<OfficePasteMode>>[
                  PopupMenuItem<OfficePasteMode>(
                    value: OfficePasteMode.keepSource,
                    child: Text(keepSourceLabel),
                  ),
                  PopupMenuItem<OfficePasteMode>(
                    value: OfficePasteMode.mergeFormatting,
                    child: Text(mergeLabel),
                  ),
                  PopupMenuItem<OfficePasteMode>(
                    value: OfficePasteMode.keepTextOnly,
                    child: Text(textOnlyLabel),
                  ),
                ],
            child: Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: enabled ? foreground : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

enum StudioFaceStyle { regular, bold, italic, boldItalic }

/// Compact ribbon combo for font family, style, or size.
class StudioCombo<T> extends StatelessWidget {
  const StudioCombo({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onSelected,
    this.width = 112,
    this.enabled = true,
    this.tooltip,
    this.previewFamily,
    this.searchHint,
    this.noMatchesLabel,
    this.searchAction,
  });

  final T value;
  final List<T> items;
  final String Function(T value) labelOf;
  final ValueChanged<T>? onSelected;
  final double width;
  final bool enabled;
  final String? tooltip;
  final String? Function(T value)? previewFamily;
  final String? searchHint;
  final String? noMatchesLabel;
  final WidgetBuilder? searchAction;

  Future<void> _showSearch(BuildContext context, String hint) async {
    var matches = items;
    final selected = await showDialog<T>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          actions: [if (searchAction case final action?) action(dialogContext)],
          content: SizedBox(
            width: 340,
            height: 360,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: hint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (query) {
                    final filter = query.trim().toLowerCase();
                    setState(() {
                      matches = items.where((item) {
                        return labelOf(item).toLowerCase().contains(filter);
                      }).toList();
                    });
                  },
                  onSubmitted: (_) {
                    if (matches.length == 1) {
                      Navigator.of(dialogContext).pop(matches.single);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: matches.isEmpty
                      ? Center(child: Text(noMatchesLabel ?? ''))
                      : ListView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final item = matches[index];
                            return ListTile(
                              dense: true,
                              selected: item == value,
                              title: Text(
                                labelOf(item),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: previewFamily?.call(item),
                                ),
                              ),
                              onTap: () =>
                                  Navigator.of(dialogContext).pop(item),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (context.mounted && selected != null) onSelected?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final field = Container(
      width: width,
      height: (studioChromeLineHeight(context, 11) + 8)
          .clamp(28.0, double.infinity)
          .toDouble(),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(3),
        color: enabled ? scheme.surface : scheme.surfaceContainerHighest,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              labelOf(value),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: enabled
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: 0.45),
                fontFamily: previewFamily?.call(value),
              ),
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: enabled
                ? scheme.onSurfaceVariant
                : scheme.onSurface.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
    final interactive = enabled && onSelected != null;
    final hint = searchHint;
    return Tooltip(
      message: tooltip ?? labelOf(value),
      child: hint != null
          ? InkWell(
              onTap: interactive ? () => _showSearch(context, hint) : null,
              child: field,
            )
          : PopupMenuButton<T>(
              enabled: interactive,
              tooltip: '',
              padding: EdgeInsets.zero,
              onSelected: onSelected,
              itemBuilder: (context) => <PopupMenuEntry<T>>[
                for (final item in items)
                  PopupMenuItem<T>(
                    value: item,
                    child: Text(
                      labelOf(item),
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: previewFamily?.call(item),
                      ),
                    ),
                  ),
              ],
              child: field,
            ),
    );
  }
}

class StudioRibbonGroup extends StatelessWidget {
  const StudioRibbonGroup({
    super.key,
    required this.id,
    required this.title,
    required this.children,
  });

  final String id;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final style = StudioRibbonStyle.maybeOf(context);
    return Padding(
      key: ValueKey('ribbon-group-$id'),
      padding: EdgeInsets.symmetric(
        horizontal: style?.compact == false ? 6 : 3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(child: Row(children: children)),
          if (style?.showGroupLabels ?? false)
            Text(
              title,
              style: TextStyle(
                fontSize: 9,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class StudioRibbonStrip extends StatefulWidget {
  const StudioRibbonStrip({
    super.key,
    required this.groups,
    this.previousTooltip = 'Previous commands',
    this.nextTooltip = 'More commands',
  });

  final List<StudioRibbonGroup> groups;
  final String previousTooltip;
  final String nextTooltip;

  static double preferredHeight(
    BuildContext context, {
    bool compact = true,
    bool showCommandLabels = true,
    bool showGroupLabels = false,
  }) {
    final iconHeight = compact ? 18.0 : 21.0;
    final commandHeight =
        (iconHeight +
                8 +
                (showCommandLabels
                    ? studioChromeLineHeight(context, 10) * 2
                    : 0))
            .clamp(compact ? 32.0 : 40.0, double.infinity);
    // Includes both command padding and the scrollbar's reserved bottom space.
    return (commandHeight +
            14 +
            (showGroupLabels ? studioChromeLineHeight(context, 9) : 0))
        .ceilToDouble()
        .clamp(compact ? 64.0 : 78.0, double.infinity)
        .toDouble();
  }

  @override
  State<StudioRibbonStrip> createState() => _StudioRibbonStripState();
}

class _StudioRibbonStripState extends State<StudioRibbonStrip> {
  final ScrollController _scroll = ScrollController();
  bool _back = false;
  bool _forward = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
    _scheduleUpdate();
  }

  @override
  void didUpdateWidget(StudioRibbonStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _update();
    });
  }

  void _update() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final back = _scroll.position.extentBefore > 1;
    final forward = _scroll.position.extentAfter > 1;
    if (back != _back || forward != _forward) {
      setState(() {
        _back = back;
        _forward = forward;
      });
    }
  }

  void _move(int direction) {
    final position = _scroll.position;
    _scroll.animateTo(
      (position.pixels + direction * position.viewportDimension * 0.75).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Row(
      children: <Widget>[
        if (_back || _forward)
          SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: widget.previousTooltip,
              onPressed: _back ? () => _move(-1) : null,
              icon: Icon(
                rtl ? Icons.chevron_right : Icons.chevron_left,
                size: 18,
              ),
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _scheduleUpdate();
              return false;
            },
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: ListView(
                controller: _scroll,
                primary: false,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
                children: <Widget>[
                  for (int i = 0; i < widget.groups.length; i++) ...<Widget>[
                    widget.groups[i],
                    if (i < widget.groups.length - 1)
                      const VerticalDivider(width: 10, indent: 4, endIndent: 4),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_back || _forward)
          SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: widget.nextTooltip,
              onPressed: _forward ? () => _move(1) : null,
              icon: Icon(
                rtl ? Icons.chevron_left : Icons.chevron_right,
                size: 18,
              ),
            ),
          ),
      ],
    );
  }
}

class StudioTabChip extends StatelessWidget {
  const StudioTabChip({
    super.key,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? accent
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class StudioAppSwitcher extends StatelessWidget {
  const StudioAppSwitcher({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Material(
            color: selected
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 34,
                child: Icon(icon, size: 17, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StudioPaneTitle extends StatelessWidget {
  const StudioPaneTitle({super.key, required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: accent.withValues(alpha: 0.1),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

/// Office-style caption button (minimize / maximize / close).
class StudioCaptionButton extends StatelessWidget {
  const StudioCaptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.close = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: close
              ? const Color(0xFFE81123)
              : Colors.white.withValues(alpha: 0.16),
          child: SizedBox(
            width: 46,
            height: double.infinity,
            child: Icon(icon, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Drag region that moves the desktop window, Office title-bar style.
class StudioDragRegion extends StatelessWidget {
  const StudioDragRegion({super.key, required this.child, this.onDoubleTap});

  final Widget child;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        StudioWindow.drag();
      },
      onDoubleTap: onDoubleTap,
      child: child,
    );
  }
}

class StudioMetaChip extends StatelessWidget {
  const StudioMetaChip({
    super.key,
    required this.label,
    required this.accent,
    this.tone,
  });

  final String label;
  final Color accent;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final Color color = tone ?? accent;
    return Container(
      margin: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
