import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_strings.dart';

/// Stages paragraph settings and applies the changed fields in one Undo step.
Future<bool> showStudioParagraphDialog({
  required BuildContext context,
  required WordEditorController controller,
  required StudioLanguage language,
  required OfficeLengthUnit unit,
}) async {
  if (controller.isDisposed) return false;
  if (_ParagraphTarget.canCapture(controller)) controller.commitPendingEdits();
  final target = _ParagraphTarget.capture(controller);
  return await showDialog<bool>(
        context: context,
        builder: (context) => _StudioParagraphDialog(
          controller: controller,
          target: target,
          language: language,
          unit: unit,
        ),
      ) ??
      false;
}

enum _Metric { before, after, left, right, line, special }

enum _SpecialIndent { none, firstLine, hanging }

enum _Pagination { pageBreak, columnBreak }

String _translate(StudioLanguage language, String en, String de, String ar) =>
    switch (language) {
      StudioLanguage.en => en,
      StudioLanguage.de => de,
      StudioLanguage.ar => ar,
    };

/// Read public story models directly: inspection must not create a paragraph.
List<WmlParagraph> _storyParagraphs(WordEditorController controller) {
  if (!controller.isEditingHeaderFooter) {
    return controller.document.paragraphs.toList();
  }
  final index = controller.editingSectionIndex;
  if (index < 0 || index >= controller.document.sections.length) return [];
  final section = controller.document.sections[index];
  final footer = controller.isEditingFooter;
  return switch (controller.editingHeaderFooterVariant) {
    WordHeaderFooterVariant.standard =>
      footer ? section.footer : section.header,
    WordHeaderFooterVariant.firstPage =>
      footer ? section.firstFooter : section.firstHeader,
    WordHeaderFooterVariant.evenPage =>
      footer ? section.evenFooter : section.evenHeader,
  };
}

Object _selectionIdentity(WordEditorController controller) => (
  document: controller.document,
  revision: controller.contentRevision,
  caret: controller.caret,
  paragraph: controller.caret.paragraphIndex,
  offset: controller.caret.logicalIndex,
  anchorParagraph: controller.caret.selectionAnchorParagraph,
  anchor: controller.caret.selectionAnchor,
  composing: controller.input.composing,
  note: controller.noteEditingTarget,
  comment: controller.isEditingComment ? controller.selectedComment : null,
  headerFooter: controller.isEditingHeaderFooter,
  footer: controller.isEditingFooter,
  variant: controller.editingHeaderFooterVariant,
  section: controller.isEditingHeaderFooter
      ? controller.editingSectionIndex
      : null,
  frame: controller.selectedFrame,
  editingFrame: controller.editingFrame,
  table: controller.selectedTable,
  tableBand: controller.selectedTableBand,
  visual: controller.selectedVisual,
  equation: controller.selectedEquation,
);

Object _formatIdentity(WmlParagraphProps props) => (
  before: props.spacingBefore,
  after: props.spacingAfter,
  line: props.lineSpacing,
  rule: props.lineSpacingRule,
  left: props.indent.left,
  right: props.indent.right,
  firstLine: props.indent.firstLine,
  hanging: props.indent.hanging,
  keep: props.keepTogether,
  page: props.pageBreakBefore,
  column: props.columnBreakBefore,
  explicitBefore: props.explicitSpacingBefore,
  explicitAfter: props.explicitSpacingAfter,
  explicitLine: props.explicitLineSpacing,
  explicitIndent: props.explicitIndent,
);

final class _ParagraphBounds {
  const _ParagraphBounds(this.width, this.height, this.leftMargin);

  final double width;
  final double height;
  final double leftMargin;

  static _ParagraphBounds of(
    WordEditorController controller,
    WmlParagraph paragraph,
  ) {
    final document = controller.document;
    final index = controller.isEditingHeaderFooter
        ? controller.editingSectionIndex
        : document.sectionIndexOf(paragraph);
    final section = document.sections[index];
    var width = controller.isEditingHeaderFooter
        ? section.contentWidth
        : section.columnWidth;
    // Actual cell/frame/wrapped-line boxes can be narrower than the section.
    for (final page in controller.documentLaidOut.pages) {
      for (final line in [...page.lines, ...page.header, ...page.footer]) {
        if (identical(line.sourceParagraph, paragraph) && line.boxWidth > 0) {
          width = math.min(width, line.boxWidth);
        }
      }
    }
    return _ParagraphBounds(
      width,
      section.pageSize.height,
      section.margins.left,
    );
  }

