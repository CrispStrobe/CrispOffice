import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

typedef StudioPrintTranslation =
    String Function(String en, String de, String ar);

enum _Paper {
  original(null),
  a4((width: 595.28, height: 841.89)),
  a3((width: 841.89, height: 1190.55)),
  letter((width: 612, height: 792)),
  legal((width: 612, height: 1008));

  const _Paper(this.points);
  final ({double width, double height})? points;
}

enum _Scale { original, actual, fit, fitWidth, custom }

typedef _Layout = ({
  _Paper paper,
  bool? landscape,
  double? margin,
  _Scale scale,
  int percent,
  bool border,
  bool? gridlines,
  bool? headings,
  bool activeSheetOnly,
});

typedef _Rendered = ({Uint8List bytes, PdfFile file});

class StudioPrintSource {
  const StudioPrintSource({
    required this.document,
    required this.fonts,
    required this.title,
    this.activeSheet = 1,
    this.openPdf,
  });

  // An Office model, or the serialized bytes for an existing PDF.
  final Object document;
  final OfficeFontSet fonts;
  final String title;
  final int activeSheet;
  final PdfFile? openPdf;

  bool get isSheet => document is SmlWorkbook;
  bool get lockedLayout => openPdf?.encrypted ?? false;

  _Rendered _render(_Layout layout) {
    final input = document;
    final Uint8List bytes;
    if (input is SmlWorkbook) {
      final scalePercent = switch (layout.scale) {
        _Scale.actual => 100,
        _Scale.custom => layout.percent,
        _ => null,
      };
      final fit = switch (layout.scale) {
        _Scale.original => null,
        _Scale.fit || _Scale.fitWidth => true,
        _ => false,
      };
      bytes = OfficePdfExport.workbook(
        input,
        title: title,
        workbookFileName: title,
        fonts: fonts,
        sheetFrom: layout.activeSheetOnly ? activeSheet : 1,
        sheetTo: layout.activeSheetOnly ? activeSheet : null,
        options: PdfSheetPrintOptions(
          useWorksheetPageSetup: true,
          paperOverride: layout.paper.points,
          landscapeOverride: layout.landscape,
          marginOverride: layout.margin,
          scalePercentOverride: scalePercent,
          fitOverride: fit,
          fitWidthOnly: layout.scale == _Scale.fitWidth,
          pageBorder: layout.border,
          gridlinesOverride: layout.gridlines,
          headingsOverride: layout.headings,
        ),
      );
    } else {
      bytes = switch (input) {
        WmlDocument doc => OfficePdfExport.word(
          doc,
          title: title,
          fonts: fonts,
        ),
        PmlPresentation deck => OfficePdfExport.presentation(
          deck,
          title: title,
          fonts: fonts,
        ),
        Uint8List pdf => pdf,
        _ => throw ArgumentError('Unsupported print source'),
      };
    }
    final file = lockedLayout ? openPdf! : PdfFile.open(bytes);
    if (file.pageCount == 0) throw StateError('No printable pages');
    return (bytes: bytes, file: file);
  }
}

_Rendered _placeLayout(({_Rendered original, _Layout layout}) request) {
  final (original: original, layout: layout) = request;
  final file = original.file;
  final placed = file.placePagesOnPaper(
    List<int>.generate(file.pageCount, (index) => index),
    PdfPaperPlacement(
      paper: layout.paper.points,
      landscape: layout.landscape,
      margin: layout.margin ?? 0,
      scale: switch (layout.scale) {
        _Scale.actual => 1,
        _Scale.custom => layout.percent / 100,
        _ => null,
      },
      border: layout.border,
    ),
  );
  return (bytes: placed, file: PdfFile.open(placed));
}

_Rendered _renderLayout(({StudioPrintSource source, _Layout layout}) request) =>
    request.source._render(request.layout);

PdfDisplayList _previewPage(({PdfFile file, int index}) request) =>
    request.file.displayList(request.index);

