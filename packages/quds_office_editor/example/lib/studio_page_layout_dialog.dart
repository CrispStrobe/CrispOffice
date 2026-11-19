import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_strings.dart';

/// Edit one captured Page Layout draft and commit it with a single Undo step.
Future<bool> showStudioPageLayoutDialog({
  required BuildContext context,
  required WordEditorController controller,
  required StudioLanguage language,
  OfficeLengthUnit? unit,
}) async {
  // Record existing note typing before focus leaves its editor. The layout
  // target must describe the revision after that independent edit boundary.
  controller.commitPendingEdits();
  final target = controller.capturePageLayout();
  return await showDialog<bool>(
        context: context,
        builder: (context) => StudioPageLayoutDialog(
          controller: controller,
          target: target,
          language: language,
          unit: unit ?? controller.config.lengthUnit,
        ),
      ) ??
      false;
}

enum _Metric { width, height, top, bottom, left, right, header, footer, gap }

/// Host chrome only; the document remains unchanged until Apply succeeds.
class StudioPageLayoutDialog extends StatefulWidget {
  const StudioPageLayoutDialog({
    super.key,
    required this.controller,
    required this.target,
    required this.language,
    required this.unit,
  });

  final WordEditorController controller;
  final WordPageLayoutTarget target;
  final StudioLanguage language;
  final OfficeLengthUnit unit;

  @override
  State<StudioPageLayoutDialog> createState() => _StudioPageLayoutDialogState();
}

class _StudioPageLayoutDialogState extends State<StudioPageLayoutDialog> {
  late OfficeLengthUnit _unit = widget.unit;
  late final WordPageLayoutSettings _initial = widget.target.settings;
  late int _columns = _initial.columnCount;
  late bool _separator = _initial.columnSeparator;
  late bool _differentFirstPage = _initial.differentFirstPage;
  late bool _differentOddEven = _initial.differentOddEven;
  late bool _lineNumbers = _initial.lineNumbers;
  late WmlSectionBreakKind _sectionStart = _initial.sectionStart;
  WordPageLayoutScope _scope = WordPageLayoutScope.currentSection;
  bool _customPaper = false;
  late WordPageLayoutSettings _preview = _initial;
  final Map<_Metric, TextEditingController> _fields =
      <_Metric, TextEditingController>{};
  final Map<_Metric, double> _exact = <_Metric, double>{};
  final Map<_Metric, String> _displayed = <_Metric, String>{};
  final Map<_Metric, String> _fieldErrors = <_Metric, String>{};
  String? _error;