  bool matches(_ParagraphBounds other) =>
      width == other.width &&
      height == other.height &&
      leftMargin == other.leftMargin;
}

final class _ParagraphTarget {
  _ParagraphTarget({
    required this.identity,
    required this.story,
    required this.paragraphs,
    required this.properties,
    required this.bounds,
  });

  final Object identity;
  final List<WmlParagraph> story;
  final List<WmlParagraph> paragraphs;
  final List<WmlParagraphProps> properties;
  final List<_ParagraphBounds> bounds;

  static bool canCapture(WordEditorController controller) =>
      !controller.isDisposed &&
      controller.config.allowsMutation &&
      !(controller.document.restrictEditing &&
          controller.document.restrictMode != WmlRestrictMode.none) &&
      !controller.commentFormatLimited &&
      controller.noteEditingTarget == null &&
      controller.selectedVisual == null &&
      controller.selectedEquation == null &&
      (controller.selectedFrame == null || controller.editingFrame) &&
      controller.selectedTable == null &&
      controller.selectedTableBand == null;

  static _ParagraphTarget? capture(WordEditorController controller) {
    if (!canCapture(controller) || controller.document.sections.isEmpty) {
      return null;
    }
    final story = _storyParagraphs(controller);
    final range = controller.caret.normalizedRange;
    if (range.startPara < 0 ||
        range.endPara >= story.length ||
        range.startPara > range.endPara) {
      return null;
    }
    final selected = story.sublist(range.startPara, range.endPara + 1);
    return _ParagraphTarget(
      identity: _selectionIdentity(controller),
      story: List.unmodifiable(story),
      paragraphs: List.unmodifiable(selected),
      properties: [
        for (final paragraph in selected) paragraph.properties.copy(),
      ],
      bounds: [
        for (final paragraph in selected)
          _ParagraphBounds.of(controller, paragraph),
      ],
    );
  }

  bool isCurrent(WordEditorController controller) {
    if (!canCapture(controller) || identity != _selectionIdentity(controller)) {
      return false;
    }
    final current = _storyParagraphs(controller);
    if (current.length != story.length) return false;
    for (var index = 0; index < story.length; index++) {
      if (!identical(current[index], story[index])) return false;
    }
    for (var index = 0; index < paragraphs.length; index++) {
      if (_formatIdentity(paragraphs[index].properties) !=
              _formatIdentity(properties[index]) ||
          !bounds[index].matches(
            _ParagraphBounds.of(controller, paragraphs[index]),
          )) {
        return false;
      }
    }
    return true;
  }
}

final class _ParagraphPatch {
  _ParagraphPatch({
    required Map<_Metric, double> values,
    required Set<_Metric> edited,
    required this.lineRule,
    required this.lineRuleEdited,
    required this.special,
    required this.specialEdited,
    required Map<_Pagination, bool?> pagination,
    required Set<_Pagination> paginationEdited,
  }) : values = Map.unmodifiable(values),
       _edited = Set.unmodifiable(edited),
       _pagination = Map.unmodifiable(pagination),
       _paginationEdited = Set.unmodifiable(paginationEdited);

  final Map<_Metric, double> values;
  final Set<_Metric> _edited;
  final WmlLineSpacingRule? lineRule;
  final bool lineRuleEdited;
  final _SpecialIndent? special;
  final bool specialEdited;
  final Map<_Pagination, bool?> _pagination;
  final Set<_Pagination> _paginationEdited;