Uint8List _extractRange(({PdfFile file, int from, int to}) request) =>
    request.file.extractPages(
      List<int>.generate(
        request.to - request.from + 1,
        (i) => request.from + i,
      ),
    );

class StudioPrintResult {
  const StudioPrintResult(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final double width;
  final double height;
}

class StudioPrintDialog extends StatefulWidget {
  const StudioPrintDialog({
    super.key,
    required this.source,
    required this.printing,
    required this.t,
  });

  final StudioPrintSource source;
  final bool printing;
  final StudioPrintTranslation t;

  @override
  State<StudioPrintDialog> createState() => _StudioPrintDialogState();
}

class _StudioPrintDialogState extends State<StudioPrintDialog> {
  static const _Layout _original = (
    paper: _Paper.original,
    landscape: null,
    margin: null,
    scale: _Scale.original,
    percent: 100,
    border: false,
    gridlines: null,
    headings: null,
    activeSheetOnly: false,
  );

  _Paper _paper = _Paper.original;
  bool? _landscape;
  double? _margin;
  _Scale _scale = _Scale.original;
  bool _border = false;
  bool? _gridlines;
  bool? _headings;
  bool _activeSheetOnly = false;
  bool _selectedPages = false;
  final _percent = TextEditingController(text: '100');
  final _from = TextEditingController();
  final _to = TextEditingController();
  _Rendered? _base;
  _Rendered? _rendered;
  _Layout? _renderedLayout;
  PdfDisplayList? _preview;
  var _page = 0;
  var _busy = false;
  var _failed = false;
  var _submitting = false;
  Timer? _debounce;

  String _t(String en, String de, String ar) => widget.t(en, de, ar);
  int get _count => _rendered?.file.pageCount ?? 0;
  int? get _scalePercent => int.tryParse(_percent.text.trim());
  bool get _validScale =>
      _scale != _Scale.custom ||
      (_scalePercent ?? 0) >= 10 && (_scalePercent ?? 0) <= 400;

  _Layout get _layout => (
    paper: _paper,
    landscape: _landscape,
    margin: _margin,
    scale: _scale,
    percent: _scale == _Scale.custom ? _scalePercent ?? 100 : 100,
    border: _border,
    gridlines: _gridlines,
    headings: _headings,
    activeSheetOnly: _activeSheetOnly,
  );