  String _t(String en, String de, String ar) => switch (widget.language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  @override
  void initState() {
    super.initState();
    _exact.addAll(<_Metric, double>{
      _Metric.width: _initial.pageSize.width,
      _Metric.height: _initial.pageSize.height,
      _Metric.top: _initial.margins.top,
      _Metric.bottom: _initial.margins.bottom,
      _Metric.left: _initial.margins.left,
      _Metric.right: _initial.margins.right,
      _Metric.header: _initial.margins.header,
      _Metric.footer: _initial.margins.footer,
      _Metric.gap: _initial.columnSpace,
    });
    for (final metric in _Metric.values) {
      final text = _format(_exact[metric]!);
      _displayed[metric] = text;
      _fields[metric] = TextEditingController(text: text);
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _format(double points) {
    final value = _unit
        .fromPoints(points)
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    return value == '-0' ? '0' : value;
  }

  double? _value(_Metric metric) {
    final text = _fields[metric]!.text;
    // Merely opening the dialog or changing units must not round document data.
    if (text == _displayed[metric]) return _exact[metric];
    final normalized = text
        .replaceAllMapped(RegExp('[٠-٩۰-۹]'), (match) {
          final code = match[0]!.codeUnitAt(0);
          return '${code >= 0x6f0 ? code - 0x6f0 : code - 0x660}';
        })
        .replaceAll('٫', '.');
    return _unit.parsePoints(normalized);
  }

  Map<_Metric, double>? _readNumbers({bool report = false}) {
    final values = <_Metric, double>{};
    if (report) _fieldErrors.clear();
    for (final metric in _Metric.values) {
      final value = _value(metric);
      if (value == null || !value.isFinite) {
        if (report) {
          _fieldErrors[metric] = _t(
            'Enter a number, optionally followed by mm, cm, in or pt.',
            'Zahl eingeben, optional mit mm, cm, in oder pt.',
            'أدخل رقماً، ويمكن إتباعه بـ mm أو cm أو in أو pt.',
          );
        }
      } else {
        values[metric] = value;
      }
    }
    return values.length == _Metric.values.length ? values : null;
  }

  WordPageLayoutSettings? _draft({bool report = false}) {
    final values = _readNumbers(report: report);
    if (values == null) return null;
    return WordPageLayoutSettings(
      pageSize: WmlPageSize(
        width: values[_Metric.width]!,
        height: values[_Metric.height]!,
      ),
      margins: WmlPageMargins(
        top: values[_Metric.top]!,
        bottom: values[_Metric.bottom]!,
        left: values[_Metric.left]!,
        right: values[_Metric.right]!,
        header: values[_Metric.header]!,
        footer: values[_Metric.footer]!,
      ),
      columnCount: _columns,
      columnSpace: values[_Metric.gap]!,
      columnSeparator: _separator,
      sectionStart: _sectionStart,
      differentFirstPage: _differentFirstPage,
      differentOddEven: _differentOddEven,
      lineNumbers: _lineNumbers,
    );
  }

  void _changed(VoidCallback update) {
    setState(() {
      update();
      _error = null;
      _fieldErrors.clear();
      final draft = _draft();
      if (draft != null && draft.validationIssue == null) _preview = draft;
    });
  }

  void _setMetric(_Metric metric, double points) {
    _exact[metric] = points;
    _displayed[metric] = _format(points);
    _fields[metric]!.text = _displayed[metric]!;
  }

  void _changeUnit(OfficeLengthUnit unit) {
    final values = _readNumbers(report: true);
    if (values == null) {
      setState(() => _error = _numberError);
      return;
    }
    _changed(() {
      _unit = unit;
      for (final entry in values.entries) {
        _setMetric(entry.key, entry.value);
      }
    });
  }

  String get _numberError => _t(
    'Check the measurements on each tab.',
    'Prüfen Sie die Maße auf jeder Registerkarte.',
    'تحقق من القياسات في كل علامة تبويب.',
  );

  String _validationMessage(WordPageLayoutIssue issue) => switch (issue) {
    WordPageLayoutIssue.paperSize => _t(
      'Paper width and height must be greater than zero.',
      'Papierbreite und -höhe müssen größer als null sein.',
      'يجب أن يكون عرض الورق وارتفاعه أكبر من صفر.',
    ),
    WordPageLayoutIssue.margins => _t(
      'Page margins cannot be negative.',
      'Seitenränder dürfen nicht negativ sein.',
      'لا يمكن أن تكون هوامش الصفحة سالبة.',
    ),
    WordPageLayoutIssue.bodySize => _t(
      'Reduce the margins or increase the paper size to leave room for text.',
      'Verkleinern Sie die Ränder oder vergrößern Sie das Papier, damit Text Platz hat.',
      'قلل الهوامش أو زد حجم الورق لتوفير مساحة للنص.',
    ),
    WordPageLayoutIssue.headerFooterDistance => _t(
      'Header and footer distances must be nonnegative and fit within the page.',
      'Kopf- und Fußzeilenabstände müssen positiv oder null sein und auf die Seite passen.',
      'يجب ألا تكون مسافات الرأس والتذييل سالبة، وأن تقع داخل الصفحة.',
    ),
    WordPageLayoutIssue.columnCount => _t(
      'Choose between one and four equal-width columns.',
      'Wählen Sie zwischen einer und vier gleich breiten Spalten.',
      'اختر من عمود واحد إلى أربعة أعمدة متساوية العرض.',
    ),
    WordPageLayoutIssue.columnSpace => _t(
      'Column spacing cannot be negative.',
      'Der Spaltenabstand darf nicht negativ sein.',
      'لا يمكن أن يكون التباعد بين الأعمدة سالباً.',
    ),
    WordPageLayoutIssue.columnWidth => _t(
      'Reduce the column spacing or margins to leave room in every column.',
      'Verkleinern Sie Spaltenabstand oder Seitenränder, damit jede Spalte Platz hat.',
      'قلل تباعد الأعمدة أو الهوامش لتوفير مساحة داخل كل عمود.',
    ),
  };

  void _apply() {
    final draft = _draft(report: true);
    if (draft == null) {
      setState(() => _error = _numberError);
      return;
    }
    final issue = draft.validationIssue;
    if (issue != null) {
      setState(() => _error = _validationMessage(issue));
      return;
    }
    if (!widget.controller.isPageLayoutTargetCurrent(widget.target)) {
      setState(() {
        _error = _t(
          'The document changed while this dialog was open. Close it and open Page Layout again.',
          'Das Dokument wurde inzwischen geändert. Schließen Sie den Dialog und öffnen Sie Seitenlayout erneut.',
          'تغير المستند أثناء فتح هذا الحوار. أغلقه وافتح تخطيط الصفحة مرة أخرى.',
        );
      });
      return;
    }
    if (!widget.controller.applyPageLayout(
      draft,
      scope: _scope,
      target: widget.target,
    )) {
      setState(() {
        _error = _t(
          'These settings cannot be applied. Check shared section columns and editing permissions.',
          'Diese Einstellungen können nicht übernommen werden. Prüfen Sie Spalten verbundener Abschnitte und die Bearbeitungsrechte.',
          'لا يمكن تطبيق هذه الإعدادات. تحقق من أعمدة المقاطع المشتركة وإذن التحرير.',
        );
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.language == StudioLanguage.ar
        ? TextDirection.rtl
        : TextDirection.ltr,
    child: DefaultTabController(
      length: 4,
      child: Dialog(
        key: const ValueKey('studio-page-layout-dialog'),
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 12, 12, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _t('Page Layout', 'Seitenlayout', 'تخطيط الصفحة'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: _t('Close', 'Schließen', 'إغلاق'),
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _dropdown<OfficeLengthUnit>(
                  id: 'unit',
                  label: _t('Measurements', 'Maßeinheiten', 'وحدات القياس'),
                  value: _unit,
                  values: OfficeLengthUnit.values,
                  labelOf: (unit) => switch (unit) {
                    OfficeLengthUnit.millimeters => _t(
                      'Millimetres (mm)',
                      'Millimeter (mm)',
                      'ملليمتر (mm)',
                    ),
                    OfficeLengthUnit.centimeters => _t(
                      'Centimetres (cm)',
                      'Zentimeter (cm)',
                      'سنتيمتر (cm)',
                    ),
                    OfficeLengthUnit.inches => _t(
                      'Inches (in)',
                      'Zoll (in)',
                      'بوصة (in)',
                    ),
                  },
                  onChanged: _changeUnit,
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: <Widget>[
                  Tab(
                    key: const ValueKey('page-layout-tab-margins'),
                    text: _t('Margins', 'Seitenränder', 'الهوامش'),
                  ),
                  Tab(
                    key: const ValueKey('page-layout-tab-paper'),
                    text: _t('Paper', 'Papier', 'الورق'),
                  ),
                  Tab(
                    key: const ValueKey('page-layout-tab-layout'),
                    text: _t('Layout', 'Layout', 'التخطيط'),
                  ),
                  Tab(
                    key: const ValueKey('page-layout-tab-columns'),
                    text: _t('Columns', 'Spalten', 'الأعمدة'),
                  ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tabs = TabBarView(
                      children: <Widget>[
                        _scroll(_marginFields()),
                        _scroll(_paperFields()),
                        _scroll(_layoutFields()),
                        _scroll(_columnFields()),
                      ],
                    );
                    if (constraints.maxWidth >= 680) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: tabs),
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: 220,
                            child: SingleChildScrollView(
                              child: _previewPanel(compact: false),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: <Widget>[
                        Expanded(child: tabs),
                        const Divider(height: 1),
                        SizedBox(
                          height: 108,
                          child: _previewPanel(compact: true),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const ValueKey('page-layout-validation'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scope = _dropdown<WordPageLayoutScope>(
                      id: 'scope',
                      label: _t('Apply to', 'Übernehmen für', 'تطبيق على'),
                      value: _scope,
                      values: WordPageLayoutScope.values,
                      labelOf: (scope) =>
                          scope == WordPageLayoutScope.currentSection
                          ? _t('This section', 'Diesen Abschnitt', 'هذا المقطع')
                          : _t(
                              'Whole document',
                              'Gesamtes Dokument',
                              'المستند بأكمله',
                            ),
                      onChanged: (value) => _changed(() => _scope = value),
                    );
                    final buttons = Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: <Widget>[
                        TextButton(
                          key: const ValueKey('page-layout-cancel'),
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(_t('Cancel', 'Abbrechen', 'إلغاء')),
                        ),
                        FilledButton(
                          key: const ValueKey('page-layout-apply'),
                          onPressed: widget.controller.config.allowsMutation
                              ? _apply
                              : null,
                          child: Text(_t('Apply', 'Übernehmen', 'تطبيق')),
                        ),
                      ],
                    );
                    if (constraints.maxWidth >= 600) {
                      return Row(
                        children: <Widget>[
                          Expanded(child: scope),
                          const SizedBox(width: 24),
                          buttons,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        scope,
                        const SizedBox(height: 8),
                        buttons,
                      ],
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

  Widget _scroll(Widget child) =>
      SingleChildScrollView(padding: const EdgeInsets.all(24), child: child);

  Widget _dropdown<T>({
    required String id,
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) labelOf,
    required ValueChanged<T>? onChanged,
  }) => InputDecorator(
    key: ValueKey('page-layout-$id'),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      enabled: onChanged != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        items: <DropdownMenuItem<T>>[
          for (final item in values)
            DropdownMenuItem<T>(
              value: item,
              child: Text(labelOf(item), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null) onChanged(next);
              },
      ),
    ),
  );

  Widget _number(_Metric metric, String label, {bool enabled = true}) =>
      TextField(
        key: ValueKey('page-layout-${metric.name}'),
        controller: _fields[metric],
        enabled: enabled,
        textDirection: TextDirection.ltr,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(
          labelText: label,
          suffixText:
              RegExp(
                r'(mm|cm|inches|inch|in|pt|["″])\s*$',
                caseSensitive: false,
              ).hasMatch(_fields[metric]!.text)
              ? null
              : _unit.suffix,
          border: const OutlineInputBorder(),
          errorText: _fieldErrors[metric],
          errorMaxLines: 3,
        ),
        onChanged: (_) => _changed(() {
          if (metric == _Metric.width || metric == _Metric.height) {
            _customPaper = true;
          }
        }),
      );

  Widget _paired(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final width = constraints.maxWidth >= 350 * textScale
          ? (constraints.maxWidth - 16) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: <Widget>[
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );

  Widget _marginFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _paired(<Widget>[
        _number(_Metric.top, _t('Top', 'Oben', 'أعلى')),
        _number(_Metric.bottom, _t('Bottom', 'Unten', 'أسفل')),
        _number(_Metric.left, _t('Left', 'Links', 'يسار')),
        _number(_Metric.right, _t('Right', 'Rechts', 'يمين')),
      ]),
      const SizedBox(height: 20),
      Text(
        _t(
          'Enter precise measurements, for example 25 mm or 1 in.',
          'Genaue Maße eingeben, zum Beispiel 25 mm oder 1 in.',
          'أدخل قياسات دقيقة، مثل 25 mm أو 1 in.',
        ),
      ),
      const SizedBox(height: 12),
      Text(
        _t(
          'Page size and margins also apply to continuous sections sharing this page.',
          'Papiergröße und Ränder gelten auch für fortlaufende Abschnitte auf dieser Seite.',
          'ينطبق حجم الورق والهوامش أيضاً على المقاطع المستمرة التي تشترك في هذه الصفحة.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  static final Map<String, WmlPageSize> _paperSizes = <String, WmlPageSize>{
    'A4': WmlPageSize.a4(),
    'Letter': WmlPageSize.letter(),
    'Legal': WmlPageSize.legal(),
    'A3': WmlPageSize.a3(),
  };

  Widget _paperFields() {
    final width = _value(_Metric.width) ?? _preview.pageSize.width;
    final height = _value(_Metric.height) ?? _preview.pageSize.height;
    final size = WmlPageSize(width: width, height: height);
    final preset = _customPaper
        ? 'custom'
        : _paperSizes.entries
                  .where((entry) => entry.value.matches(size.portrait))
                  .map((entry) => entry.key)
                  .firstOrNull ??
              'custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _dropdown<String>(
          id: 'paper-preset',
          label: _t('Paper size', 'Papierformat', 'حجم الورق'),
          value: preset,
          values: <String>[..._paperSizes.keys, 'custom'],
          labelOf: (id) =>
              id == 'custom' ? _t('Custom', 'Benutzerdefiniert', 'مخصص') : id,
          onChanged: (id) {
            final paper = _paperSizes[id];
            if (paper == null) {
              _changed(() => _customPaper = true);
              return;
            }
            _changed(() {
              _customPaper = false;
              final next = size.isLandscape ? paper.landscape : paper.portrait;
              _setMetric(_Metric.width, next.width);
              _setMetric(_Metric.height, next.height);
            });
          },
        ),
        const SizedBox(height: 16),
        _dropdown<bool>(
          id: 'orientation',
          label: _t('Orientation', 'Ausrichtung', 'الاتجاه'),
          value: size.isLandscape,
          values: const <bool>[false, true],
          labelOf: (landscape) => landscape
              ? _t('Landscape', 'Querformat', 'أفقي')
              : _t('Portrait', 'Hochformat', 'عمودي'),
          onChanged: (landscape) => _changed(() {
            final next = landscape ? size.landscape : size.portrait;
            _setMetric(_Metric.width, next.width);
            _setMetric(_Metric.height, next.height);
          }),
        ),
        const SizedBox(height: 16),
        _paired(<Widget>[
          _number(_Metric.width, _t('Width', 'Breite', 'العرض')),
          _number(_Metric.height, _t('Height', 'Höhe', 'الارتفاع')),
        ]),
      ],
    );
  }

  Widget _layoutFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _paired(<Widget>[
        _number(
          _Metric.header,
          _t('Header from top', 'Kopfzeile von oben', 'الرأس من الأعلى'),
        ),
        _number(
          _Metric.footer,
          _t('Footer from bottom', 'Fußzeile von unten', 'التذييل من الأسفل'),
        ),
      ]),
      const SizedBox(height: 8),
      CheckboxListTile(
        key: const ValueKey('page-layout-first-page'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t('Different first page', 'Erste Seite anders', 'صفحة أولى مختلفة'),
        ),
        value: _differentFirstPage,
        onChanged: (value) => _changed(() => _differentFirstPage = value!),
      ),
      CheckboxListTile(
        key: const ValueKey('page-layout-odd-even'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t(
            'Different odd and even pages',
            'Gerade und ungerade Seiten anders',
            'صفحات فردية وزوجية مختلفة',
          ),
        ),
        subtitle: Text(
          _t(
            'Applies to the whole document.',
            'Gilt für das gesamte Dokument.',
            'ينطبق على المستند بأكمله.',
          ),
        ),
        value: _differentOddEven,
        onChanged: (value) => _changed(() => _differentOddEven = value!),
      ),
      const SizedBox(height: 16),
      _dropdown<WmlSectionBreakKind>(
        id: 'section-start',
        label: _t('Section start', 'Abschnittsbeginn', 'بداية المقطع'),
        value: _sectionStart,
        values: WmlSectionBreakKind.values,
        labelOf: (kind) => switch (kind) {
          WmlSectionBreakKind.nextPage => _t(
            'New page',
            'Neue Seite',
            'صفحة جديدة',
          ),
          WmlSectionBreakKind.continuous => _t(
            'Continuous',
            'Fortlaufend',
            'مستمر',
          ),
          WmlSectionBreakKind.oddPage => _t(
            'Odd page',
            'Ungerade Seite',
            'صفحة فردية',
          ),
          WmlSectionBreakKind.evenPage => _t(
            'Even page',
            'Gerade Seite',
            'صفحة زوجية',
          ),
        },
        onChanged: _scope == WordPageLayoutScope.currentSection
            ? (value) => _changed(() => _sectionStart = value)
            : null,
      ),
      if (_scope == WordPageLayoutScope.wholeDocument)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _t(
              'Existing section starts are preserved.',
              'Bestehende Abschnittsanfänge bleiben erhalten.',
              'يتم الحفاظ على بدايات المقاطع الحالية.',
            ),
          ),
        ),
      const SizedBox(height: 8),
      CheckboxListTile(
        key: const ValueKey('page-layout-line-numbers'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t(
            'Show line numbers',
            'Zeilennummern anzeigen',
            'إظهار أرقام الأسطر',
          ),
        ),
        value: _lineNumbers,
        onChanged: (value) => _changed(() => _lineNumbers = value!),
      ),
    ],
  );

  Widget _columnFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _dropdown<int>(
        id: 'columns',
        label: _t(
          'Equal-width columns',
          'Gleich breite Spalten',
          'أعمدة متساوية العرض',
        ),
        value: _columns,
        values: <int>[1, 2, 3, 4, if (_columns < 1 || _columns > 4) _columns],
        labelOf: (count) => '$count',
        onChanged: (value) => _changed(() => _columns = value),
      ),
      const SizedBox(height: 16),
      _number(_Metric.gap, _t('Spacing', 'Abstand', 'التباعد')),
      const SizedBox(height: 8),
      CheckboxListTile(
        key: const ValueKey('page-layout-column-separator'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t('Line between columns', 'Zwischenlinie', 'خط بين الأعمدة'),
        ),
        value: _separator,
        onChanged: _columns > 1
            ? (value) => _changed(() => _separator = value!)
            : null,
      ),
      const SizedBox(height: 12),
      Text(
        _t(
          'Column width: ${_format(_preview.columnWidth)} ${_unit.suffix}',
          'Spaltenbreite: ${_format(_preview.columnWidth)} ${_unit.suffix}',
          'عرض العمود: ${_format(_preview.columnWidth)} ${_unit.suffix}',
        ),
      ),
    ],
  );

  Widget _previewPanel({required bool compact}) {
    final palette = Theme.of(context).colorScheme;
    final picture = Semantics(
      label: _t(
        'Page layout preview',
        'Vorschau des Seitenlayouts',
        'معاينة تخطيط الصفحة',
      ),
      image: true,
      child: CustomPaint(
        key: const ValueKey('page-layout-preview'),
        painter: _PagePreviewPainter(_preview, palette),
        child: const SizedBox.expand(),
      ),
    );
    final labels = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _t('Preview', 'Vorschau', 'معاينة'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${_format(_preview.pageSize.width)} × ${_format(_preview.pageSize.height)} ${_unit.suffix}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!compact) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            _t('Text area', 'Textbereich', 'مساحة النص'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${_format(_preview.contentWidth)} × ${_format(_preview.contentHeight)} ${_unit.suffix}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.all(compact ? 12 : 20),
      child: compact
          ? Row(
              children: <Widget>[
                SizedBox(width: 74, height: 84, child: picture),
                const SizedBox(width: 12),
                Expanded(child: labels),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(height: 250, child: picture),
                const SizedBox(height: 16),
                labels,
              ],
            ),
    );
  }
}

class _PagePreviewPainter extends CustomPainter {
  _PagePreviewPainter(this.layout, this.palette);

  final WordPageLayoutSettings layout;
  final ColorScheme palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.validationIssue != null) return;
    final scale = math.min(
      (size.width - 8) / layout.pageSize.width,
      (size.height - 8) / layout.pageSize.height,
    );
    if (!scale.isFinite || scale <= 0) return;
    final pageSize = Size(
      layout.pageSize.width * scale,
      layout.pageSize.height * scale,
    );
    final page = Rect.fromLTWH(
      (size.width - pageSize.width) / 2,
      (size.height - pageSize.height) / 2,
      pageSize.width,
      pageSize.height,
    );
    canvas.drawRect(
      page.shift(const Offset(2, 2)),
      Paint()..color = palette.shadow.withValues(alpha: 0.14),
    );
    canvas.drawRect(page, Paint()..color = palette.surface);
    canvas.drawRect(
      page,
      Paint()
        ..color = palette.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final body = Rect.fromLTRB(
      page.left + layout.margins.left * scale,
      page.top + layout.margins.top * scale,
      page.right - layout.margins.right * scale,
      page.bottom - layout.margins.bottom * scale,
    );
    canvas.drawRect(
      body,
      Paint()..color = palette.primary.withValues(alpha: 0.08),
    );
    final line = Paint()
      ..color = palette.onSurfaceVariant.withValues(alpha: 0.55)
      ..strokeWidth = 0.7;
    final columns = layout.columnCount;
    final columnWidth = layout.columnWidth * scale;
    final gap = layout.columnSpace * scale;
    for (var column = 0; column < columns; column++) {
      final left = body.left + column * (columnWidth + gap);
      var index = 0;
      for (var y = body.top + 5; y < body.bottom - 3; y += 5) {
        final fraction = index++ % 5 == 4 ? 0.68 : 0.94;
        canvas.drawLine(
          Offset(left + 2, y),
          Offset(left + columnWidth * fraction, y),
          line,
        );
      }
      if (layout.columnSeparator && column < columns - 1) {
        final x = left + columnWidth + gap / 2;
        canvas.drawLine(Offset(x, body.top), Offset(x, body.bottom), line);
      }
    }
    final accent = Paint()
      ..color = palette.primary.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final headerY = page.top + layout.margins.header * scale;
    final footerY = page.bottom - layout.margins.footer * scale;
    canvas.drawLine(
      Offset(body.left, headerY),
      Offset(body.right, headerY),
      accent,
    );
    canvas.drawLine(
      Offset(body.left, footerY),
      Offset(body.right, footerY),
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant _PagePreviewPainter oldDelegate) =>
      !layout.matches(oldDelegate.layout) || palette != oldDelegate.palette;
}