  void apply(WmlParagraphProps props) {
    double? edited(_Metric metric) =>
        _edited.contains(metric) ? values[metric] : null;
    final before = edited(_Metric.before);
    if (before != null && before != props.spacingBefore) {
      props.spacingBefore = before;
      props.explicitSpacingBefore = true;
    }
    final after = edited(_Metric.after);
    if (after != null && after != props.spacingAfter) {
      props.spacingAfter = after;
      props.explicitSpacingAfter = true;
    }
    final line = values[_Metric.line];
    if ((lineRuleEdited || _edited.contains(_Metric.line)) &&
        lineRule != null &&
        line != null &&
        (lineRule != props.lineSpacingRule || line != props.lineSpacing)) {
      props.lineSpacingRule = lineRule!;
      props.lineSpacing = line;
      props.explicitLineSpacing = true;
    }
    final left = edited(_Metric.left) ?? props.indent.left;
    final right = edited(_Metric.right) ?? props.indent.right;
    var first = props.indent.firstLine;
    var hanging = props.indent.hanging;
    if ((specialEdited || _edited.contains(_Metric.special)) &&
        special != null) {
      final amount = values[_Metric.special];
      if (special == _SpecialIndent.none) {
        first = 0;
        hanging = 0;
      } else if (amount != null) {
        first = special == _SpecialIndent.firstLine ? amount : 0;
        hanging = special == _SpecialIndent.hanging ? amount : 0;
      }
    }
    if (left != props.indent.left ||
        right != props.indent.right ||
        first != props.indent.firstLine ||
        hanging != props.indent.hanging) {
      props.indent = WmlIndent(
        left: left,
        right: right,
        firstLine: first,
        hanging: hanging,
      );
      props.explicitIndent = true;
    }
    for (final setting in _paginationEdited) {
      final value = _pagination[setting];
      if (value == null) continue;
      switch (setting) {
        case _Pagination.pageBreak:
          props.pageBreakBefore = value;
        case _Pagination.columnBreak:
          props.columnBreakBefore = value;
      }
    }
  }
}

class _StudioParagraphDialog extends StatefulWidget {
  const _StudioParagraphDialog({
    required this.controller,
    required this.target,
    required this.language,
    required this.unit,
  });

  final WordEditorController controller;
  final _ParagraphTarget? target;
  final StudioLanguage language;
  final OfficeLengthUnit unit;

  @override
  State<_StudioParagraphDialog> createState() => _StudioParagraphDialogState();
}

class _StudioParagraphDialogState extends State<_StudioParagraphDialog> {
  late OfficeLengthUnit _unit = widget.unit;
  WmlLineSpacingRule? _lineRule;
  _SpecialIndent? _special;
  bool _lineRuleEdited = false;
  bool _specialEdited = false;
  final _fields = <_Metric, TextEditingController>{};
  final _exact = <_Metric, double?>{};
  final _displayed = <_Metric, String>{};
  final _edited = <_Metric>{};
  final _pagination = <_Pagination, bool?>{};
  final _paginationEdited = <_Pagination>{};
  final _fieldErrors = <_Metric, String>{};
  String? _error;

  String _t(String en, String de, String ar) =>
      _translate(widget.language, en, de, ar);

  T? _common<T>(T Function(WmlParagraphProps) read) {
    final values = widget.target!.properties.map(read).toList();
    final first = values.first;
    return values.every((value) => value == first) ? first : null;
  }

  _SpecialIndent? _specialOf(WmlParagraphProps props) {
    if (props.indent.firstLine != 0 && props.indent.hanging != 0) return null;
    if (props.indent.hanging != 0) return _SpecialIndent.hanging;
    if (props.indent.firstLine != 0) return _SpecialIndent.firstLine;
    return _SpecialIndent.none;
  }