  ({int first, int last})? get _range {
    if (_count == 0) return null;
    if (!_selectedPages) return (first: 0, last: _count - 1);
    final first = int.tryParse(_from.text.trim());
    final last = _to.text.trim().isEmpty
        ? _count
        : int.tryParse(_to.text.trim());
    if (first == null ||
        last == null ||
        first < 1 ||
        last < first ||
        last > _count) {
      return null;
    }
    return (first: first - 1, last: last - 1);
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _percent.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _change(VoidCallback update, {bool typing = false}) {
    _debounce?.cancel();
    setState(() {
      update();
      _failed = false;
    });
    if (typing) {
      _debounce = Timer(const Duration(milliseconds: 250), _refresh);
    } else {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (_busy || !_validScale) return;
    final requested = _layout;
    setState(() => _busy = true);
    try {
      final rendered = _renderedLayout == requested
          ? _rendered!
          : await _render(requested);
      if (!mounted || requested != _layout) return;
      _rendered = rendered;
      _renderedLayout = requested;
      final range = _range;
      _page = _page.clamp(range?.first ?? 0, range?.last ?? _count - 1);
      final page = _page;
      final preview = await compute(_previewPage, (
        file: rendered.file,
        index: page,
      ), debugLabel: 'Render print preview page');
      if (mounted && requested == _layout && page == _page) {
        setState(() => _preview = preview);
      }
    } on Object {
      if (mounted && requested == _layout) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (requested != _layout && _debounce?.isActive != true) {
          unawaited(_refresh());
        } else if (!_failed &&
            _validScale &&
            requested == _layout &&
            _preview?.page.index != _page) {
          unawaited(_refresh());
        }
      }
    }
  }

  Future<_Rendered> _render(_Layout layout) async {
    final source = widget.source;
    if (source.isSheet) {
      return compute(_renderLayout, (
        source: source,
        layout: layout,
      ), debugLabel: 'Paginate workbook');
    }
    final _Rendered original =
        _base ??
        await compute(_renderLayout, (
          source: source,
          layout: _original,
        ), debugLabel: 'Prepare source pages');
    if (!mounted) return original;
    _base = original;
    if (layout == _original || source.lockedLayout) return original;
    return compute(_placeLayout, (
      original: original,
      layout: layout,
    ), debugLabel: 'Place pages on paper');
  }

  void _changeRange(VoidCallback change) {
    setState(() {
      change();
      final range = _range;
      if (range != null) _page = _page.clamp(range.first, range.last);
    });
    if (_preview?.page.index != _page) unawaited(_refresh());
  }

  Future<void> _submit() async {
    final rendered = _rendered;
    final range = _range;
    if (!_ready || rendered == null || range == null) return;
    setState(() => _submitting = true);
    try {
      final bytes = range.first == 0 && range.last == _count - 1
          ? rendered.bytes
          : await compute(_extractRange, (
              file: rendered.file,
              from: range.first,
              to: range.last,
            ), debugLabel: 'Select output pages');
      if (!mounted) return;
      final page = rendered.file.pageAt(range.first);
      Navigator.of(
        context,
      ).pop(StudioPrintResult(bytes, page.width, page.height));
    } on Object {
      if (mounted) {
        setState(() {
          _submitting = false;
          _failed = true;
        });
      }
    }
  }

  bool get _ready =>
      !_submitting &&
      !_busy &&
      !_failed &&
      _validScale &&
      _renderedLayout == _layout &&
      _range != null &&
      _preview?.page.index == _page &&
      _preview?.error == null;

  void _reset() => _change(() {
    _paper = _original.paper;
    _landscape = _original.landscape;
    _margin = _original.margin;
    _scale = _original.scale;
    _percent.text = '${_original.percent}';
    _border = _original.border;
    _gridlines = _original.gridlines;
    _headings = _original.headings;
    _activeSheetOnly = _original.activeSheetOnly;
    _selectedPages = false;
    _from.clear();
    _to.clear();
    _page = 0;
  });

  Widget _choice<T>(
    String label,
    T value,
    Map<T, String> choices,
    ValueChanged<T> change,
  ) {
    // The selected value is a non-null wrapper even for a document default.
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (final entry in choices.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _submitting ? null : (next) => change(next as T),
        ),
      ),
    );
  }

