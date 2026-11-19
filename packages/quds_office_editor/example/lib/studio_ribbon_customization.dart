import 'package:flutter/material.dart';

import 'studio_ribbon_preferences.dart';

typedef StudioRibbonText = String Function(String en, String de, String ar);

class StudioRibbonChoice {
  const StudioRibbonChoice(this.id, this.label, {this.required = false});

  final String id;
  final String label;
  final bool required;
}

/// Configures the current application's ribbon without changing document data.
class StudioRibbonCustomization extends StatefulWidget {
  const StudioRibbonCustomization({
    super.key,
    required this.preferences,
    required this.appId,
    required this.appLabel,
    required this.tabs,
    required this.groupsForTab,
    required this.initialTab,
    required this.text,
  });

  final StudioRibbonPreferences preferences;
  final String appId;
  final String appLabel;
  final List<StudioRibbonChoice> tabs;
  final List<StudioRibbonChoice> Function(String tab) groupsForTab;
  final String initialTab;
  final StudioRibbonText text;

  @override
  State<StudioRibbonCustomization> createState() =>
      _StudioRibbonCustomizationState();
}

class _StudioRibbonCustomizationState extends State<StudioRibbonCustomization> {
  late String _selectedTab = widget.initialTab;
  StudioRibbonPreferences get _prefs => widget.preferences;
  StudioRibbonText get _t => widget.text;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _prefs,
    builder: (context, _) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 12, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _t(
                        'Customize Ribbon',
                        'Menüband anpassen',
                        'تخصيص الشريط',
                      ),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: _t('Close', 'Schließen', 'إغلاق'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      '${widget.appLabel} · ${_t('Changes apply immediately', 'Änderungen werden sofort übernommen', 'تطبق التغييرات فوراً')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const ValueKey('ribbon-setting-compact'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        _t(
                          'Compact spacing',
                          'Kompakte Abstände',
                          'تباعد مضغوط',
                        ),
                      ),
                      value: _prefs.compact,
                      onChanged: _prefs.setCompact,
                    ),
                    SwitchListTile(
                      key: const ValueKey('ribbon-setting-command-labels'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        _t(
                          'Show command labels',
                          'Befehlsnamen anzeigen',
                          'إظهار أسماء الأوامر',
                        ),
                      ),
                      subtitle: Text(
                        _t(
                          'Full names are always available in tooltips.',
                          'Die vollständigen Namen sind immer als Tooltips verfügbar.',
                          'تتوفر الأسماء الكاملة دائماً في التلميحات.',
                        ),
                      ),
                      value: _prefs.showCommandLabels,
                      onChanged: _prefs.setShowCommandLabels,
                    ),
                    SwitchListTile(
                      key: const ValueKey('ribbon-setting-group-labels'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        _t(
                          'Show group labels',
                          'Gruppennamen anzeigen',
                          'إظهار أسماء المجموعات',
                        ),
                      ),
                      value: _prefs.showGroupLabels,
                      onChanged: _prefs.setShowGroupLabels,
                    ),
                    const Divider(),
                    Text(
                      _t(
                        'Choose visible tabs and groups, then change their order with the arrows.',
                        'Wählen Sie sichtbare Registerkarten und Gruppen und ändern Sie deren Reihenfolge mit den Pfeilen.',
                        'اختر علامات التبويب والمجموعات الظاهرة ثم غيّر ترتيبها باستخدام الأسهم.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final tabs = _choicePanel(
                          title: _t('Tabs', 'Registerkarten', 'علامات التبويب'),
                          scope: StudioRibbonPreferences.tabsScope(
                            widget.appId,
                          ),
                          choices: widget.tabs,
                          selectedId: _selectedTab,
                          onSelected: (id) => setState(() => _selectedTab = id),
                        );
                        final groups = _choicePanel(
                          title: _t('Groups', 'Gruppen', 'المجموعات'),
                          scope: StudioRibbonPreferences.groupsScope(
                            widget.appId,
                            _selectedTab,
                          ),
                          choices: widget.groupsForTab(_selectedTab),
                        );
                        if (constraints.maxWidth < 580) {
                          return Column(
                            children: <Widget>[
                              tabs,
                              const SizedBox(height: 12),
                              groups,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: tabs),
                            const SizedBox(width: 16),
                            Expanded(child: groups),
                          ],
                        );
                      },
                    ),
                    if (_prefs.saveError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _t(
                            'Your changes are active, but preferences could not be saved for the next launch.',
                            'Ihre Änderungen sind aktiv, konnten aber nicht für den nächsten Start gespeichert werden.',
                            'تغييراتك نشطة ولكن تعذر حفظ التفضيلات للتشغيل التالي.',
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: <Widget>[
                  TextButton.icon(
                    key: const ValueKey('ribbon-reset'),
                    onPressed: _prefs.reset,
                    icon: const Icon(Icons.restore),
                    label: Text(
                      _t(
                        'Restore all defaults',
                        'Alle Standardwerte wiederherstellen',
                        'استعادة كل الإعدادات الافتراضية',
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_t('Done', 'Fertig', 'تم')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _choicePanel({
    required String title,
    required String scope,
    required List<StudioRibbonChoice> choices,
    String? selectedId,
    ValueChanged<String>? onSelected,
  }) {
    final byId = <String, StudioRibbonChoice>{
      for (final choice in choices) choice.id: choice,
    };
    final ids = _prefs.orderedIds(scope, byId.keys);
    // File stays at the leading edge, where desktop users expect to find it.
    if (ids.remove('file')) ids.insert(0, 'file');
    final visibleCount = choices
        .where(
          (choice) => choice.required || _prefs.isVisible(scope, choice.id),
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Container(
          height: 260,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ListView.builder(
            key: ValueKey('ribbon-choices-$scope'),
            primary: false,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: ids.length,
            itemBuilder: (context, index) {
              final choice = byId[ids[index]]!;
              final visible =
                  choice.required || _prefs.isVisible(scope, choice.id);
              final canHide =
                  !choice.required && (!visible || visibleCount > 1);
              return Material(
                color: selectedId == choice.id
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.transparent,
                child: InkWell(
                  key: ValueKey('ribbon-choice-$scope-${choice.id}'),
                  onTap: onSelected == null
                      ? null
                      : () => onSelected(choice.id),
                  child: Row(
                    children: <Widget>[
                      Checkbox(
                        key: ValueKey('ribbon-visible-$scope-${choice.id}'),
                        value: visible,
                        onChanged: canHide
                            ? (value) =>
                                  _prefs.setVisible(scope, choice.id, value!)
                            : null,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(choice.label),
                        ),
                      ),
                      IconButton(
                        key: ValueKey('ribbon-up-$scope-${choice.id}'),
                        visualDensity: VisualDensity.compact,
                        tooltip:
                            '${_t('Move up', 'Nach oben', 'نقل لأعلى')}: ${choice.label}',
                        onPressed:
                            index > 0 &&
                                choice.id != 'file' &&
                                ids[index - 1] != 'file'
                            ? () => _move(scope, ids, index, index - 1)
                            : null,
                        icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                      ),
                      IconButton(
                        key: ValueKey('ribbon-down-$scope-${choice.id}'),
                        visualDensity: VisualDensity.compact,
                        tooltip:
                            '${_t('Move down', 'Nach unten', 'نقل لأسفل')}: ${choice.label}',
                        onPressed: index < ids.length - 1 && choice.id != 'file'
                            ? () => _move(scope, ids, index, index + 1)
                            : null,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _move(String scope, List<String> ids, int from, int to) {
    final ordered = List<String>.of(ids);
    ordered.insert(to, ordered.removeAt(from));
    _prefs.setOrder(scope, ordered);
  }
}