  @override
  void initState() {
    super.initState();
    if (widget.target == null) return;
    _lineRule = _common((props) => props.lineSpacingRule);
    _special = _common<_SpecialIndent?>(_specialOf);
    _pagination.addAll({
      _Pagination.pageBreak: _common((props) => props.pageBreakBefore),
      _Pagination.columnBreak: _common((props) => props.columnBreakBefore),
    });
    _exact.addAll({
      _Metric.before: _common((props) => props.spacingBefore),
      _Metric.after: _common((props) => props.spacingAfter),
      _Metric.left: _common((props) => props.indent.left),
      _Metric.right: _common((props) => props.indent.right),
      _Metric.line: _lineRule == null
          ? null
          : _common((props) => props.lineSpacing),
      _Metric.special: _special == null
          ? null
          : _common(
              (props) => _special == _SpecialIndent.hanging
                  ? props.indent.hanging
                  : props.indent.firstLine,
            ),
    });
    for (final metric in _Metric.values) {
      final text = _format(metric, _exact[metric]);
      _displayed[metric] = text;
      _fields[metric] = TextEditingController(text: text);
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  bool _isMultiplier(_Metric metric) =>
      metric == _Metric.line && _lineRule == WmlLineSpacingRule.auto;

  String _format(_Metric metric, double? value) {
    if (value == null) return '';
    final displayed = _isMultiplier(metric) ? value : _unit.fromPoints(value);
    final text = displayed
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    return text == '-0' ? '0' : text;
  }

  String _normalize(String text) => text
      .replaceAllMapped(RegExp('[٠-٩۰-۹]'), (match) {
        final code = match[0]!.codeUnitAt(0);
        return '${code >= 0x6f0 ? code - 0x6f0 : code - 0x660}';
      })
      .replaceAll('٫', '.');

  double? _value(_Metric metric) {
    final text = _fields[metric]!.text;
    if (text == _displayed[metric]) return _exact[metric];
    final normalized = _normalize(text).trim();
    if (!_isMultiplier(metric)) return _unit.parsePoints(normalized);
    if (!RegExp(r'^[+]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$').hasMatch(normalized)) {
      return null;
    }
    final value = double.tryParse(normalized.replaceAll(',', '.'));
    return value != null && value.isFinite ? value : null;
  }

  bool _enabled(_Metric metric) => switch (metric) {
    _Metric.line => _lineRule != null,
    _Metric.special => _special != null && _special != _SpecialIndent.none,
    _ => true,
  };

  Map<_Metric, double>? _readValues() {
    _fieldErrors.clear();
    final values = <_Metric, double>{};
    for (final metric in _Metric.values) {
      if (!_enabled(metric)) continue;
      final text = _fields[metric]!.text;
      if (text.trim().isEmpty && _exact[metric] == null) continue;
      final value = _value(metric);
      if (value == null || !value.isFinite) {
        _fieldErrors[metric] = _isMultiplier(metric)
            ? _t(
                'Enter a line multiplier.',
                'Zeilenfaktor eingeben.',
                'أدخل مضاعف تباعد الأسطر.',
              )
            : _t(
                'Enter a number with an optional mm, cm, in or pt unit.',
                'Zahl eingeben, optional mit mm, cm, in oder pt.',
                'أدخل رقماً، ويمكن إتباعه بـ mm أو cm أو in أو pt.',
              );
      } else {
        values[metric] = value;
      }
    }
    return _fieldErrors.isEmpty ? values : null;
  }

  void _setField(_Metric metric, double? value) {
    _exact[metric] = value;
    _displayed[metric] = _format(metric, value);
    _fields[metric]!.text = _displayed[metric]!;
  }

  void _changeUnit(OfficeLengthUnit unit) {
    final values = _readValues();
    if (values == null) {
      setState(() => _error = _numberError);
      return;
    }
    setState(() {
      _unit = unit;
      for (final metric in _Metric.values) {
        _setField(
          metric,
          values[metric] ?? (_enabled(metric) ? null : _exact[metric]),
        );
      }
      _error = null;
    });
  }

  void _changed(VoidCallback change) => setState(() {
    change();
    _fieldErrors.clear();
    _error = null;
  });

  String get _numberError => _t(
    'Check the highlighted values.',
    'Prüfen Sie die markierten Werte.',
    'تحقق من القيم المحددة.',
  );

  String? _validate(
    WmlParagraphProps before,
    WmlParagraphProps after,
    _ParagraphBounds bounds,
  ) {
    if ((before.spacingBefore != after.spacingBefore &&
            (after.spacingBefore < 0 || after.spacingBefore > bounds.height)) ||
        (before.spacingAfter != after.spacingAfter &&
            (after.spacingAfter < 0 || after.spacingAfter > bounds.height))) {
      return _t(
        'Paragraph spacing must be nonnegative and fit within a page.',
        'Absatzabstände dürfen nicht negativ sein und müssen auf eine Seite passen.',
        'يجب ألا يكون تباعد الفقرات سالباً، وأن يتسع ضمن الصفحة.',
      );
    }
    if (before.lineSpacing != after.lineSpacing ||
        before.lineSpacingRule != after.lineSpacingRule) {
      final maximum = after.lineSpacingRule == WmlLineSpacingRule.auto
          ? 20.0
          : bounds.height;
      if (after.lineSpacing <= 0 || after.lineSpacing > maximum) {
        return _t(
          'Line spacing must be greater than zero; the maximum multiplier is 20.',
          'Der Zeilenabstand muss größer als null sein; der maximale Faktor ist 20.',
          'يجب أن يكون تباعد الأسطر أكبر من صفر؛ وأقصى مضاعف هو 20.',
        );
      }
    }
    final old = before.indent;
    final next = after.indent;
    if (old.left != next.left ||
        old.right != next.right ||
        old.firstLine != next.firstLine ||
        old.hanging != next.hanging) {
      if ([
            next.left,
            next.right,
            next.firstLine,
            next.hanging,
          ].any((value) => value < 0) ||
          bounds.width - next.left - next.right - next.firstLine < 12 ||
          next.hanging > next.left + bounds.leftMargin) {
        return _t(
          'Use nonnegative indents and leave at least 12 pt of text width.',
          'Verwenden Sie nichtnegative Einzüge und lassen Sie mindestens 12 pt Textbreite.',
          'استخدم مسافات بادئة غير سالبة واترك عرضاً للنص لا يقل عن 12 pt.',
        );
      }
    }
    return null;
  }

  void _apply() {
    final target = widget.target!;
    if (!target.isCurrent(widget.controller)) {
      setState(
        () => _error = _t(
          'The document or selection changed. Close this dialog and open Paragraph again.',
          'Dokument oder Auswahl wurden geändert. Schließen Sie den Dialog und öffnen Sie Absatz erneut.',
          'تغير المستند أو التحديد. أغلق هذا الحوار وافتح إعدادات الفقرة مجدداً.',
        ),
      );
      return;
    }
    final values = _readValues();
    if (values == null) {
      setState(() => _error = _numberError);
      return;
    }
    final patch = _ParagraphPatch(
      values: values,
      edited: _edited,
      lineRule: _lineRule,
      lineRuleEdited: _lineRuleEdited,
      special: _special,
      specialEdited: _specialEdited,
      pagination: _pagination,
      paginationEdited: _paginationEdited,
    );
    var changed = false;
    for (var index = 0; index < target.properties.length; index++) {
      final before = target.properties[index];
      final after = before.copy();
      patch.apply(after);
      final error = _validate(before, after, target.bounds[index]);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      changed = changed || _formatIdentity(before) != _formatIdentity(after);
    }
    if (changed) widget.controller.applyParagraphFormat(patch.apply);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final direction = widget.language == StudioLanguage.ar
        ? TextDirection.rtl
        : TextDirection.ltr;
    if (widget.target == null) {
      return Directionality(
        textDirection: direction,
        child: AlertDialog(
          key: const ValueKey('paragraph-unavailable'),
          title: Text(_t('Paragraph', 'Absatz', 'الفقرة')),
          content: Text(
            _t(
              'Select editable document text or a header or footer to change paragraph settings.',
              'Wählen Sie bearbeitbaren Dokumenttext oder eine Kopf- oder Fußzeile für Absatzeinstellungen.',
              'حدد نصاً قابلاً للتحرير في المستند أو الرأس أو التذييل لتغيير إعدادات الفقرة.',
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('paragraph-close'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_t('Close', 'Schließen', 'إغلاق')),
            ),
          ],
        ),
      );
    }
    return Directionality(
      textDirection: direction,
      child: Dialog(
        key: const ValueKey('studio-paragraph-dialog'),
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660, maxHeight: 740),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 8),
                child: Text(
                  _t('Paragraph', 'Absatz', 'الفقرة'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('paragraph-scroll'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.target!.paragraphs.length == 1
                            ? _t(
                                'Settings apply to the current paragraph.',
                                'Die Einstellungen gelten für den aktuellen Absatz.',
                                'تُطبّق الإعدادات على الفقرة الحالية.',
                              )
                            : _t(
                                'Settings apply to selected paragraphs. Mixed values stay unchanged until edited.',
                                'Die Einstellungen gelten für die ausgewählten Absätze. Unterschiedliche Werte bleiben ohne Bearbeitung erhalten.',
                                'تُطبّق الإعدادات على الفقرات المحددة. تبقى القيم المختلفة كما هي حتى تعدّلها.',
                              ),
                      ),
                      const SizedBox(height: 16),
                      _dropdown<OfficeLengthUnit>(
                        id: 'unit',
                        label: _t(
                          'Measurements',
                          'Maßeinheiten',
                          'وحدات القياس',
                        ),
                        value: _unit,
                        values: OfficeLengthUnit.values,
                        labelOf: (unit) => switch (unit) {
                          OfficeLengthUnit.inches => _t(
                            'Inches (in)',
                            'Zoll (in)',
                            'بوصة (in)',
                          ),
                          OfficeLengthUnit.centimeters => _t(
                            'Centimetres (cm)',
                            'Zentimeter (cm)',
                            'سنتيمتر (cm)',
                          ),
                          OfficeLengthUnit.millimeters => _t(
                            'Millimetres (mm)',
                            'Millimeter (mm)',
                            'ملليمتر (mm)',
                          ),
                        },
                        onChanged: _changeUnit,
                      ),
                      _heading(_t('Spacing', 'Abstand', 'التباعد')),
                      _pair(
                        _number(
                          _Metric.before,
                          _t('Before paragraph', 'Vor Absatz', 'قبل الفقرة'),
                        ),
                        _number(
                          _Metric.after,
                          _t('After paragraph', 'Nach Absatz', 'بعد الفقرة'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pair(
                        _dropdown<WmlLineSpacingRule>(
                          id: 'line-rule',
                          label: _t(
                            'Line spacing',
                            'Zeilenabstand',
                            'تباعد الأسطر',
                          ),
                          value: _lineRule,
                          values: WmlLineSpacingRule.values,
                          labelOf: (rule) => switch (rule) {
                            WmlLineSpacingRule.auto => _t(
                              'Multiple',
                              'Mehrfach',
                              'مضاعف',
                            ),
                            WmlLineSpacingRule.exact => _t(
                              'Exactly',
                              'Genau',
                              'بالضبط',
                            ),
                            WmlLineSpacingRule.atLeast => _t(
                              'At least',
                              'Mindestens',
                              'على الأقل',
                            ),
                          },
                          onChanged: (rule) => _changed(() {
                            if (rule == _lineRule) return;
                            _lineRule = rule;
                            _lineRuleEdited = true;
                            _edited.add(_Metric.line);
                            _setField(
                              _Metric.line,
                              rule == WmlLineSpacingRule.auto ? 1.15 : 12,
                            );
                          }),
                        ),
                        _number(
                          _Metric.line,
                          _lineRule == WmlLineSpacingRule.auto
                              ? _t(
                                  'Line multiplier',
                                  'Zeilenfaktor',
                                  'مضاعف الأسطر',
                                )
                              : _t('Line height', 'Zeilenhöhe', 'ارتفاع السطر'),
                        ),
                      ),
                      _heading(
                        _t('Indentation', 'Einzüge', 'المسافات البادئة'),
                      ),
                      _pair(
                        _number(
                          _Metric.left,
                          _t(
                            'Left indent',
                            'Einzug links',
                            'المسافة البادئة اليسرى',
                          ),
                        ),
                        _number(
                          _Metric.right,
                          _t(
                            'Right indent',
                            'Einzug rechts',
                            'المسافة البادئة اليمنى',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pair(
                        _dropdown<_SpecialIndent>(
                          id: 'special-kind',
                          label: _t(
                            'Special indent',
                            'Sondereinzug',
                            'مسافة بادئة خاصة',
                          ),
                          value: _special,
                          values: _SpecialIndent.values,
                          labelOf: (kind) => switch (kind) {
                            _SpecialIndent.none => _t('None', 'Keiner', 'بلا'),
                            _SpecialIndent.firstLine => _t(
                              'First line',
                              'Erste Zeile',
                              'السطر الأول',
                            ),
                            _SpecialIndent.hanging => _t(
                              'Hanging',
                              'Hängend',
                              'معلقة',
                            ),
                          },
                          onChanged: (kind) => _changed(() {
                            if (kind == _special) return;
                            final amount = _value(_Metric.special);
                            _special = kind;
                            _specialEdited = true;
                            _edited.add(_Metric.special);
                            _setField(
                              _Metric.special,
                              kind == _SpecialIndent.none
                                  ? 0
                                  : amount != null && amount > 0
                                  ? amount
                                  : 36,
                            );
                          }),
                        ),
                        _number(_Metric.special, _t('By', 'Um', 'بمقدار')),
                      ),
                      _heading(
                        _t('Pagination', 'Seitenumbruch', 'تقسيم الصفحات'),
                      ),
                      _check(
                        _Pagination.pageBreak,
                        _t(
                          'Page break before',
                          'Seitenumbruch vor Absatz',
                          'فاصل صفحة قبل الفقرة',
                        ),
                      ),
                      _check(
                        _Pagination.columnBreak,
                        _t(
                          'Column break before',
                          'Spaltenumbruch vor Absatz',
                          'فاصل عمود قبل الفقرة',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const ValueKey('paragraph-validation'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OverflowBar(
                  spacing: 12,
                  overflowSpacing: 8,
                  alignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const ValueKey('paragraph-cancel'),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(_t('Cancel', 'Abbrechen', 'إلغاء')),
                    ),
                    FilledButton(
                      key: const ValueKey('paragraph-apply'),
                      onPressed: _apply,
                      child: Text(_t('Apply', 'Übernehmen', 'تطبيق')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (constraints.maxWidth < 480 * scale.clamp(1, 1.6)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 12), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    },
  );

  Widget _number(_Metric metric, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 6),
      Semantics(
        label: label,
        child: TextField(
          key: ValueKey('paragraph-${metric.name}'),
          controller: _fields[metric],
          enabled: _enabled(metric),
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: _t(
              'Mixed (unchanged)',
              'Unterschiedlich (unverändert)',
              'مختلفة (دون تغيير)',
            ),
            suffixText: _isMultiplier(metric)
                ? '×'
                : RegExp(
                    r'[a-z"″]+\s*$',
                    caseSensitive: false,
                  ).hasMatch(_fields[metric]!.text)
                ? null
                : _unit.suffix,
            errorText: _fieldErrors[metric],
            errorMaxLines: 3,
          ),
          onChanged: (_) => _changed(() => _edited.add(metric)),
        ),
      ),
    ],
  );

  Widget _dropdown<T extends Object>({
    required String id,
    required String label,
    required T? value,
    required List<T> values,
    required String Function(T) labelOf,
    required void Function(T) onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 6),
      DropdownButtonFormField<T>(
        key: ValueKey('paragraph-$id'),
        initialValue: value,
        isExpanded: true,
        hint: Text(
          _t(
            'Mixed (unchanged)',
            'Unterschiedlich (unverändert)',
            'مختلفة (دون تغيير)',
          ),
          overflow: TextOverflow.ellipsis,
        ),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final item in values)
            DropdownMenuItem(
              value: item,
              child: Text(labelOf(item), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    ],
  );

  Widget _check(_Pagination setting, String label) => CheckboxListTile(
    key: ValueKey('paragraph-${setting.name}'),
    value: _pagination[setting],
    tristate: _pagination[setting] == null,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(label),
    onChanged: (value) => _changed(() {
      _pagination[setting] = value;
      _paginationEdited.add(setting);
      if (value == true) {
        final other = setting == _Pagination.pageBreak
            ? _Pagination.columnBreak
            : _Pagination.pageBreak;
        _pagination[other] = false;
        _paginationEdited.add(other);
      }
    }),
  );
}