  Widget _numbers(
    TextEditingController controller,
    String label,
    VoidCallback update,
  ) => TextField(
    controller: controller,
    enabled: !_submitting,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, isDense: true),
    onChanged: (_) => update(),
  );

  Widget _settings() {
    final original = _t(
      'Document settings',
      'Dokumenteinstellungen',
      'إعدادات المستند',
    );
    final locked = widget.source.lockedLayout;
    return ListView(
      primary: false,
      padding: const EdgeInsets.all(16),
      children: [
        if (locked)
          Text(
            _t(
              'This PDF is protected. Output uses the original page layout and range.',
              'Diese PDF-Datei ist geschützt. Ausgabe mit ursprünglichem Seitenlayout und Seitenbereich.',
              'ملف PDF محمي. يستخدم الإخراج تخطيط الصفحات ونطاقها الأصليين.',
            ),
          ),
        if (!locked) ...[
          if (widget.source.isSheet) ...[
            _choice(
              _t('Sheets', 'Tabellenblätter', 'الأوراق'),
              _activeSheetOnly,
              {
                false: _t(
                  'Entire workbook',
                  'Ganze Arbeitsmappe',
                  'المصنف بالكامل',
                ),
                true: _t('Active sheet', 'Aktives Blatt', 'الورقة النشطة'),
              },
              (value) => _change(() => _activeSheetOnly = value),
            ),
            const SizedBox(height: 12),
          ],
          _choice(_t('Paper size', 'Papierformat', 'حجم الورق'), _paper, {
            _Paper.original: original,
            _Paper.a4: 'A4',
            _Paper.a3: 'A3',
            _Paper.letter: _t('US Letter', 'US Letter', 'أمريكي Letter'),
            _Paper.legal: _t('US Legal', 'US Legal', 'أمريكي Legal'),
          }, (value) => _change(() => _paper = value)),
          const SizedBox(height: 12),
          _choice(
            _t('Orientation', 'Ausrichtung', 'الاتجاه'),
            (_landscape,),
            {
              (null,): original,
              (false,): _t('Portrait', 'Hochformat', 'عمودي'),
              (true,): _t('Landscape', 'Querformat', 'أفقي'),
            },
            (value) => _change(() => _landscape = value.$1),
          ),
          const SizedBox(height: 12),
          _choice(
            _t('Margins', 'Seitenränder', 'الهوامش'),
            (_margin,),
            {
              (null,): original,
              (0.0,): _t('None', 'Keine', 'بدون'),
              (18.0,): _t('Narrow (6 mm)', 'Schmal (6 mm)', 'ضيقة (6 مم)'),
              (36.0,): _t('Medium (13 mm)', 'Mittel (13 mm)', 'متوسطة (13 مم)'),
              (72.0,): _t('Wide (25 mm)', 'Breit (25 mm)', 'عريضة (25 مم)'),
            },
            (value) => _change(() => _margin = value.$1),
          ),
          const SizedBox(height: 12),
          _choice(_t('Scaling', 'Skalierung', 'التحجيم'), _scale, {
            _Scale.original: original,
            _Scale.actual: _t(
              'Actual size (100%)',
              'Originalgröße (100 %)',
              'الحجم الفعلي (100٪)',
            ),
            _Scale.fit: widget.source.isSheet
                ? _t(
                    'Fit to one page',
                    'Auf eine Seite einpassen',
                    'ملاءمة صفحة واحدة',
                  )
                : _t(
                    'Shrink to fit',
                    'Auf Seitengröße verkleinern',
                    'تصغير لملاءمة الصفحة',
                  ),
            if (widget.source.isSheet)
              _Scale.fitWidth: _t(
                'Fit all columns',
                'Alle Spalten einpassen',
                'ملاءمة جميع الأعمدة',
              ),
            _Scale.custom: _t(
              'Custom percentage',
              'Eigener Prozentsatz',
              'نسبة مخصصة',
            ),
          }, (value) => _change(() => _scale = value)),
          if (_scale == _Scale.custom) ...[
            const SizedBox(height: 12),
            _numbers(
              _percent,
              _t(
                'Scale (10–400%)',
                'Skalierung (10–400 %)',
                'المقياس (10–400٪)',
              ),
              () => _change(() {}, typing: true),
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(_t('Page border', 'Seitenrahmen', 'إطار الصفحة')),
            value: _border,
            onChanged: _submitting
                ? null
                : (value) => _change(() => _border = value!),
          ),
          if (widget.source.isSheet) ...[
            _sheetChoice(
              _t('Gridlines', 'Gitternetzlinien', 'خطوط الشبكة'),
              _gridlines,
              (value) => _gridlines = value,
            ),
            const SizedBox(height: 12),
            _sheetChoice(
              _t(
                'Row and column headings',
                'Zeilen- und Spaltenüberschriften',
                'عناوين الصفوف والأعمدة',
              ),
              _headings,
              (value) => _headings = value,
            ),
            const SizedBox(height: 12),
          ],
          _choice(
            _t('Pages', 'Seiten', 'الصفحات'),
            _selectedPages,
            {
              false: _t('All pages', 'Alle Seiten', 'جميع الصفحات'),
              true: _t('Page range', 'Seitenbereich', 'نطاق الصفحات'),
            },
            (value) => _changeRange(() {
              if (value && _from.text.isEmpty) _from.text = '${_page + 1}';
              _selectedPages = value;
            }),
          ),
          if (_selectedPages) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _numbers(
                    _from,
                    _t('From', 'Von', 'من'),
                    () => _changeRange(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _numbers(
                    _to,
                    _t('To', 'Bis', 'إلى'),
                    () => _changeRange(() {}),
                  ),
                ),
              ],
            ),
            if (_count > 0 && _range == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _t(
                    'Enter a range from 1 to $_count.',
                    'Geben Sie einen Bereich von 1 bis $_count ein.',
                    'أدخل نطاقًا من 1 إلى $_count.',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _sheetChoice(String label, bool? value, ValueChanged<bool?> update) =>
      _choice(
        label,
        (value,),
        {
          (null,): _t('Sheet settings', 'Blatteinstellungen', 'إعدادات الورقة'),
          (true,): _t('Show', 'Anzeigen', 'إظهار'),
          (false,): _t('Hide', 'Ausblenden', 'إخفاء'),
        },
        (next) => _change(() => update(next.$1)),
      );

  Widget _paperPreview() {
    final colors = Theme.of(context).colorScheme;
    final range = _range;
    final preview = _preview;
    final pending = _busy || _renderedLayout != _layout;
    final failed = _failed || preview?.error != null;
    return Column(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (preview != null && preview.error == null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: math.max(
                              1.0,
                              math.min(
                                constraints.maxWidth - 24,
                                (constraints.maxHeight - 24) *
                                    preview.page.width /
                                    preview.page.height,
                              ),
                            ),
                            child: PdfPageThumb(
                              key: ObjectKey(preview),
                              list: preview,
                            ),
                          ),
                        ),
                      ),
                    if (pending && _validScale && !failed)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(),
                      ),
                    if (!_validScale || failed)
                      Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              !_validScale
                                  ? _t(
                                      'Enter a scale from 10 to 400%.',
                                      'Geben Sie 10 bis 400 % ein.',
                                      'أدخل مقياسًا بين 10 و400٪.',
                                    )
                                  : _t(
                                      'Could not prepare the selected output.',
                                      'Die gewählte Ausgabe konnte nicht vorbereitet werden.',
                                      'تعذر تجهيز الإخراج المحدد.',
                                    ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: _t('Previous page', 'Vorherige Seite', 'الصفحة السابقة'),
              onPressed:
                  _busy || _submitting || range == null || _page <= range.first
                  ? null
                  : () => _changeRange(() => _page--),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              _count == 0
                  ? _t('Preview', 'Vorschau', 'معاينة')
                  : _t(
                      'Page ${_page + 1} of $_count',
                      'Seite ${_page + 1} von $_count',
                      'الصفحة ${_page + 1} من $_count',
                    ),
            ),
            IconButton(
              tooltip: _t('Next page', 'Nächste Seite', 'الصفحة التالية'),
              onPressed:
                  _busy || _submitting || range == null || _page >= range.last
                  ? null
                  : () => _changeRange(() => _page++),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.printing
        ? _t('Print', 'Drucken', 'طباعة')
        : _t('Export PDF', 'PDF exportieren', 'تصدير PDF');
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Text(action),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      content: SizedBox(
        width: math.min(850.0, size.width * .87),
        height: math.min(600.0, size.height * .66),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final settings = _settings();
            final preview = _paperPreview();
            return constraints.maxWidth >= 580
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 280, child: settings),
                      const SizedBox(width: 8),
                      Expanded(child: preview),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: preview),
                      Expanded(child: settings),
                    ],
                  );
          },
        ),
      ),
      actions: [
        if (!widget.source.lockedLayout)
          TextButton(
            onPressed: _submitting ? null : _reset,
            child: Text(_t('Reset', 'Zurücksetzen', 'إعادة تعيين')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('Cancel', 'Abbrechen', 'إلغاء')),
        ),
        FilledButton(
          autofocus: true,
          onPressed: _ready ? _submit : null,
          child: Text(action),
        ),
      ],
    );
  }
}
