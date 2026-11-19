import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_proofing_harper/quds_proofing_harper.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';

import 'sample_library.dart';
import 'studio_about.dart';
import 'studio_chrome.dart';
import 'studio_files.dart';
import 'studio_find_pane.dart';
import 'studio_linguistic_analysis.dart';
import 'studio_mail.dart';
import 'studio_strings.dart';
import 'studio_pdf_gallery.dart';
import 'studio_pdf_gallery_dialog.dart';
import 'studio_pdf_office.dart';
import 'studio_pdf_tools.dart';
import 'studio_pdf_surface.dart';
import 'studio_hunspell_host.dart';
import 'studio_hunspell_setup.dart';
import 'studio_spacy_host.dart';
import 'studio_spacy_setup.dart';
import 'studio_window.dart';
import 'studio_zotero.dart';

enum SuiteApp { word, excel, powerpoint, pdf }

enum SuiteLook { light, dark, highContrast }

enum _SavePhase { idle, picking, saving }

enum _WordLinkKind { web, bookmark, file }

enum _RibbonTab {
  file,
  home,
  insert,
  layout,
  review,
  formulas,
  data,
  design,
  transitions,
  animations,
  view,
}

class SuiteWorkspace extends StatefulWidget {
  const SuiteWorkspace({super.key, this.zoteroTransportFactory});

  /// Creates a connection owned by one Zotero workspace. Hosts may supply
  /// their own client configuration; the workspace disposes it when closed.
  final StudioZoteroTransport Function()? zoteroTransportFactory;

  @override
  State<SuiteWorkspace> createState() => _SuiteWorkspaceState();
}

class _SuiteWorkspaceState extends State<SuiteWorkspace> {
  SuiteApp _app = SuiteApp.word;
  SuiteLook _look = SuiteLook.light;
  OfficeInteractionMode _mode = OfficeInteractionMode.editing;
  _RibbonTab _tab = _RibbonTab.home;
  StudioLanguage _language = StudioLanguage.en;
  bool get _arabic => _language == StudioLanguage.ar;
  set _arabic(bool value) =>
      _language = value ? StudioLanguage.ar : StudioLanguage.en;
  StudioStrings get _strings => StudioStrings(_language);
  String _t(String en, String de, String ar) => switch (_language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };
  var _wordRulers = true;
  var _sheetGridlines = true;
  var _sheetHeaders = true;
  var _slideHandles = true;
  var _showNotes = false;
  var _showComments = false;
  var _showOutline = false;
  var _showRibbonGroupLabels = false;
  OfficeLengthUnit _lengthUnit = OfficeLengthUnit.millimeters;
  var _showAnimPane = true;
  var _showPasteOptions = false;
  final GlobalKey _settingsButtonKey = GlobalKey();
  final GlobalKey _accountButtonKey = GlobalKey();
  final FocusNode _wordFocus = FocusNode(debugLabel: 'studio-word');
  final FocusNode _sheetFocus = FocusNode(debugLabel: 'studio-sheet');
  final FocusNode _slideFocus = FocusNode(debugLabel: 'studio-slide');

  late final WordEditorController _word;
  final ZoteroSession _zoteroSession = ZoteroSession();
  bool _zoteroOpen = false;
  late final SheetEditorController _sheet;
  late final SlideEditorController _slides;
  late final PdfEditorController _pdf;
  WmlDocument? _commentDraftDocument;
  final Map<int, _CommentReplyDraft> _commentReplyDrafts =
      <int, _CommentReplyDraft>{};
  Timer? _commentReviewTimer;
  final TextEditingController _pdfFind = TextEditingController();
  Timer? _pdfFindDebounce;
  final TextEditingController _slideNotesEdit = TextEditingController();
  int _notesSlideIndex = -1;
  final VirtualViewport _commentViewport = VirtualViewport();
  final GlobalKey _commentCanvasKey = GlobalKey(
    debugLabel: 'studio-comment-caret-context',
  );
  OverlayEntry? _commentContextMenu;
  bool Function()? _commentContextIsCurrent;
  bool _commentContextKeyboard = false;
  OverlayEntry? _slideSorterMenu;
  var _savePhase = _SavePhase.idle;
  var _saveHeavy = false;
  var _saveProgress = 0.0;
  Timer? _saveTicker;
  var _opening = false;
  var _openHeavy = false;
  var _openProgress = 0.0;
  var _openStage = 'archive';
  String _openName = '';
  Timer? _openTicker;
  String? _wordPath;
  String? _sheetPath;
  String? _slidePath;
  String _wordName = 'CrispOffice product brief.docx';
  String _sheetName = 'Budget.xlsx';
  String _slideName = 'Studio deck.pptx';
  String? _pdfPath;
  String _pdfName = 'Studio.pdf';
  late final StudioPdfViewerEvents _pdfEvents;
  var _pdfNightMode = false;
  var _pdfSwipeHorizontal = false;
  var _pdfPageSnap = true;
  var _pdfPageFling = true;
  var _pdfEnableSwipe = true;
  var _pdfShowScroll = true;
  var _pdfPreventLinks = false;
  PdfFitPolicy _pdfFitPolicy = PdfFitPolicy.width;
  StudioPdfSampleKind _galleryKind = StudioPdfSampleKind.templates;
  String _galleryGroup = StudioPdfGallery.templateGroups.first;
  String? _gallerySampleId;

  OfficeSurfaceConfig? _cachedConfig;
  Object? _configKey;
  var _rebuildScheduled = false;
  var _slideshowFullscreen = false;
  var _findOpen = false;
  var _pdfSideTab = 0; // 0 thumbs, 1 outline
  final ValueNotifier<int> _navigationRevision = ValueNotifier<int>(0);
  final ScrollController _pdfThumbScroll = ScrollController();
  final ScrollController _compactPdfThumbScroll = ScrollController();
  int _pdfThumbSyncedPage = -1;
  int _compactPdfThumbSyncedPage = -1;
  final Set<String> _pdfOutlineExpanded = <String>{};
  var _findReplace = false;
  var _printPreview = false;
  static const MethodChannel _aboutChannel = MethodChannel('crispoffice/about');

  @override
  void initState() {
    super.initState();
    _aboutChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'show' && mounted) {
        await _showAbout();
      }
    });
    _pdfEvents = StudioPdfViewerEvents(
      onChanged: () {
        if (!mounted) {
          return;
        }
        scheduleMicrotask(() {
          if (mounted) {
            setState(() {});
          }
        });
      },
    );
    _word = WordEditorController(document: SampleLibrary.wordBriefing());
    _word.onFollowExternalLink = _openExternalLink;
    _sheet = SheetEditorController(workbook: SampleLibrary.excelBudget());
    _slides = SlideEditorController(presentation: SampleLibrary.slideDeck());
    _pdf = PdfEditorController.fromBytes(studioSamplePdf());
    _bindHostActions(_word);
    _bindHostActions(_sheet);
    _bindHostActions(_slides);
    studioSpacyHost.addListener(_syncSpacyGrammar);
    unawaited(studioSpacyHost.restoreGrammarOptIn().catchError((Object _) {}));
    // Re-verifies dictionaries the user installed earlier (no network).
    studioHunspellHost.addListener(_syncHunspell);
    unawaited(studioHunspellHost.refresh().catchError((Object _) {}));
    _slides.onPlayMedia = (PmlShape shape) {
      _toast(
        _arabic ? 'تشغيل ${shape.mediaName}' : 'Playing ${shape.mediaName}',
      );
    };
    _word.addListener(_rebuild);
    _sheet.addListener(_rebuild);
    _slides.addListener(_rebuild);
    _pdf.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StudioWindow.setTitle('$_chromeTitle — CrispOffice');
    });
  }

  void _rebuild() {
    _commentReviewTimer?.cancel();
    if (_commentContextMenu != null &&
        !(_commentContextIsCurrent?.call() ?? false)) {
      _dismissCommentContext();
    }
    _syncCommentReplyDrafts();
    if (!mounted || _rebuildScheduled) {
      return;
    }
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) {
        setState(() {
          if (_app == SuiteApp.word &&
              _tab == _RibbonTab.design &&
              _word.selectedEquation == null) {
            _tab = _RibbonTab.insert;
          }
        });
        StudioWindow.setTitle('$_chromeTitle — CrispOffice');
        _syncSlideshowFullscreen();
      }
    });
  }

  void _syncSlideshowFullscreen() {
    final bool want = _app == SuiteApp.powerpoint && _slides.isPresenting;
    if (want == _slideshowFullscreen) {
      return;
    }
    _slideshowFullscreen = want;
    StudioWindow.setFullScreen(want);
  }

  OfficeController get _active => switch (_app) {
    SuiteApp.word => _word,
    SuiteApp.excel => _sheet,
    SuiteApp.powerpoint => _slides,
    SuiteApp.pdf => _word,
  };

  Color get _accent => switch (_app) {
    SuiteApp.word => const Color(0xFF2B579A),
    SuiteApp.excel => const Color(0xFF217346),
    SuiteApp.powerpoint => const Color(0xFFB7472A),
    SuiteApp.pdf => const Color(0xFFC0392B),
  };

  OfficeTheme get _officeTheme {
    const String arabicBody = 'Tajawal';
    return switch (_look) {
      SuiteLook.light => OfficeTheme.light.copyWith(
        focusRing: _accent,
        fontFamily: arabicBody,
      ),
      SuiteLook.dark => OfficeTheme.dark.copyWith(
        focusRing: _accent,
        fontFamily: arabicBody,
      ),
      SuiteLook.highContrast => OfficeTheme.highContrast.copyWith(
        fontFamily: arabicBody,
      ),
    };
  }

  OfficeSurfaceConfig get _config {
    final Object key = (
      _app,
      _look,
      _mode,
      _arabic,
      _wordRulers,
      _sheetGridlines,
      _sheetHeaders,
      _slideHandles,
      _lengthUnit,
    );
    if (_cachedConfig != null && _configKey == key) {
      return _cachedConfig!;
    }
    _configKey = key;
    _cachedConfig = OfficeSurfaceConfig(
      mode: _mode,
      theme: _officeTheme,
      showRulers: _app == SuiteApp.word && _wordRulers,
      showFormulaBar: false,
      showGridHeaders: _sheetHeaders,
      showGridlines: _sheetGridlines,
      showSlideHandles: _slideHandles,
      lengthUnit: _lengthUnit,
      textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
      strings: _arabic ? OfficeStrings.arabic : OfficeStrings.english,
      formFactor: OfficeFormFactor.automatic,
      density: OfficeDensity.comfortable,
      adaptiveChrome: true,
      interactiveRulers: _wordRulers,
      showNotesPane: _app == SuiteApp.word && _showNotes,
    );
    return _cachedConfig!;
  }

  bool get _canMutate => _mode == OfficeInteractionMode.editing && !_opening;

  @override
  void dispose() {
    _aboutChannel.setMethodCallHandler(null);
    studioSpacyHost.removeListener(_syncSpacyGrammar);
    studioHunspellHost.removeListener(_syncHunspell);
    _spacyGrammarEpoch++;
    _word
      ..removeListener(_rebuild)
      ..dispose();
    _sheet
      ..removeListener(_rebuild)
      ..dispose();
    _slides
      ..removeListener(_rebuild)
      ..dispose();
    _pdf
      ..removeListener(_rebuild)
      ..dispose();
    _commentReviewTimer?.cancel();
    _commentReplyDrafts.clear();
    _pdfFindDebounce?.cancel();
    _pdfFind.dispose();
    _pdfThumbScroll.dispose();
    _compactPdfThumbScroll.dispose();
    _navigationRevision.dispose();
    _slideNotesEdit.dispose();
    _commentContextKeyboard = false;
    _wordFocus.dispose();
    _sheetFocus.dispose();
    _slideFocus.dispose();
    _saveTicker?.cancel();
    _openTicker?.cancel();
    _dismissCommentContext();
    OfficeContextMenu.dismiss(_slideSorterMenu);
    _slideSorterMenu = null;
    if (_slideshowFullscreen) {
      StudioWindow.setFullScreen(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = _look != SuiteLook.light;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyY, meta: true): _redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _redo,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _selectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _selectAll,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
        if (studioZoteroDesktopAvailable) ...{
          const SingleActivator(
            LogicalKeyboardKey.keyC,
            control: true,
            alt: true,
          ): _addEditZoteroCitation,
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true, alt: true):
              _addEditZoteroCitation,
          const SingleActivator(
            LogicalKeyboardKey.keyR,
            control: true,
            alt: true,
          ): _refreshZoteroCitations,
          const SingleActivator(LogicalKeyboardKey.keyR, meta: true, alt: true):
              _refreshZoteroCitations,
        },
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): _cut,
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): _cut,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _paste,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _paste,
        const SingleActivator(
          LogicalKeyboardKey.keyV,
          control: true,
          shift: true,
        ): () =>
            _pasteMode(OfficePasteMode.keepTextOnly),
        const SingleActivator(
          LogicalKeyboardKey.keyV,
          meta: true,
          shift: true,
        ): () =>
            _pasteMode(OfficePasteMode.keepTextOnly),
        const SingleActivator(LogicalKeyboardKey.f5): _slideShowFromStart,
        const SingleActivator(LogicalKeyboardKey.f5, shift: true):
            _slideShowFromCurrent,
        const SingleActivator(LogicalKeyboardKey.escape): _workspaceEscape,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyH, control: true):
            _openReplace,
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
            _openReplace,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            _exportPdf,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): _exportPdf,
        const SingleActivator(LogicalKeyboardKey.f3): _findNext,
        const SingleActivator(LogicalKeyboardKey.f3, shift: true):
            _findPrevious,
        const SingleActivator(LogicalKeyboardKey.f1): _openPdfSampleGallery,
        const SingleActivator(LogicalKeyboardKey.f7): _showSpelling,
        const SingleActivator(LogicalKeyboardKey.f7, shift: true):
            _word.requestThesaurus,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _toggleBold,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): _toggleBold,
        const SingleActivator(LogicalKeyboardKey.keyI, control: true):
            _toggleItalic,
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true):
            _toggleItalic,
        const SingleActivator(LogicalKeyboardKey.keyU, control: true):
            _toggleUnderline,
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true):
            _toggleUnderline,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveFile,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveFile,
        const SingleActivator(LogicalKeyboardKey.equal, control: true):
            _shortcutZoomIn,
        const SingleActivator(LogicalKeyboardKey.equal, meta: true):
            _shortcutZoomIn,
        const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
            _shortcutZoomIn,
        const SingleActivator(LogicalKeyboardKey.add, control: true):
            _shortcutZoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, control: true):
            _shortcutZoomOut,
        const SingleActivator(LogicalKeyboardKey.minus, meta: true):
            _shortcutZoomOut,
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
            _shortcutZoomOut,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            _shortcutZoomReset,
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true):
            _shortcutZoomReset,
      },
      child: StudioWindowScope(
        onChanged: () {
          if (mounted) {
            setState(() {});
          }
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: _onWorkspaceDirectionKey,
          child: Directionality(
            textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
            child: _app == SuiteApp.powerpoint && _slides.isPresenting
                ? ColoredBox(
                    color: const Color(0xFF000000),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: QudsSlideEditor(
                            controller: _slides,
                            focusNode: _slideFocus,
                            config: _config,
                          ),
                        ),
                        SizedBox(width: 260, child: _presenterPane()),
                      ],
                    ),
                  )
                : Scaffold(
                    backgroundColor: dark
                        ? const Color(0xFF1B1B1B)
                        : const Color(0xFFE8E8E8),
                    body: Column(
                      children: <Widget>[
                        _titleBar(),
                        _tabStrip(dark),
                        _ribbon(dark),
                        if (_showPasteOptions) _pasteOptionsBar(dark),
                        Expanded(child: _body(dark)),
                        _statusBar(),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _slideShowFromStart() {
    if (_app != SuiteApp.powerpoint) {
      return;
    }
    if (_slides.isPresenting) {
      _slides.endShow();
      return;
    }
    if (_slides.isPreviewing) {
      _slides.endShow();
    }
    _slides.startShow(from: 0);
    _slides.startPresenter();
  }

  void _slideShowFromCurrent() {
    if (_app != SuiteApp.powerpoint) {
      return;
    }
    if (_slides.isPresenting) {
      _slides.endShow();
      return;
    }
    if (_slides.isPreviewing) {
      _slides.endShow();
    }
    _slides.startShow(from: _slides.activeSlideIndex);
    _slides.startPresenter();
  }

  void _slideShowEscape() {
    if (_app == SuiteApp.powerpoint &&
        (_slides.isPresenting || _slides.isPreviewing)) {
      _slides.endShow();
    }
  }

  void _toggleBold() {
    if (!_canMutate || _app != SuiteApp.word) {
      return;
    }
    _word.applyRunFormat((WmlRunProps p) => p.bold = !p.bold);
  }

  void _toggleItalic() {
    if (!_canMutate || _app != SuiteApp.word) {
      return;
    }
    _word.applyRunFormat((WmlRunProps p) => p.italic = !p.italic);
  }

  void _toggleUnderline() {
    if (!_canMutate || _app != SuiteApp.word) {
      return;
    }
    _word.applyRunFormat((WmlRunProps p) {
      p.underline = p.underline == WmlUnderline.none
          ? WmlUnderline.single
          : WmlUnderline.none;
    });
  }

  void _undo() => _active.undo();

  void _redo() => _active.redo();

  void _selectAll() {
    if (_app == SuiteApp.pdf) {
      _pdf.selectAll();
      return;
    }
    _active.selectAll();
  }

  void _copy() {
    _active.copyToClipboard();
  }

  void _cut() {
    if (!_canMutate) {
      return;
    }
    _active.cutToClipboard();
  }

  void _paste() => _pasteMode(OfficePasteMode.keepSource);

  Future<void> _pasteMode(OfficePasteMode mode) async {
    if (!_canMutate) {
      return;
    }
    await _active.pasteFromClipboard(mode: mode);
    if (mounted) {
      setState(() => _showPasteOptions = true);
    }
  }

  Widget _titleBar() {
    return Material(
      color: _accent,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          height: (studioChromeLineHeight(context, 13) + 12)
              .clamp(36.0, double.infinity)
              .toDouble(),
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              StudioDragRegion(
                onDoubleTap: StudioWindow.toggleMaximize,
                child: const SizedBox.expand(),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('studio-title-actions-scroll'),
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(left: 10, right: 4),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  Icons.auto_awesome_mosaic,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  _strings.appTitle,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _titleQuickAccess(),
                          Row(
                            children: <Widget>[
                              StudioAppSwitcher(
                                label: _strings.documents,
                                icon: Icons.description_outlined,
                                selected: _app == SuiteApp.word,
                                onTap: () => _switchApp(SuiteApp.word),
                              ),
                              StudioAppSwitcher(
                                label: _strings.spreadsheets,
                                icon: Icons.grid_on_outlined,
                                selected: _app == SuiteApp.excel,
                                onTap: () => _switchApp(SuiteApp.excel),
                              ),
                              StudioAppSwitcher(
                                label: _strings.presentations,
                                icon: Icons.slideshow_outlined,
                                selected: _app == SuiteApp.powerpoint,
                                onTap: () => _switchApp(SuiteApp.powerpoint),
                              ),
                              StudioAppSwitcher(
                                label: _strings.pdf,
                                icon: Icons.picture_as_pdf_outlined,
                                selected: _app == SuiteApp.pdf,
                                onTap: () => _switchApp(SuiteApp.pdf),
                              ),
                              StudioAppSwitcher(
                                label: _strings.mail,
                                icon: Icons.mail_outline,
                                selected: false,
                                onTap: _openMail,
                              ),
                            ],
                          ),
                          SizedBox(
                            width: 280,
                            child: StudioDragRegion(
                              onDoubleTap: StudioWindow.toggleMaximize,
                              child: Align(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Text(
                                    _documentLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.94,
                                      ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: _settingsButtonKey,
                    tooltip: _strings.settings,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 36,
                    ),
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                    onPressed: _openSettings,
                  ),
                  IconButton(
                    key: _accountButtonKey,
                    tooltip: _strings.account,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 36,
                    ),
                    icon: const Icon(
                      Icons.person_outline,
                      color: Colors.white,
                      size: 16,
                    ),
                    onPressed: _openAccount,
                  ),
                  if (StudioWindow.supported) const SizedBox(width: 138),
                ],
              ),
              if (StudioWindow.supported)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      StudioCaptionButton(
                        icon: Icons.minimize,
                        tooltip: _strings.minimize,
                        onPressed: StudioWindow.minimize,
                      ),
                      StudioCaptionButton(
                        icon: StudioWindow.maximized
                            ? Icons.filter_none
                            : Icons.crop_square,
                        tooltip: StudioWindow.maximized
                            ? _strings.restore
                            : _strings.maximize,
                        onPressed: StudioWindow.toggleMaximize,
                      ),
                      StudioCaptionButton(
                        icon: Icons.close,
                        tooltip: _strings.close,
                        onPressed: StudioWindow.close,
                        close: true,
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

  Widget _titleQuickAccess() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _titleQat(
          Icons.save_outlined,
          _strings.save,
          _isSaving || _opening ? null : _saveFile,
        ),
        _titleQat(
          Icons.undo,
          _strings.undo,
          _canMutate && _active.canUndo ? _undo : null,
        ),
        _titleQat(
          Icons.redo,
          _strings.redo,
          _canMutate && _active.canRedo ? _redo : null,
        ),
      ],
    );
  }

  Widget _titleQat(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      icon: Icon(
        icon,
        size: 15,
        color: onPressed == null ? Colors.white54 : Colors.white,
      ),
      onPressed: onPressed,
    );
  }

  String get _chromeTitle {
    final String app = switch (_app) {
      SuiteApp.word => _strings.documents,
      SuiteApp.excel => _strings.spreadsheets,
      SuiteApp.powerpoint => _strings.presentations,
      SuiteApp.pdf => _strings.pdf,
    };
    return '$_documentLabel — $app';
  }

  String get _documentLabel {
    final String name = switch (_app) {
      SuiteApp.word => _wordName,
      SuiteApp.excel => _sheetName,
      SuiteApp.powerpoint => _slideName,
      SuiteApp.pdf => _pdfName,
    };
    final String clean = name.trim().isEmpty ? _untitledName : name.trim();
    final bool dirty = _app == SuiteApp.pdf ? _pdf.isDirty : _active.isDirty;
    return dirty ? '$clean*' : clean;
  }

  String get _untitledName => switch (_app) {
    SuiteApp.word => 'Document1.docx',
    SuiteApp.excel => 'Book1.xlsx',
    SuiteApp.powerpoint => 'Presentation1.pptx',
    SuiteApp.pdf => 'Document.pdf',
  };

  String get _activeName => switch (_app) {
    SuiteApp.word => _wordName,
    SuiteApp.excel => _sheetName,
    SuiteApp.powerpoint => _slideName,
    SuiteApp.pdf => _pdfName,
  };

  set _activeName(String value) {
    switch (_app) {
      case SuiteApp.word:
        _wordName = value;
      case SuiteApp.excel:
        _sheetName = value;
      case SuiteApp.powerpoint:
        _slideName = value;
      case SuiteApp.pdf:
        _pdfName = value;
    }
  }

  String _nameFromPicked(PickedOfficeFile picked) {
    if (picked.name.trim().isNotEmpty) {
      return picked.name.trim();
    }
    final String? path = picked.path;
    if (path != null && path.isNotEmpty) {
      return StudioFiles.nameOf(path);
    }
    return _untitledName;
  }

  void _switchApp(SuiteApp app) {
    _dismissCommentContext();
    setState(() {
      _app = app;
      _tab = app == SuiteApp.pdf ? _RibbonTab.view : _RibbonTab.home;
    });
    StudioWindow.setTitle('$_chromeTitle — CrispOffice');
  }

  RelativeRect _menuRectFor(GlobalKey key) {
    final BuildContext? buttonContext = key.currentContext;
    final RenderBox? button = buttonContext?.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (button == null || !button.hasSize || overlay == null) {
      return RelativeRect.fromLTRB(
        MediaQuery.sizeOf(context).width - 220,
        36,
        8,
        8,
      );
    }
    final Offset topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final Offset bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    return RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          void changed(VoidCallback update) {
            setState(update);
            setDialogState(() {});
          }

          return AlertDialog(
            title: Text(_strings.settings),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<OfficeInteractionMode>(
                      initialValue: _mode,
                      decoration: InputDecoration(labelText: _strings.mode),
                      items: <DropdownMenuItem<OfficeInteractionMode>>[
                        for (final value in OfficeInteractionMode.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(switch (value) {
                              OfficeInteractionMode.editing => _t(
                                'Editing',
                                'Bearbeiten',
                                'تحرير',
                              ),
                              OfficeInteractionMode.selecting => _t(
                                'Selecting',
                                'Auswählen',
                                'تحديد',
                              ),
                              OfficeInteractionMode.viewing => _t(
                                'Viewing',
                                'Ansehen',
                                'عرض',
                              ),
                            }),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) changed(() => _mode = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<SuiteLook>(
                      initialValue: _look,
                      decoration: InputDecoration(labelText: _strings.look),
                      items: <DropdownMenuItem<SuiteLook>>[
                        for (final value in SuiteLook.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(switch (value) {
                              SuiteLook.light => _t('Light', 'Hell', 'فاتح'),
                              SuiteLook.dark => _t('Dark', 'Dunkel', 'داكن'),
                              SuiteLook.highContrast => _t(
                                'High contrast',
                                'Hoher Kontrast',
                                'تباين عالٍ',
                              ),
                            }),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) changed(() => _look = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<StudioLanguage>(
                      initialValue: _language,
                      decoration: InputDecoration(
                        labelText: _strings.languageLabel,
                      ),
                      items: const <DropdownMenuItem<StudioLanguage>>[
                        DropdownMenuItem(
                          value: StudioLanguage.en,
                          child: Text('English'),
                        ),
                        DropdownMenuItem(
                          value: StudioLanguage.de,
                          child: Text('Deutsch'),
                        ),
                        DropdownMenuItem(
                          value: StudioLanguage.ar,
                          child: Text('العربية'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) changed(() => _language = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<OfficeLengthUnit>(
                      initialValue: _lengthUnit,
                      decoration: InputDecoration(
                        labelText: _strings.measurement,
                      ),
                      items: <DropdownMenuItem<OfficeLengthUnit>>[
                        DropdownMenuItem(
                          value: OfficeLengthUnit.millimeters,
                          child: Text(_strings.millimetres),
                        ),
                        DropdownMenuItem(
                          value: OfficeLengthUnit.centimeters,
                          child: Text(_strings.centimetres),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) changed(() => _lengthUnit = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_strings.showOutline),
                      value: _showOutline,
                      onChanged: (value) => changed(() => _showOutline = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_strings.showComments),
                      value: _showComments,
                      onChanged: (value) =>
                          changed(() => _showComments = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_strings.showNotes),
                      value: _showNotes,
                      onChanged: (value) => changed(() => _showNotes = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_strings.showRibbonLabels),
                      value: _showRibbonGroupLabels,
                      onChanged: (value) =>
                          changed(() => _showRibbonGroupLabels = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_strings.close),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openMail() => showDialog<void>(
    context: context,
    builder: (BuildContext context) => StudioMailDialog(strings: _strings),
  );

  void _cycleLanguage() {
    setState(() {
      _language = switch (_language) {
        StudioLanguage.en => StudioLanguage.de,
        StudioLanguage.de => StudioLanguage.ar,
        StudioLanguage.ar => StudioLanguage.en,
      };
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // syncConfig runs in editor didUpdateWidget; re-focus so IME / caret return.
      if (_app == SuiteApp.word) {
        _wordFocus.requestFocus();
        if (_canMutate) {
          _word.attachInput();
        }
      } else if (_app == SuiteApp.excel) {
        _sheetFocus.requestFocus();
      } else {
        _slideFocus.requestFocus();
      }
    });
  }

  void _openAccount() {
    showMenu<String>(
      context: context,
      position: _menuRectFor(_accountButtonKey),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            _t('Local account', StudioStrings.de('Local account'), 'حساب محلي'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(value: 'about', child: Text(_strings.about)),
      ],
    ).then((String? value) {
      if (value == 'about') {
        _showAbout();
      }
    });
  }

  Future<void> _showAbout() => showStudioAbout(context, _strings);

  String get _modeLabel => switch (_mode) {
    OfficeInteractionMode.editing => _t(
      'Editing',
      StudioStrings.de('Editing'),
      'تحرير',
    ),
    OfficeInteractionMode.selecting => _t(
      'Selecting',
      StudioStrings.de('Selecting'),
      'تحديد',
    ),
    OfficeInteractionMode.viewing => _t(
      'Viewing',
      StudioStrings.de('Viewing'),
      'عرض',
    ),
  };

  List<_RibbonTab> get _tabsForApp => switch (_app) {
    SuiteApp.word => <_RibbonTab>[
      _RibbonTab.file,
      _RibbonTab.home,
      _RibbonTab.insert,
      if (_word.selectedEquation != null) _RibbonTab.design,
      _RibbonTab.layout,
      _RibbonTab.review,
      _RibbonTab.view,
    ],
    SuiteApp.excel => const <_RibbonTab>[
      _RibbonTab.file,
      _RibbonTab.home,
      _RibbonTab.insert,
      _RibbonTab.formulas,
      _RibbonTab.data,
      _RibbonTab.view,
    ],
    SuiteApp.powerpoint => const <_RibbonTab>[
      _RibbonTab.file,
      _RibbonTab.home,
      _RibbonTab.insert,
      _RibbonTab.design,
      _RibbonTab.transitions,
      _RibbonTab.animations,
      _RibbonTab.view,
    ],
    SuiteApp.pdf => const <_RibbonTab>[
      _RibbonTab.file,
      _RibbonTab.view,
      _RibbonTab.review,
      _RibbonTab.insert,
    ],
  };

  String _tabLabel(_RibbonTab tab) => switch (tab) {
    _RibbonTab.file => _t('File', StudioStrings.de('File'), 'ملف'),
    _RibbonTab.home => _t('Home', StudioStrings.de('Home'), 'الرئيسية'),
    _RibbonTab.insert =>
      _app == SuiteApp.pdf
          ? (_t('Form', StudioStrings.de('Form'), 'نموذج'))
          : (_t('Insert', StudioStrings.de('Insert'), 'إدراج')),
    _RibbonTab.layout => _t('Layout', StudioStrings.de('Layout'), 'تخطيط'),
    _RibbonTab.review =>
      _app == SuiteApp.pdf
          ? (_t('Annotate', StudioStrings.de('Annotate'), 'تعليق'))
          : (_t('Review', StudioStrings.de('Review'), 'مراجعة')),
    _RibbonTab.formulas => _t('Formulas', StudioStrings.de('Formulas'), 'صيغ'),
    _RibbonTab.data => _t('Data', StudioStrings.de('Data'), 'بيانات'),
    _RibbonTab.design =>
      _app == SuiteApp.word
          ? (_t('Equation', StudioStrings.de('Equation'), 'معادلة'))
          : (_t('Design', StudioStrings.de('Design'), 'تصميم')),
    _RibbonTab.transitions => _t(
      'Transitions',
      StudioStrings.de('Transitions'),
      'انتقالات',
    ),
    _RibbonTab.animations => _t(
      'Animations',
      StudioStrings.de('Animations'),
      'حركات',
    ),
    _RibbonTab.view => _t('View', StudioStrings.de('View'), 'عرض'),
  };

  Widget _tabStrip(bool dark) {
    return Material(
      color: dark ? const Color(0xFF2A2A2A) : Colors.white,
      child: SizedBox(
        height: 36 + _extraChromeTextHeight(13),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: <Widget>[
              if (constraints.maxWidth < 700)
                StudioIconCmd(
                  icon: Icons.menu,
                  tooltip: _t(
                    'Navigation',
                    StudioStrings.de('Navigation'),
                    'التنقل',
                  ),
                  accent: _accent,
                  foreground: _officeTheme.chromeText,
                  onPressed: () => _openCompactNavigation(dark),
                ),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey<String>('studio-ribbon-tabs-scroll'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(width: 4),
                      for (final _RibbonTab tab in _tabsForApp)
                        StudioTabChip(
                          label: _tabLabel(tab),
                          selected: _tab == tab,
                          accent: _accent,
                          onTap: () => setState(() => _tab = tab),
                        ),
                    ],
                  ),
                ),
              ),
              StudioIconCmd(
                icon: Icons.undo,
                tooltip: _strings.undo,
                accent: _accent,
                foreground: _officeTheme.chromeText,
                onPressed:
                    _canMutate &&
                        (_app == SuiteApp.pdf ? _pdf.canUndo : _active.canUndo)
                    ? (_app == SuiteApp.pdf ? _pdf.undo : _active.undo)
                    : null,
              ),
              StudioIconCmd(
                icon: Icons.redo,
                tooltip: _strings.redo,
                accent: _accent,
                foreground: _officeTheme.chromeText,
                onPressed:
                    _canMutate &&
                        (_app == SuiteApp.pdf ? _pdf.canRedo : _active.canRedo)
                    ? (_app == SuiteApp.pdf ? _pdf.redo : _active.redo)
                    : null,
              ),
              StudioIconCmd(
                icon: Icons.translate,
                tooltip: _strings.languageLabel,
                accent: _accent,
                foreground: _officeTheme.chromeText,
                onPressed: _cycleLanguage,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  double _extraChromeTextHeight(double fontSize) =>
      math.max(0, MediaQuery.textScalerOf(context).scale(fontSize) - fontSize) *
      1.6;

  Future<void> _openCompactNavigation(bool dark) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => AnimatedBuilder(
      animation: Listenable.merge([
        _app == SuiteApp.pdf ? _pdf : _active,
        _navigationRevision,
      ]),
      builder: (context, _) => Directionality(
        textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: _sidePane(dark, compact: true),
        ),
      ),
    ),
  );

  void _updateNavigationState(VoidCallback update) {
    setState(update);
    // The compact sheet is a separate route. Its local tabs and expansion
    // state must rebuild alongside the inline desktop navigation pane.
    _navigationRevision.value++;
  }

  Widget _ribbon(bool dark) {
    return Material(
      color: dark ? const Color(0xFF2A2A2A) : Colors.white,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _accent.withValues(alpha: 0.35),
              width: 2,
            ),
          ),
        ),
        child: SizedBox(
          height: StudioRibbonStrip.preferredHeight(context),
          child: StudioRibbonStrip(groups: _ribbonGroups()),
        ),
      ),
    );
  }

  List<StudioRibbonGroup> _ribbonGroups() {
    StudioRibbonGroup.showTitles = _showRibbonGroupLabels;
    return switch ((_app, _tab)) {
      (SuiteApp.word, _RibbonTab.file) => _fileGroups(_resetWord, _newWord),
      (SuiteApp.word, _RibbonTab.home) => _wordHome(),
      (SuiteApp.word, _RibbonTab.insert) => _wordInsert(),
      (SuiteApp.word, _RibbonTab.design) => _wordEquationTools(),
      (SuiteApp.word, _RibbonTab.layout) => _wordLayout(),
      (SuiteApp.word, _RibbonTab.review) => _wordReview(),
      (SuiteApp.word, _RibbonTab.view) => _wordView(),
      (SuiteApp.excel, _RibbonTab.file) => _fileGroups(_resetSheet, _newSheet),
      (SuiteApp.excel, _RibbonTab.home) => _sheetHome(),
      (SuiteApp.excel, _RibbonTab.insert) => _sheetInsert(),
      (SuiteApp.excel, _RibbonTab.formulas) => _sheetFormulas(),
      (SuiteApp.excel, _RibbonTab.data) => _sheetData(),
      (SuiteApp.excel, _RibbonTab.view) => _sheetView(),
      (SuiteApp.powerpoint, _RibbonTab.file) => _fileGroups(
        _resetSlides,
        _newSlides,
      ),
      (SuiteApp.powerpoint, _RibbonTab.home) => _slideHome(),
      (SuiteApp.powerpoint, _RibbonTab.insert) => _slideInsert(),
      (SuiteApp.powerpoint, _RibbonTab.design) => _slideDesign(),
      (SuiteApp.powerpoint, _RibbonTab.transitions) => _slideTransitions(),
      (SuiteApp.powerpoint, _RibbonTab.animations) => _slideAnimations(),
      (SuiteApp.powerpoint, _RibbonTab.view) => _slideView(),
      (SuiteApp.pdf, _RibbonTab.file) => _pdfFileGroups(),
      (SuiteApp.pdf, _RibbonTab.review) => _pdfAnnotate(),
      (SuiteApp.pdf, _RibbonTab.insert) => _pdfForm(),
      (SuiteApp.pdf, _) => _pdfView(),
      _ => _fileGroups(_resetWord, _newWord),
    };
  }

  void _resetPdf() {
    _pdf.loadBytesAsync(studioSamplePdf());
    _pdfPath = null;
    _pdfName = 'Studio.pdf';
  }

  void _newPdf() {
    _pdf.loadBytesAsync(studioSamplePdf());
    _pdfPath = null;
    _pdfName = 'Document.pdf';
  }

  List<StudioRibbonGroup> _pdfFileGroups() {
    return <StudioRibbonGroup>[
      ..._fileGroups(_resetPdf, _newPdf),
      StudioRibbonGroup(
        title: _t(
          'Sample lab',
          StudioStrings.de('Sample lab'),
          'عينات تجريبية',
        ),
        children: <Widget>[
          _cmd(
            Icons.auto_awesome,
            _t(
              'PDF gallery (F1)',
              StudioStrings.de('PDF gallery (F1)'),
              'معرض PDF (F1)',
            ),
            _opening || _isSaving ? null : _openPdfSampleGallery,
          ),
          _cmd(
            Icons.build_circle_outlined,
            _t('PDF tools', StudioStrings.de('PDF tools'), 'أدوات PDF'),
            _opening || _isSaving ? null : _openPdfTools,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Convert', StudioStrings.de('Convert'), 'تحويل'),
        children: <Widget>[
          _cmd(
            Icons.description_outlined,
            _strings.documents,
            _opening || _isSaving ? null : () => _convertOpenPdf('docx'),
          ),
          _cmd(
            Icons.grid_on_outlined,
            _strings.spreadsheets,
            _opening || _isSaving ? null : () => _convertOpenPdf('xlsx'),
          ),
          _cmd(
            Icons.slideshow_outlined,
            _strings.presentations,
            _opening || _isSaving ? null : () => _convertOpenPdf('pptx'),
          ),
        ],
      ),
    ];
  }

  Future<void> _convertOpenPdf(String extension) async {
    if (_pdf.file == null || _opening || _isSaving) {
      return;
    }
    final PdfOfficeExportResult? result = await studioPdfOfficeDialog(
      context: context,
      arabic: _arabic,
      extension: extension,
      readBytes: _pdf.saveBytes,
    );
    if (result == null || !mounted) {
      return;
    }
    final String? error = result.error;
    if (error != null) {
      _toast(
        error == 'empty'
            ? (_t(
                'This PDF has no pages.',
                StudioStrings.de('This PDF has no pages.'),
                'الملف بلا صفحات.',
              ))
            : (_arabic ? 'تعذّر التحويل: $error' : 'Convert failed: $error'),
      );
      return;
    }
    final Uint8List? bytes = result.bytes;
    if (bytes == null) {
      return;
    }
    final String stem = _pdfName.toLowerCase().endsWith('.pdf')
        ? _pdfName.substring(0, _pdfName.length - 4)
        : _pdfName;
    final String? picked = await StudioFiles.pickSavePath(
      fileName: '$stem.$extension',
    );
    if (picked == null || !mounted) {
      return;
    }
    final String path = StudioFiles.withExtension(picked, '$stem.$extension');
    try {
      await File(path).writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      _toast(_arabic ? 'تعذّر الحفظ: $error' : 'Save failed: $error');
      return;
    }
    if (!mounted) {
      return;
    }
    final List<String> notes = _pdfConvertNotes(result.notes);
    final String saved = StudioFiles.nameOf(path);
    if (notes.isEmpty) {
      _toast(_arabic ? 'تم التحويل: $saved' : 'Converted $saved');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
          _t(
            'Conversion notes',
            StudioStrings.de('Conversion notes'),
            'ملاحظات التحويل',
          ),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_arabic ? 'تم التحويل: $saved' : 'Converted $saved'),
              const SizedBox(height: 12),
              for (final String line in notes.take(12))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('OK', StudioStrings.de('OK'), 'موافق')),
          ),
        ],
      ),
    );
  }

  List<String> _pdfConvertNotes(List<PdfOfficeExportNote> notes) {
    return <String>[
      for (final PdfOfficeExportNote note in notes)
        _pdfConvertLine(note.page, _pdfExportNoteText(note)),
    ];
  }

  String _pdfConvertLine(int? page, String message) {
    final int number = (page ?? 0) + 1;
    return _arabic ? 'الصفحة $number: $message' : 'Page $number: $message';
  }

  String _pdfExportNoteText(PdfOfficeExportNote note) {
    return switch (note.kind) {
      'noExtractableText' =>
        _arabic
            ? 'لا يوجد نص قابل للاستخراج. الصفحات الممسوحة لا تُقرأ.'
            : 'No extractable text on this page. Scanned pages are not read.',
      'rotationFlattened' =>
        _arabic
            ? 'كُتب النص المدار كسطر أفقي.'
            : 'Rotated text was written as a horizontal line.',
      'jpegOnSlide' =>
        _arabic
            ? 'صور JPEG تُحفظ في Word. الشرائح تضمّن PNG فقط.'
            : 'JPEG pictures are saved in Word. Slides embed PNG only.',
      'imageSkipped' =>
        note.message.startsWith('JPX')
            ? (_arabic
                  ? 'صور JPX وJBIG2 لا تُضمَّن.'
                  : 'JPX and JBIG2 images are not embedded.')
            : (_arabic
                  ? 'تُضمَّن صور JPEG وPNG فقط.'
                  : 'Only JPEG and PNG images are embedded.'),
      _ => note.message,
    };
  }

  Future<void> _openPdfSampleGallery() async {
    if (_opening || _isSaving) {
      return;
    }
    final StudioPdfSample? sample = await showDialog<StudioPdfSample>(
      context: context,
      builder: (BuildContext context) {
        return PdfSampleGalleryDialog(
          arabic: _arabic,
          accent: _accent,
          initialKind: _galleryKind,
          initialGroup: _galleryGroup,
          initialSampleId: _gallerySampleId,
        );
      },
    );
    if (sample == null || !mounted) {
      return;
    }
    await _loadPdfSample(sample);
  }

  Future<void> _openPdfTools() async {
    final Uint8List current = _pdf.saveBytes();
    final PdfToolOutput? output = await showDialog<PdfToolOutput>(
      context: context,
      builder: (BuildContext context) {
        return PdfToolsLabDialog(
          arabic: _arabic,
          accent: _accent,
          currentBytes: current.isEmpty ? null : current,
          currentName: _pdfName,
        );
      },
    );
    if (output == null || !mounted) {
      return;
    }
    _switchApp(SuiteApp.pdf);
    await _pdf.loadBytesAsync(output.bytes);
    if (!mounted) {
      return;
    }
    setState(() {
      _pdfPath = null;
      _pdfName = output.name;
      _pdfThumbSyncedPage = -1;
    });
  }

  Future<void> _loadPdfSample(StudioPdfSample sample) async {
    setState(() {
      _opening = true;
      _openHeavy = true;
      _openProgress = 0.08;
      _openStage = 'sample';
      _openName = sample.fileName;
    });
    _openTicker?.cancel();
    _openTicker = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted || !_opening) {
        return;
      }
      setState(() {
        _openProgress = (_openProgress + 0.04).clamp(0.0, 0.92);
      });
    });
    try {
      await SampleLibrary.preload();
      final OfficeFontSet fontSet = sample.id == 'office-crispoffice-word'
          ? StudioFiles.exportFontSetForWord(SampleLibrary.wordBriefing())
          : StudioFiles.exportFontSetCovering(<String>[
              sample.titleEn,
              sample.blurbEn,
              'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',
              'حي التحرير التعافي',
            ]);
      final SfntFont? font = fontSet.primary ?? StudioFiles.latinExportFont();
      final Uint8List bytes = await Future<Uint8List>(() {
        return sample.build(font: font, fonts: fontSet);
      });
      final Directory dir = Directory(
        '${Directory.systemTemp.path}/quds_pdf_samples',
      )..createSync(recursive: true);
      final File file = File('${dir.path}/${sample.fileName}');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) {
        return;
      }
      _switchApp(SuiteApp.pdf);
      await _pdf.loadBytesAsync(bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _pdfPath = file.path;
        _pdfName = sample.fileName;
        _pdfThumbSyncedPage = -1;
        _openProgress = 1;
        _galleryKind = sample.kind;
        if (sample.group.isNotEmpty) {
          _galleryGroup = sample.group;
        }
        _gallerySampleId = sample.id;
      });
    } catch (error, stack) {
      debugPrint('PDF sample failed: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _arabic ? 'تعذّر إنشاء العينة: $error' : 'Sample failed: $error',
            ),
          ),
        );
      }
    } finally {
      _openTicker?.cancel();
      _openTicker = null;
      if (mounted) {
        setState(() {
          _opening = false;
          _openHeavy = false;
          _openProgress = 0;
          _openStage = 'archive';
          _openName = '';
        });
      }
    }
  }

  PdfViewerOptions get _pdfViewerOptions => studioPdfViewerOptions(
    nightMode: _pdfNightMode,
    swipeHorizontal: _pdfSwipeHorizontal,
    pageSnap: _pdfPageSnap,
    pageFling: _pdfPageFling,
    enableSwipe: _pdfEnableSwipe,
    showScrollIndicators: _pdfShowScroll,
    preventLinkNavigation: _pdfPreventLinks,
    fitPolicy: _pdfFitPolicy,
    backgroundColor: _pdfNightMode ? const Color(0xFF121212) : null,
  );

  void _togglePdfOption(void Function() mutate, {String? toast}) {
    setState(mutate);
    if (toast != null) {
      _toast(toast);
    }
  }

  List<StudioRibbonGroup> _pdfView() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('View', StudioStrings.de('View'), 'عرض'),
        children: <Widget>[
          _cmd(
            Icons.zoom_in,
            _t('Zoom in', StudioStrings.de('Zoom in'), 'تكبير'),
            () {
              _pdf.zoomBy(1.1);
            },
          ),
          _cmd(
            Icons.zoom_out,
            _t('Zoom out', StudioStrings.de('Zoom out'), 'تصغير'),
            () {
              _pdf.zoomBy(1 / 1.1);
            },
          ),
          _cmd(
            Icons.fit_screen_outlined,
            _t('Fit width', StudioStrings.de('Fit width'), 'عرض'),
            () {
              _togglePdfOption(() {
                _pdfFitPolicy = PdfFitPolicy.width;
                _pdf.fitVisibleWidth();
              });
            },
            selected: _pdfFitPolicy == PdfFitPolicy.width,
          ),
          _cmd(
            Icons.aspect_ratio,
            _t('Fit page', StudioStrings.de('Fit page'), 'صفحة'),
            () {
              _togglePdfOption(() {
                _pdfFitPolicy = PdfFitPolicy.page;
                final Size e = _pdf.viewport.extent;
                _pdf.fitPage(
                  e.width > 0 ? e.width : 720,
                  e.height > 0 ? e.height : 900,
                );
              });
            },
            selected: _pdfFitPolicy == PdfFitPolicy.page,
          ),
          _cmd(
            Icons.height,
            _t('Fit height', StudioStrings.de('Fit height'), 'ارتفاع'),
            () {
              _togglePdfOption(() {
                _pdfFitPolicy = PdfFitPolicy.height;
                final double h = _pdf.viewport.extent.height;
                _pdf.fitHeight(h > 0 ? h : 900);
              });
            },
            selected: _pdfFitPolicy == PdfFitPolicy.height,
          ),
          _cmd(
            Icons.search,
            _t('Find', StudioStrings.de('Find'), 'بحث'),
            _openFind,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t(
          'Viewer options',
          StudioStrings.de('Viewer options'),
          'خيارات العارض',
        ),
        children: <Widget>[
          _cmd(
            Icons.dark_mode_outlined,
            _t('Night', StudioStrings.de('Night'), 'ليلي'),
            () => _togglePdfOption(
              () => _pdfNightMode = !_pdfNightMode,
              toast: _pdfNightMode
                  ? (_t(
                      'Night mode off',
                      StudioStrings.de('Night mode off'),
                      'الوضع الليلي مغلق',
                    ))
                  : (_t(
                      'Night mode on',
                      StudioStrings.de('Night mode on'),
                      'الوضع الليلي مفعّل',
                    )),
            ),
            selected: _pdfNightMode,
          ),
          _cmd(
            Icons.swap_horiz,
            _t('Horizontal', StudioStrings.de('Horizontal'), 'أفقي'),
            () => _togglePdfOption(
              () => _pdfSwipeHorizontal = !_pdfSwipeHorizontal,
              toast: _pdfSwipeHorizontal
                  ? (_t(
                      'Vertical swipe',
                      StudioStrings.de('Vertical swipe'),
                      'تمرير عمودي',
                    ))
                  : (_t(
                      'Horizontal swipe',
                      StudioStrings.de('Horizontal swipe'),
                      'تمرير أفقي',
                    )),
            ),
            selected: _pdfSwipeHorizontal,
          ),
          _cmd(
            Icons.align_vertical_top,
            _t('Page snap', StudioStrings.de('Page snap'), 'محاذاة'),
            () => _togglePdfOption(() => _pdfPageSnap = !_pdfPageSnap),
            selected: _pdfPageSnap,
          ),
          _cmd(
            Icons.speed,
            _t('Fling', StudioStrings.de('Fling'), 'زخم'),
            () => _togglePdfOption(() => _pdfPageFling = !_pdfPageFling),
            selected: _pdfPageFling,
          ),
          _cmd(
            Icons.pan_tool_alt,
            _t('Swipe', StudioStrings.de('Swipe'), 'سحب'),
            () => _togglePdfOption(() => _pdfEnableSwipe = !_pdfEnableSwipe),
            selected: _pdfEnableSwipe,
          ),
          _cmd(
            Icons.linear_scale,
            _t('Scrollbar', StudioStrings.de('Scrollbar'), 'شريط'),
            () => _togglePdfOption(() => _pdfShowScroll = !_pdfShowScroll),
            selected: _pdfShowScroll,
          ),
          _cmd(
            Icons.link_off,
            _t('Block links', StudioStrings.de('Block links'), 'منع رابط'),
            () => _togglePdfOption(
              () => _pdfPreventLinks = !_pdfPreventLinks,
              toast: _pdfPreventLinks
                  ? (_t(
                      'Link open allowed',
                      StudioStrings.de('Link open allowed'),
                      'فتح الروابط مسموح',
                    ))
                  : (_arabic
                        ? 'الروابط تُبلَّغ فقط دون فتح'
                        : 'Links reported only'),
            ),
            selected: _pdfPreventLinks,
          ),
        ],
      ),
    ];
  }

  Widget _pdfFindBar(bool dark) {
    final int total = _pdf.findMarks.length;
    final int current = total == 0 || _pdf.findIndex < 0
        ? 0
        : _pdf.findIndex + 1;
    final String status = _pdfFind.text.isEmpty
        ? ''
        : total == 0
        ? (_t('No matches', StudioStrings.de('No matches'), 'لا نتائج'))
        : (_arabic ? '$current من $total' : '$current of $total');
    return Material(
      elevation: 4,
      color: dark ? const Color(0xFF2A2A2A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _pdfFind,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _t(
                    'Find in PDF',
                    StudioStrings.de('Find in PDF'),
                    'بحث في PDF',
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: _schedulePdfFind,
                onSubmitted: (_) => _pdfFindNext(),
              ),
            ),
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(status),
              ),
            IconButton(
              tooltip: _t('Previous', StudioStrings.de('Previous'), 'السابق'),
              onPressed: total == 0 ? null : _pdfFindPrevious,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: _t('Next', StudioStrings.de('Next'), 'التالي'),
              onPressed: total == 0 ? null : _pdfFindNext,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            IconButton(onPressed: _closeFind, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }

  void _schedulePdfFind(String query) {
    _pdfFindDebounce?.cancel();
    _pdfFindDebounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) {
        return;
      }
      _pdf.find(query);
      setState(() {});
    });
  }

  void _pdfFindNext() {
    if (_pdf.findMarks.isEmpty) {
      _pdf.find(_pdfFind.text);
    } else {
      _pdf.findNext();
    }
    setState(() {});
  }

  void _pdfFindPrevious() {
    if (_pdf.findMarks.isEmpty) {
      _pdf.find(_pdfFind.text);
    } else {
      _pdf.findPrevious();
    }
    setState(() {});
  }

  List<StudioRibbonGroup> _pdfAnnotate() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Annotate', StudioStrings.de('Annotate'), 'تعليق'),
        children: <Widget>[
          _cmd(
            Icons.highlight_outlined,
            _t('Highlight', StudioStrings.de('Highlight'), 'تمييز'),
            () {
              _pdf.highlightSelection();
            },
          ),
          _cmd(
            Icons.sticky_note_2_outlined,
            _t('Note', StudioStrings.de('Note'), 'ملاحظة'),
            () {
              _pdf.addNote(
                const PdfRect(x: 72, y: 72, width: 24, height: 24),
                _t('Note', StudioStrings.de('Note'), 'ملاحظة'),
              );
            },
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _pdfForm() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Pages', StudioStrings.de('Pages'), 'صفحات'),
        children: <Widget>[
          _cmd(
            Icons.note_add_outlined,
            _t('Blank page', StudioStrings.de('Blank page'), 'صفحة'),
            () {
              _pdf.insertBlankPage(_pdf.pageIndex + 1);
            },
          ),
          _cmd(
            Icons.rotate_right,
            _t('Rotate', StudioStrings.de('Rotate'), 'تدوير'),
            () {
              _pdf.rotateCurrentPage(90);
            },
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _fileGroups(
    VoidCallback reset,
    VoidCallback createNew,
  ) {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('File', StudioStrings.de('File'), 'ملف'),
        children: <Widget>[
          _cmd(
            Icons.note_add_outlined,
            _t('New', StudioStrings.de('New'), 'جديد'),
            createNew,
          ),
          _cmd(
            Icons.folder_open,
            _t('Open', StudioStrings.de('Open'), 'فتح'),
            _opening || _isSaving ? null : _openFile,
          ),
          _cmd(
            Icons.save_outlined,
            _strings.save,
            _isSaving || _opening ? null : _saveFile,
          ),
          _cmd(
            Icons.picture_as_pdf_outlined,
            _t('Export PDF', StudioStrings.de('Export PDF'), 'تصدير PDF'),
            _exportPdf,
          ),
          _cmd(
            Icons.refresh,
            _t(
              'Reload sample',
              StudioStrings.de('Reload sample'),
              'إعادة العينة',
            ),
            reset,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Mode', StudioStrings.de('Mode'), 'وضع العمل'),
        children: <Widget>[
          _cmd(Icons.edit, _t('Edit', StudioStrings.de('Edit'), 'تحرير'), () {
            setState(() => _mode = OfficeInteractionMode.editing);
          }, selected: _mode == OfficeInteractionMode.editing),
          _cmd(
            Icons.select_all,
            _t('Select', StudioStrings.de('Select'), 'تحديد'),
            () {
              setState(() => _mode = OfficeInteractionMode.selecting);
            },
            selected: _mode == OfficeInteractionMode.selecting,
          ),
          _cmd(
            Icons.visibility,
            _t('View', StudioStrings.de('View'), 'عرض'),
            () {
              setState(() => _mode = OfficeInteractionMode.viewing);
            },
            selected: _mode == OfficeInteractionMode.viewing,
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _wordHome() {
    return <StudioRibbonGroup>[
      _clipboardGroup(),
      StudioRibbonGroup(
        title: _t('Font', StudioStrings.de('Font'), 'خط'),
        children: <Widget>[
          StudioCombo<String>(
            value: _activeFontFamily,
            items: _fontFamilies,
            labelOf: (String name) => name,
            previewFamily: (String name) => name,
            width: 148,
            enabled: _wordFullFormat,
            tooltip: _t('Font', StudioStrings.de('Font'), 'الخط'),
            onSelected: _wordFullFormat ? _setFontFamily : null,
          ),
          const SizedBox(width: 4),
          StudioCombo<int>(
            value: _activeFontSizePt,
            items: OfficeTypeface.sizesPt,
            labelOf: (int pt) => '$pt',
            width: 52,
            enabled: _wordFullFormat,
            tooltip: _t('Size', StudioStrings.de('Size'), 'الحجم'),
            onSelected: _wordFullFormat ? _setFontSizePt : null,
          ),
          const SizedBox(width: 4),
          StudioCombo<StudioFaceStyle>(
            value: _activeFaceStyle,
            items: StudioFaceStyle.values,
            labelOf: _faceStyleLabel,
            width: 88,
            enabled: _canMutate,
            tooltip: _t('Style', StudioStrings.de('Style'), 'النوع'),
            onSelected: _canMutate ? _setFaceStyle : null,
          ),
          const SizedBox(width: 6),
          _icon(
            Icons.format_bold,
            _t('Bold', StudioStrings.de('Bold'), 'عريض'),
            _canMutate
                ? () =>
                      _word.applyRunFormat((WmlRunProps p) => p.bold = !p.bold)
                : null,
            selected: _word.activeRunProps.bold,
          ),
          _icon(
            Icons.format_italic,
            _t('Italic', StudioStrings.de('Italic'), 'مائل'),
            _canMutate
                ? () => _word.applyRunFormat(
                    (WmlRunProps p) => p.italic = !p.italic,
                  )
                : null,
            selected: _word.activeRunProps.italic,
          ),
          _icon(
            Icons.format_underline,
            _t('Underline', StudioStrings.de('Underline'), 'تسطير'),
            _canMutate
                ? () => _word.applyRunFormat((WmlRunProps p) {
                    p.underline = p.underline == WmlUnderline.none
                        ? WmlUnderline.single
                        : WmlUnderline.none;
                  })
                : null,
            selected: _word.activeRunProps.underline == WmlUnderline.single,
          ),
          _icon(
            Icons.format_strikethrough,
            _t('Strike', StudioStrings.de('Strike'), 'يتوسطه خط'),
            _canMutate
                ? () => _word.applyRunFormat(
                    (WmlRunProps p) => p.strike = !p.strike,
                  )
                : null,
            selected: _word.activeRunProps.strike,
          ),
          _icon(
            Icons.superscript,
            _t('Superscript', StudioStrings.de('Superscript'), 'مرتفع'),
            _wordFullFormat
                ? () => _toggleVertAlign(WmlVertAlign.superscript)
                : null,
            selected:
                _word.activeRunProps.vertAlign == WmlVertAlign.superscript,
          ),
          _icon(
            Icons.subscript,
            _t('Subscript', StudioStrings.de('Subscript'), 'منخفض'),
            _wordFullFormat
                ? () => _toggleVertAlign(WmlVertAlign.subscript)
                : null,
            selected: _word.activeRunProps.vertAlign == WmlVertAlign.subscript,
          ),
          _icon(
            Icons.format_color_text,
            _t('Text color', StudioStrings.de('Text color'), 'لون النص'),
            _canMutate ? _cycleTextColor : null,
          ),
          _icon(
            Icons.border_color,
            _t('Highlight', StudioStrings.de('Highlight'), 'تمييز'),
            _canMutate ? _cycleHighlight : null,
          ),
          _icon(
            Icons.text_increase,
            _t('Grow', StudioStrings.de('Grow'), 'تكبير'),
            _wordFullFormat ? () => _nudgeFontSize(2) : null,
          ),
          _icon(
            Icons.text_decrease,
            _t('Shrink', StudioStrings.de('Shrink'), 'تصغير'),
            _wordFullFormat ? () => _nudgeFontSize(-2) : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Styles', StudioStrings.de('Styles'), 'أنماط'),
        children: <Widget>[
          StudioCombo<int>(
            value: _word.activeHeadingLevel,
            items: const <int>[0, 1, 2, 3, 4],
            labelOf: _headingStyleLabel,
            width: 118,
            enabled: _wordFullFormat,
            tooltip: _t(
              'Paragraph style',
              StudioStrings.de('Paragraph style'),
              'نمط الفقرة',
            ),
            onSelected: _wordFullFormat ? _word.applyHeading : null,
          ),
          const SizedBox(width: 4),
          StudioCombo<String>(
            value: WordStyles.ofParagraph(_activeParagraph).id,
            items: <String>[
              for (final WmlStyle style in WordStyles.catalog) style.id,
            ],
            labelOf: (String id) =>
                WordStyles.byId(id)?.label(arabic: _arabic) ?? id,
            width: 132,
            enabled: _wordFullFormat,
            tooltip: _t(
              'Style gallery',
              StudioStrings.de('Style gallery'),
              'معرض الأنماط',
            ),
            onSelected: _wordFullFormat ? _word.applyStyle : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Paragraph', StudioStrings.de('Paragraph'), 'فقرة'),
        children: <Widget>[
          _icon(
            Icons.format_align_left,
            _t('Left', StudioStrings.de('Left'), 'يسار'),
            _wordFullFormat ? () => _setAlign(WmlJustification.left) : null,
            selected:
                _activeParagraph.properties.justification ==
                WmlJustification.left,
          ),
          _icon(
            Icons.format_align_center,
            _t('Center', StudioStrings.de('Center'), 'وسط'),
            _wordFullFormat ? () => _setAlign(WmlJustification.center) : null,
            selected:
                _activeParagraph.properties.justification ==
                WmlJustification.center,
          ),
          _icon(
            Icons.format_align_right,
            _t('Right', StudioStrings.de('Right'), 'يمين'),
            _wordFullFormat ? () => _setAlign(WmlJustification.right) : null,
            selected:
                _activeParagraph.properties.justification ==
                WmlJustification.right,
          ),
          _icon(
            Icons.format_align_justify,
            _t('Justify', StudioStrings.de('Justify'), 'ضبط'),
            _wordFullFormat ? () => _setAlign(WmlJustification.justify) : null,
            selected:
                _activeParagraph.properties.justification ==
                WmlJustification.justify,
          ),
          _icon(
            Icons.format_textdirection_r_to_l,
            _t('RTL', StudioStrings.de('RTL'), 'من اليمين'),
            _wordFullFormat ? () => _setWordDirection(rtl: true) : null,
            selected: _activeParagraph.properties.rightToLeft == true,
          ),
          _icon(
            Icons.format_textdirection_l_to_r,
            _t('LTR', StudioStrings.de('LTR'), 'من اليسار'),
            _wordFullFormat ? () => _setWordDirection(rtl: false) : null,
            selected: _activeParagraph.properties.rightToLeft != true,
          ),
          _icon(
            Icons.format_list_bulleted,
            _t('Bullets', StudioStrings.de('Bullets'), 'تعداد'),
            _wordFullFormat ? () => _word.toggleList(numbered: false) : null,
            selected: _activeParagraph.properties.numId == 1,
          ),
          _icon(
            Icons.format_list_numbered,
            _t('Numbering', StudioStrings.de('Numbering'), 'ترقيم'),
            _wordFullFormat ? () => _word.toggleList(numbered: true) : null,
            selected: _activeParagraph.properties.numId == 2,
          ),
          _icon(
            Icons.format_indent_increase,
            _t('Indent', StudioStrings.de('Indent'), 'زيادة المسافة'),
            _wordFullFormat ? () => _nudgeIndent(18) : null,
          ),
          _icon(
            Icons.format_indent_decrease,
            _t('Outdent', StudioStrings.de('Outdent'), 'إنقاص المسافة'),
            _wordFullFormat ? () => _nudgeIndent(-18) : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t(
          'Quick insert',
          StudioStrings.de('Quick insert'),
          'إدراج سريع',
        ),
        children: <Widget>[
          _icon(
            Icons.image_outlined,
            _t('Picture', StudioStrings.de('Picture'), 'صورة'),
            _canMutate ? () => _insertWordPicture(fromFile: true) : null,
          ),
          _icon(
            Icons.bar_chart,
            _t('Chart', StudioStrings.de('Chart'), 'مخطط'),
            _canMutate
                ? () => _insertWordVisual(OfficeVisualKind.chartColumn)
                : null,
          ),
          _icon(
            Icons.account_tree,
            _t('Process', StudioStrings.de('Process'), 'عملية'),
            _canMutate
                ? () => _insertWordVisual(OfficeVisualKind.diagramProcess)
                : null,
          ),
          _icon(
            Icons.grid_on,
            _t('Table', StudioStrings.de('Table'), 'جدول'),
            _canMutate ? () => _insertWordTable(3, 3) : null,
          ),
          _icon(
            Icons.functions,
            _t('Equation', StudioStrings.de('Equation'), 'معادلة'),
            _canMutate ? () => _insertWordEquation() : null,
          ),
        ],
      ),
      if (_word.selectedVisual != null) ..._visualRibbon(),
      if (_word.selectedEquation != null) ..._wordEquationTools(),
      if (_word.isInTable) ..._wordTableTools(),
    ];
  }

  List<StudioRibbonGroup> _wordTableTools() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Table', StudioStrings.de('Table'), 'جدول'),
        children: <Widget>[
          _cmd(
            Icons.keyboard_arrow_up,
            _t('Row above', StudioStrings.de('Row above'), 'صف أعلى'),
            _canMutate ? () => _word.insertTableRow(after: false) : null,
          ),
          _cmd(
            Icons.keyboard_arrow_down,
            _t('Row below', StudioStrings.de('Row below'), 'صف أسفل'),
            _canMutate ? () => _word.insertTableRow(after: true) : null,
          ),
          _cmd(
            Icons.keyboard_arrow_left,
            _t('Column left', StudioStrings.de('Column left'), 'عمود يسار'),
            _canMutate ? () => _word.insertTableColumn(after: false) : null,
          ),
          _cmd(
            Icons.keyboard_arrow_right,
            _t('Column right', StudioStrings.de('Column right'), 'عمود يمين'),
            _canMutate ? () => _word.insertTableColumn(after: true) : null,
          ),
          _cmd(
            Icons.table_rows,
            _t('Delete row', StudioStrings.de('Delete row'), 'حذف صف'),
            _canMutate ? () => _word.deleteTableRow() : null,
          ),
          _cmd(
            Icons.view_column,
            _t('Delete column', StudioStrings.de('Delete column'), 'حذف عمود'),
            _canMutate ? () => _word.deleteTableColumn() : null,
          ),
          _cmd(
            Icons.call_merge,
            _t('Merge', StudioStrings.de('Merge'), 'دمج'),
            _canMutate && _word.canMergeTableCells
                ? () => _word.mergeTableCells()
                : null,
          ),
          _cmd(
            Icons.call_split,
            _t('Split', StudioStrings.de('Split'), 'إلغاء الدمج'),
            _canMutate && _word.canUnmergeTableCells
                ? () => _word.unmergeTableCells()
                : null,
          ),
          _cmd(
            Icons.fit_screen,
            _t('Contents', StudioStrings.de('Contents'), 'محتوى'),
            _canMutate
                ? () => _word.autoFitTable(WordTableAutoFit.contents)
                : null,
          ),
          _cmd(
            Icons.width_full,
            _t('Window', StudioStrings.de('Window'), 'نافذة'),
            _canMutate
                ? () => _word.autoFitTable(WordTableAutoFit.window)
                : null,
          ),
          _cmd(
            Icons.view_week_outlined,
            _t('Fixed', StudioStrings.de('Fixed'), 'ثابت'),
            _canMutate
                ? () => _word.autoFitTable(WordTableAutoFit.fixed)
                : null,
          ),
          _cmd(
            Icons.delete_outline,
            _t('Delete table', StudioStrings.de('Delete table'), 'حذف الجدول'),
            _canMutate ? _word.deleteTable : null,
          ),
        ],
      ),
    ];
  }

  bool get _canOpenZotero =>
      mounted &&
      !_zoteroOpen &&
      _app == SuiteApp.word &&
      !_word.isDisposed &&
      _wordRouteIsCurrent;

  bool get _canRunZoteroCommand {
    final body = _word.input.composing;
    final note = _word.noteEditingTarget?.composing;
    return _canOpenZotero &&
        _canMutate &&
        _word.config.allowsMutation &&
        (!body.isValid || body.isCollapsed) &&
        (note == null || !note.isValid || note.isCollapsed);
  }

  void _addEditZoteroCitation() =>
      unawaited(_openZotero(command: ZoteroCitingCommand.addEditCitation));

  void _refreshZoteroCitations() =>
      unawaited(_openZotero(command: ZoteroCitingCommand.refresh));

  Future<void> _openZotero({ZoteroCitingCommand? command}) async {
    if (!_canOpenZotero ||
        (command != null &&
            (!_canRunZoteroCommand || !studioZoteroDesktopAvailable))) {
      return;
    }
    final transport =
        widget.zoteroTransportFactory?.call() ?? StudioZoteroTransport();
    setState(() => _zoteroOpen = true);
    try {
      await showWordZoteroDialog(
        context,
        controller: _word,
        session: _zoteroSession,
        transport: transport.send,
        localTransport: transport.supportsLocal ? transport.send : null,
        initialCommand: command,
        closeAfterCommand: command != null,
      );
    } finally {
      transport.dispose();
      if (mounted) setState(() => _zoteroOpen = false);
    }
  }

  Widget _zoteroCommand(
    IconData icon,
    String label,
    ZoteroCitingCommand command, {
    String? shortcut,
  }) {
    final button = _cmd(
      icon,
      label,
      _canRunZoteroCommand ? () => _openZotero(command: command) : null,
    );
    if (shortcut == null) return button;
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? 'Cmd+Alt'
        : 'Ctrl+Alt';
    return Tooltip(
      message: '$label ($modifier+$shortcut)',
      child: TooltipVisibility(visible: false, child: button),
    );
  }

  List<StudioRibbonGroup> _wordInsert() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('References', StudioStrings.de('References'), 'المراجع'),
        children: <Widget>[
          _cmd(
            Icons.menu_book_outlined,
            'Zotero',
            _canOpenZotero ? _openZotero : null,
          ),
          if (studioZoteroDesktopAvailable) ...[
            _zoteroCommand(
              Icons.format_quote,
              _t(
                'Add/Edit citation',
                StudioStrings.de('Add/Edit citation'),
                'إضافة/تحرير استشهاد',
              ),
              ZoteroCitingCommand.addEditCitation,
              shortcut: 'C',
            ),
            _zoteroCommand(
              Icons.list_alt,
              _t(
                'Bibliography',
                StudioStrings.de('Bibliography'),
                'قائمة المراجع',
              ),
              ZoteroCitingCommand.addEditBibliography,
            ),
            _zoteroCommand(
              Icons.note_add_outlined,
              _t(
                'Add Zotero note',
                StudioStrings.de('Add Zotero note'),
                'ملاحظة من Zotero',
              ),
              ZoteroCitingCommand.addNote,
            ),
            _zoteroCommand(
              Icons.format_quote_outlined,
              _t(
                'Add Zotero annotation',
                StudioStrings.de('Add Zotero annotation'),
                'تعليق توضيحي من Zotero',
              ),
              ZoteroCitingCommand.addAnnotation,
            ),
            _zoteroCommand(
              Icons.refresh,
              _t(
                'Refresh citations',
                StudioStrings.de('Refresh citations'),
                'تحديث الاستشهادات',
              ),
              ZoteroCitingCommand.refresh,
              shortcut: 'R',
            ),
            _zoteroCommand(
              Icons.format_paint_outlined,
              _t(
                'Citation style',
                StudioStrings.de('Citation style'),
                'نمط الاستشهاد',
              ),
              ZoteroCitingCommand.setDocPrefs,
            ),
          ],
        ],
      ),
      StudioRibbonGroup(
        title: _t('Pages', StudioStrings.de('Pages'), 'صفحات'),
        children: <Widget>[
          _cmd(
            Icons.insert_page_break,
            _t('Page break', StudioStrings.de('Page break'), 'فاصل صفحة'),
            _canMutate ? _insertPageBreak : null,
          ),
          _cmd(
            Icons.note_add_outlined,
            _t('Blank page', StudioStrings.de('Blank page'), 'صفحة فارغة'),
            _canMutate ? _insertPageBreak : null,
          ),
          _cmd(
            Icons.view_week,
            _t('Column break', StudioStrings.de('Column break'), 'فاصل عمود'),
            _canMutate
                ? () {
                    _word.insertColumnBreak();
                    _word.refresh();
                  }
                : null,
          ),
          _cmd(
            Icons.vertical_split_outlined,
            _t('Section break', StudioStrings.de('Section break'), 'فاصل قسم'),
            _canMutate
                ? () {
                    _word.insertSectionBreak();
                    _word.refresh();
                  }
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Text', StudioStrings.de('Text'), 'نص'),
        children: <Widget>[
          _cmd(
            Icons.title,
            _t('Heading 1', StudioStrings.de('Heading 1'), 'عنوان ١'),
            _canMutate
                ? () => _word.insertHeading(
                    level: 1,
                    text: _t(
                      'New heading',
                      StudioStrings.de('New heading'),
                      'عنوان جديد',
                    ),
                  )
                : null,
          ),
          _cmd(
            Icons.text_fields,
            _t('Heading 2', StudioStrings.de('Heading 2'), 'عنوان ٢'),
            _canMutate
                ? () => _word.insertHeading(
                    level: 2,
                    text: _t(
                      'New subheading',
                      StudioStrings.de('New subheading'),
                      'عنوان فرعي',
                    ),
                  )
                : null,
          ),
          _cmd(
            Icons.list_alt,
            _t('Contents', StudioStrings.de('Contents'), 'المحتويات'),
            _canMutate
                ? () => _word.insertTableOfContents(
                    title: _t(
                      'Table of Contents',
                      StudioStrings.de('Table of Contents'),
                      'جدول المحتويات',
                    ),
                  )
                : null,
          ),
          _cmd(
            Icons.sync,
            _t('Update all', StudioStrings.de('Update all'), 'تحديث الكل'),
            _canMutate && WordToc.tocs(_word.document).isNotEmpty
                ? () => _word.updateTableOfContents()
                : null,
          ),
          _cmd(
            Icons.filter_9,
            _t(
              'Page numbers',
              StudioStrings.de('Page numbers'),
              'أرقام الصفحات',
            ),
            _canMutate && WordToc.tocs(_word.document).isNotEmpty
                ? () => _word.updateTableOfContents(pageNumbersOnly: true)
                : null,
          ),
          _cmd(
            Icons.link,
            _t('Web link', StudioStrings.de('Web link'), 'رابط ويب'),
            _canMutate ? () => _insertWordLink(kind: _WordLinkKind.web) : null,
          ),
          _cmd(
            Icons.insert_link,
            _t('Cross-ref', StudioStrings.de('Cross-ref'), 'مرجع داخلي'),
            _canMutate
                ? () => _insertWordLink(kind: _WordLinkKind.bookmark)
                : null,
          ),
          _cmd(
            Icons.folder_open,
            _t('File link', StudioStrings.de('File link'), 'ملف محلي'),
            _canMutate ? () => _insertWordLink(kind: _WordLinkKind.file) : null,
          ),
          _cmd(
            Icons.superscript,
            _t('Footnote', StudioStrings.de('Footnote'), 'حاشية'),
            _canMutate ? () => _word.insertFootnote() : null,
          ),
          _cmd(
            Icons.subscript,
            _t('Endnote', StudioStrings.de('Endnote'), 'نهاية حاشية'),
            _canMutate ? () => _word.insertFootnote(endnote: true) : null,
          ),
          _cmd(
            Icons.subtitles_outlined,
            _t('Caption', StudioStrings.de('Caption'), 'تسمية'),
            _canMutate ? () => _word.insertCaption() : null,
          ),
          _cmd(
            Icons.collections_bookmark_outlined,
            _t('Figures', StudioStrings.de('Figures'), 'جدول أشكال'),
            _canMutate ? () => _word.insertTableOfFigures() : null,
          ),
          _cmd(
            Icons.pin,
            _t('Page #', StudioStrings.de('Page #'), 'رقم صفحة'),
            _canMutate ? () => _word.insertField(WmlFieldKind.page) : null,
          ),
          _cmd(
            Icons.calendar_today,
            _t('Date', StudioStrings.de('Date'), 'تاريخ'),
            _canMutate ? () => _word.insertField(WmlFieldKind.date) : null,
          ),
          _cmd(
            Icons.branding_watermark,
            _t('Watermark', StudioStrings.de('Watermark'), 'علامة مائية'),
            _canMutate
                ? () => _word.setWatermark(
                    _t('DRAFT', StudioStrings.de('DRAFT'), 'مسودة'),
                  )
                : null,
          ),
          _cmd(
            Icons.short_text,
            _t('Paragraph', StudioStrings.de('Paragraph'), 'فقرة'),
            _canMutate
                ? () {
                    _word.insertParagraphBreak();
                    _word.insertText(
                      _arabic
                          ? 'فقرة يمكن تحريرها مباشرة من لوحة المفاتيح.'
                          : 'A paragraph you can type into immediately.',
                    );
                  }
                : null,
          ),
          _cmd(
            Icons.format_quote,
            _t('Quote', StudioStrings.de('Quote'), 'اقتباس'),
            _canMutate ? _insertQuote : null,
          ),
          _cmd(
            Icons.crop_square,
            _t('Text box', StudioStrings.de('Text box'), 'إطار نص'),
            _canMutate
                ? () {
                    _word.insertTextFrame(
                      text: _t(
                        'Text box',
                        StudioStrings.de('Text box'),
                        'إطار نص',
                      ),
                    );
                    _word.refresh();
                  }
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Table', StudioStrings.de('Table'), 'جدول'),
        children: <Widget>[
          _cmd(
            Icons.table_chart,
            _t('2×2', StudioStrings.de('2×2'), '٢×٢'),
            _canMutate ? () => _insertWordTable(2, 2) : null,
          ),
          _cmd(
            Icons.grid_on,
            _t('3×3', StudioStrings.de('3×3'), '٣×٣'),
            _canMutate ? () => _insertWordTable(3, 3) : null,
          ),
          _cmd(
            Icons.table_view,
            _t('4×4', StudioStrings.de('4×4'), '٤×٤'),
            _canMutate ? () => _insertWordTable(4, 4) : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Illustrations', StudioStrings.de('Illustrations'), 'رسوم'),
        children: <Widget>[
          _cmd(
            Icons.image_outlined,
            _t('Picture', StudioStrings.de('Picture'), 'صورة'),
            _canMutate ? () => _insertWordPicture(fromFile: true) : null,
          ),
          _cmd(
            Icons.bar_chart,
            _t('Column', StudioStrings.de('Column'), 'أعمدة'),
            _canMutate
                ? () => _insertWordVisual(OfficeVisualKind.chartColumn)
                : null,
          ),
          _cmd(
            Icons.stacked_bar_chart,
            _t('Bar', StudioStrings.de('Bar'), 'شريطي'),
            _canMutate
                ? () => _insertWordVisual(OfficeVisualKind.chartBar)
                : null,
          ),
          _cmd(
            Icons.pie_chart,
            _t('Pie', StudioStrings.de('Pie'), 'دائري'),
            _canMutate
                ? () => _insertWordVisual(OfficeVisualKind.chartPie)
                : null,
          ),
          _cmd(
            Icons.show_chart,
            _t('Line', StudioStrings.de('Line'), 'خطي'),
            _canMutate
                ? () => _insertWordVisual(OfficeVisualKind.chartLine)
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Diagram', StudioStrings.de('Diagram'), 'مخطط'),
        children: <Widget>[
          _cmd(
            Icons.linear_scale,
            _t('Process', StudioStrings.de('Process'), 'عملية'),
            _canMutate
                ? () => _insertWordVisual(OfficeVisualKind.diagramProcess)
                : null,
          ),
          _cmd(
            Icons.sync,
            _t('Cycle', StudioStrings.de('Cycle'), 'دورة'),
            _canMutate
                ? () => _insertWordVisual(OfficeVisualKind.diagramCycle)
                : null,
          ),
          _cmd(
            Icons.account_tree,
            _t('Tree', StudioStrings.de('Tree'), 'هرمي'),
            _canMutate
                ? () => _insertWordVisual(OfficeVisualKind.diagramHierarchy)
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('References', StudioStrings.de('References'), 'مراجع'),
        children: <Widget>[
          _cmd(
            Icons.format_quote,
            _t('Citation', StudioStrings.de('Citation'), 'استشهاد'),
            _canMutate ? _insertStudioCitation : null,
          ),
          _cmd(
            Icons.menu_book_outlined,
            _t('Bibliography', StudioStrings.de('Bibliography'), 'مراجع'),
            _canMutate ? _word.insertBibliography : null,
          ),
          _cmd(
            Icons.bookmark_add_outlined,
            _t('Mark index', StudioStrings.de('Mark index'), 'فهرس'),
            _canMutate
                ? () => _word.markIndexTerm(
                    _t('Term', StudioStrings.de('Term'), 'مصطلح'),
                  )
                : null,
          ),
          _cmd(
            Icons.list_alt_outlined,
            _t('Index', StudioStrings.de('Index'), 'إدراج الفهرس'),
            _canMutate ? _word.insertIndex : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Mailings', StudioStrings.de('Mailings'), 'مراسلات'),
        children: <Widget>[
          _cmd(
            Icons.mark_email_read_outlined,
            _t('Merge', StudioStrings.de('Merge'), 'دمج'),
            _canMutate ? _studioMergeMail : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Equations', StudioStrings.de('Equations'), 'معادلات'),
        children: <Widget>[
          _cmd(
            Icons.functions,
            _t('Equation', StudioStrings.de('Equation'), 'معادلة'),
            _canMutate ? () => _insertWordEquation() : null,
          ),
          _cmd(
            Icons.calculate_outlined,
            _t('Quadratic', StudioStrings.de('Quadratic'), 'تربيعي'),
            _canMutate ? () => _insertWordEquation(id: 'quadratic') : null,
          ),
          _cmd(
            Icons.integration_instructions_outlined,
            _t('Integral', StudioStrings.de('Integral'), 'تكامل'),
            _canMutate ? () => _insertWordEquation(id: 'integral') : null,
          ),
          StudioCombo<String>(
            value: 'gallery',
            width: 132,
            enabled: _canMutate,
            tooltip: _t(
              'Equation gallery',
              StudioStrings.de('Equation gallery'),
              'معرض المعادلات',
            ),
            items: <String>[
              'gallery',
              for (final OmmlGalleryItem item in OmmlGallery.items)
                if (item.id != 'blank') item.id,
            ],
            labelOf: (String id) {
              if (id == 'gallery') {
                return _t('Gallery', StudioStrings.de('Gallery'), 'المعرض');
              }
              return OmmlGallery.byId(id).title(arabic: _arabic);
            },
            onSelected: _canMutate
                ? (String id) {
                    if (id != 'gallery') {
                      _insertWordEquation(id: id);
                    }
                  }
                : null,
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _wordLayout() {
    final WmlParagraphProps para = _activeParagraph.properties;
    final WmlPageMargins margins = _word.pageMargins;
    final WmlPageSize size = _word.pageSize;
    final int columns = _word.sectionAtCaret.columnCount;
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Margins', StudioStrings.de('Margins'), 'الهوامش'),
        children: <Widget>[
          StudioCombo<String>(
            value: _marginPresetId(margins),
            items: const <String>['normal', 'narrow', 'moderate', 'wide'],
            labelOf: _marginPresetLabel,
            width: 118,
            enabled: _canMutate,
            tooltip: _t(
              'Page margins',
              StudioStrings.de('Page margins'),
              'هوامش الصفحة',
            ),
            onSelected: _canMutate ? _applyMarginPreset : null,
          ),
          _cmd(
            Icons.border_outer,
            _t('Normal', StudioStrings.de('Normal'), 'عادي'),
            _canMutate
                ? () => _word.setPageMargins(WmlPageMargins.normal)
                : null,
            selected: margins.matches(WmlPageMargins.normal),
          ),
          _cmd(
            Icons.border_clear,
            _t('Narrow', StudioStrings.de('Narrow'), 'ضيق'),
            _canMutate
                ? () => _word.setPageMargins(WmlPageMargins.narrow)
                : null,
            selected: margins.matches(WmlPageMargins.narrow),
          ),
          _cmd(
            Icons.border_style,
            _t('Moderate', StudioStrings.de('Moderate'), 'متوسط'),
            _canMutate
                ? () => _word.setPageMargins(WmlPageMargins.moderate)
                : null,
            selected: margins.matches(WmlPageMargins.moderate),
          ),
          _cmd(
            Icons.border_all,
            _t('Wide', StudioStrings.de('Wide'), 'واسع'),
            _canMutate ? () => _word.setPageMargins(WmlPageMargins.wide) : null,
            selected: margins.matches(WmlPageMargins.wide),
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Orientation', StudioStrings.de('Orientation'), 'الاتجاه'),
        children: <Widget>[
          _cmd(
            Icons.crop_portrait,
            _t('Portrait', StudioStrings.de('Portrait'), 'عمودي'),
            _canMutate ? () => _word.setPageLandscape(false) : null,
            selected: !size.isLandscape,
          ),
          _cmd(
            Icons.crop_landscape,
            _t('Landscape', StudioStrings.de('Landscape'), 'أفقي'),
            _canMutate ? () => _word.setPageLandscape(true) : null,
            selected: size.isLandscape,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Size', StudioStrings.de('Size'), 'الحجم'),
        children: <Widget>[
          _cmd(
            Icons.crop_din,
            'A4',
            _canMutate
                ? () => _word.setPageSize(
                    size.isLandscape
                        ? WmlPageSize.a4().landscape
                        : WmlPageSize.a4(),
                  )
                : null,
            selected: size.portrait.matches(WmlPageSize.a4()),
          ),
          _cmd(
            Icons.crop_5_4,
            'Letter',
            _canMutate
                ? () => _word.setPageSize(
                    size.isLandscape
                        ? WmlPageSize.letter().landscape
                        : WmlPageSize.letter(),
                  )
                : null,
            selected: size.portrait.matches(WmlPageSize.letter()),
          ),
          _cmd(
            Icons.crop_16_9,
            'Legal',
            _canMutate
                ? () => _word.setPageSize(
                    size.isLandscape
                        ? WmlPageSize.legal().landscape
                        : WmlPageSize.legal(),
                  )
                : null,
            selected: size.portrait.matches(WmlPageSize.legal()),
          ),
          _cmd(
            Icons.crop_3_2,
            'A3',
            _canMutate
                ? () => _word.setPageSize(
                    size.isLandscape
                        ? WmlPageSize.a3().landscape
                        : WmlPageSize.a3(),
                  )
                : null,
            selected: size.portrait.matches(WmlPageSize.a3()),
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Columns', StudioStrings.de('Columns'), 'أعمدة'),
        children: <Widget>[
          _cmd(
            Icons.view_agenda,
            _t('One', StudioStrings.de('One'), 'واحد'),
            _canMutate ? () => _word.setSectionColumns(1) : null,
            selected: columns == 1,
          ),
          _cmd(
            Icons.view_column,
            _t('Two', StudioStrings.de('Two'), 'اثنان'),
            _canMutate ? () => _word.setSectionColumns(2, sep: true) : null,
            selected: columns == 2,
          ),
          _cmd(
            Icons.view_week,
            _t('Three', StudioStrings.de('Three'), 'ثلاثة'),
            _canMutate ? () => _word.setSectionColumns(3, sep: true) : null,
            selected: columns == 3,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Breaks', StudioStrings.de('Breaks'), 'فواصل'),
        children: <Widget>[
          _cmd(
            Icons.insert_page_break,
            _t('Page', StudioStrings.de('Page'), 'صفحة'),
            _canMutate ? _insertPageBreak : null,
          ),
          _cmd(
            Icons.view_week_outlined,
            _t('Column', StudioStrings.de('Column'), 'عمود'),
            _canMutate
                ? () {
                    _word.insertColumnBreak();
                    _word.refresh();
                  }
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Paragraph', StudioStrings.de('Paragraph'), 'فقرة'),
        children: <Widget>[
          _cmd(
            Icons.format_line_spacing,
            '1.0',
            _canMutate ? () => _setLineSpacing(1.0) : null,
            selected: para.lineSpacing == 1.0,
          ),
          _cmd(
            Icons.format_line_spacing,
            '1.15',
            _canMutate ? () => _setLineSpacing(1.15) : null,
            selected: para.lineSpacing == 1.15,
          ),
          _cmd(
            Icons.format_line_spacing,
            '1.5',
            _canMutate ? () => _setLineSpacing(1.5) : null,
            selected: para.lineSpacing == 1.5,
          ),
          _cmd(
            Icons.format_line_spacing,
            '2.0',
            _canMutate ? () => _setLineSpacing(2.0) : null,
            selected: para.lineSpacing == 2.0,
          ),
          _cmd(
            Icons.vertical_align_top,
            _t('Before+', StudioStrings.de('Before+'), 'قبل+'),
            _canMutate ? () => _nudgeParagraphSpacing(before: 6) : null,
          ),
          _cmd(
            Icons.vertical_align_bottom,
            _t('After+', StudioStrings.de('After+'), 'بعد+'),
            _canMutate ? () => _nudgeParagraphSpacing(after: 6) : null,
          ),
          _cmd(
            Icons.format_indent_increase,
            _t('Indent', StudioStrings.de('Indent'), 'مسافة'),
            _canMutate ? () => _nudgeIndent(18) : null,
          ),
          _cmd(
            Icons.format_indent_decrease,
            _t('Outdent', StudioStrings.de('Outdent'), 'إنقاص'),
            _canMutate ? () => _nudgeIndent(-18) : null,
          ),
          _cmd(
            Icons.subdirectory_arrow_right,
            _t('First line', StudioStrings.de('First line'), 'سطر أول'),
            _canMutate ? _toggleFirstLineIndent : null,
            selected: para.indent.firstLine > 0,
          ),
          _cmd(
            Icons.subdirectory_arrow_left,
            _t('Hanging', StudioStrings.de('Hanging'), 'معلّق'),
            _canMutate ? _toggleHangingIndent : null,
            selected: para.indent.hanging > 0,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Header', StudioStrings.de('Header'), 'ترويسة'),
        children: <Widget>[
          _cmd(
            Icons.web_asset,
            _t('Header', StudioStrings.de('Header'), 'ترويسة'),
            _canMutate
                ? () {
                    if (_word.isEditingHeader) {
                      _word.endHeaderFooterEdit();
                    } else {
                      _word.beginHeaderFooterEdit(
                        _word.visiblePageIndex,
                        footer: false,
                      );
                    }
                    setState(() {});
                  }
                : null,
            selected: _word.isEditingHeader,
          ),
          _cmd(
            Icons.web_asset_outlined,
            _t('Footer', StudioStrings.de('Footer'), 'تذييل'),
            _canMutate
                ? () {
                    if (_word.isEditingFooter) {
                      _word.endHeaderFooterEdit();
                    } else {
                      _word.beginHeaderFooterEdit(
                        _word.visiblePageIndex,
                        footer: true,
                      );
                    }
                    setState(() {});
                  }
                : null,
            selected: _word.isEditingFooter,
          ),
          _cmd(
            Icons.done,
            _t('Close', StudioStrings.de('Close'), 'إغلاق'),
            _word.isEditingHeaderFooter ? _word.endHeaderFooterEdit : null,
          ),
          _cmd(
            Icons.filter_1,
            _t('First page', StudioStrings.de('First page'), 'أول صفحة'),
            _canMutate
                ? () => _word.setDifferentFirstPage(
                    !_word.sectionAtCaret.differentFirstPage,
                  )
                : null,
            selected: _word.sectionAtCaret.differentFirstPage,
          ),
          _cmd(
            Icons.swap_vert,
            _t('Odd/even', StudioStrings.de('Odd/even'), 'فردي/زوجي'),
            _canMutate
                ? () => _word.setDifferentOddEven(
                    !_word.sectionAtCaret.differentOddEven,
                  )
                : null,
            selected: _word.sectionAtCaret.differentOddEven,
          ),
          _cmd(
            Icons.link,
            _t('Link prev', StudioStrings.de('Link prev'), 'ربط بالسابق'),
            _canMutate
                ? () => _word.setLinkToPrevious(
                    !_word.sectionAtCaret.linkToPrevious,
                  )
                : null,
            selected: _word.sectionAtCaret.linkToPrevious,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t(
          'Paragraph look',
          StudioStrings.de('Paragraph look'),
          'مظهر الفقرة',
        ),
        children: <Widget>[
          _cmd(
            Icons.format_size,
            _t('Drop cap', StudioStrings.de('Drop cap'), 'حرف استهلالي'),
            _canMutate
                ? () => _word.setDropCap(para.dropCapLines > 0 ? 0 : 3)
                : null,
            selected: para.dropCapLines > 0,
          ),
          _cmd(
            Icons.format_list_numbered,
            _t('Line numbers', StudioStrings.de('Line numbers'), 'ترقيم أسطر'),
            _canMutate
                ? () => _word.setLineNumbers(!_word.sectionAtCaret.lineNumbers)
                : null,
            selected: _word.sectionAtCaret.lineNumbers,
          ),
          _cmd(
            Icons.format_color_fill,
            _t('Shading', StudioStrings.de('Shading'), 'تظليل'),
            _canMutate
                ? () => _word.setParagraphShading(
                    para.shadingFill == null ? 'FFF2CC' : null,
                  )
                : null,
            selected: para.shadingFill != null,
          ),
          _cmd(
            Icons.border_outer,
            _t('Border', StudioStrings.de('Border'), 'حدود'),
            _canMutate
                ? () => _word.setParagraphBorder(
                    para.borderColor == null ? '2E75B6' : null,
                  )
                : null,
            selected: para.borderColor != null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Interface', StudioStrings.de('Interface'), 'واجهة'),
        children: <Widget>[
          _cmd(Icons.format_textdirection_r_to_l, 'RTL', () {
            setState(() => _arabic = true);
          }, selected: _arabic),
          _cmd(Icons.format_textdirection_l_to_r, 'LTR', () {
            setState(() => _arabic = false);
          }, selected: !_arabic),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _wordReview() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Proofing', StudioStrings.de('Proofing'), 'التدقيق'),
        children: <Widget>[
          _cmd(
            Icons.spellcheck,
            _t('Spelling', StudioStrings.de('Spelling'), 'تدقيق'),
            _showSpelling,
            selected:
                _word.reviewPaneVisible &&
                _word.reviewPaneTab == WordReviewPaneTab.proofing,
          ),
          _cmd(
            Icons.menu_book_outlined,
            _t('Thesaurus', StudioStrings.de('Thesaurus'), 'قاموس المرادفات'),
            _word.requestThesaurus,
          ),
          _cmd(
            Icons.download_for_offline_outlined,
            _t(
              'Dictionaries',
              StudioStrings.de('Dictionaries'),
              'قواميس التدقيق',
            ),
            _showHunspellSetup,
          ),
          _cmd(
            Icons.edit_note,
            _t(
              'Check as you type',
              StudioStrings.de('Check as you type'),
              'تدقيق أثناء الكتابة',
            ),
            () => _word.proofing.enabled = !_word.proofing.enabled,
            selected: _word.proofing.enabled,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Changes', StudioStrings.de('Changes'), 'تغييرات'),
        children: <Widget>[
          _cmd(
            Icons.rate_review_outlined,
            _t(
              'Review changes',
              StudioStrings.de('Review changes'),
              'مراجعة التغييرات',
            ),
            () => _word.openReviewPane(tab: WordReviewPaneTab.changes),
            selected:
                _word.reviewPaneVisible &&
                _word.reviewPaneTab == WordReviewPaneTab.changes,
          ),
          _cmd(
            Icons.track_changes,
            _t('Track', StudioStrings.de('Track'), 'تعقب'),
            _canMutate
                ? () => _word.setTrackRevisions(!_word.document.trackRevisions)
                : null,
            selected: _word.document.trackRevisions,
          ),
          _cmd(
            Icons.done_all,
            _t('Accept', StudioStrings.de('Accept'), 'قبول'),
            !_canMutate || _word.selectedRevision == null
                ? null
                : () => _word.acceptRevision(_word.selectedRevision!),
          ),
          _cmd(
            Icons.remove_done,
            _t('Reject', StudioStrings.de('Reject'), 'رفض'),
            !_canMutate || _word.selectedRevision == null
                ? null
                : () => _word.rejectRevision(_word.selectedRevision!),
          ),
          _cmd(
            Icons.keyboard_arrow_up,
            _t('Prev change', StudioStrings.de('Prev change'), 'تغيير سابق'),
            _word.document.revisions.isEmpty
                ? null
                : () => _word.stepRevision(-1),
          ),
          _cmd(
            Icons.keyboard_arrow_down,
            _t('Next change', StudioStrings.de('Next change'), 'تغيير تالٍ'),
            _word.document.revisions.isEmpty
                ? null
                : () => _word.stepRevision(1),
          ),
          _cmd(
            Icons.done_outline,
            _t('Accept all', StudioStrings.de('Accept all'), 'قبول الكل'),
            !_canMutate || _word.document.revisions.isEmpty
                ? null
                : _word.acceptAllRevisions,
          ),
          _cmd(
            Icons.remove_circle_outline,
            _t('Reject all', StudioStrings.de('Reject all'), 'رفض الكل'),
            !_canMutate || _word.document.revisions.isEmpty
                ? null
                : _word.rejectAllRevisions,
          ),
          _cmd(
            Icons.sync,
            _t(
              'Update fields',
              StudioStrings.de('Update fields'),
              'تحديث حقول',
            ),
            _canMutate ? _word.updateFields : null,
          ),
          _cmd(
            Icons.lock_outline,
            _t('Restrict', StudioStrings.de('Restrict'), 'تقييد'),
            _canMutate
                ? () =>
                      _word.setRestrictEditing(!_word.document.restrictEditing)
                : null,
            selected: _word.document.restrictEditing,
          ),
          _cmd(
            Icons.compare_arrows,
            _t('Compare', StudioStrings.de('Compare'), 'مقارنة'),
            _studioCompareDocument,
          ),
          _cmd(
            Icons.print,
            _t(
              'Print preview',
              StudioStrings.de('Print preview'),
              'معاينة طباعة',
            ),
            () => setState(() => _printPreview = !_printPreview),
            selected: _printPreview,
          ),
          _cmd(
            Icons.preview,
            _t('Merge record', StudioStrings.de('Merge record'), 'سجل دمج'),
            _canMutate ? _studioMergePreview : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t(
          'Language analysis',
          StudioStrings.de('Language analysis'),
          'تحليل لغوي',
        ),
        children: <Widget>[
          _cmd(
            Icons.manage_search,
            _t(
              'German analysis',
              StudioStrings.de('German analysis'),
              'تحليل الألمانية',
            ),
            _showLinguisticAnalysis,
          ),
          _cmd(
            Icons.download_for_offline_outlined,
            _t(
              'Analysis setup',
              StudioStrings.de('Analysis setup'),
              'إعداد التحليل',
            ),
            _showSpacySetup,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Select', StudioStrings.de('Select'), 'تحديد'),
        children: <Widget>[
          _cmd(
            Icons.select_all,
            _t('All', StudioStrings.de('All'), 'الكل'),
            _selectAllDocument,
          ),
          _cmd(
            Icons.text_fields,
            _t('Word', StudioStrings.de('Word'), 'كلمة'),
            _word.selectWordAtCaret,
          ),
          _cmd(
            Icons.notes,
            _t('Paragraph', StudioStrings.de('Paragraph'), 'فقرة'),
            _word.selectParagraphAtCaret,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Edit', StudioStrings.de('Edit'), 'تحرير'),
        children: <Widget>[
          _cmd(
            Icons.undo,
            _strings.undo,
            _canMutate && _word.canUndo ? _word.undo : null,
          ),
          _cmd(
            Icons.redo,
            _strings.redo,
            _canMutate && _word.canRedo ? _word.redo : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Comments', StudioStrings.de('Comments'), 'تعليقات'),
        children: <Widget>[
          _cmd(
            Icons.view_sidebar_outlined,
            _t('Pane', StudioStrings.de('Pane'), 'اللوحة'),
            () => _setShowComments(!_showComments),
            selected: _showComments,
          ),
          _cmd(
            Icons.add_comment_outlined,
            _t('New', StudioStrings.de('New'), 'جديد'),
            _canMutate ? _newWordComment : null,
          ),
          _cmd(
            Icons.reply,
            _t('Reply', StudioStrings.de('Reply'), 'رد'),
            _canMutate && _word.selectedComment != null
                ? () => _replyWordComment(_word.selectedCommentId!)
                : null,
          ),
          _cmd(
            _selectedThreadResolved ? Icons.replay : Icons.task_alt,
            _selectedThreadResolved
                ? (_t('Reopen', StudioStrings.de('Reopen'), 'إعادة فتح'))
                : (_t('Resolve', StudioStrings.de('Resolve'), 'حل')),
            _canMutate && _word.selectedComment != null
                ? () => _word.setCommentResolved(
                    _word.selectedCommentId!,
                    !_selectedThreadResolved,
                  )
                : null,
          ),
          _cmd(
            Icons.delete_outline,
            _t('Delete', StudioStrings.de('Delete'), 'حذف'),
            _canMutate && _word.selectedCommentId != null
                ? () => _word.deleteComment(_word.selectedCommentId!)
                : null,
          ),
          _cmd(
            Icons.keyboard_arrow_up,
            _t('Previous', StudioStrings.de('Previous'), 'السابق'),
            WordComment.roots(_word.document).isNotEmpty
                ? () => _word.stepComment(-1)
                : null,
          ),
          _cmd(
            Icons.keyboard_arrow_down,
            _t('Next', StudioStrings.de('Next'), 'التالي'),
            WordComment.roots(_word.document).isNotEmpty
                ? () => _word.stepComment(1)
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Document', StudioStrings.de('Document'), 'تحرير المستند'),
        children: <Widget>[
          _cmd(
            Icons.search,
            _t('Find', StudioStrings.de('Find'), 'بحث'),
            _openFind,
          ),
          _cmd(
            Icons.find_replace,
            _t('Replace', StudioStrings.de('Replace'), 'استبدال'),
            _canMutate ? _openReplace : null,
          ),
          _cmd(
            Icons.info_outline,
            _t('Properties', StudioStrings.de('Properties'), 'خصائص'),
            _showProperties,
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _wordView() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Page', StudioStrings.de('Page'), 'عرض الصفحة'),
        children: <Widget>[
          _cmd(
            _wordRulers ? Icons.straighten : Icons.straighten_outlined,
            _t('Rulers', StudioStrings.de('Rulers'), 'مساطر'),
            () => setState(() => _wordRulers = !_wordRulers),
            selected: _wordRulers,
          ),
          _cmd(
            Icons.keyboard_arrow_up,
            _t(
              'Previous page',
              StudioStrings.de('Previous page'),
              'الصفحة السابقة',
            ),
            _word.visiblePageIndex > 0
                ? () => _jumpWordPage(_word.visiblePageIndex - 1)
                : null,
          ),
          _cmd(
            Icons.keyboard_arrow_down,
            _t('Next page', StudioStrings.de('Next page'), 'الصفحة التالية'),
            _word.visiblePageIndex < _word.pageCount - 1
                ? () => _jumpWordPage(_word.visiblePageIndex + 1)
                : null,
          ),
          ..._zoomCmds(),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _sheetHome() {
    return <StudioRibbonGroup>[
      _clipboardGroup(),
      StudioRibbonGroup(
        title: _t('History', StudioStrings.de('History'), 'سجل'),
        children: <Widget>[
          _cmd(
            Icons.undo,
            _strings.undo,
            _canMutate && _sheet.canUndo ? _sheet.undo : null,
          ),
          _cmd(
            Icons.redo,
            _strings.redo,
            _canMutate && _sheet.canRedo ? _sheet.redo : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Cells', StudioStrings.de('Cells'), 'خلايا'),
        children: <Widget>[
          _cmd(
            Icons.edit_outlined,
            _t('Edit F2', StudioStrings.de('Edit F2'), 'تحرير F2'),
            _canMutate ? _sheet.beginCellEdit : null,
          ),
          _cmd(
            Icons.clear,
            _t('Clear', StudioStrings.de('Clear'), 'مسح'),
            _canMutate ? _sheet.clearSelectedCells : null,
          ),
          _cmd(
            Icons.backspace_outlined,
            _t('Clear cell', StudioStrings.de('Clear cell'), 'مسح البؤرة'),
            _canMutate ? _clearActiveCell : null,
          ),
          _cmd(
            Icons.table_rows,
            _t('Insert row', StudioStrings.de('Insert row'), 'إدراج صف'),
            _canMutate ? () => _sheet.insertSheetRows(after: false) : null,
          ),
          _cmd(
            Icons.view_column,
            _t(
              'Insert column',
              StudioStrings.de('Insert column'),
              'إدراج عمود',
            ),
            _canMutate ? () => _sheet.insertSheetCols(after: false) : null,
          ),
          _cmd(
            Icons.delete_sweep_outlined,
            _t('Delete row', StudioStrings.de('Delete row'), 'حذف صف'),
            _canMutate ? () => _sheet.deleteSheetRows() : null,
          ),
          _cmd(
            Icons.delete_outline,
            _t('Delete column', StudioStrings.de('Delete column'), 'حذف عمود'),
            _canMutate ? () => _sheet.deleteSheetCols() : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Select', StudioStrings.de('Select'), 'تحديد'),
        children: <Widget>[
          _cmd(Icons.table_rows, _t('Row', StudioStrings.de('Row'), 'صف'), () {
            _sheet.selection.selectRow(_sheet.selection.focus.row);
            _sheet.refresh();
          }),
          _cmd(
            Icons.view_column,
            _t('Column', StudioStrings.de('Column'), 'عمود'),
            () {
              _sheet.selection.selectColumn(_sheet.selection.focus.col);
              _sheet.refresh();
            },
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Alignment', StudioStrings.de('Alignment'), 'محاذاة'),
        children: <Widget>[
          _cmd(
            Icons.call_merge,
            _t(
              'Merge & Center',
              StudioStrings.de('Merge & Center'),
              'دمج وتوسيط',
            ),
            _canMutate && _sheet.canMergeAndCenter
                ? _sheet.toggleMergeAndCenter
                : null,
            selected: _sheet.hasMergedSelection,
          ),
          _cmd(
            Icons.call_split,
            _t('Unmerge', StudioStrings.de('Unmerge'), 'إلغاء الدمج'),
            _canMutate && _sheet.canUnmergeCells ? _sheet.unmergeCells : null,
          ),
          _cmd(
            Icons.format_color_fill,
            _t('Fill', StudioStrings.de('Fill'), 'تعبئة'),
            _canMutate ? _sheet.cycleSelectionFillRgb : null,
          ),
          _cmd(
            Icons.format_color_text,
            _t('Font color', StudioStrings.de('Font color'), 'لون النص'),
            _canMutate ? _sheet.cycleSelectionFontRgb : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Size', StudioStrings.de('Size'), 'تحجيم'),
        children: <Widget>[
          _cmd(
            Icons.unfold_more,
            _t('Wider', StudioStrings.de('Wider'), 'أوسع'),
            _canMutate ? () => _sheet.nudgeColumnWidth(16) : null,
          ),
          _cmd(
            Icons.unfold_less,
            _t('Narrower', StudioStrings.de('Narrower'), 'أضيق'),
            _canMutate ? () => _sheet.nudgeColumnWidth(-16) : null,
          ),
          _cmd(
            Icons.height,
            _t('Taller', StudioStrings.de('Taller'), 'أطول'),
            _canMutate ? () => _sheet.nudgeRowHeight(8) : null,
          ),
          _cmd(
            Icons.compress,
            _t('Shorter', StudioStrings.de('Shorter'), 'أقصر'),
            _canMutate ? () => _sheet.nudgeRowHeight(-8) : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t(
          'Quick insert',
          StudioStrings.de('Quick insert'),
          'إدراج سريع',
        ),
        children: <Widget>[
          _cmd(
            Icons.image_outlined,
            _t('Picture', StudioStrings.de('Picture'), 'صورة'),
            _canMutate ? () => _insertSheetPicture(fromFile: true) : null,
          ),
          _cmd(
            Icons.bar_chart,
            _t('Column', StudioStrings.de('Column'), 'أعمدة'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.chartColumn)
                : null,
          ),
          _cmd(
            Icons.pie_chart,
            _t('Pie', StudioStrings.de('Pie'), 'دائري'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.chartPie)
                : null,
          ),
        ],
      ),
      if (_sheet.selectedDrawing != null) ..._visualRibbon(),
    ];
  }

  List<StudioRibbonGroup> _sheetInsert() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Illustrations', StudioStrings.de('Illustrations'), 'رسوم'),
        children: <Widget>[
          _cmd(
            Icons.image_outlined,
            _t('Picture', StudioStrings.de('Picture'), 'صورة'),
            _canMutate ? () => _insertSheetPicture(fromFile: true) : null,
          ),
          _cmd(
            Icons.bar_chart,
            _t('Column', StudioStrings.de('Column'), 'أعمدة'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.chartColumn)
                : null,
          ),
          _cmd(
            Icons.stacked_bar_chart,
            _t('Bar', StudioStrings.de('Bar'), 'شريطي'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.chartBar)
                : null,
          ),
          _cmd(
            Icons.pie_chart,
            _t('Pie', StudioStrings.de('Pie'), 'دائري'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.chartPie)
                : null,
          ),
          _cmd(
            Icons.show_chart,
            _t('Line', StudioStrings.de('Line'), 'خطي'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.chartLine)
                : null,
          ),
          _cmd(
            Icons.account_tree,
            _t('Process', StudioStrings.de('Process'), 'عملية'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.diagramProcess)
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Cells', StudioStrings.de('Cells'), 'خلايا'),
        children: <Widget>[
          _cmd(
            Icons.table_rows,
            _t('Row', StudioStrings.de('Row'), 'صف'),
            _canMutate ? () => _sheet.insertSheetRows(after: false) : null,
          ),
          _cmd(
            Icons.view_column,
            _t('Column', StudioStrings.de('Column'), 'عمود'),
            _canMutate ? () => _sheet.insertSheetCols(after: false) : null,
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _sheetFormulas() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Function', StudioStrings.de('Function'), 'دالة'),
        children: <Widget>[
          _cmd(
            Icons.functions,
            'SUM',
            _canMutate ? () => _insertFormula('SUM') : null,
          ),
          _cmd(
            Icons.functions,
            'AVERAGE',
            _canMutate ? () => _insertFormula('AVERAGE') : null,
          ),
          _cmd(
            Icons.functions,
            'MIN',
            _canMutate ? () => _insertFormula('MIN') : null,
          ),
          _cmd(
            Icons.functions,
            'MAX',
            _canMutate ? () => _insertFormula('MAX') : null,
          ),
          _cmd(
            Icons.functions,
            'COUNT',
            _canMutate ? () => _insertFormula('COUNT') : null,
          ),
          _cmd(
            Icons.functions,
            'COUNTA',
            _canMutate ? () => _insertFormula('COUNTA') : null,
          ),
          _cmd(Icons.functions, 'IF', _canMutate ? _insertIfFormula : null),
          _cmd(
            Icons.functions,
            'SUMIF',
            _canMutate ? () => _insertFormula('SUMIF') : null,
          ),
          _cmd(
            Icons.functions,
            'COUNTIF',
            _canMutate ? () => _insertFormula('COUNTIF') : null,
          ),
          _cmd(
            Icons.functions,
            'IFERROR',
            _canMutate ? () => _insertFormula('IFERROR') : null,
          ),
          _cmd(
            Icons.functions,
            'ROUND',
            _canMutate ? () => _insertFormula('ROUND') : null,
          ),
          _cmd(
            Icons.functions,
            'CONCAT',
            _canMutate ? () => _insertFormula('CONCAT') : null,
          ),
          _cmd(
            Icons.functions,
            'VLOOKUP',
            _canMutate ? () => _insertFormula('VLOOKUP') : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Reference', StudioStrings.de('Reference'), 'مرجع'),
        children: <Widget>[
          _cmd(
            Icons.menu_book_outlined,
            _t(
              'Function guide',
              StudioStrings.de('Function guide'),
              'دليل الدوال',
            ),
            _openFunctionGuide,
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _sheetData() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Sheets', StudioStrings.de('Sheets'), 'أوراق'),
        children: <Widget>[
          _cmd(
            Icons.post_add,
            _t('Insert', StudioStrings.de('Insert'), 'ورقة'),
            _canMutate ? _addSheet : null,
          ),
          _cmd(
            Icons.delete_outline,
            _t('Delete', StudioStrings.de('Delete'), 'حذف'),
            _canMutate && _sheet.workbook.sheets.length > 1
                ? _deleteSheet
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Charts', StudioStrings.de('Charts'), 'رسوم'),
        children: <Widget>[
          _cmd(
            Icons.bar_chart,
            _t('Column', StudioStrings.de('Column'), 'أعمدة'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.chartColumn)
                : null,
          ),
          _cmd(
            Icons.pie_chart,
            _t('Pie', StudioStrings.de('Pie'), 'دائري'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.chartPie)
                : null,
          ),
          _cmd(
            Icons.show_chart,
            _t('Line', StudioStrings.de('Line'), 'خطي'),
            _canMutate
                ? () => _insertSheetChart(OfficeVisualKind.chartLine)
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Data', StudioStrings.de('Data'), 'بيانات'),
        children: <Widget>[
          _cmd(
            Icons.sort_by_alpha,
            _t('Sort', StudioStrings.de('Sort'), 'فرز'),
            _canMutate ? () => _sheet.sortSelection() : null,
          ),
          _cmd(
            Icons.filter_alt,
            _t('Filter', StudioStrings.de('Filter'), 'تصفية'),
            _canMutate ? () => _sheet.filterSelection() : null,
            selected: _sheet.sheet.autoFilter != null,
          ),
          _cmd(
            Icons.filter_alt_off,
            _t('Clear', StudioStrings.de('Clear'), 'إلغاء التصفية'),
            _canMutate && _sheet.sheet.autoFilter != null
                ? _sheet.clearFilter
                : null,
          ),
          _cmd(
            Icons.bookmark_border,
            _t('Name', StudioStrings.de('Name'), 'اسم'),
            _canMutate
                ? () => _sheet.defineName(
                    'Range${_sheet.workbook.namedRanges.length + 1}',
                  )
                : null,
          ),
          _cmd(
            Icons.print_outlined,
            _t('Print area', StudioStrings.de('Print area'), 'منطقة طباعة'),
            _canMutate ? () => _sheet.setPrintArea(null) : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Tools', StudioStrings.de('Tools'), 'أدوات'),
        children: <Widget>[
          _cmd(
            Icons.comment_outlined,
            _t('Comment', StudioStrings.de('Comment'), 'تعليق'),
            _canMutate
                ? () => _sheet.setCellComment(
                    _t(
                      'Cell comment',
                      StudioStrings.de('Cell comment'),
                      'تعليق خلية',
                    ),
                  )
                : null,
          ),
          _cmd(
            Icons.lock_outline,
            _t('Protect', StudioStrings.de('Protect'), 'حماية'),
            _canMutate
                ? () => _sheet.protectSheet(
                    enabled: !(_sheet.sheet.protection?.enabled ?? false),
                  )
                : null,
            selected: _sheet.sheet.protection?.enabled ?? false,
          ),
          _cmd(
            Icons.table_chart_outlined,
            _t('Table', StudioStrings.de('Table'), 'جدول'),
            _canMutate
                ? () => _sheet.addTable(
                    name: 'Table${_sheet.sheet.tables.length + 1}',
                  )
                : null,
          ),
          _cmd(
            Icons.checklist,
            _t('Validate', StudioStrings.de('Validate'), 'تحقق'),
            _canMutate ? _studioSheetValidation : null,
          ),
          _cmd(
            Icons.pivot_table_chart,
            _t('Pivot', StudioStrings.de('Pivot'), 'محور'),
            _canMutate ? _studioInsertPivot : null,
          ),
          _cmd(
            Icons.south,
            _t('Fill', StudioStrings.de('Fill'), 'تعبئة'),
            _canMutate ? () => _sheet.fillSeries() : null,
          ),
          _cmd(
            Icons.show_chart,
            _t('Sparkline', StudioStrings.de('Sparkline'), 'شرارة'),
            _canMutate ? () => _sheet.addSparkline() : null,
          ),
          _cmd(
            Icons.adjust,
            _t('Goal seek', StudioStrings.de('Goal seek'), 'هدف'),
            _canMutate ? _studioGoalSeek : null,
          ),
          _cmd(
            Icons.table_view,
            _t('CSV', StudioStrings.de('CSV'), 'CSV'),
            _canMutate ? _studioImportCsv : null,
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _sheetView() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Grid', StudioStrings.de('Grid'), 'عرض الشبكة'),
        children: <Widget>[
          _cmd(
            Icons.border_all,
            _t('Gridlines', StudioStrings.de('Gridlines'), 'خطوط'),
            () => setState(() => _sheetGridlines = !_sheetGridlines),
            selected: _sheetGridlines,
          ),
          _cmd(
            Icons.view_headline,
            _t('Headers', StudioStrings.de('Headers'), 'رؤوس'),
            () => setState(() => _sheetHeaders = !_sheetHeaders),
            selected: _sheetHeaders,
          ),
          _cmd(
            Icons.ac_unit,
            _arabic
                ? (_sheet.hasFrozenPanes ? 'إلغاء التجميد' : 'تجميد')
                : (_sheet.hasFrozenPanes ? 'Unfreeze' : 'Freeze'),
            _sheet.toggleFreezePanes,
            selected: _sheet.hasFrozenPanes,
          ),
          _cmd(
            Icons.table_rows,
            _t('Freeze row', StudioStrings.de('Freeze row'), 'تجميد صف'),
            _canMutate ? _sheet.freezeTopRow : null,
            selected:
                _sheet.sheet.freezeRows == 1 && _sheet.sheet.freezeCols == 0,
          ),
          _cmd(
            Icons.view_column,
            _t(
              'Freeze column',
              StudioStrings.de('Freeze column'),
              'تجميد عمود',
            ),
            _canMutate ? _sheet.freezeFirstColumn : null,
            selected:
                _sheet.sheet.freezeCols == 1 && _sheet.sheet.freezeRows == 0,
          ),
          ..._zoomCmds(),
        ],
      ),
      StudioRibbonGroup(
        title: _t(
          'Sheet direction',
          StudioStrings.de('Sheet direction'),
          'اتجاه الورقة',
        ),
        children: <Widget>[
          _cmd(
            Icons.format_textdirection_r_to_l,
            _t('RTL', StudioStrings.de('RTL'), 'من اليمين'),
            _canMutate ? () => _sheet.setSheetRightToLeft(true) : null,
            selected: _sheet.sheet.rightToLeft,
          ),
          _cmd(
            Icons.format_textdirection_l_to_r,
            _t('LTR', StudioStrings.de('LTR'), 'من اليسار'),
            _canMutate ? () => _sheet.setSheetRightToLeft(false) : null,
            selected: !_sheet.sheet.rightToLeft,
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _slideHome() {
    return <StudioRibbonGroup>[
      _clipboardGroup(),
      StudioRibbonGroup(
        title: _t('Slides', StudioStrings.de('Slides'), 'الشرائح'),
        children: <Widget>[
          _cmd(
            Icons.add_box_outlined,
            _t('New', StudioStrings.de('New'), 'جديد'),
            _canMutate ? _addSlide : null,
          ),
          _cmd(
            Icons.copy_outlined,
            _t('Duplicate', StudioStrings.de('Duplicate'), 'نسخ'),
            _canMutate ? _duplicateSlide : null,
          ),
          _cmd(
            Icons.delete_outline,
            _t('Delete', StudioStrings.de('Delete'), 'حذف'),
            _canMutate && _slides.presentation.slides.length > 1
                ? _deleteSlide
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Navigate', StudioStrings.de('Navigate'), 'تنقل'),
        children: <Widget>[
          _cmd(
            Icons.navigate_before,
            _t('Prev', StudioStrings.de('Prev'), 'السابق'),
            () {
              _slides.setActiveSlide(_slides.activeSlideIndex - 1);
            },
          ),
          _cmd(
            Icons.navigate_next,
            _t('Next', StudioStrings.de('Next'), 'التالي'),
            () {
              _slides.setActiveSlide(_slides.activeSlideIndex + 1);
            },
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Arrange', StudioStrings.de('Arrange'), 'ترتيب'),
        children: <Widget>[
          _cmd(
            Icons.align_horizontal_left,
            _t('Left', StudioStrings.de('Left'), 'يسار'),
            _canMutate ? () => _slides.alignShapes(PmlAlignAxis.left) : null,
          ),
          _cmd(
            Icons.align_horizontal_center,
            _t('Center', StudioStrings.de('Center'), 'وسط'),
            _canMutate ? () => _slides.alignShapes(PmlAlignAxis.center) : null,
          ),
          _cmd(
            Icons.align_vertical_top,
            _t('Top', StudioStrings.de('Top'), 'أعلى'),
            _canMutate ? () => _slides.alignShapes(PmlAlignAxis.top) : null,
          ),
          _cmd(
            Icons.view_agenda_outlined,
            _t('Section', StudioStrings.de('Section'), 'قسم'),
            _canMutate
                ? () => _slides.addSlideSection(
                    _t(
                      'New section',
                      StudioStrings.de('New section'),
                      'قسم جديد',
                    ),
                  )
                : null,
          ),
          _cmd(
            Icons.group_work_outlined,
            _t('Group', StudioStrings.de('Group'), 'تجميع'),
            _canMutate && _slides.slide.shapes.length >= 2
                ? () => _slides.groupShapes()
                : null,
          ),
          _cmd(
            Icons.group_off_outlined,
            _t('Ungroup', StudioStrings.de('Ungroup'), 'فك'),
            _canMutate ? () => _slides.ungroupShapes() : null,
          ),
          _cmd(
            Icons.title,
            _t('Placeholder', StudioStrings.de('Placeholder'), 'عنصر نائب'),
            _canMutate
                ? () => _slides.setLayoutPlaceholder(
                    layoutName: _slides.slide.layoutName.isEmpty
                        ? 'Title Slide'
                        : _slides.slide.layoutName,
                    text: _t(
                      'Click to add title',
                      StudioStrings.de('Click to add title'),
                      'انقر للعنوان',
                    ),
                  )
                : null,
          ),
          _cmd(
            Icons.videocam_outlined,
            _t('Media', StudioStrings.de('Media'), 'وسائط'),
            _canMutate && _slides.selected != null
                ? () => _slides.setShapeMedia(
                    _slides.selected!,
                    name: 'clip.mp4',
                    bytes: <int>[0, 0, 0, 0],
                  )
                : null,
          ),
          _cmd(
            Icons.play_circle_outline,
            _t('Play', StudioStrings.de('Play'), 'تشغيل'),
            _slides.selected?.hasMedia == true
                ? () => _slides.playShapeMedia(_slides.selected!)
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Text font', StudioStrings.de('Text font'), 'خط النص'),
        children: <Widget>[
          StudioCombo<int>(
            value: _slideFontSizePt,
            items: OfficeTypeface.sizesPt,
            labelOf: (int pt) => '$pt',
            width: 52,
            enabled:
                _canMutate &&
                _slides.selected != null &&
                _slides.selected!.visual == null,
            tooltip: _t('Text size', StudioStrings.de('Text size'), 'حجم النص'),
            onSelected:
                _canMutate &&
                    _slides.selected != null &&
                    _slides.selected!.visual == null
                ? (int pt) => _slides.updateSelected(fontSizePt: pt.toDouble())
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Paragraph', StudioStrings.de('Paragraph'), 'فقرة'),
        children: <Widget>[
          _icon(
            Icons.format_align_left,
            _t('Left', StudioStrings.de('Left'), 'يسار'),
            _canEditSlideText
                ? () => _slides.setSelectedTextAlign(PmlTextAlign.left)
                : null,
            selected: _slides.selected?.textAlign == PmlTextAlign.left,
          ),
          _icon(
            Icons.format_align_center,
            _t('Center', StudioStrings.de('Center'), 'وسط'),
            _canEditSlideText
                ? () => _slides.setSelectedTextAlign(PmlTextAlign.center)
                : null,
            selected: _slides.selected?.textAlign == PmlTextAlign.center,
          ),
          _icon(
            Icons.format_align_right,
            _t('Right', StudioStrings.de('Right'), 'يمين'),
            _canEditSlideText
                ? () => _slides.setSelectedTextAlign(PmlTextAlign.right)
                : null,
            selected: _slides.selected?.textAlign == PmlTextAlign.right,
          ),
          _icon(
            Icons.format_align_justify,
            _t('Justify', StudioStrings.de('Justify'), 'ضبط'),
            _canEditSlideText
                ? () => _slides.setSelectedTextAlign(PmlTextAlign.justify)
                : null,
            selected: _slides.selected?.textAlign == PmlTextAlign.justify,
          ),
          _icon(
            Icons.format_textdirection_r_to_l,
            _t('RTL', StudioStrings.de('RTL'), 'من اليمين'),
            _canEditSlideText
                ? () => _slides.setSelectedTextDirection(rtl: true)
                : null,
            selected: _slides.selected?.rightToLeft == true,
          ),
          _icon(
            Icons.format_textdirection_l_to_r,
            _t('LTR', StudioStrings.de('LTR'), 'من اليسار'),
            _canEditSlideText
                ? () => _slides.setSelectedTextDirection(rtl: false)
                : null,
            selected: _slides.selected?.rightToLeft == false,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Arrange', StudioStrings.de('Arrange'), 'ترتيب'),
        children: <Widget>[
          _cmd(
            Icons.arrow_back,
            '',
            _canMutate ? () => _slides.nudgeSelected(-127000, 0) : null,
          ),
          _cmd(
            Icons.arrow_forward,
            '',
            _canMutate ? () => _slides.nudgeSelected(127000, 0) : null,
          ),
          _cmd(
            Icons.arrow_upward,
            '',
            _canMutate ? () => _slides.nudgeSelected(0, -127000) : null,
          ),
          _cmd(
            Icons.arrow_downward,
            '',
            _canMutate ? () => _slides.nudgeSelected(0, 127000) : null,
          ),
          _cmd(
            Icons.flip_to_front,
            _t('Forward', StudioStrings.de('Forward'), 'أمام'),
            _canMutate ? () => _slides.reorderSelected(forward: true) : null,
          ),
          _cmd(
            Icons.flip_to_back,
            _t('Back', StudioStrings.de('Back'), 'خلف'),
            _canMutate ? () => _slides.reorderSelected(forward: false) : null,
          ),
          _cmd(
            Icons.align_horizontal_left,
            _t('Left', StudioStrings.de('Left'), 'يسار'),
            _canMutate && _slides.selected != null
                ? () => _alignSelectedShape(x: 0)
                : null,
          ),
          _cmd(
            Icons.align_horizontal_center,
            _t('Center', StudioStrings.de('Center'), 'وسط'),
            _canMutate && _slides.selected != null
                ? _centerSelectedShape
                : null,
          ),
          _cmd(
            Icons.align_horizontal_right,
            _t('Right', StudioStrings.de('Right'), 'يمين'),
            _canMutate && _slides.selected != null
                ? () => _alignSelectedShape(x: 1)
                : null,
          ),
          _cmd(
            Icons.align_vertical_top,
            _t('Top', StudioStrings.de('Top'), 'أعلى'),
            _canMutate && _slides.selected != null
                ? () => _alignSelectedShape(y: 0)
                : null,
          ),
          _cmd(
            Icons.align_vertical_bottom,
            _t('Bottom', StudioStrings.de('Bottom'), 'أسفل'),
            _canMutate && _slides.selected != null
                ? () => _alignSelectedShape(y: 1)
                : null,
          ),
          _cmd(
            Icons.text_fields,
            _t('Edit text', StudioStrings.de('Edit text'), 'تحرير النص'),
            _canMutate &&
                    _slides.selected != null &&
                    _slides.selected!.visual == null
                ? _slides.beginTextEdit
                : null,
          ),
          _cmd(
            Icons.delete_outline,
            _t('Delete', StudioStrings.de('Delete'), 'حذف'),
            _canMutate && _slides.selected != null
                ? _slides.deleteSelectedShape
                : null,
          ),
        ],
      ),
      if (_slides.selectedTable != null)
        StudioRibbonGroup(
          title: _t('Table', StudioStrings.de('Table'), 'جدول'),
          children: <Widget>[
            _cmd(
              Icons.table_rows,
              _t('Row above', StudioStrings.de('Row above'), 'صف أعلى'),
              _canEditSlideTable
                  ? () => _slides.insertSelectedTableRow(after: false)
                  : null,
            ),
            _cmd(
              Icons.table_rows_outlined,
              _t('Row below', StudioStrings.de('Row below'), 'صف أسفل'),
              _canEditSlideTable
                  ? () => _slides.insertSelectedTableRow(after: true)
                  : null,
            ),
            _cmd(
              Icons.view_column,
              _t('Column left', StudioStrings.de('Column left'), 'عمود يسار'),
              _canEditSlideTable
                  ? () => _slides.insertSelectedTableColumn(after: false)
                  : null,
            ),
            _cmd(
              Icons.view_week,
              _t('Column right', StudioStrings.de('Column right'), 'عمود يمين'),
              _canEditSlideTable
                  ? () => _slides.insertSelectedTableColumn(after: true)
                  : null,
            ),
            _cmd(
              Icons.delete_sweep,
              _t('Delete row', StudioStrings.de('Delete row'), 'حذف صف'),
              _canEditSlideTable && (_slides.selectedTable?.rowCount ?? 0) > 1
                  ? _slides.deleteSelectedTableRow
                  : null,
            ),
            _cmd(
              Icons.view_column_outlined,
              _t(
                'Delete column',
                StudioStrings.de('Delete column'),
                'حذف عمود',
              ),
              _canEditSlideTable && (_slides.selectedTable?.colCount ?? 0) > 1
                  ? _slides.deleteSelectedTableColumn
                  : null,
            ),
          ],
        ),
    ];
  }

  List<StudioRibbonGroup> _slideInsert() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Shapes', StudioStrings.de('Shapes'), 'أشكال'),
        children: <Widget>[
          _cmd(
            Icons.crop_square,
            _t('Card', StudioStrings.de('Card'), 'بطاقة'),
            _canMutate ? _addCardShape : null,
          ),
          _cmd(
            Icons.title,
            _t('Title', StudioStrings.de('Title'), 'عنوان'),
            _canMutate ? _addTitleShape : null,
          ),
          _cmd(
            Icons.rounded_corner,
            _t('Accent', StudioStrings.de('Accent'), 'تمييز'),
            _canMutate ? _addAccentShape : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Illustrations', StudioStrings.de('Illustrations'), 'رسوم'),
        children: <Widget>[
          _cmd(
            Icons.image_outlined,
            _t('Picture', StudioStrings.de('Picture'), 'صورة'),
            _canMutate ? () => _insertSlidePicture(fromFile: true) : null,
          ),
          _cmd(
            Icons.bar_chart,
            _t('Column', StudioStrings.de('Column'), 'أعمدة'),
            _canMutate
                ? () => _insertSlideVisual(OfficeVisualKind.chartColumn)
                : null,
          ),
          _cmd(
            Icons.pie_chart,
            _t('Pie', StudioStrings.de('Pie'), 'دائري'),
            _canMutate
                ? () => _insertSlideVisual(OfficeVisualKind.chartPie)
                : null,
          ),
          _cmd(
            Icons.account_tree,
            _t('Process', StudioStrings.de('Process'), 'عملية'),
            _canMutate
                ? () => _insertSlideVisual(OfficeVisualKind.diagramProcess)
                : null,
          ),
          _cmd(
            Icons.stacked_bar_chart,
            _t('Bar', StudioStrings.de('Bar'), 'شريطي'),
            _canMutate
                ? () => _insertSlideVisual(OfficeVisualKind.chartBar)
                : null,
          ),
          _cmd(
            Icons.show_chart,
            _t('Line', StudioStrings.de('Line'), 'خطي'),
            _canMutate
                ? () => _insertSlideVisual(OfficeVisualKind.chartLine)
                : null,
          ),
          _cmd(
            Icons.sync,
            _t('Cycle', StudioStrings.de('Cycle'), 'دورة'),
            _canMutate
                ? () => _insertSlideVisual(OfficeVisualKind.diagramCycle)
                : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Table', StudioStrings.de('Table'), 'جدول'),
        children: <Widget>[
          _cmd(
            Icons.table_chart,
            _t('2×2', StudioStrings.de('2×2'), '٢×٢'),
            _canMutate
                ? () => _slides.insertTable(rows: 2, cols: 2, arabic: _arabic)
                : null,
          ),
          _cmd(
            Icons.grid_on,
            _t('3×3', StudioStrings.de('3×3'), '٣×٣'),
            _canMutate
                ? () => _slides.insertTable(rows: 3, cols: 3, arabic: _arabic)
                : null,
          ),
          _cmd(
            Icons.table_view,
            _t('4×4', StudioStrings.de('4×4'), '٤×٤'),
            _canMutate
                ? () => _slides.insertTable(rows: 4, cols: 4, arabic: _arabic)
                : null,
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _slideDesign() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Shape', StudioStrings.de('Shape'), 'شكل'),
        children: <Widget>[
          _cmd(
            Icons.format_color_fill,
            _t('Fill', StudioStrings.de('Fill'), 'تعبئة'),
            _canMutate && _slides.selected != null ? _cycleShapeFill : null,
          ),
          _cmd(
            Icons.filter_center_focus,
            _t('Center', StudioStrings.de('Center'), 'توسيط'),
            _canMutate && _slides.selected != null
                ? _centerSelectedShape
                : null,
          ),
          _cmd(
            Icons.title,
            _t('Text', StudioStrings.de('Text'), 'نص'),
            _canMutate &&
                    _slides.selected != null &&
                    _slides.selected!.visual == null
                ? _slides.beginTextEdit
                : null,
          ),
        ],
      ),
      if (_slides.selected?.visual != null) ..._visualRibbon(),
    ];
  }

  List<StudioRibbonGroup> _slideTransitions() {
    final PmlSlideTransition current = _slides.slide.transition;
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Preview', StudioStrings.de('Preview'), 'معاينة'),
        children: <Widget>[
          _cmd(
            Icons.play_circle_outline,
            _t('Preview', StudioStrings.de('Preview'), 'معاينة'),
            _slides.previewTransition,
          ),
          _cmd(
            Icons.slideshow,
            _t('From here', StudioStrings.de('From here'), 'عرض'),
            () => _slides.startShow(
              from: _slides.activeSlideIndex,
              withTransition: _slides.activeSlideIndex > 0,
            ),
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Effect', StudioStrings.de('Effect'), 'التأثير'),
        children: <Widget>[
          for (final PmlTransitionKind kind in PmlMotionCatalog.transitions)
            _cmd(
              _transitionIcon(kind),
              PmlMotionCatalog.transitionLabel(kind, arabic: _arabic),
              () => _slides.setSlideTransition(current.copyWith(kind: kind)),
              selected: current.kind == kind,
            ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Options', StudioStrings.de('Options'), 'خيارات'),
        children: <Widget>[
          _cmd(
            Icons.swap_horiz,
            _dirLabel(current.direction),
            PmlMotionCatalog.usesDirection(current.kind)
                ? () => _slides.setSlideTransition(
                    current.copyWith(direction: _nextDir(current.direction)),
                  )
                : null,
          ),
          _cmd(
            Icons.timer,
            _durationLabel(current.durationMs),
            () => _slides.setSlideTransition(
              current.copyWith(durationMs: _nextDuration(current.durationMs)),
              preview: false,
            ),
          ),
          _cmd(
            Icons.touch_app,
            current.advanceOnClick
                ? (_t('On click', StudioStrings.de('On click'), 'بالنقر'))
                : (_t('No click', StudioStrings.de('No click'), 'بدون نقر')),
            () => _slides.setSlideTransition(
              current.copyWith(advanceOnClick: !current.advanceOnClick),
              preview: false,
            ),
            selected: current.advanceOnClick,
          ),
          _cmd(
            Icons.more_time,
            _advanceLabel(current),
            () => _slides.setSlideTransition(
              _cycleAdvance(current),
              preview: false,
            ),
          ),
          _cmd(
            Icons.copy_all,
            _t('Apply all', StudioStrings.de('Apply all'), 'الكل'),
            () => _slides.setSlideTransition(
              current,
              applyToAll: true,
              preview: false,
            ),
          ),
        ],
      ),
    ];
  }

  List<StudioRibbonGroup> _slideAnimations() {
    final bool hasShape = _slides.selected != null;
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Entrance', StudioStrings.de('Entrance'), 'دخول'),
        children: <Widget>[
          for (final PmlAnimPreset preset in PmlMotionCatalog.entrance)
            _cmd(
              Icons.login,
              PmlMotionCatalog.animLabel(preset, arabic: _arabic),
              hasShape ? () => _slides.addShapeAnimation(preset) : null,
            ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Emphasis', StudioStrings.de('Emphasis'), 'تأكيد'),
        children: <Widget>[
          for (final PmlAnimPreset preset in PmlMotionCatalog.emphasis)
            _cmd(
              Icons.highlight,
              PmlMotionCatalog.animLabel(preset, arabic: _arabic),
              hasShape ? () => _slides.addShapeAnimation(preset) : null,
            ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Exit', StudioStrings.de('Exit'), 'خروج'),
        children: <Widget>[
          for (final PmlAnimPreset preset in PmlMotionCatalog.exit)
            _cmd(
              Icons.logout,
              PmlMotionCatalog.animLabel(preset, arabic: _arabic),
              hasShape ? () => _slides.addShapeAnimation(preset) : null,
            ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Motion', StudioStrings.de('Motion'), 'مسار'),
        children: <Widget>[
          for (final PmlAnimPreset preset in PmlMotionCatalog.motion)
            _cmd(
              Icons.timeline,
              PmlMotionCatalog.animLabel(preset, arabic: _arabic),
              hasShape ? () => _slides.addShapeAnimation(preset) : null,
            ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Timing', StudioStrings.de('Timing'), 'توقيت'),
        children: <Widget>[
          _cmd(
            Icons.play_arrow,
            _t('Preview', StudioStrings.de('Preview'), 'معاينة'),
            _slides.previewAnimations,
          ),
          _cmd(
            Icons.view_sidebar_outlined,
            _t('Pane', StudioStrings.de('Pane'), 'الجزء'),
            () => setState(() => _showAnimPane = !_showAnimPane),
            selected: _showAnimPane,
          ),
          _cmd(
            Icons.touch_app,
            _triggerLabel(_activeAnim?.trigger ?? PmlAnimTrigger.onClick),
            _activeAnimIndex == null
                ? null
                : () => _slides.updateShapeAnimation(
                    _activeAnimIndex!,
                    trigger: _nextTrigger(_activeAnim!.trigger),
                  ),
          ),
          _cmd(
            Icons.swap_horiz,
            _dirLabel(_activeAnim?.direction ?? PmlTransitionDir.left),
            _activeAnimIndex == null ||
                    !PmlMotionCatalog.animUsesDirection(_activeAnim!.preset)
                ? null
                : () => _slides.updateShapeAnimation(
                    _activeAnimIndex!,
                    direction: _nextDir(_activeAnim!.direction),
                  ),
          ),
          _cmd(
            Icons.timer,
            _durationLabel(_activeAnim?.durationMs ?? 500),
            _activeAnimIndex == null
                ? null
                : () => _slides.updateShapeAnimation(
                    _activeAnimIndex!,
                    durationMs: _nextDuration(_activeAnim!.durationMs),
                  ),
          ),
          _cmd(
            Icons.more_time,
            _delayLabel(_activeAnim?.delayMs ?? 0),
            _activeAnimIndex == null
                ? null
                : () => _slides.updateShapeAnimation(
                    _activeAnimIndex!,
                    delayMs: _nextDelay(_activeAnim!.delayMs),
                  ),
          ),
        ],
      ),
    ];
  }

  int? get _activeAnimIndex =>
      _slides.selectedAnimationIndex ??
      (_slides.slide.animations.isEmpty
          ? null
          : _slides.slide.animations.length - 1);

  PmlShapeAnimation? get _activeAnim {
    final int? index = _activeAnimIndex;
    if (index == null) {
      return null;
    }
    return _slides.slide.animations[index];
  }

  String _triggerLabel(PmlAnimTrigger trigger) {
    return switch (trigger) {
      PmlAnimTrigger.onClick => _t(
        'On click',
        StudioStrings.de('On click'),
        'عند النقر',
      ),
      PmlAnimTrigger.withPrevious => _t(
        'With previous',
        StudioStrings.de('With previous'),
        'مع السابق',
      ),
      PmlAnimTrigger.afterPrevious => _t(
        'After previous',
        StudioStrings.de('After previous'),
        'بعد السابق',
      ),
    };
  }

  PmlAnimTrigger _nextTrigger(PmlAnimTrigger trigger) {
    return switch (trigger) {
      PmlAnimTrigger.onClick => PmlAnimTrigger.withPrevious,
      PmlAnimTrigger.withPrevious => PmlAnimTrigger.afterPrevious,
      PmlAnimTrigger.afterPrevious => PmlAnimTrigger.onClick,
    };
  }

  PmlTransitionDir _nextDir(PmlTransitionDir dir) {
    const List<PmlTransitionDir> cycle = <PmlTransitionDir>[
      PmlTransitionDir.left,
      PmlTransitionDir.right,
      PmlTransitionDir.up,
      PmlTransitionDir.down,
    ];
    return cycle[(cycle.indexOf(dir) + 1) % cycle.length];
  }

  int _nextDuration(int ms) {
    if (ms <= 400) {
      return 700;
    }
    if (ms < 1000) {
      return 1200;
    }
    return 350;
  }

  int _nextDelay(int ms) {
    if (ms <= 0) {
      return 250;
    }
    if (ms < 500) {
      return 750;
    }
    if (ms < 1000) {
      return 1500;
    }
    return 0;
  }

  String _durationLabel(int ms) {
    if (ms <= 400) {
      return _t('Fast', StudioStrings.de('Fast'), 'سريع');
    }
    if (ms >= 1000) {
      return _t('Slow', StudioStrings.de('Slow'), 'بطيء');
    }
    return _t('Medium', StudioStrings.de('Medium'), 'متوسط');
  }

  String _delayLabel(int ms) {
    if (ms <= 0) {
      return _t('No delay', StudioStrings.de('No delay'), 'بدون تأخير');
    }
    return _arabic ? 'تأخير ${ms}ms' : 'Delay ${ms}ms';
  }

  String _dirLabel(PmlTransitionDir dir) {
    return switch (dir) {
      PmlTransitionDir.left => _t('Left', StudioStrings.de('Left'), 'يسار'),
      PmlTransitionDir.right => _t('Right', StudioStrings.de('Right'), 'يمين'),
      PmlTransitionDir.up => _t('Up', StudioStrings.de('Up'), 'أعلى'),
      PmlTransitionDir.down => _t('Down', StudioStrings.de('Down'), 'أسفل'),
      PmlTransitionDir.horizontal => _t(
        'Horizontal',
        StudioStrings.de('Horizontal'),
        'أفقي',
      ),
      PmlTransitionDir.vertical => _t(
        'Vertical',
        StudioStrings.de('Vertical'),
        'عمودي',
      ),
      PmlTransitionDir.inward => _t(
        'Inward',
        StudioStrings.de('Inward'),
        'للداخل',
      ),
      PmlTransitionDir.outward => _t(
        'Outward',
        StudioStrings.de('Outward'),
        'للخارج',
      ),
    };
  }

  String _advanceLabel(PmlSlideTransition t) {
    final int? ms = t.advanceAfterMs;
    if (ms == null || ms <= 0) {
      return _t('Manually', StudioStrings.de('Manually'), 'تقديم يدوي');
    }
    final int sec = (ms / 1000).round();
    return _arabic ? 'بعد $sec ث' : 'After ${sec}s';
  }

  PmlSlideTransition _cycleAdvance(PmlSlideTransition current) {
    final int? next = switch (current.advanceAfterMs) {
      null => 2000,
      <= 2000 => 5000,
      <= 5000 => 10000,
      _ => null,
    };
    return current.copyWith(
      advanceAfterMs: next,
      clearAdvanceAfter: next == null,
    );
  }

  IconData _transitionIcon(PmlTransitionKind kind) {
    return switch (kind) {
      PmlTransitionKind.none => Icons.block,
      PmlTransitionKind.morph => Icons.transform,
      PmlTransitionKind.fade ||
      PmlTransitionKind.fadeThroughBlack => Icons.blur_on,
      PmlTransitionKind.cut => Icons.content_cut,
      PmlTransitionKind.push => Icons.keyboard_double_arrow_left,
      PmlTransitionKind.wipe => Icons.cleaning_services_outlined,
      PmlTransitionKind.split ||
      PmlTransitionKind.doors => Icons.vertical_split,
      PmlTransitionKind.uncover || PmlTransitionKind.reveal => Icons.visibility,
      PmlTransitionKind.cover => Icons.layers,
      PmlTransitionKind.dissolve => Icons.grain,
      PmlTransitionKind.checkerboard => Icons.grid_on,
      PmlTransitionKind.blinds || PmlTransitionKind.comb => Icons.view_week,
      PmlTransitionKind.clock => Icons.schedule,
      PmlTransitionKind.shapeCircle => Icons.circle_outlined,
      PmlTransitionKind.shapeDiamond => Icons.diamond_outlined,
      PmlTransitionKind.shapePlus => Icons.add_box_outlined,
      PmlTransitionKind.newsflash => Icons.flash_on,
      PmlTransitionKind.zoom => Icons.zoom_in,
      PmlTransitionKind.flash => Icons.wb_sunny_outlined,
      PmlTransitionKind.strips ||
      PmlTransitionKind.randomBars => Icons.view_stream,
      PmlTransitionKind.gallery => Icons.view_carousel,
    };
  }

  List<StudioRibbonGroup> _slideView() {
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Slide show', StudioStrings.de('Slide show'), 'عرض الشرائح'),
        children: <Widget>[
          _cmd(
            Icons.slideshow,
            _t('From start', StudioStrings.de('From start'), 'من البداية'),
            _slides.isPresenting
                ? _slides.endShow
                : () => _slides.startShow(from: 0),
            selected: _slides.isPresenting,
          ),
          _cmd(
            Icons.play_arrow,
            _t('From current', StudioStrings.de('From current'), 'من الحالية'),
            () => _slides.startShow(from: _slides.activeSlideIndex),
          ),
          _cmd(
            Icons.view_sidebar_outlined,
            _t(
              'Animation pane',
              StudioStrings.de('Animation pane'),
              'جزء الحركة',
            ),
            () => setState(() => _showAnimPane = !_showAnimPane),
            selected: _showAnimPane,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Stage', StudioStrings.de('Stage'), 'مسرح'),
        children: <Widget>[
          _cmd(
            Icons.highlight_alt,
            _t('Handles', StudioStrings.de('Handles'), 'مقابض'),
            () => setState(() => _slideHandles = !_slideHandles),
            selected: _slideHandles,
          ),
          _cmd(
            Icons.notes,
            _t('Notes', StudioStrings.de('Notes'), 'ملاحظات'),
            () => setState(() => _showNotes = !_showNotes),
            selected: _showNotes,
          ),
          _cmd(
            Icons.view_compact_alt,
            _t('Layout', StudioStrings.de('Layout'), 'تخطيط'),
            _canMutate
                ? () => _slides.setStageKind(
                    _slides.stageKind == SlideStageKind.layout
                        ? SlideStageKind.slide
                        : SlideStageKind.layout,
                  )
                : null,
            selected: _slides.stageKind == SlideStageKind.layout,
          ),
          _cmd(
            Icons.layers_outlined,
            _t('Master', StudioStrings.de('Master'), 'رئيس'),
            _canMutate
                ? () => _slides.setStageKind(
                    _slides.stageKind == SlideStageKind.master
                        ? SlideStageKind.slide
                        : SlideStageKind.master,
                  )
                : null,
            selected: _slides.stageKind == SlideStageKind.master,
          ),
          ..._zoomCmds(),
        ],
      ),
    ];
  }

  List<Widget> _zoomCmds() {
    return <Widget>[
      _cmd(
        Icons.zoom_out,
        _t('Zoom out', StudioStrings.de('Zoom out'), 'تصغير'),
        () {
          _setZoom(_viewScale - 0.1);
        },
      ),
      _cmd(Icons.search, '$_zoomPercent%', () => _setZoom(1)),
      _cmd(
        Icons.zoom_in,
        _t('Zoom in', StudioStrings.de('Zoom in'), 'تكبير'),
        () {
          _setZoom(_viewScale + 0.1);
        },
      ),
    ];
  }

  double get _viewScale =>
      _app == SuiteApp.pdf ? _pdf.viewport.scale : _active.viewport.scale;

  int get _zoomPercent => (_viewScale * 100).round();

  void _setZoom(double value) {
    if (_app == SuiteApp.pdf) {
      _pdf.setScale(value);
      setState(() {});
      return;
    }
    final controller = _active;
    controller.viewport.setScale(value);
    if (controller is WordEditorController) {
      controller.refreshView();
    } else {
      controller.refresh();
    }
  }

  void _shortcutZoomIn() {
    if (_app == SuiteApp.pdf) {
      _pdf.zoomBy(1.1);
      return;
    }
    _setZoom(_viewScale + 0.1);
  }

  void _shortcutZoomOut() {
    if (_app == SuiteApp.pdf) {
      _pdf.zoomBy(1 / 1.1);
      return;
    }
    _setZoom(_viewScale - 0.1);
  }

  void _shortcutZoomReset() {
    _setZoom(1);
  }

  Future<void> _openFile() async {
    if (_opening || _isSaving) {
      return;
    }
    try {
      final PickedOfficeFile? picked = await StudioFiles.open();
      if (picked == null || !mounted) {
        return;
      }
      if (picked.name.toLowerCase().endsWith('.pdf')) {
        _switchApp(SuiteApp.pdf);
        if (picked.path != null && picked.path!.isNotEmpty) {
          await loadPdfFromFilePath(
            _pdf,
            picked.path!,
            onError: (Object error) {
              _toast(
                _arabic ? 'فشل فتح PDF: $error' : 'PDF open failed: $error',
              );
            },
          );
        } else {
          final Uint8List pdfBytes = await StudioFiles.ensureBytes(picked);
          if (!mounted) {
            return;
          }
          await _pdf.loadBytesAsync(pdfBytes);
        }
        if (!mounted) {
          return;
        }
        _pdfPath = picked.path;
        _pdfName = _nameFromPicked(picked);
        return;
      }
      if (picked.kind == OpcPackageKind.unknown) {
        _toast(
          _t(
            'Unknown file format.',
            StudioStrings.de('Unknown file format.'),
            'صيغة الملف غير معروفة.',
          ),
        );
        return;
      }
      setState(() {
        _opening = true;
        _openHeavy = _pickedFileIsHeavy(picked);
        _openProgress = 0.04;
        _openStage = 'archive';
        _openName = picked.name;
      });
      _startOpenTicker();
      await WidgetsBinding.instance.endOfFrame;
      final Uint8List bytes = await StudioFiles.ensureBytes(picked);
      if (!mounted) {
        return;
      }
      setState(() {
        _openHeavy = OfficeIsolateOpen.isHeavyBytes(bytes);
      });
      void onProgress(OfficeOpenProgress progress) {
        if (!mounted || !_opening) {
          return;
        }
        setState(() {
          _openStage = progress.stage;
          if (progress.value > _openProgress) {
            _openProgress = progress.value;
          }
        });
      }

      switch (picked.kind) {
        case OpcPackageKind.word:
          _switchApp(SuiteApp.word);
          await _word.loadBytesAsync(bytes, onProgress: onProgress);
          _wordPath = picked.path;
          _wordName = _nameFromPicked(picked);
        case OpcPackageKind.sheet:
          _switchApp(SuiteApp.excel);
          await _sheet.loadBytesAsync(bytes, onProgress: onProgress);
          _sheetPath = picked.path;
          _sheetName = _nameFromPicked(picked);
        case OpcPackageKind.slide:
          _switchApp(SuiteApp.powerpoint);
          await _slides.loadBytesAsync(bytes, onProgress: onProgress);
          _slidePath = picked.path;
          _slideName = _nameFromPicked(picked);
        case OpcPackageKind.unknown:
          break;
      }
      if (mounted) {
        setState(() => _openProgress = 1);
      }
    } catch (error) {
      _toast(_openFailureMessage(error));
    } finally {
      _stopOpenTicker();
      if (mounted) {
        setState(() {
          _opening = false;
          _openProgress = 0;
        });
      }
    }
  }

  String _openFailureMessage(Object error) {
    final Object root = error is StateError ? error.message : error;
    final PdfOpenError? kind = root is PdfOpenException
        ? root.error
        : _pdfOpenErrorFromText('$error');
    if (kind != null) {
      return switch (kind) {
        PdfOpenError.encrypted || PdfOpenError.wrongPassword =>
          _arabic
              ? 'الملف محمي بكلمة مرور.'
              : 'This PDF is password-protected.',
        PdfOpenError.unsupportedFilter =>
          _arabic
              ? 'المحرّك لا يفكّ هذا النوع من ضغط مجاري PDF بعد.'
              : 'This PDF uses a stream filter that is not decoded yet.',
        PdfOpenError.unsupportedHandler =>
          _arabic
              ? 'معالج حماية PDF غير مدعوم.'
              : 'This PDF uses an unsupported security handler.',
        PdfOpenError.limit =>
          _arabic
              ? 'الملف أكبر من حد الأمان.'
              : 'The file exceeds the safety limit.',
        PdfOpenError.badHeader || PdfOpenError.badXref =>
          _arabic
              ? 'ملف PDF تالف أو جدول الإسناد غير صالح.'
              : 'The PDF is damaged or its cross-reference table is invalid.',
      };
    }
    if ('$error'.contains('ZipDeflate') || '$error'.contains('Flate')) {
      return _arabic
          ? 'تعذر فك ضغط مجرى في ملف PDF.'
          : 'Could not inflate a stream inside the PDF.';
    }
    return _arabic
        ? 'تعذر فتح الملف. قد يكون الأرشيف تالفاً أو مضغوطاً بطريقة غير مدعومة بعد.'
        : 'Could not open the file. The archive may be damaged or use an unsupported compression stream.';
  }

  PdfOpenError? _pdfOpenErrorFromText(String text) {
    for (final PdfOpenError value in PdfOpenError.values) {
      if (text.contains('PdfOpenException.$value') ||
          text.contains('PdfOpenError.$value')) {
        return value;
      }
    }
    return null;
  }

  bool _pickedFileIsHeavy(PickedOfficeFile picked) {
    if (OfficeIsolateOpen.isHeavyBytes(picked.bytes)) {
      return true;
    }
    final String? path = picked.path;
    if (path == null || kIsWeb) {
      return false;
    }
    try {
      return File(path).lengthSync() >= OfficeSaveCost.isolateThresholdBytes;
    } on FileSystemException {
      return false;
    }
  }

  void _startOpenTicker() {
    _openTicker?.cancel();
    _openTicker = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted || !_opening) {
        return;
      }
      setState(() {
        final double cap = _openHeavy ? 0.82 : 0.90;
        final double step = _openHeavy ? 0.005 : 0.016;
        if (_openProgress < cap) {
          _openProgress += step;
        }
      });
    });
  }

  void _stopOpenTicker() {
    _openTicker?.cancel();
    _openTicker = null;
  }

  String get _openStatusLabel {
    final int percent = (_openProgress * 100).round().clamp(0, 100);
    final String name = _openName;
    final String action = name.isEmpty
        ? (_t('Opening', StudioStrings.de('Opening'), 'جاري الفتح'))
        : (_arabic ? 'جاري فتح $name' : 'Opening $name');
    final String stage = switch (_openStage) {
      'archive' => _t('archive', StudioStrings.de('archive'), 'الأرشيف'),
      'document' => _t('document', StudioStrings.de('document'), 'المستند'),
      'layout' => _t('layout', StudioStrings.de('layout'), 'التخطيط'),
      'formulas' => _t('formulas', StudioStrings.de('formulas'), 'الصيغ'),
      'apply' => _t('display', StudioStrings.de('display'), 'العرض'),
      'convert' => _t('convert', StudioStrings.de('convert'), 'التحويل'),
      _ => _openStage,
    };
    final String heavy = _openHeavy
        ? (_t(
            ' · large file',
            StudioStrings.de(' · large file'),
            ' · ملف كبير',
          ))
        : '';
    return '$action$heavy · $stage · $percent%';
  }

  bool get _isSaving => _savePhase != _SavePhase.idle;

  String? get _activePath => switch (_app) {
    SuiteApp.word => _wordPath,
    SuiteApp.excel => _sheetPath,
    SuiteApp.powerpoint => _slidePath,
    SuiteApp.pdf => _pdfPath,
  };

  set _activePath(String? value) {
    switch (_app) {
      case SuiteApp.word:
        _wordPath = value;
      case SuiteApp.excel:
        _sheetPath = value;
      case SuiteApp.powerpoint:
        _slidePath = value;
      case SuiteApp.pdf:
        _pdfPath = value;
    }
  }

  String get _defaultSaveName {
    final String name = _activeName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    return _untitledName;
  }

  OpcPackageKind get _activeKind => switch (_app) {
    SuiteApp.word => OpcPackageKind.word,
    SuiteApp.excel => OpcPackageKind.sheet,
    SuiteApp.powerpoint => OpcPackageKind.slide,
    SuiteApp.pdf => OpcPackageKind.unknown,
  };

  bool get _activeSaveIsHeavy => switch (_app) {
    SuiteApp.word => OfficeSaveCost.isHeavyWord(_word.document),
    SuiteApp.excel => OfficeSaveCost.isHeavyWorkbook(_sheet.workbook),
    SuiteApp.powerpoint => OfficeSaveCost.isHeavyPresentation(
      _slides.presentation,
    ),
    SuiteApp.pdf => false,
  };

  String get _saveStatusLabel {
    if (_savePhase == _SavePhase.picking) {
      return _t(
        'Choose save location',
        StudioStrings.de('Choose save location'),
        'اختر مكان الحفظ',
      );
    }
    final int percent = (_saveProgress * 100).round();
    final String? path = _activePath;
    final String name = path == null ? '' : StudioFiles.nameOf(path);
    final String action = name.isEmpty
        ? (_t('Saving', StudioStrings.de('Saving'), 'جاري الحفظ'))
        : (_arabic ? 'جاري حفظ $name' : 'Saving $name');
    final String heavy = _saveHeavy
        ? (_t(
            ' · large file',
            StudioStrings.de(' · large file'),
            ' · ملف كبير',
          ))
        : '';
    return '$action$heavy · $percent%';
  }

  void _startSaveTicker() {
    _saveTicker?.cancel();
    _saveTicker = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted || _savePhase != _SavePhase.saving) {
        return;
      }
      setState(() {
        final double cap = _saveHeavy ? 0.78 : 0.88;
        final double step = _saveHeavy ? 0.006 : 0.018;
        if (_saveProgress < cap) {
          _saveProgress += step;
        }
      });
    });
  }

  void _stopSaveTicker() {
    _saveTicker?.cancel();
    _saveTicker = null;
  }

  Future<void> _saveFile() async {
    if (_isSaving) {
      return;
    }
    if (_app == SuiteApp.pdf) {
      await StudioFiles.save(
        bytes: _pdf.saveBytes(),
        fileName: _defaultSaveName,
      );
      return;
    }
    try {
      final String name = _defaultSaveName;
      if (kIsWeb) {
        setState(() {
          _saveHeavy = _activeSaveIsHeavy;
          _savePhase = _SavePhase.saving;
          _saveProgress = 0.04;
        });
        _startSaveTicker();
        await WidgetsBinding.instance.endOfFrame;
        final Uint8List bytes = await _active.saveBytesAsync();
        if (!mounted) {
          return;
        }
        await StudioFiles.save(bytes: bytes, fileName: name);
        _active.markClean();
        return;
      }

      String? path = _activePath;
      if (path == null) {
        setState(() => _savePhase = _SavePhase.picking);
        path = await StudioFiles.pickSavePath(fileName: name);
        if (path == null || !mounted) {
          return;
        }
        path = StudioFiles.withExtension(path, name);
        _activePath = path;
        _activeName = StudioFiles.nameOf(path);
      }

      setState(() {
        _saveHeavy = _activeSaveIsHeavy;
        _savePhase = _SavePhase.saving;
        _saveProgress = 0.04;
      });
      _startSaveTicker();
      await WidgetsBinding.instance.endOfFrame;
      await StudioFiles.saveOfficeToPath(
        path: path,
        kind: _activeKind,
        word: _app == SuiteApp.word ? _word.document : null,
        workbook: _app == SuiteApp.excel ? _sheet.workbook : null,
        presentation: _app == SuiteApp.powerpoint ? _slides.presentation : null,
      );
      if (!mounted) {
        return;
      }
      _active.markClean();
      setState(() => _saveProgress = 1);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    } catch (error) {
      _toast(
        _t(
          'Could not save the file.',
          StudioStrings.de('Could not save the file.'),
          'تعذر حفظ الملف.',
        ),
      );
    } finally {
      _stopSaveTicker();
      if (mounted) {
        setState(() {
          _savePhase = _SavePhase.idle;
          _saveHeavy = false;
          _saveProgress = 0;
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    try {
      if (_app == SuiteApp.pdf) {
        await StudioFiles.save(bytes: _pdf.saveBytes(), fileName: _pdfName);
        return;
      }
      final String stem = switch (_app) {
        SuiteApp.word => 'document',
        SuiteApp.excel => 'workbook',
        SuiteApp.powerpoint => 'presentation',
        SuiteApp.pdf => 'document',
      };
      final OfficeFontSet fonts = switch (_app) {
        SuiteApp.word => StudioFiles.exportFontSetForWord(
          _word.document,
          themeFamily: _officeTheme.fontFamily,
        ),
        SuiteApp.excel => StudioFiles.exportFontSetCovering(<String>[
          'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
          for (final SmlWorksheet sheet in _sheet.workbook.sheets) ...<String>[
            sheet.name,
            for (final SmlCell cell in sheet.allCells) cell.asString,
            for (final SmlDrawing drawing in sheet.drawings) ...<String>[
              drawing.visual.title,
              for (final ChartPoint point in drawing.visual.points) point.label,
            ],
          ],
        ]),
        SuiteApp.powerpoint => StudioFiles.exportFontSetCovering(<String>[
          for (final PmlSlide slide in _slides.presentation.slides) ...<String>[
            slide.notes,
            for (final PmlShape shape in slide.shapes) ...<String>[
              _slides.presentation.resolveText(shape, slide),
              if (shape.visual != null) shape.visual!.title,
              if (shape.visual != null)
                for (final ChartPoint point in shape.visual!.points)
                  point.label,
            ],
          ],
        ]),
        SuiteApp.pdf => const OfficeFontSet(),
      };
      final Uint8List bytes = _active.exportPdf(
        settings: OfficePrintSettings(title: stem),
        font: fonts.primary,
        fonts: fonts.isEmpty ? null : fonts,
      );
      await StudioFiles.save(bytes: bytes, fileName: '$stem.pdf');
    } catch (error) {
      _toast(
        _t(
          'Could not export PDF.',
          StudioStrings.de('Could not export PDF.'),
          'تعذر تصدير PDF.',
        ),
      );
    }
  }

  void _bindHostActions(OfficeController controller) {
    if (controller is WordEditorController) {
      // Harper remains local and initializes only for an English request.
      // Missing optional native/web artifacts are reported in the review UI.
      controller.proofing.configure(_wordProofingService(controller));
      // Set the Studio session's initial preference once. Rebuilding the editor
      // or returning from another app must preserve a later user opt-out.
      controller.proofing.enabled = true;
    }
    controller.onFindRequested = () {
      if (!mounted) {
        return;
      }
      setState(() {
        _findOpen = true;
        _findReplace = false;
      });
    };
    controller.onReplaceRequested = () {
      if (!mounted) {
        return;
      }
      setState(() {
        _findOpen = true;
        _findReplace = true;
      });
    };
    controller.onPrintRequested = () {
      _exportPdf();
    };
    controller.onSpellCheckRequested = _showSpelling;
  }

  void _openFind() {
    if (_app == SuiteApp.pdf) {
      setState(() => _findOpen = true);
      return;
    }
    _active.requestFind();
  }

  void _openReplace() => _active.requestReplace();

  void _closeFind() {
    _pdfFindDebounce?.cancel();
    if (_app == SuiteApp.pdf) {
      _pdf.find('');
    } else {
      _active.closeFind();
    }
    setState(() => _findOpen = false);
  }

  void _findNext() {
    if (!_findOpen) {
      _openFind();
      return;
    }
    if (_app == SuiteApp.pdf) {
      _pdfFindNext();
      return;
    }
    _navigateOffice(_active, _active.findNext);
    setState(() {});
  }

  void _findPrevious() {
    if (!_findOpen) {
      _openFind();
      return;
    }
    if (_app == SuiteApp.pdf) {
      _pdfFindPrevious();
      return;
    }
    _navigateOffice(_active, _active.findPrevious);
    setState(() {});
  }

  void _navigateOffice(OfficeController controller, VoidCallback operation) {
    try {
      operation();
    } on StateError catch (error) {
      if (controller is! SheetEditorController ||
          controller.lastValidationError != error.message) {
        rethrow;
      }
      _toast(
        _arabic
            ? 'صحّح الخلية الحالية قبل المتابعة.'
            : 'Correct the current cell before continuing.',
      );
    }
  }

  void _workspaceEscape() {
    if (_commentContextMenu != null) {
      _dismissCommentContext();
      return;
    }
    if (_findOpen) {
      _closeFind();
      return;
    }
    if (_app == SuiteApp.word && _word.reviewPaneVisible) {
      _word.closeReviewPane();
      _wordFocus.requestFocus();
      return;
    }
    _slideShowEscape();
  }

  Future<void> _showSpelling() async {
    if (_app != SuiteApp.word) {
      _toast(
        _t(
          'Spelling is available in Word',
          StudioStrings.de('Spelling is available in Word'),
          'التدقيق للمستندات',
        ),
      );
      return;
    }
    if (_word.config.allowsMutation) _word.commitPendingEdits();
    _word.openReviewPane();
    try {
      // An explicit F7/ribbon check may use opted-in manual grammar providers;
      // ordinary editing remains on the lightweight background service.
      await _word.checkDocumentProofing();
    } catch (_) {
      _toast(
        _arabic
            ? 'تعذر إكمال تدقيق المستند. حاول مجددًا.'
            : 'The document check could not finish. Try again.',
      );
    }
  }

  /// Fresh provider instances for the Word session's ordinary service. The
  /// Arabic rules precede an installed Arabic dictionary so that, where both
  /// agree on a correction, the rule's specific message is the one shown.
  OfficeProofingService _wordProofingService(WordEditorController controller) {
    final vocabulary = controller.proofing.vocabulary;
    return OfficeProofingService(
      providers: [
        GermanSpellingProvider(vocabulary: vocabulary),
        GermanWritingRulesProvider(),
        ArabicWritingRulesProvider(),
        ...studioHunspellHost.createProviders(vocabulary),
        HarperProofingProvider(vocabulary: vocabulary),
      ],
    );
  }

  String? _hunspellKey;

  /// Rebuilds the Word service when a dictionary is installed or removed.
  void _syncHunspell() {
    final key = studioHunspellHost.configurationKey;
    if (key == _hunspellKey) return;
    final first = _hunspellKey == null && key.isEmpty;
    _hunspellKey = key;
    if (first || !mounted) return;
    _word.proofing.configure(_wordProofingService(_word));
  }

  Future<void> _showHunspellSetup() async {
    await showStudioHunspellSetup(context);
    if (mounted) _wordFocus.requestFocus();
  }

  Future<void> _showSpacySetup() async {
    await showStudioSpacySetup(context);
    if (mounted) _wordFocus.requestFocus();
  }

  int _spacyGrammarEpoch = 0;
  String? _spacyGrammarKey;

  /// Registers the optional spaCy grammar provider on the Word session's
  /// manual service exactly while the user has it enabled for a verified,
  /// grammar-qualified build. It never joins the typing-time service.
  Future<void> _syncSpacyGrammar() async {
    final status = studioSpacyHost.status;
    final key = status.grammarEnabled && status.grammarOffered
        ? status.configurationKey
        : null;
    if (key == _spacyGrammarKey) return;
    _spacyGrammarKey = key;
    final epoch = ++_spacyGrammarEpoch;
    if (key == null) {
      _word.proofing.configureManual(null);
      return;
    }
    try {
      final transport = await studioSpacyHost.openTransport();
      if (!mounted || epoch != _spacyGrammarEpoch) {
        await transport.dispose();
        return;
      }
      _word.proofing.configureManual(
        OfficeProofingService(
          providers: [
            SpacyGrammarProvider.withTransport(
              transport: transport,
              enabled: true,
              vocabulary: _word.proofing.vocabulary,
            ),
          ],
          timeout: const Duration(seconds: 30),
        ),
      );
    } on Object catch (error) {
      if (!mounted || epoch != _spacyGrammarEpoch) return;
      _spacyGrammarKey = null;
      _toast(
        _arabic
            ? 'تعذر تشغيل التدقيق النحوي الألماني.'
            : 'German grammar check unavailable: $error',
      );
    }
  }

  Future<void> _showLinguisticAnalysis() async {
    await showDialog<void>(
      context: context,
      builder: (_) => StudioLinguisticAnalysisDialog(controller: _word),
    );
    if (mounted) _wordFocus.requestFocus();
  }

  Future<void> _showProperties() async {
    final OfficeDocumentProperties props = _active.documentProperties.copy();
    final TextEditingController title = TextEditingController(
      text: props.title,
    );
    final TextEditingController author = TextEditingController(
      text: props.creator,
    );
    try {
      final bool? save = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              _t(
                'Document properties',
                StudioStrings.de('Document properties'),
                'خصائص المستند',
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: _t(
                      'Title',
                      StudioStrings.de('Title'),
                      'العنوان',
                    ),
                  ),
                ),
                TextField(
                  controller: author,
                  decoration: InputDecoration(
                    labelText: _t(
                      'Author',
                      StudioStrings.de('Author'),
                      'المؤلف',
                    ),
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_t('Cancel', StudioStrings.de('Cancel'), 'إلغاء')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_t('Save', StudioStrings.de('Save'), 'حفظ')),
              ),
            ],
          );
        },
      );
      if (save == true) {
        _active.documentProperties
          ..title = title.text
          ..creator = author.text;
        _active.refresh();
      }
    } finally {
      title.dispose();
      author.dispose();
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  StudioRibbonGroup _clipboardGroup() {
    final OfficeStrings strings = _arabic
        ? OfficeStrings.arabic
        : OfficeStrings.english;
    return StudioRibbonGroup(
      title: _t('Clipboard', StudioStrings.de('Clipboard'), 'الحافظة'),
      children: <Widget>[
        StudioPasteCmd(
          accent: _accent,
          foreground: _officeTheme.chromeText,
          pasteLabel: strings.paste,
          keepSourceLabel: strings.pasteKeepSource,
          mergeLabel: strings.pasteMerge,
          textOnlyLabel: strings.pasteTextOnly,
          onPaste: _canMutate ? _paste : null,
          onKeepSource: _canMutate
              ? () => _pasteMode(OfficePasteMode.keepSource)
              : null,
          onMerge: _canMutate
              ? () => _pasteMode(OfficePasteMode.mergeFormatting)
              : null,
          onTextOnly: _canMutate
              ? () => _pasteMode(OfficePasteMode.keepTextOnly)
              : null,
        ),
        _cmd(
          Icons.content_cut,
          strings.cut,
          _canMutate && _active.canCut ? _cut : null,
        ),
        _cmd(Icons.content_copy, strings.copy, _active.canCopy ? _copy : null),
      ],
    );
  }

  Widget _pasteOptionsBar(bool dark) {
    final OfficeStrings strings = _arabic
        ? OfficeStrings.arabic
        : OfficeStrings.english;
    return Material(
      color: dark ? const Color(0xFF333333) : const Color(0xFFF3F3F3),
      child: SizedBox(
        height: 36,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 12),
            Icon(Icons.content_paste, size: 16, color: _accent),
            const SizedBox(width: 8),
            Text(
              strings.paste,
              style: TextStyle(fontSize: 12, color: _officeTheme.chromeText),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => _pasteMode(OfficePasteMode.keepSource),
              child: Text(strings.pasteKeepSource),
            ),
            TextButton(
              onPressed: () => _pasteMode(OfficePasteMode.mergeFormatting),
              child: Text(strings.pasteMerge),
            ),
            TextButton(
              onPressed: () => _pasteMode(OfficePasteMode.keepTextOnly),
              child: Text(strings.pasteTextOnly),
            ),
            const Spacer(),
            IconButton(
              tooltip: _strings.close,
              onPressed: () => setState(() => _showPasteOptions = false),
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  StudioCmd _cmd(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool selected = false,
  }) {
    return StudioCmd(
      icon: icon,
      label: label,
      accent: _accent,
      foreground: _officeTheme.chromeText,
      onPressed: onPressed,
      selected: selected,
    );
  }

  StudioIconCmd _icon(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool selected = false,
  }) {
    return StudioIconCmd(
      icon: icon,
      tooltip: tooltip,
      accent: _accent,
      foreground: _officeTheme.chromeText,
      onPressed: onPressed,
      selected: selected,
    );
  }

  WmlParagraph get _activeParagraph {
    final List<WmlParagraph> paras = _word.document.paragraphs.toList();
    if (paras.isEmpty) {
      return WmlParagraph();
    }
    return paras[_word.documentCaret.paragraphIndex.clamp(0, paras.length - 1)];
  }

  bool get _wordFullFormat => _canMutate && !_word.commentFormatLimited;

  bool get _canEditSlideText =>
      _canMutate &&
      _slides.selected != null &&
      _slides.selected!.visual == null &&
      _slides.selected!.table == null;

  bool get _canEditSlideTable => _canMutate && _slides.selectedTable != null;

  void _setAlign(WmlJustification justification) {
    if (!_wordFullFormat) {
      return;
    }
    _word.applyParagraphFormat((WmlParagraphProps props) {
      props.justification = justification;
    });
  }

  void _setWordDirection({required bool rtl}) {
    if (!_wordFullFormat) {
      return;
    }
    _word.setParagraphDirection(rtl: rtl);
  }

  KeyEventResult _onWorkspaceDirectionKey(FocusNode node, KeyEvent event) {
    final bool? rtl = officeDirectionFromKeyEvent(event);
    if (rtl == null || !_canMutate) {
      return KeyEventResult.ignored;
    }
    switch (_app) {
      case SuiteApp.word:
        if (!_wordFullFormat) {
          return KeyEventResult.ignored;
        }
        _word.setParagraphDirection(rtl: rtl);
        return KeyEventResult.handled;
      case SuiteApp.excel:
        _sheet.setSheetRightToLeft(rtl);
        return KeyEventResult.handled;
      case SuiteApp.powerpoint:
        if (!_canEditSlideText) {
          return KeyEventResult.ignored;
        }
        _slides.setSelectedTextDirection(rtl: rtl);
        return KeyEventResult.handled;
      case SuiteApp.pdf:
        return KeyEventResult.ignored;
    }
  }

  static const List<String> _textColors = <String>[
    '000000',
    '1F4E79',
    'C00000',
    '217346',
    'B7472A',
  ];

  static const List<String?> _highlights = <String?>[
    null,
    'FFFF00',
    '00B0F0',
    '92D050',
  ];

  void _cycleTextColor() {
    _word.applyRunFormat((WmlRunProps p) {
      final int i = _textColors.indexOf(p.color);
      p.color = _textColors[(i + 1) % _textColors.length];
    });
  }

  void _cycleHighlight() {
    _word.applyRunFormat((WmlRunProps p) {
      final int i = _highlights.indexOf(p.highlight);
      p.highlight = _highlights[(i + 1) % _highlights.length];
    });
  }

  void _nudgeFontSize(int deltaHalfPoints) {
    _word.applyRunFormat((WmlRunProps p) {
      p.fontSizeHalfPoints = (p.fontSizeHalfPoints + deltaHalfPoints)
          .clamp(16, 144)
          .toInt();
    });
  }

  List<String> get _fontFamilies {
    final String current = _activeFontFamily;
    if (OfficeTypeface.families.contains(current)) {
      return OfficeTypeface.families;
    }
    return <String>[current, ...OfficeTypeface.families];
  }

  String get _activeFontFamily {
    final WmlRunProps props = _word.activeRunProps;
    final List<WmlParagraph> paras = _word.document.paragraphs.toList();
    final String paraText = paras.isEmpty
        ? ''
        : paras[_word.documentCaret.paragraphIndex.clamp(0, paras.length - 1)]
              .text;
    final bool rtl = PaintRunText.looksRtl(paraText);
    final String face = rtl
        ? (props.csFont.isNotEmpty ? props.csFont : props.asciiFont)
        : (props.asciiFont.isNotEmpty ? props.asciiFont : props.csFont);
    if (OfficeTypeface.families.contains(face)) {
      return face;
    }
    if (face.isNotEmpty) {
      return face;
    }
    return _officeTheme.fontFamily ?? OfficeTypeface.arabicTheme;
  }

  int get _activeFontSizePt {
    final int pt = _word.activeRunProps.fontSizeHalfPoints ~/ 2;
    if (OfficeTypeface.sizesPt.contains(pt)) {
      return pt;
    }
    return pt.clamp(OfficeTypeface.sizesPt.first, OfficeTypeface.sizesPt.last);
  }

  StudioFaceStyle get _activeFaceStyle {
    final WmlRunProps props = _word.activeRunProps;
    if (props.bold && props.italic) {
      return StudioFaceStyle.boldItalic;
    }
    if (props.bold) {
      return StudioFaceStyle.bold;
    }
    if (props.italic) {
      return StudioFaceStyle.italic;
    }
    return StudioFaceStyle.regular;
  }

  int get _slideFontSizePt {
    final double size = _slides.selected?.fontSizePt ?? 18;
    final int pt = size > 0 ? size.round() : 18;
    if (OfficeTypeface.sizesPt.contains(pt)) {
      return pt;
    }
    return pt.clamp(OfficeTypeface.sizesPt.first, OfficeTypeface.sizesPt.last);
  }

  String _faceStyleLabel(StudioFaceStyle style) {
    return switch (style) {
      StudioFaceStyle.regular => _t(
        'Regular',
        StudioStrings.de('Regular'),
        'عادي',
      ),
      StudioFaceStyle.bold => _t('Bold', StudioStrings.de('Bold'), 'عريض'),
      StudioFaceStyle.italic => _t(
        'Italic',
        StudioStrings.de('Italic'),
        'مائل',
      ),
      StudioFaceStyle.boldItalic => _t(
        'Bold Italic',
        StudioStrings.de('Bold Italic'),
        'عريض مائل',
      ),
    };
  }

  void _setFontFamily(String family) {
    _word.applyRunFormat((WmlRunProps p) {
      p.asciiFont = family;
      p.csFont = family;
    });
  }

  void _setFontSizePt(int pt) {
    _word.applyRunFormat((WmlRunProps p) {
      p.fontSizeHalfPoints = (pt * 2).clamp(16, 144);
    });
  }

  void _setFaceStyle(StudioFaceStyle style) {
    _word.applyRunFormat((WmlRunProps p) {
      p.bold =
          style == StudioFaceStyle.bold || style == StudioFaceStyle.boldItalic;
      p.italic =
          style == StudioFaceStyle.italic ||
          style == StudioFaceStyle.boldItalic;
    });
  }

  void _toggleVertAlign(WmlVertAlign align) {
    _word.applyRunFormat((WmlRunProps p) {
      p.vertAlign = p.vertAlign == align ? WmlVertAlign.baseline : align;
    });
  }

  void _nudgeIndent(double delta) {
    _word.applyParagraphFormat((WmlParagraphProps p) {
      final WmlIndent current = p.indent;
      p.indent = WmlIndent(
        left: (current.left + delta).clamp(0, 144),
        right: current.right,
        firstLine: current.firstLine,
        hanging: current.hanging,
      );
    });
  }

  void _insertStudioCitation() {
    _word.insertCitation(
      WmlCitation(
        tag: 'Quds',
        author: _t(
          'CrispOffice',
          StudioStrings.de('CrispOffice'),
          'مكتب القدس',
        ),
        title: _t(
          'Office Guide',
          StudioStrings.de('Office Guide'),
          'دليل المكتب',
        ),
        year: '2026',
      ),
    );
  }

  void _studioMergeMail() {
    if (WordMailMerge.fieldsOf(_word.document).isEmpty) {
      _word.insertText(
        _t('Dear «Name»,', StudioStrings.de('Dear «Name»,'), 'عزيزي «الاسم»،'),
      );
    }
    _word.mergeMail(<String, String>{'Name': 'Mohammed', 'الاسم': 'محمد'});
  }

  void _studioCompareDocument() {
    _showDocumentReview(WordReviewTab.compare);
  }

  void _showDocumentReview(WordReviewTab tab) {
    unawaited(
      showWordReviewDialog(
        context,
        controller: _word,
        documentName: _wordName,
        pickDocument: StudioFiles.pickComparisonDocument,
        onExportReport: (name, json) => StudioFiles.save(
          fileName: name,
          bytes: Uint8List.fromList(utf8.encode(json)),
        ),
        initialTab: tab,
        arabic: _arabic,
      ),
    );
  }

  void _studioSheetValidation() {
    _sheet.addValidation(
      SmlDataValidation(
        range: _sheet.selection.range,
        kind: SmlValidationKind.list,
        formula1: _t('Yes,No', StudioStrings.de('Yes,No'), 'نعم,لا'),
      ),
    );
  }

  void _studioMergePreview() {
    final List<Map<String, String>> records = <Map<String, String>>[
      <String, String>{'Name': 'Ada', 'الاسم': 'آدا'},
      <String, String>{'Name': 'Omar', 'الاسم': 'عمر'},
    ];
    final int next = (_word.document.mailMergePreview + 1) % records.length;
    _word.previewMailMerge(records, index: next);
  }

  void _studioGoalSeek() {
    final SmlRange range = _sheet.selection.range;
    _sheet.goalSeek(
      target: SmlCellRef(range.maxCol, range.maxRow),
      changing: SmlCellRef(range.minCol, range.minRow),
      goal: 10,
    );
  }

  void _studioImportCsv() {
    _sheet.importCsv('Name,Amt\nAda,4\nOmar,6');
  }

  void _studioInsertPivot() {
    final SmlRange range = _sheet.selection.range;
    _sheet.insertPivot(
      source: range,
      rowField: 0,
      dataField: range.maxCol > range.minCol ? 1 : 0,
    );
  }

  void _insertWordTable(int rows, int cols) {
    final double width = cols == 2 ? 180 : 120;
    _insertBlockAfterActive(
      WmlTable(
        grid: <double>[for (int c = 0; c < cols; c++) width],
        rows: <WmlTableRow>[
          for (int r = 0; r < rows; r++)
            WmlTableRow(
              cells: <WmlTableCell>[
                for (int c = 0; c < cols; c++)
                  WmlTableCell(
                    blocks: <WmlBlock>[
                      WmlParagraph(
                        inlines: <WmlInline>[
                          WmlRun(
                            text: _arabic
                                ? 'خلية ${r + 1}×${c + 1}'
                                : 'Cell ${r + 1}×${c + 1}',
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<Uint8List> _pictureBytes({required bool fromFile}) async {
    if (fromFile) {
      final Uint8List? picked = await StudioFiles.pickImage();
      if (picked != null) {
        return picked;
      }
    }
    return PngBytes.studioCard();
  }

  Future<void> _insertWordPicture({bool fromFile = false}) async {
    if (_word.isEditingComment) {
      await _insertCommentPicture();
      return;
    }
    final Uint8List bytes = await _pictureBytes(fromFile: fromFile);
    _insertBlockAfterActive(
      WmlVisual(
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          title: _t('Picture', StudioStrings.de('Picture'), 'صورة'),
          imageBytes: bytes,
          width: 280,
          height: 160,
        ),
      ),
    );
  }

  void _insertWordEquation({String id = 'blank'}) {
    final OmmlEquation math = OmmlGallery.byId(id).build();
    _word.insertEquation(math);
    setState(() => _tab = _RibbonTab.design);
  }

  List<StudioRibbonGroup> _wordEquationTools() {
    final bool active = _word.selectedEquation != null && _canMutate;
    final OmmlView view =
        _word.selectedEquation?.math.view ?? OmmlView.professional;
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t('Tools', StudioStrings.de('Tools'), 'أدوات'),
        children: <Widget>[
          _cmd(
            Icons.auto_awesome,
            _t('Professional', StudioStrings.de('Professional'), 'احترافي'),
            active ? () => _word.setEquationView(OmmlView.professional) : null,
            selected: view == OmmlView.professional,
          ),
          _cmd(
            Icons.short_text,
            _t('Linear', StudioStrings.de('Linear'), 'خطي'),
            active ? () => _word.setEquationView(OmmlView.linear) : null,
            selected: view == OmmlView.linear,
          ),
          _cmd(
            Icons.delete_outline,
            _t('Delete', StudioStrings.de('Delete'), 'حذف'),
            active ? _word.deleteSelectedEquation : null,
          ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Symbols', StudioStrings.de('Symbols'), 'رموز'),
        children: <Widget>[
          for (final String symbol in const <String>[
            'π',
            'θ',
            'α',
            'β',
            'λ',
            '∞',
            '±',
            '×',
            '÷',
            '≠',
            '≤',
            '≥',
            '→',
          ])
            _cmd(
              Icons.functions,
              symbol,
              active ? () => _word.insertEquationSymbol(symbol) : null,
            ),
        ],
      ),
      StudioRibbonGroup(
        title: _t('Structures', StudioStrings.de('Structures'), 'تراكيب'),
        children: <Widget>[
          _cmd(
            Icons.horizontal_split,
            _t('Fraction', StudioStrings.de('Fraction'), 'كسر'),
            active
                ? () => _word.applyEquationStructure(OmmlStructure.fractionBar)
                : null,
          ),
          _cmd(
            Icons.superscript,
            _t('Script', StudioStrings.de('Script'), 'أس'),
            active
                ? () => _word.applyEquationStructure(OmmlStructure.superscript)
                : null,
          ),
          _cmd(
            Icons.square_foot,
            _t('Radical', StudioStrings.de('Radical'), 'جذر'),
            active
                ? () => _word.applyEquationStructure(OmmlStructure.squareRoot)
                : null,
          ),
          _cmd(
            Icons.integration_instructions,
            '∫',
            active
                ? () => _word.applyEquationStructure(
                    OmmlStructure.integralDefinite,
                  )
                : null,
          ),
          _cmd(
            Icons.functions,
            '∑',
            active
                ? () => _word.applyEquationStructure(OmmlStructure.sum)
                : null,
          ),
          _cmd(
            Icons.data_array,
            _t('Bracket', StudioStrings.de('Bracket'), 'قوس'),
            active
                ? () => _word.applyEquationStructure(OmmlStructure.paren)
                : null,
          ),
          _cmd(
            Icons.grid_on,
            _t('Matrix', StudioStrings.de('Matrix'), 'مصفوفة'),
            active
                ? () => _word.applyEquationStructure(OmmlStructure.matrix2x2)
                : null,
          ),
          _cmd(
            Icons.architecture,
            _t('sin', StudioStrings.de('sin'), 'sin'),
            active
                ? () => _word.applyEquationStructure(OmmlStructure.sin)
                : null,
          ),
          _cmd(
            Icons.trending_flat,
            _t('Limit', StudioStrings.de('Limit'), 'نهاية'),
            active
                ? () => _word.applyEquationStructure(OmmlStructure.lim)
                : null,
          ),
          _cmd(
            Icons.change_history,
            _t('Accent', StudioStrings.de('Accent'), 'قبعة'),
            active
                ? () => _word.applyEquationStructure(OmmlStructure.accentHat)
                : null,
          ),
        ],
      ),
    ];
  }

  void _insertWordVisual(OfficeVisualKind kind) {
    final bool diagram =
        kind == OfficeVisualKind.diagramProcess ||
        kind == OfficeVisualKind.diagramCycle ||
        kind == OfficeVisualKind.diagramHierarchy;
    _insertBlockAfterActive(
      WmlVisual(
        visual: OfficeVisual(
          kind: kind,
          title: _visualTitle(kind),
          points: diagram
              ? OfficeVisual.sampleSteps(arabic: _arabic)
              : OfficeVisual.sampleSeries(arabic: _arabic),
          width: 400,
          height: diagram ? 130 : 180,
        ),
      ),
    );
  }

  String _visualTitle(OfficeVisualKind kind) {
    return switch (kind) {
      OfficeVisualKind.picture => _t(
        'Picture',
        StudioStrings.de('Picture'),
        'صورة',
      ),
      OfficeVisualKind.chartColumn => _t(
        'Column chart',
        StudioStrings.de('Column chart'),
        'أعمدة',
      ),
      OfficeVisualKind.chartBar => _t(
        'Bar chart',
        StudioStrings.de('Bar chart'),
        'شريطي',
      ),
      OfficeVisualKind.chartPie => _t(
        'Pie chart',
        StudioStrings.de('Pie chart'),
        'دائري',
      ),
      OfficeVisualKind.chartLine => _t(
        'Line chart',
        StudioStrings.de('Line chart'),
        'خطي',
      ),
      OfficeVisualKind.diagramProcess => _t(
        'Process',
        StudioStrings.de('Process'),
        'عملية',
      ),
      OfficeVisualKind.diagramCycle => _t(
        'Cycle',
        StudioStrings.de('Cycle'),
        'دورة',
      ),
      OfficeVisualKind.diagramHierarchy => _t(
        'Hierarchy',
        StudioStrings.de('Hierarchy'),
        'هرمي',
      ),
    };
  }

  List<ChartPoint> _chartPointsFromSheet() {
    final SmlRange range = _sheet.selection.range;
    if (range.start.col == range.end.col && range.start.row == range.end.row) {
      return OfficeVisual.sampleSeries(arabic: _arabic);
    }
    final List<ChartPoint> points = SheetChartData.fromRange(
      book: _sheet.workbook,
      sheet: _sheet.sheet,
      from: range.start,
      to: range.end,
    );
    return points.isEmpty ? OfficeVisual.sampleSeries(arabic: _arabic) : points;
  }

  Future<void> _insertSheetPicture({bool fromFile = false}) async {
    final Uint8List bytes = await _pictureBytes(fromFile: fromFile);
    _sheet.sheet.drawings.add(
      SmlDrawing(
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          title: _t('Picture', StudioStrings.de('Picture'), 'صورة'),
          imageBytes: bytes,
          width: 240,
          height: 140,
        ),
        col: (_sheet.selection.focus.col + 2).clamp(0, 20),
        row: _sheet.selection.focus.row,
      ),
    );
    _sheet.selectDrawing(_sheet.sheet.drawings.length - 1);
  }

  void _insertSheetChart(OfficeVisualKind kind) {
    final SmlRange range = _sheet.selection.range;
    final bool linked =
        range.start.col != range.end.col || range.start.row != range.end.row;
    _sheet.sheet.drawings.add(
      SmlDrawing(
        visual: OfficeVisual(
          kind: kind,
          title: _visualTitle(kind),
          points: _chartPointsFromSheet(),
          width: 280,
          height: 160,
        ),
        col: (_sheet.selection.focus.col + 2).clamp(0, 20),
        row: _sheet.selection.focus.row,
        sourceFromA1: linked ? range.start.a1 : null,
        sourceToA1: linked ? range.end.a1 : null,
      ),
    );
    _sheet.selectDrawing(_sheet.sheet.drawings.length - 1);
  }

  Future<void> _insertSlidePicture({bool fromFile = false}) async {
    final Uint8List bytes = await _pictureBytes(fromFile: fromFile);
    final PmlSlide slide = _slides.slide;
    final PmlShape shape = PmlShape(
      id: _nextShapeId(slide),
      name: 'Picture',
      fillColor: 'FFFFFF',
      transform: const PmlTransform(
        x: 2200000,
        y: 1200000,
        cx: 4700000,
        cy: 2600000,
      ),
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: _t('Picture', StudioStrings.de('Picture'), 'صورة'),
        imageBytes: bytes,
      ),
    );
    slide.shapes.add(shape);
    _slides.selectShape(shape);
  }

  void _insertSlideVisual(OfficeVisualKind kind) {
    final PmlSlide slide = _slides.slide;
    final bool diagram =
        kind == OfficeVisualKind.diagramProcess ||
        kind == OfficeVisualKind.diagramCycle ||
        kind == OfficeVisualKind.diagramHierarchy;
    final PmlShape shape = PmlShape(
      id: _nextShapeId(slide),
      name: kind.name,
      fillColor: 'FFFFFF',
      transform: const PmlTransform(
        x: 1600000,
        y: 1100000,
        cx: 5900000,
        cy: 2800000,
      ),
      visual: OfficeVisual(
        kind: kind,
        title: _visualTitle(kind),
        points: diagram
            ? OfficeVisual.sampleSteps(arabic: _arabic)
            : OfficeVisual.sampleSeries(arabic: _arabic),
      ),
    );
    slide.shapes.add(shape);
    _slides.selectShape(shape);
  }

  void _openExternalLink(WmlHyperlink link) {
    final String? target = link.url ?? link.file;
    if (target == null || target.isEmpty) {
      return;
    }
    if (Platform.isWindows) {
      Process.start('cmd', <String>['/c', 'start', '', target]);
    } else if (Platform.isMacOS) {
      Process.start('open', <String>[target]);
    } else {
      Process.start('xdg-open', <String>[target]);
    }
  }

  bool get _selectedThreadResolved {
    final int? id = _word.selectedCommentId;
    if (id == null) {
      return false;
    }
    return WordComment.byId(
          _word.document,
          WordComment.threadRootId(_word.document, id),
        )?.resolved ??
        false;
  }

  void _newWordComment() {
    if (!_canMutate) {
      return;
    }
    setState(() => _showComments = true);
    _word.insertComment(author: 'CrispOffice', initials: 'QO');
  }

  void _setShowComments(bool show) {
    if (!show) _dismissCommentContext();
    setState(() => _showComments = show);
  }

  void _dismissCommentContext() {
    _commentReviewTimer?.cancel();
    OfficeContextMenu.dismiss(_commentContextMenu);
    _commentContextMenu = null;
    _restoreCommentContextFocus();
    _commentContextIsCurrent = null;
  }

  void _restoreCommentContextFocus() {
    final restore =
        _commentContextKeyboard && (_commentContextIsCurrent?.call() ?? false);
    _commentContextKeyboard = false;
    if (restore && mounted && _wordRouteIsCurrent) _wordFocus.requestFocus();
  }

  void _syncCommentReplyDrafts() {
    final document = _word.document;
    if (!identical(_commentDraftDocument, document)) {
      _commentReplyDrafts.clear();
      _commentDraftDocument = document;
    }
    _commentReplyDrafts.removeWhere(
      (id, draft) =>
          !identical(WordComment.byId(document, id), draft.root) ||
          draft.root.parentId != null,
    );
  }

  _CommentReplyDraft _commentReplyDraft(WmlComment root) {
    _syncCommentReplyDrafts();
    return _commentReplyDrafts.putIfAbsent(
      root.id,
      () => _CommentReplyDraft(root),
    );
  }

  void _replyWordComment(int parentId) {
    if (!_canMutate || !_word.config.allowsMutation) return;
    final document = _word.document;
    final root = WordComment.byId(
      document,
      WordComment.threadRootId(document, parentId),
    );
    if (root == null || root.parentId != null) return;
    final draft = _commentReplyDraft(root);
    setState(() => _showComments = true);
    _word.endCommentEdit();
    _word.selectComment(root.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_showComments ||
          !_canMutate ||
          !identical(document, _word.document) ||
          !identical(WordComment.byId(document, root.id), root) ||
          _word.selectedCommentId != root.id) {
        return;
      }
      draft.key.currentState?.focusReply();
    });
  }

  bool _postCommentReply(_CommentReplyDraft draft) {
    _syncCommentReplyDrafts();
    final text = draft.text.trim();
    final root = draft.root;
    final selected = _word.selectedCommentId;
    if (text.isEmpty ||
        !_canMutate ||
        !_word.config.allowsMutation ||
        !identical(_commentReplyDrafts[root.id], draft) ||
        !identical(WordComment.byId(_word.document, root.id), root) ||
        selected == null ||
        WordComment.threadRootId(_word.document, selected) != root.id) {
      return false;
    }
    final before = _word.document.comments.length;
    _word.replyToComment(root.id, text: text);
    if (_word.document.comments.length != before + 1) return false;
    draft.text = '';
    return true;
  }

  void _showCommentReview(OfficeContextHit hit) {
    _commentReviewTimer?.cancel();
    final document = _word.document;
    final comment = _word.selectedComment;
    _commentReviewTimer = Timer(kDoubleTapTimeout, () {
      if (!mounted ||
          comment == null ||
          !_wordRouteIsCurrent ||
          (_word.input.composing.isValid &&
              !_word.input.composing.isCollapsed) ||
          !identical(document, _word.document) ||
          !identical(comment, _word.selectedComment)) {
        return;
      }
      final paragraph = hit.paragraph;
      final offset = hit.proofingOffset;
      if (paragraph == null || offset == null) return;
      final issue = _word.proofing.issuesAt(paragraph, offset).firstOrNull;
      if (issue == null) return;
      _word.selectProofingIssue(issue, reveal: false);
      if (_word.reviewPaneVisible) {
        _word.setReviewPaneTab(WordReviewPaneTab.proofing);
      } else {
        _showCommentContext(comment, hit, reviewOnly: true);
      }
    });
  }

  bool get _wordRouteIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  void _showCommentCaretContext() {
    if (!mounted ||
        _app != SuiteApp.word ||
        !_showComments ||
        !_wordFocus.hasPrimaryFocus ||
        !_wordRouteIsCurrent ||
        !_word.config.allowsSelection ||
        !_word.isEditingComment ||
        (_word.input.composing.isValid && !_word.input.composing.isCollapsed)) {
      return;
    }
    final comment = _word.selectedComment;
    final canvas = _commentCanvasKey.currentContext?.findRenderObject();
    if (comment == null ||
        canvas is! RenderWordCanvas ||
        canvas.selectedCommentId != comment.id ||
        !identical(canvas.caret, _word.commentCaret)) {
      return;
    }
    var hit = canvas.contextHitForCaret();
    if (hit == null || !comment.paragraphs.contains(hit.paragraph)) return;
    // The selected finding's caret can sit just past its underline. Preserve
    // both the source offset and the identity of overlapping findings.
    final selected = _word.selectedProofingIssue;
    final caret = _word.commentCaret;
    WordProofingIssue? preferredIssue;
    if (selected != null &&
        identical(selected.paragraph, hit.paragraph) &&
        caret.selectionAnchorParagraph == caret.paragraphIndex &&
        ((caret.selectionAnchor == selected.finding.start &&
                caret.logicalIndex == selected.finding.end) ||
            (caret.selectionAnchor == selected.finding.end &&
                caret.logicalIndex == selected.finding.start))) {
      preferredIssue = selected;
      hit = canvas.contextHitForCaret(proofingOffset: selected.finding.start);
      if (hit == null) return;
    }
    _showCommentContext(
      comment,
      hit,
      keyboardNavigation: true,
      preferredIssue: preferredIssue,
    );
  }

  void _showCommentContext(
    WmlComment comment,
    OfficeContextHit hit, {
    bool reviewOnly = false,
    bool keyboardNavigation = false,
    WordProofingIssue? preferredIssue,
  }) {
    _dismissCommentContext();
    if (!_wordRouteIsCurrent ||
        !_word.config.allowsSelection ||
        (_word.input.composing.isValid && !_word.input.composing.isCollapsed)) {
      return;
    }
    final document = _word.document;
    if (!identical(comment, _word.selectedComment) ||
        !identical(WordComment.byId(document, comment.id), comment)) {
      return;
    }
    // A secondary click does not run the canvas's primary-click selection
    // handler. Route ordinary editing commands to this comment as well as
    // routing proofing commands by their explicit finding.
    if (!_word.isEditingComment) {
      _word.beginCommentEdit(comment.id);
    }
    final root = WordComment.byId(
      document,
      WordComment.threadRootId(document, comment.id),
    );
    final revision = _word.contentRevision;
    final paragraph = hit.paragraph;
    final offset = hit.proofingOffset;
    final issues =
        paragraph != null &&
            offset != null &&
            comment.paragraphs.contains(paragraph)
        ? _word.proofing.issuesAt(paragraph, offset)
        : const <WordProofingIssue>[];
    final issue = preferredIssue != null && issues.contains(preferredIssue)
        ? preferredIssue
        : issues.firstOrNull;
    final editing = _word.isEditingComment;
    final caret = (
      paragraph: _word.commentCaret.paragraphIndex,
      index: _word.commentCaret.logicalIndex,
      anchorParagraph: _word.commentCaret.selectionAnchorParagraph,
      anchor: _word.commentCaret.selectionAnchor,
    );
    bool current() =>
        mounted &&
        _app == SuiteApp.word &&
        _showComments &&
        identical(document, _word.document) &&
        identical(comment, _word.selectedComment) &&
        identical(WordComment.byId(document, comment.id), comment) &&
        root != null &&
        identical(WordComment.byId(document, root.id), root) &&
        _word.contentRevision == revision &&
        _word.isEditingComment == editing &&
        _word.commentCaret.paragraphIndex == caret.paragraph &&
        _word.commentCaret.logicalIndex == caret.index &&
        _word.commentCaret.selectionAnchorParagraph == caret.anchorParagraph &&
        _word.commentCaret.selectionAnchor == caret.anchor &&
        (issue == null || _word.proofing.isCurrent(issue));
    bool canMutateCurrent() =>
        current() &&
        _wordRouteIsCurrent &&
        _canMutate &&
        _word.config.allowsMutation &&
        !(_word.input.composing.isValid && !_word.input.composing.isCollapsed);
    if (!current()) return;
    final actions = <OfficeContextAction>[
      if (issue != null) ...[
        OfficeContextAction.caption(issue.finding.message),
        for (var i = 0; i < issue.finding.replacements.length && i < 8; i++)
          OfficeContextAction(
            id: 'proofing:replace:$i',
            label: issue.finding.replacements[i].isEmpty
                ? (_t('Delete', StudioStrings.de('Delete'), 'حذف'))
                : issue.finding.replacements[i],
            enabled: _canMutate && _word.canApplyProofingIssue(issue),
          ),
        OfficeContextAction(
          id: 'proofing:ignore',
          label: _t(
            'Ignore once',
            StudioStrings.de('Ignore once'),
            'تجاهل مرة واحدة',
          ),
        ),
        if (issue.finding.category == OfficeProofingCategory.spelling) ...[
          OfficeContextAction(
            id: 'proofing:ignoreWord',
            label: _t(
              'Ignore this word',
              StudioStrings.de('Ignore this word'),
              'تجاهل هذه الكلمة',
            ),
          ),
          OfficeContextAction(
            id: 'proofing:add',
            label: _arabic
                ? 'إضافة إلى الكلمات الشخصية'
                : 'Add to personal words',
          ),
        ],
      ],
      OfficeContextAction(
        id: 'proofing:review',
        label: _t(
          'Open writing pane',
          StudioStrings.de('Open writing pane'),
          'فتح لوحة الكتابة',
        ),
        shortcut: 'F7',
        separatorBefore: issue != null,
      ),
      if (!reviewOnly)
        ...OfficeContextMenu.word(
          hit: OfficeContextHit(
            kind: OfficeContextKind.comment,
            globalPosition: hit.globalPosition,
            commentId: comment.id,
            paragraph: paragraph,
            proofingOffset: offset,
          ),
          controller: _word,
        ),
    ];
    _commentContextIsCurrent = current;
    _commentContextKeyboard = keyboardNavigation;
    _commentContextMenu = OfficeContextMenu.show(
      context: context,
      globalPosition: hit.globalPosition,
      actions: actions,
      enableFiltering: !reviewOnly,
      keyboardNavigation: keyboardNavigation,
      onDismiss: () {
        _commentContextMenu = null;
        _restoreCommentContextFocus();
        _commentContextIsCurrent = null;
      },
      onSelect: (id) {
        if (!current() || !_wordRouteIsCurrent) return;
        if (id == 'proofing:review') {
          if (issue != null) _word.selectProofingIssue(issue, reveal: false);
          _word.openReviewPane();
          return;
        }
        if (_word.input.composing.isValid &&
            !_word.input.composing.isCollapsed) {
          return;
        }
        if (issue != null && id.startsWith('proofing:')) {
          if (id == 'proofing:ignore') {
            _word.proofing.ignoreOnce(issue);
          } else if (id == 'proofing:ignoreWord') {
            _word.proofing.ignoreWord(issue);
          } else if (id == 'proofing:add') {
            _word.proofing.addWord(issue);
          } else if (id.startsWith('proofing:replace:') && _canMutate) {
            final index = int.tryParse(id.split(':').last);
            if (index != null &&
                index >= 0 &&
                index < issue.finding.replacements.length) {
              _word.applyProofingSuggestion(
                issue,
                issue.finding.replacements[index],
              );
            }
          }
          if (!_word.proofing.enabled) {
            unawaited(_checkCommentProofing());
          }
          return;
        }
        if (id == 'copy') {
          _word.copyToClipboard();
        } else if (id == 'selectAll') {
          _word.selectAll();
        } else if (_canMutate && _word.config.allowsMutation) {
          switch (id) {
            case 'cut':
              _word.cutToClipboard(isCurrent: canMutateCurrent);
            case 'paste':
              _word.pasteFromClipboard(isCurrent: canMutateCurrent);
            case 'replyComment':
              _replyWordComment(comment.id);
            case 'resolveComment':
              _word.setCommentResolved(comment.id, true);
            case 'reopenComment':
              _word.setCommentResolved(comment.id, false);
            case 'deleteComment':
              _word.deleteComment(comment.id);
          }
        }
      },
    );
  }

  Future<void> _checkCommentProofing() async {
    try {
      await _word.proofing.checkNow(includeManualProviders: false);
    } on Object {
      if (!mounted) return;
      _toast(
        _arabic
            ? 'تعذر إكمال تدقيق المستند. حاول مجددًا.'
            : 'The document check could not finish. Try again.',
      );
    }
  }

  Future<void> _insertCommentPicture() async {
    final int? id = _word.selectedCommentId;
    if (id == null || !_canMutate) {
      return;
    }
    final Uint8List bytes = await _pictureBytes(fromFile: true);
    _word.insertCommentVisual(
      id,
      OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: _t('Picture', StudioStrings.de('Picture'), 'صورة'),
        imageBytes: bytes,
        width: 180,
        height: 100,
      ),
    );
  }

  String _commentDateLabel(WmlComment comment) {
    if (comment.dateIso.isEmpty) {
      return '';
    }
    final DateTime? parsed = DateTime.tryParse(comment.dateIso);
    if (parsed == null) {
      return comment.dateIso;
    }
    final DateTime local = parsed.toLocal();
    final String mm = local.month.toString().padLeft(2, '0');
    final String dd = local.day.toString().padLeft(2, '0');
    final String hh = local.hour.toString().padLeft(2, '0');
    final String min = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd $hh:$min';
  }

  Color _hexColor(String hex) {
    final int value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0;
    return Color(0xFF000000 | value);
  }

  TextStyle _commentRunStyle(WmlRunProps props) {
    return TextStyle(
      fontSize: 12,
      height: 1.35,
      fontWeight: props.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: props.italic ? FontStyle.italic : FontStyle.normal,
      decoration: props.strike
          ? TextDecoration.lineThrough
          : props.underline == WmlUnderline.none
          ? TextDecoration.none
          : TextDecoration.underline,
      color: _hexColor(props.color),
      backgroundColor: props.highlight == null
          ? null
          : _hexColor(props.highlight!),
    );
  }

  List<InlineSpan> _commentSpans(WmlComment comment) {
    final List<InlineSpan> spans = <InlineSpan>[];
    for (int i = 0; i < comment.paragraphs.length; i++) {
      if (i > 0) {
        spans.add(const TextSpan(text: '\n'));
      }
      for (final WmlInline inline in comment.paragraphs[i].inlines) {
        if (inline is WmlRun && inline.text.isNotEmpty) {
          spans.add(
            TextSpan(
              text: inline.text,
              style: _commentRunStyle(inline.properties),
            ),
          );
        }
      }
    }
    if (spans.isEmpty && comment.text.isNotEmpty) {
      spans.add(TextSpan(text: comment.text));
    }
    return spans;
  }

  Widget _wordCommentsPane(bool dark, {bool expanded = false}) {
    // Match the Word surface's current mode before its child rebuilds.
    _word.syncConfig(
      _printPreview
          ? _config.copyWith(mode: OfficeInteractionMode.viewing)
          : _config,
    );
    _syncCommentReplyDrafts();
    final Color bg = dark ? const Color(0xFF242424) : const Color(0xFFF3F3F3);
    final List<WmlComment> roots = WordComment.roots(_word.document);
    return Material(
      color: bg,
      child: SizedBox(
        key: const ValueKey<String>('studio-comments-pane'),
        width: expanded ? null : 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            StudioPaneTitle(
              text: _t('Comments', StudioStrings.de('Comments'), 'تعليقات'),
              accent: _accent,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      roots.isEmpty
                          ? (_t(
                              'No comments',
                              StudioStrings.de('No comments'),
                              'لا تعليقات',
                            ))
                          : (_arabic
                                ? '${roots.length} محادثة'
                                : '${roots.length} threads'),
                      style: TextStyle(
                        fontSize: 11,
                        color: _officeTheme.chromeText,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _t('Hide', StudioStrings.de('Hide'), 'إخفاء'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _setShowComments(false),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                children: <Widget>[
                  if (roots.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _arabic
                            ? 'حدّد فقرة أو جزءاً من النص ثم اضغط جديداً لإدراج تعليق.'
                            : 'Select a paragraph or range, then insert a comment.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _officeTheme.chromeText.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  for (final WmlComment root in roots) ...<Widget>[
                    _commentCard(root, root: root, dark: dark),
                    for (final WmlComment reply in WordComment.repliesOf(
                      _word.document,
                      root.id,
                    ))
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 18),
                        child: _commentCard(reply, root: root, dark: dark),
                      ),
                    if (_word.selectedCommentId != null &&
                        WordComment.threadRootId(
                              _word.document,
                              _word.selectedCommentId!,
                            ) ==
                            root.id &&
                        _canMutate)
                      _commentReplyBox(root, dark),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentReplyBox(WmlComment root, bool dark) {
    final draft = _commentReplyDraft(root);
    final document = _word.document;
    return _CommentReplyComposer(
      key: draft.key,
      draft: draft,
      proofing: _word.proofing,
      isCurrent: () =>
          mounted &&
          _app == SuiteApp.word &&
          _showComments &&
          !_opening &&
          _canMutate &&
          _word.config.allowsMutation &&
          _wordRouteIsCurrent &&
          identical(document, _word.document) &&
          identical(_commentReplyDrafts[root.id], draft) &&
          identical(WordComment.byId(document, root.id), root) &&
          _word.selectedCommentId != null &&
          WordComment.threadRootId(document, _word.selectedCommentId!) ==
              root.id,
      arabic: _arabic,
      dark: dark,
      textColor: _officeTheme.chromeText,
      accent: _accent,
      onPost: () => _postCommentReply(draft),
    );
  }

  Widget _commentCard(
    WmlComment comment, {
    required WmlComment root,
    required bool dark,
  }) {
    final bool selected = _word.selectedCommentId == comment.id;
    final bool dimmed = root.resolved;
    return Opacity(
      key: ValueKey<String>('studio-comment-${comment.id}'),
      opacity: dimmed ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: selected
              ? _accent.withValues(alpha: dark ? 0.22 : 0.12)
              : (dark ? const Color(0xFF2A2A2A) : Colors.white),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: selected ? _accent : const Color(0x33000000),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                InkWell(
                  onTap: () => _word.jumpToComment(comment.id),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: _accent,
                        child: Text(
                          (comment.initials.isEmpty
                                  ? comment.author
                                  : comment.initials)
                              .substring(
                                0,
                                ((comment.initials.isEmpty
                                            ? comment.author
                                            : comment.initials)
                                        .length)
                                    .clamp(0, 2),
                              )
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              comment.author,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _officeTheme.chromeText,
                              ),
                            ),
                            if (_commentDateLabel(comment).isNotEmpty)
                              Text(
                                _commentDateLabel(comment),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: _officeTheme.chromeText.withValues(
                                    alpha: 0.65,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (root.resolved)
                        Text(
                          _t(
                            'Resolved',
                            StudioStrings.de('Resolved'),
                            'تم الحل',
                          ),
                          style: TextStyle(
                            fontSize: 9,
                            color: _accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                if (selected && !_opening && _word.config.allowsSelection)
                  _commentBodySurface(comment)
                else
                  Text.rich(
                    TextSpan(
                      children: _commentSpans(comment).isEmpty
                          ? <InlineSpan>[
                              TextSpan(
                                text: _t(
                                  '(empty)',
                                  StudioStrings.de('(empty)'),
                                  '(فارغ)',
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: _officeTheme.chromeText.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                            ]
                          : _commentSpans(comment),
                    ),
                  ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 0,
                      children: <Widget>[
                        IconButton(
                          key: ValueKey<String>(
                            'studio-comment-reply-action-${comment.id}',
                          ),
                          tooltip: _t('Reply', StudioStrings.de('Reply'), 'رد'),
                          visualDensity: VisualDensity.compact,
                          onPressed: _canMutate
                              ? () => _replyWordComment(root.id)
                              : null,
                          icon: const Icon(Icons.reply, size: 16),
                        ),
                        IconButton(
                          tooltip: root.resolved
                              ? (_t(
                                  'Reopen',
                                  StudioStrings.de('Reopen'),
                                  'إعادة فتح',
                                ))
                              : (_t(
                                  'Resolve',
                                  StudioStrings.de('Resolve'),
                                  'حل',
                                )),
                          visualDensity: VisualDensity.compact,
                          onPressed: _canMutate
                              ? () => _word.setCommentResolved(
                                  root.id,
                                  !root.resolved,
                                )
                              : null,
                          icon: Icon(
                            root.resolved ? Icons.replay : Icons.task_alt,
                            size: 16,
                          ),
                        ),
                        IconButton(
                          tooltip: _t(
                            'Delete',
                            StudioStrings.de('Delete'),
                            'حذف',
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: _canMutate
                              ? () => _word.deleteComment(comment.id)
                              : null,
                          icon: const Icon(Icons.delete_outline, size: 16),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _commentBodySurface(WmlComment comment) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _word.setCommentSurfaceWidth(width);
          }
        });
        final LaidOutDocument? laid = _word.commentLaidOut;
        if (laid == null) {
          return const SizedBox(height: 56);
        }
        return SizedBox(
          height: _word.commentSurfaceHeight,
          child: Builder(
            key: _commentCanvasKey,
            builder: (_) => WordCanvas(
              key: ValueKey<String>('studio-comment-canvas-${comment.id}'),
              compact: true,
              document: _word.commentDocument,
              laidOut: laid,
              caret: _word.commentCaret,
              viewport: _commentViewport,
              hasFocus:
                  _word.isEditingComment &&
                  _word.selectedCommentId == comment.id,
              config: _word.config.copyWith(showRulers: false),
              selectedCommentId: comment.id,
              proofingFindings: _word.proofing.findingsByParagraph,
              onReviewTap: _showCommentReview,
              onContextMenu: (hit) => _showCommentContext(comment, hit),
              onChanged: () {
                if (!_word.isEditingComment ||
                    _word.selectedCommentId != comment.id) {
                  _word.beginCommentEdit(comment.id);
                } else {
                  // Selection, dragging, and repeated clicks must cancel a
                  // pending review tap without invalidating checked text.
                  _word.refreshView();
                }
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _insertWordLink({required _WordLinkKind kind}) async {
    if (!_canMutate) {
      return;
    }
    final List<WmlHeadingRef> headings = WordToc.headings(_word.document);
    final TextEditingController label = TextEditingController(
      text: !_word.documentCaret.isCollapsed
          ? _activeParagraph.text.substring(
              _word.documentCaret.normalizedRange.startIdx,
              _word.documentCaret.normalizedRange.endIdx,
            )
          : (kind == _WordLinkKind.bookmark && headings.isNotEmpty
                ? headings.first.text
                : kind == _WordLinkKind.file
                ? (_t('Local file', StudioStrings.de('Local file'), 'ملف محلي'))
                : 'ECMA-376'),
    );
    final TextEditingController target = TextEditingController(
      text: switch (kind) {
        _WordLinkKind.web => 'https://www.ecma-international.org/',
        _WordLinkKind.file => '/etc/os-release',
        _WordLinkKind.bookmark =>
          headings.isEmpty
              ? ''
              : WordLink.headingBookmark(
                  headings.first.text,
                  headings.first.level,
                ),
      },
    );
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(switch (kind) {
            _WordLinkKind.web => _t(
              'Web link',
              StudioStrings.de('Web link'),
              'رابط ويب',
            ),
            _WordLinkKind.file => _t(
              'File link',
              StudioStrings.de('File link'),
              'رابط ملف',
            ),
            _WordLinkKind.bookmark => _t(
              'Document reference',
              StudioStrings.de('Document reference'),
              'مرجع داخل المستند',
            ),
          }),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: label,
                  decoration: InputDecoration(
                    labelText: _t('Text', StudioStrings.de('Text'), 'النص'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: target,
                  decoration: InputDecoration(
                    labelText: switch (kind) {
                      _WordLinkKind.web => _t(
                        'URL',
                        StudioStrings.de('URL'),
                        'العنوان',
                      ),
                      _WordLinkKind.file => _t(
                        'Path',
                        StudioStrings.de('Path'),
                        'المسار',
                      ),
                      _WordLinkKind.bookmark => _t(
                        'Bookmark / heading',
                        StudioStrings.de('Bookmark / heading'),
                        'إشارة مرجعية / عنوان',
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('Cancel', StudioStrings.de('Cancel'), 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('Insert', StudioStrings.de('Insert'), 'إدراج')),
            ),
          ],
        );
      },
    );
    if (ok != true) {
      label.dispose();
      target.dispose();
      return;
    }
    final WmlHyperlink? link = switch (kind) {
      _WordLinkKind.web => WmlHyperlink(url: target.text.trim()),
      _WordLinkKind.file => WmlHyperlink(file: target.text.trim()),
      _WordLinkKind.bookmark => WmlHyperlink.fromTarget(target.text.trim()),
    };
    if (link != null) {
      _word.insertHyperlink(text: label.text.trim(), link: link);
    }
    label.dispose();
    target.dispose();
  }

  void _insertQuote() {
    _word.insertParagraphBreak();
    _word.insertText(
      _arabic
          ? 'اقتباس: حدد النص ثم طبّق تنسيق التحديد فقط.'
          : 'Quote: select a range, then apply formatting to that range only.',
    );
    final WmlParagraph para = _activeParagraph;
    para.properties.indent = const WmlIndent(left: 36);
    para.properties.justification = WmlJustification.left;
    for (final WmlInline inline in para.inlines) {
      if (inline is WmlRun) {
        inline.properties.italic = true;
        inline.properties.color = '595959';
      }
    }
    _word.relayout();
    _word.refresh();
  }

  void _insertPageBreak() {
    _word.insertParagraphBreak();
    _activeParagraph.properties.pageBreakBefore = true;
    _word.insertText(
      _t('New page', StudioStrings.de('New page'), 'صفحة جديدة'),
    );
    _word.relayout();
    _word.refresh();
  }

  void _setLineSpacing(double value) {
    _word.applyParagraphFormat((WmlParagraphProps p) => p.lineSpacing = value);
  }

  void _nudgeParagraphSpacing({double before = 0, double after = 0}) {
    _word.applyParagraphFormat((WmlParagraphProps p) {
      p.spacingBefore = (p.spacingBefore + before).clamp(0, 72);
      p.spacingAfter = (p.spacingAfter + after).clamp(0, 72);
    });
  }

  void _toggleFirstLineIndent() {
    _word.applyParagraphFormat((WmlParagraphProps p) {
      final WmlIndent cur = p.indent;
      p.indent = WmlIndent(
        left: cur.left,
        right: cur.right,
        firstLine: cur.firstLine > 0 ? 0 : 36,
        hanging: 0,
      );
    });
  }

  void _toggleHangingIndent() {
    _word.applyParagraphFormat((WmlParagraphProps p) {
      final WmlIndent cur = p.indent;
      p.indent = WmlIndent(
        left: cur.left,
        right: cur.right,
        firstLine: 0,
        hanging: cur.hanging > 0 ? 0 : 36,
      );
    });
  }

  String _marginPresetId(WmlPageMargins margins) {
    if (margins.matches(WmlPageMargins.narrow)) {
      return 'narrow';
    }
    if (margins.matches(WmlPageMargins.moderate)) {
      return 'moderate';
    }
    if (margins.matches(WmlPageMargins.wide)) {
      return 'wide';
    }
    return 'normal';
  }

  String _marginPresetLabel(String id) => switch (id) {
    'narrow' => _t(
      'Narrow (0.5")',
      StudioStrings.de('Narrow (0.5")'),
      'ضيق (0.5")',
    ),
    'moderate' => _t(
      'Moderate (0.75")',
      StudioStrings.de('Moderate (0.75")'),
      'متوسط (0.75")',
    ),
    'wide' => _t('Wide (2")', StudioStrings.de('Wide (2")'), 'واسع (2")'),
    _ => _t('Normal (1")', StudioStrings.de('Normal (1")'), 'عادي (1")'),
  };

  void _applyMarginPreset(String id) {
    _word.setPageMargins(switch (id) {
      'narrow' => WmlPageMargins.narrow,
      'moderate' => WmlPageMargins.moderate,
      'wide' => WmlPageMargins.wide,
      _ => WmlPageMargins.normal,
    });
  }

  void _selectAllDocument() => _word.selectAll();

  void _insertBlockAfterActive(WmlBlock block) {
    for (final WmlSection section in _word.document.sections) {
      final int index = _topLevelIndexOf(section.blocks, _activeParagraph);
      if (index >= 0) {
        section.blocks.insert(index + 1, block);
        _word.relayout();
        if (block is WmlVisual) {
          _word.selectVisual(block);
        }
        if (block is WmlEquation) {
          _word.selectEquation(block);
        }
        _word.refresh();
        return;
      }
    }
    _word.document.sections.first.blocks.add(block);
    _word.relayout();
    if (block is WmlVisual) {
      _word.selectVisual(block);
    }
    if (block is WmlEquation) {
      _word.selectEquation(block);
    }
    _word.refresh();
  }

  int _topLevelIndexOf(List<WmlBlock> blocks, WmlParagraph para) {
    for (int i = 0; i < blocks.length; i++) {
      final WmlBlock current = blocks[i];
      if (identical(current, para)) {
        return i;
      }
      if (current is WmlToc && WordToc.ownsParagraph(current, para)) {
        return i;
      }
      if (current is WmlTable) {
        for (final WmlTableRow row in current.rows) {
          for (final WmlTableCell cell in row.cells) {
            if (_containsParagraph(cell.blocks, para)) {
              return i;
            }
          }
        }
      }
    }
    return -1;
  }

  bool _containsParagraph(List<WmlBlock> blocks, WmlParagraph para) {
    for (final WmlBlock block in blocks) {
      if (identical(block, para)) {
        return true;
      }
      if (block is WmlToc && WordToc.ownsParagraph(block, para)) {
        return true;
      }
      if (block is WmlTable) {
        for (final WmlTableRow row in block.rows) {
          for (final WmlTableCell cell in row.cells) {
            if (_containsParagraph(cell.blocks, para)) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  void _clearActiveCell() {
    _sheet.beginCellEdit(initial: '', replace: true);
    _sheet.commitCellEdit();
  }

  String _formulaArgs() {
    final SmlRange range = _sheet.selection.range;
    if (range.start.col != range.end.col || range.start.row != range.end.row) {
      return '${range.start.a1}:${range.end.a1}';
    }
    final SmlCellRef focus = _sheet.selection.focus;
    if (focus.col > 0) {
      return '${SmlCellRef(0, focus.row).a1}:${SmlCellRef(focus.col - 1, focus.row).a1}';
    }
    return '${SmlCellRef(1, focus.row).a1}:${SmlCellRef(4, focus.row).a1}';
  }

  void _insertFormula(String name) {
    final String formula = '=$name(${_formulaArgs()})';
    _sheet.beginCellEdit(initial: formula, replace: true);
    _sheet.commitCellEdit();
  }

  String _fnCategoryLabel(FormulaFnCategory category) {
    return switch (category) {
      FormulaFnCategory.math => _t('Math', StudioStrings.de('Math'), 'رياضية'),
      FormulaFnCategory.statistical => _t(
        'Statistical',
        StudioStrings.de('Statistical'),
        'إحصاء',
      ),
      FormulaFnCategory.logical => _t(
        'Logical',
        StudioStrings.de('Logical'),
        'منطقية',
      ),
      FormulaFnCategory.text => _t('Text', StudioStrings.de('Text'), 'نص'),
      FormulaFnCategory.lookup => _t(
        'Lookup',
        StudioStrings.de('Lookup'),
        'بحث',
      ),
      FormulaFnCategory.information => _t(
        'Information',
        StudioStrings.de('Information'),
        'معلومات',
      ),
      FormulaFnCategory.date => _t('Date', StudioStrings.de('Date'), 'تاريخ'),
      FormulaFnCategory.financial => _t(
        'Financial',
        StudioStrings.de('Financial'),
        'مالية',
      ),
    };
  }

  Future<void> _openFunctionGuide() async {
    FormulaFnCategory? filter;
    String query = '';
    FormulaFnDoc selected = FormulaFunctionGuide.all.first;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialog) {
            final List<FormulaFnDoc> rows = <FormulaFnDoc>[
              for (final FormulaFnDoc doc in FormulaFunctionGuide.all)
                if ((filter == null || doc.category == filter) &&
                    (query.isEmpty ||
                        doc.name.contains(query.toUpperCase()) ||
                        doc.aliases.any(
                          (String a) => a.contains(query.toUpperCase()),
                        ) ||
                        doc.summary(_arabic).contains(query)))
                  doc,
            ];
            if (rows.isNotEmpty && !rows.contains(selected)) {
              selected = rows.first;
            }
            return AlertDialog(
              title: Text(
                _t(
                  'Excel function guide',
                  StudioStrings.de('Excel function guide'),
                  'دليل دوال الإكسل',
                ),
              ),
              content: SizedBox(
                width: 720,
                height: 440,
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 280,
                      child: Column(
                        children: <Widget>[
                          TextField(
                            decoration: InputDecoration(
                              hintText: _t(
                                'Search',
                                StudioStrings.de('Search'),
                                'بحث',
                              ),
                              isDense: true,
                            ),
                            onChanged: (String value) {
                              setDialog(() => query = value);
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: <Widget>[
                              ChoiceChip(
                                label: Text(
                                  _t('All', StudioStrings.de('All'), 'الكل'),
                                ),
                                selected: filter == null,
                                onSelected: (_) =>
                                    setDialog(() => filter = null),
                              ),
                              for (final FormulaFnCategory category
                                  in FormulaFnCategory.values)
                                ChoiceChip(
                                  label: Text(_fnCategoryLabel(category)),
                                  selected: filter == category,
                                  onSelected: (_) =>
                                      setDialog(() => filter = category),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (BuildContext context, int i) {
                                final FormulaFnDoc doc = rows[i];
                                return ListTile(
                                  dense: true,
                                  selected: identical(doc, selected),
                                  title: Text(doc.name),
                                  subtitle: Text(
                                    _fnCategoryLabel(doc.category),
                                    maxLines: 1,
                                  ),
                                  onTap: () => setDialog(() => selected = doc),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 16),
                    Expanded(
                      child: ListView(
                        children: <Widget>[
                          Text(
                            selected.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            selected.syntax,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 12),
                          Text(selected.summary(_arabic)),
                          if (selected.example.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              _t(
                                'Example',
                                StudioStrings.de('Example'),
                                'مثال',
                              ),
                            ),
                            Text(selected.example),
                          ],
                          if (selected.aliases.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              '${_t('Aliases', StudioStrings.de('Aliases'), 'أسماء بديلة')}: '
                              '${selected.aliases.join(', ')}',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_t('Close', StudioStrings.de('Close'), 'إغلاق')),
                ),
                if (_canMutate)
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _sheet.beginCellEdit(
                        initial: '=${selected.name}(',
                        replace: true,
                      );
                    },
                    child: Text(
                      _t('Insert', StudioStrings.de('Insert'), 'إدراج'),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _insertIfFormula() {
    final SmlCellRef focus = _sheet.selection.focus;
    final String probe = focus.col > 0
        ? SmlCellRef(focus.col - 1, focus.row).a1
        : SmlCellRef(focus.col + 1, focus.row).a1;
    final String yes = _t('Yes', StudioStrings.de('Yes'), 'نعم');
    final String no = _t('No', StudioStrings.de('No'), 'لا');
    _sheet.beginCellEdit(initial: '=IF($probe>0,"$yes","$no")', replace: true);
    _sheet.commitCellEdit();
  }

  void _newWord() {
    _wordPath = null;
    _wordName = 'Document1.docx';
    _word.document = WmlDocument.empty(
      text: _t('New document', StudioStrings.de('New document'), 'مستند جديد'),
      rtl: _arabic,
    );
    _word.documentCaret.paragraphIndex = 0;
    _word.documentCaret.logicalIndex = 0;
    _word.documentCaret.collapseSelection();
    _word.relayout();
    _word.refresh();
  }

  void _newSheet() {
    _sheetPath = null;
    _sheetName = 'Book1.xlsx';
    _sheet.cancelCellEdit();
    _sheet.workbook = SmlWorkbook();
    _sheet.setActiveSheet(0);
    _resetSheetSelection();
  }

  void _newSlides() {
    _slidePath = null;
    _slideName = 'Presentation1.pptx';
    _slides.presentation = PmlPresentation();
    _slides.setActiveSlide(0);
  }

  void _resetWord() {
    _wordPath = null;
    _wordName = 'CrispOffice product brief.docx';
    _word.document = SampleLibrary.wordBriefing();
    _word.documentCaret.paragraphIndex = 0;
    _word.documentCaret.logicalIndex = 0;
    _word.documentCaret.collapseSelection();
    _word.relayout();
    _word.refresh();
  }

  void _resetSheet() {
    _sheetPath = null;
    _sheetName = 'Budget.xlsx';
    _sheet.cancelCellEdit();
    _sheet.workbook = SampleLibrary.excelBudget();
    _sheet.setActiveSheet(0);
    _resetSheetSelection();
  }

  void _resetSheetSelection() {
    // Replacing/deleting a worksheet requires an explicit reset even when its
    // numeric index is unchanged. Ordinary same-sheet navigation is a no-op.
    _sheet.selectedDrawingIndex = null;
    _sheet.selection.selectCell(const SmlCellRef(0, 0));
    _sheet.viewport.origin = Offset.zero;
    _sheet.refresh();
  }

  void _resetSlides() {
    _slidePath = null;
    _slideName = 'Studio deck.pptx';
    _slides.presentation = SampleLibrary.slideDeck();
    _slides.setActiveSlide(0);
  }

  int _nextSlideId() {
    var maxId = 255;
    for (final PmlSlide slide in _slides.presentation.slides) {
      if (slide.id > maxId) {
        maxId = slide.id;
      }
    }
    return maxId + 1;
  }

  int _nextShapeId(PmlSlide slide) {
    var maxId = 1;
    for (final PmlShape shape in slide.shapes) {
      if (shape.id > maxId) {
        maxId = shape.id;
      }
    }
    return maxId + 1;
  }

  void _addSlide() {
    _slides.presentation.slides.add(
      PmlSlide(
        id: _nextSlideId(),
        shapes: <PmlShape>[
          PmlShape(
            id: 2,
            name: 'Title',
            text: _t('New slide', StudioStrings.de('New slide'), 'شريحة جديدة'),
            fillColor: '2B579A',
            transform: const PmlTransform(
              x: 800000,
              y: 1800000,
              cx: 7500000,
              cy: 1200000,
            ),
          ),
        ],
      ),
    );
    _slides.setActiveSlide(_slides.presentation.slides.length - 1);
  }

  void _duplicateSlide() {
    final PmlSlide src = _slides.slide;
    _slides.presentation.slides.add(
      PmlSlide(
        id: _nextSlideId(),
        layoutName: src.layoutName,
        notes: src.notes,
        transition: src.transition,
        animations: <PmlShapeAnimation>[
          for (final PmlShapeAnimation anim in src.animations) anim.copyWith(),
        ],
        shapes: <PmlShape>[
          for (final PmlShape shape in src.shapes)
            PmlShape(
              id: shape.id,
              name: shape.name,
              text: shape.text,
              fillColor: shape.fillColor,
              textColor: shape.textColor,
              fontSizePt: shape.fontSizePt,
              preset: shape.preset,
              transform: shape.transform,
              visual: shape.visual?.copy(),
              table: shape.table?.copy(),
              rightToLeft: shape.rightToLeft,
              textAlign: shape.textAlign,
            ),
        ],
      ),
    );
    _slides.setActiveSlide(_slides.presentation.slides.length - 1);
  }

  void _deleteSlide() {
    if (_slides.presentation.slides.length <= 1) {
      return;
    }
    final int index = _slides.activeSlideIndex;
    _slides.presentation.slides.removeAt(index);
    _slides.setActiveSlide(index - 1);
  }

  void _addCardShape() {
    final PmlSlide slide = _slides.slide;
    final PmlShape shape = PmlShape(
      id: _nextShapeId(slide),
      name: 'Card',
      text: _t('New card', StudioStrings.de('New card'), 'بطاقة جديدة'),
      fillColor: '217346',
      transform: const PmlTransform(
        x: 1400000,
        y: 1600000,
        cx: 6200000,
        cy: 1600000,
      ),
    );
    slide.shapes.add(shape);
    _slides.selectShape(shape);
  }

  void _addTitleShape() {
    final PmlSlide slide = _slides.slide;
    final PmlShape shape = PmlShape(
      id: _nextShapeId(slide),
      name: 'Title',
      text: _t('Slide title', StudioStrings.de('Slide title'), 'عنوان الشريحة'),
      fillColor: 'B7472A',
      transform: const PmlTransform(
        x: 600000,
        y: 400000,
        cx: 8000000,
        cy: 900000,
      ),
    );
    slide.shapes.add(shape);
    _slides.selectShape(shape);
  }

  void _addAccentShape() {
    final PmlSlide slide = _slides.slide;
    final PmlShape shape = PmlShape(
      id: _nextShapeId(slide),
      name: 'Accent',
      text: _t('Accent shape', StudioStrings.de('Accent shape'), 'شكل تمييز'),
      fillColor: '7030A0',
      transform: const PmlTransform(
        x: 2800000,
        y: 2000000,
        cx: 3600000,
        cy: 1400000,
      ),
    );
    slide.shapes.add(shape);
    _slides.selectShape(shape);
  }

  static const List<String> _shapeFills = <String>[
    '2B579A',
    '217346',
    'B7472A',
    'ED7D31',
    '5B9BD5',
    '7030A0',
    'C45911',
    '548235',
  ];

  void _cycleShapeFill() {
    final PmlShape? shape = _slides.selected;
    if (shape == null) {
      return;
    }
    final int i = _shapeFills.indexOf(shape.fillColor.toUpperCase());
    final String next = _shapeFills[(i + 1) % _shapeFills.length];
    _slides.updateSelected(fillColor: next);
  }

  void _centerSelectedShape() {
    _alignSelectedShape(x: 0.5, y: 0.5);
  }

  void _alignSelectedShape({double? x, double? y}) {
    final PmlShape? shape = _slides.selected;
    if (shape == null) {
      return;
    }
    final PmlTransform t = shape.transform;
    final int nextX = x == null
        ? t.x
        : ((_slides.presentation.slideWidth - t.cx) * x).round();
    final int nextY = y == null
        ? t.y
        : ((_slides.presentation.slideHeight - t.cy) * y).round();
    _slides.applyTransform(
      shape,
      PmlTransform(x: nextX, y: nextY, cx: t.cx, cy: t.cy, rot: t.rot),
    );
    _slides.refresh();
  }

  void _jumpWordPage(int index) {
    final int last = _word.pageCount < 1 ? 0 : _word.pageCount - 1;
    final int page = index.clamp(0, last);
    final double scale = _word.viewport.scale * (96 / 72);
    _word.viewport.origin = Offset(
      _word.viewport.origin.dx,
      _word.documentLaidOut.pageStackTop(page, scale),
    );
    _word.refreshView();
  }

  Widget _body(bool dark) {
    return ColoredBox(
      color: dark ? const Color(0xFF121212) : const Color(0xFFD0D0D0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final commentsBelow =
              _app == SuiteApp.word &&
              _showComments &&
              constraints.maxWidth < 1040;
          final stage = Row(
            children: <Widget>[
              if (constraints.maxWidth >= 700 &&
                  !(_app == SuiteApp.powerpoint && _slides.isPresenting) &&
                  (_app != SuiteApp.word || _showOutline))
                _sidePane(dark),
              Expanded(child: _stage(dark)),
              if (_app == SuiteApp.word && _showComments && !commentsBelow)
                _wordCommentsPane(dark),
              if (_selectedOfficeVisual != null &&
                  !(_app == SuiteApp.powerpoint && _slides.isPresenting))
                _visualPane(dark),
              if (_app == SuiteApp.powerpoint &&
                  _showAnimPane &&
                  !_slides.isPresenting)
                _animationPane(dark),
            ],
          );
          if (!commentsBelow) return stage;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: stage),
              SizedBox(
                height: math.min(340, constraints.maxHeight * 0.45),
                child: _wordCommentsPane(dark, expanded: true),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stage(bool dark) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1E1E1E) : Colors.white,
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x33000000), blurRadius: 8),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            switch (_app) {
              SuiteApp.word => Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  QudsWordEditor(
                    controller: _word,
                    focusNode: _wordFocus,
                    onCommentContextMenuRequested: _showCommentCaretContext,
                    config: _printPreview
                        ? _config.copyWith(mode: OfficeInteractionMode.viewing)
                        : _config,
                  ),
                  if (_printPreview) _wordPrintPreviewBanner(),
                ],
              ),
              SuiteApp.excel => Column(
                children: <Widget>[
                  _excelFormulaBar(dark),
                  Expanded(
                    child: QudsSheetEditor(
                      controller: _sheet,
                      focusNode: _sheetFocus,
                      config: _config,
                    ),
                  ),
                  _excelSheetTabs(dark),
                ],
              ),
              SuiteApp.powerpoint => Column(
                children: <Widget>[
                  Expanded(
                    child: QudsSlideEditor(
                      controller: _slides,
                      focusNode: _slideFocus,
                      config: _config,
                    ),
                  ),
                  if (_showNotes && !_slides.isPresenting) _slideNotes(dark),
                ],
              ),
              SuiteApp.pdf => StudioPdfSurface(
                controller: _pdf,
                config: _config,
                options: _pdfViewerOptions,
                events: _pdfEvents,
                onFollowLink: (PdfLinkAction action) {
                  final String target =
                      action.uri ??
                      (action.pageIndex != null
                          ? '${_t('page', StudioStrings.de('page'), 'صفحة')} ${action.pageIndex! + 1}'
                          : '?');
                  if (_pdfPreventLinks && action.uri != null) {
                    _toast(
                      _arabic
                          ? 'رابط بدون فتح: $target'
                          : 'Link blocked: $target',
                    );
                  }
                },
              ),
            },
            if (_findOpen && _app == SuiteApp.pdf)
              Positioned(top: 8, left: 8, right: 8, child: _pdfFindBar(dark)),
            if (_findOpen && _app != SuiteApp.pdf)
              Positioned(
                top: 0,
                bottom: 0,
                left: _arabic ? 0 : null,
                right: _arabic ? null : 0,
                child: StudioFindPane(
                  controller: _active,
                  arabic: _arabic,
                  accent: _accent,
                  replaceMode: _findReplace,
                  onReplaceMode: (bool value) {
                    setState(() => _findReplace = value);
                  },
                  onClose: _closeFind,
                ),
              ),
            if (_opening) _openProgressOverlay(dark),
          ],
        ),
      ),
    );
  }

  Widget _wordPrintPreviewBanner() {
    final List<LaidOutPage> pages = _word.printPreviewPages();
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: const Color(0xEE2B579A),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _arabic
                    ? 'معاينة طباعة · ${pages.length} صفحة'
                    : 'Print preview · ${pages.length} pages',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              IconButton(
                onPressed: () => _jumpWordPage(_word.visiblePageIndex - 1),
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              IconButton(
                onPressed: () => _jumpWordPage(_word.visiblePageIndex + 1),
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
              IconButton(
                onPressed: () => setState(() => _printPreview = false),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _openProgressOverlay(bool dark) {
    final int percent = (_openProgress * 100).round().clamp(0, 100);
    final Color card = dark ? const Color(0xFF1E1E22) : Colors.white;
    final Color track = dark
        ? const Color(0xFF3A3A42)
        : const Color(0xFFE8E8EE);
    return ColoredBox(
      color: const Color(0xB3000000),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Material(
            color: card,
            elevation: 16,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[_accent, _accent.withValues(alpha: 0.55)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          color: _accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _t(
                          'Preparing document',
                          StudioStrings.de('Preparing document'),
                          'جاري تجهيز المستند',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: _officeTheme.chromeText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _openStatusLabel,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: _officeTheme.chromeText.withValues(
                            alpha: 0.65,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: _openProgress.clamp(0.04, 1),
                          minHeight: 8,
                          backgroundColor: track,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _excelFormulaBar(bool dark) {
    return Material(
      color: dark ? const Color(0xFF2A2A2A) : const Color(0xFFF7F7F7),
      child: SizedBox(
        height: 32,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 72,
              child: Center(
                child: Text(
                  _sheet.selectionAddress,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _officeTheme.chromeText,
                  ),
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              color: dark ? const Color(0xFF444444) : const Color(0xFFD0D0D0),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'fx',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: _accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: _canMutate ? _sheet.beginCellEdit : null,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text.rich(
                    _sheet.cellEditor.editing
                        ? FormulaRefStyle.textSpan(
                            _sheet.formulaBarText,
                            baseColor: _officeTheme.chromeText,
                            fontSize: 14,
                          )
                        : TextSpan(
                            text: _sheet.formulaBarText,
                            style: TextStyle(color: _officeTheme.chromeText),
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            if (_sheet.cellEditor.editing)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _sheet.commitCellEdit,
                icon: Icon(Icons.check, size: 16, color: _accent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _excelSheetTabs(bool dark) {
    return Material(
      color: dark ? const Color(0xFF252525) : const Color(0xFFEEEEEE),
      child: SizedBox(
        height: 28,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: <Widget>[
            for (int i = 0; i < _sheet.workbook.sheets.length; i++)
              InkWell(
                onTap: () =>
                    _navigateOffice(_sheet, () => _sheet.setActiveSheet(i)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == _sheet.activeSheetIndex
                        ? (dark ? const Color(0xFF1E1E1E) : Colors.white)
                        : Colors.transparent,
                    border: Border(
                      top: BorderSide(
                        color: i == _sheet.activeSheetIndex
                            ? _accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    _sheet.workbook.sheets[i].name,
                    style: TextStyle(
                      fontSize: 12,
                      color: i == _sheet.activeSheetIndex
                          ? _accent
                          : _officeTheme.chromeText,
                      fontWeight: i == _sheet.activeSheetIndex
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            InkWell(
              onTap: _canMutate ? _addSheet : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.add, size: 16, color: _accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addSheet() {
    _navigateOffice(_sheet, () {
      _sheet.commitPendingEdits();
      _sheet.workbook.sheets.add(
        SmlWorksheet(
          name: 'Sheet${_sheet.workbook.sheets.length + 1}',
          sheetId: _sheet.workbook.sheets.length + 1,
        ),
      );
      _sheet.setActiveSheet(_sheet.workbook.sheets.length - 1);
    });
  }

  void _deleteSheet() {
    if (_sheet.workbook.sheets.length <= 1) {
      return;
    }
    _navigateOffice(_sheet, () {
      _sheet.commitPendingEdits();
      final int index = _sheet.activeSheetIndex;
      _sheet.workbook.sheets.removeAt(index);
      _sheet.setActiveSheet(index - 1);
      _resetSheetSelection();
    });
  }

  OfficeVisual? get _selectedOfficeVisual {
    return switch (_app) {
      SuiteApp.word => _word.selectedVisual?.visual,
      SuiteApp.excel => _sheet.selectedDrawing?.visual,
      SuiteApp.powerpoint => _slides.selected?.visual,
      SuiteApp.pdf => null,
    };
  }

  void _mutateVisual(void Function(OfficeVisual visual) edit) {
    switch (_app) {
      case SuiteApp.word:
        _word.mutateSelectedVisual(edit);
      case SuiteApp.excel:
        _sheet.mutateSelectedDrawing(edit);
      case SuiteApp.powerpoint:
        _slides.mutateSelectedShapeVisual(edit);
      case SuiteApp.pdf:
        break;
    }
  }

  void _deleteSelectedVisual() {
    switch (_app) {
      case SuiteApp.word:
        _word.deleteSelectedVisual();
      case SuiteApp.excel:
        _sheet.deleteSelectedDrawing();
      case SuiteApp.powerpoint:
        _slides.deleteSelectedShape();
      case SuiteApp.pdf:
        break;
    }
  }

  List<StudioRibbonGroup> _visualRibbon() {
    final OfficeVisual? visual = _selectedOfficeVisual;
    if (visual == null) {
      return const <StudioRibbonGroup>[];
    }
    if (visual.isPicture) {
      return <StudioRibbonGroup>[
        StudioRibbonGroup(
          title: _t(
            'Picture format',
            StudioStrings.de('Picture format'),
            'تنسيق الصورة',
          ),
          children: <Widget>[
            _cmd(
              Icons.photo_library_outlined,
              _t('Replace', StudioStrings.de('Replace'), 'استبدال'),
              _canMutate ? _replaceSelectedPicture : null,
            ),
            _cmd(
              Icons.crop,
              _t('Crop', StudioStrings.de('Crop'), 'قص'),
              _canMutate ? _toggleWordPictureCrop : null,
              selected: _app == SuiteApp.word && _word.pictureCropMode,
            ),
            _cmd(
              Icons.crop_free,
              _t('Clear crop', StudioStrings.de('Clear crop'), 'إلغاء القص'),
              _canMutate
                  ? () => _mutateVisual((OfficeVisual v) {
                      v.picture
                        ..cropLeft = 0
                        ..cropTop = 0
                        ..cropRight = 0
                        ..cropBottom = 0;
                    })
                  : null,
            ),
            _cmd(
              Icons.rotate_right,
              _t('Rotate', StudioStrings.de('Rotate'), 'دوران'),
              _canMutate
                  ? () => _mutateVisual((OfficeVisual v) => v.rotateBy(90))
                  : null,
            ),
            _cmd(
              Icons.wb_sunny_outlined,
              _t('Bright', StudioStrings.de('Bright'), 'إضاءة'),
              _canMutate
                  ? () =>
                        _mutateVisual((OfficeVisual v) => v.bumpBrightness(0.1))
                  : null,
            ),
            _cmd(
              Icons.contrast,
              _t('Contrast', StudioStrings.de('Contrast'), 'تباين'),
              _canMutate
                  ? () =>
                        _mutateVisual((OfficeVisual v) => v.bumpContrast(0.15))
                  : null,
            ),
            _cmd(
              Icons.border_style,
              _t('Border', StudioStrings.de('Border'), 'إطار'),
              _canMutate
                  ? () => _mutateVisual((OfficeVisual v) => v.cycleBorder())
                  : null,
            ),
            _cmd(
              Icons.opacity,
              _t('Opacity', StudioStrings.de('Opacity'), 'شفافية'),
              _canMutate
                  ? () => _mutateVisual(
                      (OfficeVisual v) => v.bumpTransparency(0.1),
                    )
                  : null,
            ),
            _cmd(
              Icons.flip,
              _t('Flip H', StudioStrings.de('Flip H'), 'قلب أفقي'),
              _canMutate
                  ? () => _mutateVisual((OfficeVisual v) => v.toggleFlipH())
                  : null,
              selected: visual.picture.flipH,
            ),
            _cmd(
              Icons.flip_camera_android,
              _t('Flip V', StudioStrings.de('Flip V'), 'قلب عمودي'),
              _canMutate
                  ? () => _mutateVisual((OfficeVisual v) => v.toggleFlipV())
                  : null,
              selected: visual.picture.flipV,
            ),
            _cmd(
              Icons.wrap_text,
              _t('Wrap', StudioStrings.de('Wrap'), 'التفاف'),
              _canMutate
                  ? () => _mutateVisual((OfficeVisual v) => v.cycleWrap())
                  : null,
            ),
            _cmd(
              Icons.aspect_ratio,
              _t('Lock', StudioStrings.de('Lock'), 'نسبة'),
              _canMutate
                  ? () => _mutateVisual(
                      (OfficeVisual v) =>
                          v.picture.lockAspect = !v.picture.lockAspect,
                    )
                  : null,
              selected: visual.picture.lockAspect,
            ),
            _cmd(
              Icons.blur_on,
              _t('Shadow', StudioStrings.de('Shadow'), 'ظل'),
              _canMutate
                  ? () => _mutateVisual(
                      (OfficeVisual v) => v.picture.shadow = !v.picture.shadow,
                    )
                  : null,
              selected: visual.picture.shadow,
            ),
            _cmd(
              Icons.restart_alt,
              _t('Reset', StudioStrings.de('Reset'), 'إعادة'),
              _canMutate
                  ? () => _mutateVisual((OfficeVisual v) => v.resetPicture())
                  : null,
            ),
            _cmd(
              Icons.delete_outline,
              _t('Delete', StudioStrings.de('Delete'), 'حذف'),
              _canMutate ? _deleteSelectedVisual : null,
            ),
          ],
        ),
      ];
    }
    return <StudioRibbonGroup>[
      StudioRibbonGroup(
        title: _t(
          'Chart design',
          StudioStrings.de('Chart design'),
          'تصميم المخطط',
        ),
        children: <Widget>[
          _cmd(
            Icons.bar_chart,
            _t('Column', StudioStrings.de('Column'), 'أعمدة'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) => v.kind = OfficeVisualKind.chartColumn,
                  )
                : null,
            selected: visual.kind == OfficeVisualKind.chartColumn,
          ),
          _cmd(
            Icons.stacked_bar_chart,
            _t('Bar', StudioStrings.de('Bar'), 'شريطي'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) => v.kind = OfficeVisualKind.chartBar,
                  )
                : null,
            selected: visual.kind == OfficeVisualKind.chartBar,
          ),
          _cmd(
            Icons.pie_chart,
            _t('Pie', StudioStrings.de('Pie'), 'دائري'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) => v.kind = OfficeVisualKind.chartPie,
                  )
                : null,
            selected: visual.kind == OfficeVisualKind.chartPie,
          ),
          _cmd(
            Icons.show_chart,
            _t('Line', StudioStrings.de('Line'), 'خطي'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) => v.kind = OfficeVisualKind.chartLine,
                  )
                : null,
            selected: visual.kind == OfficeVisualKind.chartLine,
          ),
          _cmd(
            Icons.title,
            _t('Title', StudioStrings.de('Title'), 'عنوان'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) => v.cycleTitle(arabic: _arabic),
                  )
                : null,
          ),
          _cmd(
            Icons.add,
            _t('Point', StudioStrings.de('Point'), 'نقطة'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) => v.addSamplePoint(arabic: _arabic),
                  )
                : null,
          ),
          _cmd(
            Icons.remove,
            _t('Remove', StudioStrings.de('Remove'), 'حذف نقطة'),
            _canMutate && visual.points.length > 1
                ? () => _mutateVisual((OfficeVisual v) => v.removeLastPoint())
                : null,
          ),
          _cmd(
            Icons.legend_toggle,
            _t('Legend', StudioStrings.de('Legend'), 'وسيلة إيضاح'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) =>
                        v.chart.showLegend = !v.chart.showLegend,
                  )
                : null,
            selected: visual.chart.showLegend,
          ),
          _cmd(
            Icons.label_outline,
            _t('Labels', StudioStrings.de('Labels'), 'تسميات'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) =>
                        v.chart.showDataLabels = !v.chart.showDataLabels,
                  )
                : null,
            selected: visual.chart.showDataLabels,
          ),
          _cmd(
            Icons.grid_4x4,
            _t('Axes', StudioStrings.de('Axes'), 'محاور'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) => v.chart.showAxes = !v.chart.showAxes,
                  )
                : null,
            selected: visual.chart.showAxes,
          ),
          _cmd(
            Icons.grid_on,
            _t('Grid', StudioStrings.de('Grid'), 'خطوط شبكة'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) =>
                        v.chart.showGridlines = !v.chart.showGridlines,
                  )
                : null,
            selected: visual.chart.showGridlines,
          ),
          _cmd(
            Icons.place,
            _t('Legend pos', StudioStrings.de('Legend pos'), 'موضع الإيضاح'),
            _canMutate
                ? () => _mutateVisual((OfficeVisual v) => v.cycleLegendPos())
                : null,
          ),
          _cmd(
            Icons.title,
            _t('Show title', StudioStrings.de('Show title'), 'إظهار العنوان'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) => v.chart.showTitle = !v.chart.showTitle,
                  )
                : null,
            selected: visual.chart.showTitle,
          ),
          _cmd(
            Icons.percent,
            _t('Percent', StudioStrings.de('Percent'), 'نسب'),
            _canMutate
                ? () => _mutateVisual(
                    (OfficeVisual v) =>
                        v.chart.showPercent = !v.chart.showPercent,
                  )
                : null,
            selected: visual.chart.showPercent,
          ),
          _cmd(
            Icons.delete_outline,
            _t('Delete', StudioStrings.de('Delete'), 'حذف'),
            _canMutate ? _deleteSelectedVisual : null,
          ),
        ],
      ),
    ];
  }

  void _toggleWordPictureCrop() {
    if (_app == SuiteApp.word) {
      _word.togglePictureCropMode();
      return;
    }
    _mutateVisual((OfficeVisual v) => v.cropBy(0.06));
  }

  Future<void> _replaceSelectedPicture() async {
    final Uint8List? bytes = await StudioFiles.pickImage();
    if (bytes == null) {
      return;
    }
    _mutateVisual((OfficeVisual v) {
      v
        ..kind = OfficeVisualKind.picture
        ..imageBytes = bytes
        ..resetPicture();
    });
  }

  Widget _visualPane(bool dark) {
    final OfficeVisual? visual = _selectedOfficeVisual;
    if (visual == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: dark ? const Color(0xFF242424) : const Color(0xFFF3F3F3),
      child: SizedBox(
        width: 260,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            StudioPaneTitle(
              text: visual.isPicture
                  ? (_t(
                      'Picture format',
                      StudioStrings.de('Picture format'),
                      'تنسيق الصورة',
                    ))
                  : (_t(
                      'Chart editor',
                      StudioStrings.de('Chart editor'),
                      'تحرير المخطط',
                    )),
              accent: _accent,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                visual.title.isEmpty ? _visualTitle(visual.kind) : visual.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _officeTheme.chromeText,
                ),
              ),
            ),
            if (visual.isPicture) ...<Widget>[
              _visualSlider(
                _t('Rotation', StudioStrings.de('Rotation'), 'دوران'),
                visual.picture.rotationDeg,
                0,
                359,
                '${visual.picture.rotationDeg.round()}°',
                (double v) => _mutateVisual(
                  (OfficeVisual vis) => vis.picture.rotationDeg = v,
                ),
              ),
              _visualSlider(
                _t('Brightness', StudioStrings.de('Brightness'), 'إضاءة'),
                visual.picture.brightness,
                -0.5,
                0.5,
                visual.picture.brightness.toStringAsFixed(2),
                (double v) => _mutateVisual(
                  (OfficeVisual vis) => vis.picture.brightness = v,
                ),
              ),
              _visualSlider(
                _t('Contrast', StudioStrings.de('Contrast'), 'تباين'),
                visual.picture.contrast,
                0.5,
                1.8,
                visual.picture.contrast.toStringAsFixed(2),
                (double v) => _mutateVisual(
                  (OfficeVisual vis) => vis.picture.contrast = v,
                ),
              ),
              _visualSlider(
                _t('Transparency', StudioStrings.de('Transparency'), 'شفافية'),
                visual.picture.transparency,
                0,
                0.85,
                '${(visual.picture.transparency * 100).round()}%',
                (double v) => _mutateVisual(
                  (OfficeVisual vis) => vis.picture.transparency = v,
                ),
              ),
              _visualSlider(
                _t('Crop', StudioStrings.de('Crop'), 'قص'),
                visual.picture.cropLeft,
                0,
                0.4,
                '${(visual.picture.cropLeft * 100).round()}%',
                (double v) => _mutateVisual((OfficeVisual vis) {
                  vis.picture
                    ..cropLeft = v
                    ..cropTop = v
                    ..cropRight = v
                    ..cropBottom = v;
                }),
              ),
              _visualSlider(
                _t(
                  'Border width',
                  StudioStrings.de('Border width'),
                  'عرض الإطار',
                ),
                visual.picture.borderWidth,
                0,
                12,
                visual.picture.borderWidth.toStringAsFixed(1),
                (double v) => _mutateVisual((OfficeVisual vis) {
                  vis.picture.borderWidth = v;
                  if (v > 0 && vis.picture.borderColor.isEmpty) {
                    vis.picture.borderColor = '2B579A';
                  }
                }),
              ),
              _visualFact(
                _t('Text wrap', StudioStrings.de('Text wrap'), 'التفاف النص'),
                _wrapLabel(visual.picture.wrap),
              ),
              _visualFact(
                _t('Alt text', StudioStrings.de('Alt text'), 'نص بديل'),
                visual.picture.altDescription.isEmpty
                    ? visual.title
                    : visual.picture.altDescription,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  spacing: 4,
                  children: <Widget>[
                    for (final PictureWrap wrap in PictureWrap.values)
                      ChoiceChip(
                        label: Text(
                          _wrapLabel(wrap),
                          style: const TextStyle(fontSize: 10),
                        ),
                        selected: visual.picture.wrap == wrap,
                        onSelected: _canMutate
                            ? (_) => _mutateVisual(
                                (OfficeVisual v) => v.picture.wrap = wrap,
                              )
                            : null,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ] else ...<Widget>[
              SwitchListTile(
                dense: true,
                title: Text(
                  _t('Legend', StudioStrings.de('Legend'), 'وسيلة إيضاح'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _officeTheme.chromeText,
                  ),
                ),
                value: visual.chart.showLegend,
                onChanged: _canMutate
                    ? (bool v) => _mutateVisual(
                        (OfficeVisual vis) => vis.chart.showLegend = v,
                      )
                    : null,
              ),
              SwitchListTile(
                dense: true,
                title: Text(
                  _t(
                    'Data labels',
                    StudioStrings.de('Data labels'),
                    'تسميات البيانات',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: _officeTheme.chromeText,
                  ),
                ),
                value: visual.chart.showDataLabels,
                onChanged: _canMutate
                    ? (bool v) => _mutateVisual(
                        (OfficeVisual vis) => vis.chart.showDataLabels = v,
                      )
                    : null,
              ),
              SwitchListTile(
                dense: true,
                title: Text(
                  _t('Axes', StudioStrings.de('Axes'), 'محاور'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _officeTheme.chromeText,
                  ),
                ),
                value: visual.chart.showAxes,
                onChanged: _canMutate
                    ? (bool v) => _mutateVisual(
                        (OfficeVisual vis) => vis.chart.showAxes = v,
                      )
                    : null,
              ),
              SwitchListTile(
                dense: true,
                title: Text(
                  _t('Gridlines', StudioStrings.de('Gridlines'), 'خطوط الشبكة'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _officeTheme.chromeText,
                  ),
                ),
                value: visual.chart.showGridlines,
                onChanged: _canMutate
                    ? (bool v) => _mutateVisual(
                        (OfficeVisual vis) => vis.chart.showGridlines = v,
                      )
                    : null,
              ),
              _visualFact(
                _t(
                  'Legend position',
                  StudioStrings.de('Legend position'),
                  'موضع الإيضاح',
                ),
                visual.chart.legendPos.name,
              ),
              _visualSlider(
                _t('Gap width', StudioStrings.de('Gap width'), 'فجوة الأعمدة'),
                visual.chart.gapWidth.toDouble(),
                0,
                400,
                '${visual.chart.gapWidth}',
                (double v) => _mutateVisual(
                  (OfficeVisual vis) => vis.chart.gapWidth = v.round(),
                ),
              ),
              for (int i = 0; i < visual.points.length; i++)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 8,
                    backgroundColor: Color(
                      0xFF000000 |
                          (int.tryParse(visual.points[i].color, radix: 16) ??
                              0x4472C4),
                    ),
                  ),
                  title: Text(
                    '${visual.points[i].label}  ${visual.points[i].value.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _officeTheme.chromeText,
                    ),
                  ),
                  onTap: _canMutate
                      ? () => _mutateVisual(
                          (OfficeVisual v) => v.cyclePointColor(i),
                        )
                      : null,
                  trailing: SizedBox(
                    width: 72,
                    child: Row(
                      children: <Widget>[
                        InkWell(
                          onTap: _canMutate
                              ? () => _mutateVisual(
                                  (OfficeVisual v) => v.bumpPointValue(i, -5),
                                )
                              : null,
                          child: const Icon(Icons.remove, size: 16),
                        ),
                        InkWell(
                          onTap: _canMutate
                              ? () => _mutateVisual(
                                  (OfficeVisual v) => v.bumpPointValue(i, 5),
                                )
                              : null,
                          child: const Icon(Icons.add, size: 16),
                        ),
                        InkWell(
                          onTap: _canMutate
                              ? () => _mutateVisual(
                                  (OfficeVisual v) =>
                                      v.cyclePointLabel(i, arabic: _arabic),
                                )
                              : null,
                          child: const Icon(Icons.text_fields, size: 16),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _visualFact(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: TextStyle(fontSize: 11, color: _officeTheme.chromeText),
      ),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _accent,
        ),
      ),
    );
  }

  Widget _visualSlider(
    String label,
    double value,
    double min,
    double max,
    String display,
    void Function(double value) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: _officeTheme.chromeText,
                  ),
                ),
              ),
              Text(
                display,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: _accent,
              thumbColor: _accent,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: _canMutate ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  String _wrapLabel(PictureWrap wrap) {
    if (_arabic) {
      return switch (wrap) {
        PictureWrap.inline => 'ضمن السطر',
        PictureWrap.square => 'مربع',
        PictureWrap.tight => 'ضيق',
        PictureWrap.through => 'خلال',
        PictureWrap.topAndBottom => 'أعلى وأسفل',
        PictureWrap.behind => 'خلف النص',
        PictureWrap.inFront => 'أمام النص',
      };
    }
    return switch (wrap) {
      PictureWrap.inline => 'In line',
      PictureWrap.square => 'Square',
      PictureWrap.tight => 'Tight',
      PictureWrap.through => 'Through',
      PictureWrap.topAndBottom => 'Top and bottom',
      PictureWrap.behind => 'Behind',
      PictureWrap.inFront => 'In front',
    };
  }

  Widget _animationPane(bool dark) {
    final List<PmlShapeAnimation> anims = _slides.slide.animations;
    var clickNo = 0;
    return Material(
      color: dark ? const Color(0xFF242424) : const Color(0xFFF3F3F3),
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            StudioPaneTitle(
              text: _t(
                'Animation pane',
                StudioStrings.de('Animation pane'),
                'جزء الحركة',
              ),
              accent: _accent,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                anims.isEmpty
                    ? (_arabic
                          ? 'حدد شكلاً ثم اختر حركة من الشريط.'
                          : 'Select a shape, then add an effect.')
                    : '${anims.length} ${_t('effects', StudioStrings.de('effects'), 'حركة')}',
                style: TextStyle(
                  fontSize: 11,
                  color: _officeTheme.chromeText.withValues(alpha: 0.7),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: anims.length,
                itemBuilder: (BuildContext context, int i) {
                  final PmlShapeAnimation anim = anims[i];
                  if (i == 0 || anim.trigger == PmlAnimTrigger.onClick) {
                    clickNo++;
                  }
                  final bool on = _slides.selectedAnimationIndex == i;
                  final String shapeName = _slides.slide.shapes
                      .firstWhere(
                        (PmlShape s) => s.id == anim.shapeId,
                        orElse: () => PmlShape(
                          id: anim.shapeId,
                          name: '#${anim.shapeId}',
                        ),
                      )
                      .name;
                  final Color tone = switch (anim.category) {
                    PmlAnimClass.entrance => const Color(0xFF217346),
                    PmlAnimClass.emphasis => const Color(0xFFC9A227),
                    PmlAnimClass.exit => const Color(0xFFB7472A),
                    PmlAnimClass.motion => const Color(0xFF2B579A),
                  };
                  return ListTile(
                    dense: true,
                    selected: on,
                    selectedTileColor: _accent.withValues(alpha: 0.12),
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: tone,
                      child: Text(
                        '$clickNo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    title: Text(
                      PmlMotionCatalog.animLabel(anim.preset, arabic: _arabic),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _officeTheme.chromeText,
                      ),
                    ),
                    subtitle: Text(
                      '$shapeName · ${_triggerLabel(anim.trigger)}'
                      '${anim.delayMs > 0 ? ' · ${anim.delayMs}ms' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: _officeTheme.chromeText.withValues(alpha: 0.7),
                      ),
                    ),
                    onTap: () => _slides.selectAnimation(i),
                  );
                },
              ),
            ),
            if (anims.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Wrap(
                  spacing: 4,
                  children: <Widget>[
                    _icon(
                      Icons.keyboard_arrow_up,
                      _t('Up', StudioStrings.de('Up'), 'أعلى'),
                      _slides.selectedAnimationIndex == null
                          ? null
                          : () => _slides.moveShapeAnimation(
                              _slides.selectedAnimationIndex!,
                              -1,
                            ),
                    ),
                    _icon(
                      Icons.keyboard_arrow_down,
                      _t('Down', StudioStrings.de('Down'), 'أسفل'),
                      _slides.selectedAnimationIndex == null
                          ? null
                          : () => _slides.moveShapeAnimation(
                              _slides.selectedAnimationIndex!,
                              1,
                            ),
                    ),
                    _icon(
                      Icons.delete_outline,
                      _t('Remove', StudioStrings.de('Remove'), 'حذف'),
                      _slides.selectedAnimationIndex == null
                          ? null
                          : () => _slides.removeShapeAnimation(
                              _slides.selectedAnimationIndex!,
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _presenterPane() {
    final Duration elapsed = _slides.presenterElapsed;
    final String clock =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final int? next = _slides.nextVisibleSlide;
    final String nextText = next == null
        ? (_t('End', StudioStrings.de('End'), 'النهاية'))
        : _slides.presentation.slides[next].notes.isEmpty
        ? '${_t('Slide', StudioStrings.de('Slide'), 'الشريحة')} ${next + 1}'
        : _slides.presentation.slides[next].notes;
    return ColoredBox(
      color: const Color(0xFF1A1A1A),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _t(
                      'Presenter',
                      StudioStrings.de('Presenter'),
                      'عرض المقدّم',
                    ),
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _slides.pausePresenter,
                  icon: Icon(
                    _slides.presenterPaused ? Icons.play_arrow : Icons.pause,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
            Text(
              clock,
              style: const TextStyle(color: Color(0xFF8CD3FF), fontSize: 28),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: IgnorePointer(
                child: SlideStage(
                  slide: _slides.slide,
                  preview: true,
                  config: _config.copyWith(
                    mode: OfficeInteractionMode.viewing,
                    showSlideHandles: false,
                    showRulers: false,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _slides.presentation.slides.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: 6),
                itemBuilder: (BuildContext context, int i) {
                  final bool on = i == _slides.activeSlideIndex;
                  return GestureDetector(
                    onTap: () => _slides.setActiveSlide(i),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: on ? _accent : const Color(0xFF555555),
                          width: on ? 2 : 1,
                        ),
                      ),
                      child: SizedBox(
                        width: 72,
                        child: IgnorePointer(
                          child: SlideStage(
                            slide: _slides.presentation.slides[i],
                            preview: true,
                            config: _config.copyWith(
                              mode: OfficeInteractionMode.viewing,
                              showSlideHandles: false,
                              showRulers: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _t(
                'This slide',
                StudioStrings.de('This slide'),
                'ملاحظات هذه الشريحة',
              ),
              style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 11),
            ),
            Text(
              _slides.slide.notes.isEmpty
                  ? (_t('No notes', StudioStrings.de('No notes'), 'لا ملاحظات'))
                  : _slides.slide.notes,
              style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              _t('Next', StudioStrings.de('Next'), 'التالي'),
              style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 11),
            ),
            Text(
              nextText,
              style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _syncSlideNotesField() {
    if (_notesSlideIndex == _slides.activeSlideIndex &&
        _slideNotesEdit.text == _slides.slide.notes) {
      return;
    }
    _notesSlideIndex = _slides.activeSlideIndex;
    if (_slideNotesEdit.text != _slides.slide.notes) {
      _slideNotesEdit.value = TextEditingValue(
        text: _slides.slide.notes,
        selection: TextSelection.collapsed(offset: _slides.slide.notes.length),
      );
    }
  }

  Widget _slideNotes(bool dark) {
    _syncSlideNotesField();
    return Material(
      color: dark ? const Color(0xFF242424) : const Color(0xFFF7F7F7),
      child: SizedBox(
        height: 88,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _t(
                  'Presenter notes',
                  StudioStrings.de('Presenter notes'),
                  'ملاحظات المحاضر',
                ),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TextField(
                  controller: _slideNotesEdit,
                  enabled: _canMutate,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12,
                    color: _officeTheme.chromeText,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: _arabic
                        ? 'اكتب ملاحظات المتحدث…'
                        : 'Type speaker notes…',
                  ),
                  onChanged: _slides.setSpeakerNotes,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidePane(bool dark, {bool compact = false}) {
    final Color bg = dark ? const Color(0xFF242424) : const Color(0xFFF3F3F3);
    return Material(
      color: bg,
      child: SizedBox(
        width: 268,
        child: switch (_app) {
          SuiteApp.word => _wordNav(),
          SuiteApp.excel => _sheetNav(),
          SuiteApp.powerpoint => _slideNav(),
          SuiteApp.pdf => _pdfNav(compact: compact),
        },
      ),
    );
  }

  String _headingStyleLabel(int level) {
    if (level <= 0) {
      return _t('Normal', StudioStrings.de('Normal'), 'عادي');
    }
    return _arabic ? 'عنوان $level' : 'Heading $level';
  }

  Widget _wordNav() {
    final List<WmlHeadingRef> headings = WordToc.headings(_word.document);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StudioPaneTitle(
          text: _t('Outline', StudioStrings.de('Outline'), 'المخطط'),
          accent: _accent,
        ),
        Expanded(
          child: ListView(
            children: <Widget>[
              for (final WmlHeadingRef heading in headings)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsetsDirectional.only(
                    start: 12 + (heading.level - 1) * 12,
                    end: 8,
                  ),
                  selected: _word.documentCaret.paragraphIndex == heading.index,
                  selectedTileColor: _accent.withValues(alpha: 0.12),
                  title: Text(
                    heading.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: heading.level == 1 ? 13 : 12,
                      fontWeight: heading.level == 1
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: _officeTheme.chromeText,
                    ),
                  ),
                  onTap: () => _word.jumpToParagraph(heading.index),
                ),
              const Divider(height: 1),
              StudioPaneTitle(
                text: _t(
                  'Properties',
                  StudioStrings.de('Properties'),
                  'الخصائص',
                ),
                accent: _accent,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Text(
                  _t(
                    'Try from the ribbon',
                    StudioStrings.de('Try from the ribbon'),
                    'جرّب من الشريط',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: _officeTheme.chromeText.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  children: <Widget>[
                    StudioMetaChip(
                      label: _t(
                        'Bold / Italic',
                        StudioStrings.de('Bold / Italic'),
                        'عريض / مائل',
                      ),
                      accent: _accent,
                    ),
                    StudioMetaChip(
                      label: _t(
                        '3×3 table',
                        StudioStrings.de('3×3 table'),
                        'جدول ٣×٣',
                      ),
                      accent: _accent,
                    ),
                    StudioMetaChip(
                      label: _t(
                        'Page break',
                        StudioStrings.de('Page break'),
                        'فاصل صفحة',
                      ),
                      accent: _accent,
                    ),
                    StudioMetaChip(
                      label: 'RTL / LTR',
                      accent: const Color(0xFF217346),
                    ),
                    StudioMetaChip(
                      label: 'Ctrl+Z',
                      accent: const Color(0xFFB7472A),
                      tone: const Color(0xFFB7472A),
                    ),
                    StudioMetaChip(
                      label: _t(
                        'Select word',
                        StudioStrings.de('Select word'),
                        'تحديد كلمة',
                      ),
                      accent: const Color(0xFFC9A227),
                      tone: const Color(0xFFC9A227),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sheetNav() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StudioPaneTitle(
          text: _t('Sheets', StudioStrings.de('Sheets'), 'الأوراق'),
          accent: _accent,
        ),
        for (int i = 0; i < _sheet.workbook.sheets.length; i++)
          ListTile(
            dense: true,
            leading: Icon(Icons.table_chart_outlined, color: _accent, size: 18),
            selected: i == _sheet.activeSheetIndex,
            selectedTileColor: _accent.withValues(alpha: 0.12),
            title: Text(_sheet.workbook.sheets[i].name),
            subtitle: Text(
              '${_sheet.workbook.sheets[i].allCells.length} '
              '${_t('cells', StudioStrings.de('cells'), 'خلية')}',
            ),
            onTap: () =>
                _navigateOffice(_sheet, () => _sheet.setActiveSheet(i)),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${_t('Cell', StudioStrings.de('Cell'), 'الخلية')} ${_sheet.selectionAddress}\n'
            '${_sheet.formulaBarText}',
            style: TextStyle(fontSize: 12, color: _officeTheme.chromeText),
          ),
        ),
      ],
    );
  }

  Widget _pdfNav({bool compact = false}) {
    final PdfOutlineNode? outline = _pdf.file?.outline;
    final bool hasOutline = outline != null && outline.children.isNotEmpty;
    final int tab = hasOutline ? _pdfSideTab.clamp(0, 1) : 0;
    if (!hasOutline && _pdfSideTab != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateNavigationState(() => _pdfSideTab = 0);
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: tab == 0
              ? _pdfThumbsPane(compact: compact)
              : _pdfOutlinePane(outline!),
        ),
        if (hasOutline) _pdfSideTabBar(tab),
      ],
    );
  }

  Widget _pdfSideTabBar(int tab) {
    Widget iconTab({
      required IconData icon,
      required int index,
      required String tip,
    }) {
      final bool selected = tab == index;
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _updateNavigationState(() => _pdfSideTab = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 40,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? _accent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: selected
                  ? _accent
                  : _officeTheme.chromeText.withValues(alpha: 0.55),
            ),
          ),
        ),
      );
    }

    return Material(
      color: _officeTheme.chromeFill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: _officeTheme.chromeText.withValues(alpha: 0.12),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            iconTab(
              icon: Icons.grid_view_rounded,
              index: 0,
              tip: _t(
                'Page previews',
                StudioStrings.de('Page previews'),
                'معاينة الصفحات',
              ),
            ),
            iconTab(
              icon: Icons.format_list_bulleted_rounded,
              index: 1,
              tip: _t('Outline', StudioStrings.de('Outline'), 'المخطط'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pdfThumbsPane({bool compact = false}) {
    final List<PdfDisplayList> lists = _pdf.lists;
    final int current = _pdf.pageIndex;
    final ScrollController scrollController = compact
        ? _compactPdfThumbScroll
        : _pdfThumbScroll;
    final int syncedPage = compact
        ? _compactPdfThumbSyncedPage
        : _pdfThumbSyncedPage;
    if (current != syncedPage) {
      if (compact) {
        _compactPdfThumbSyncedPage = current;
      } else {
        _pdfThumbSyncedPage = current;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scrollController.hasClients || lists.isEmpty) {
          return;
        }
        // ListView.builder may not have built the selected child yet, so
        // estimate offset from page aspect instead of ensureVisible alone.
        const double pad = 12;
        const double contentW = 268 - pad * 2;
        var y = 4.0;
        for (int i = 0; i < current && i < lists.length; i++) {
          final PdfDisplayList list = lists[i];
          final double pageW = list.page.width <= 0 ? 595 : list.page.width;
          final double pageH = list.page.height <= 0 ? 842 : list.page.height;
          final double thumbH = contentW * pageH / pageW;
          y += thumbH + 6 + 16 + 12; // thumb + gap + label + padding
        }
        // Resizing may show both panes. Their separate controllers keep each
        // normal desktop scrollbar attached to exactly one viewport.
        final position = scrollController.position;
        if (!position.hasContentDimensions) {
          return;
        }
        final double target = (y - 24).clamp(0.0, position.maxScrollExtent);
        position.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StudioPaneTitle(
          text: _t(
            'Page previews',
            StudioStrings.de('Page previews'),
            'معاينة الصفحات',
          ),
          accent: _accent,
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: lists.length,
            itemBuilder: (BuildContext context, int index) {
              final bool selected = index == current;
              return Padding(
                key: ValueKey<int>(index),
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pdf.goToPage(index),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      PdfPageThumb(
                        list: lists[index],
                        selected: selected,
                        annots:
                            _pdf.file?.annotsOn(index) ?? const <PdfAnnot>[],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_t('Page', StudioStrings.de('Page'), 'صفحة')} ${index + 1}'
                        '${selected ? (_t('  ·  current', StudioStrings.de('  ·  current'), '  ·  الحالية')) : ''}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? _accent
                              : _officeTheme.chromeText.withValues(alpha: 0.7),
                        ),
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

  Widget _pdfOutlinePane(PdfOutlineNode root) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StudioPaneTitle(
          text: _t('Outline', StudioStrings.de('Outline'), 'المخطط'),
          accent: _accent,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 16),
            children: <Widget>[
              for (int i = 0; i < root.children.length; i++)
                _pdfOutlineTile(root.children[i], 'r$i', 0),
            ],
          ),
        ),
      ],
    );
  }

  int? _outlineTargetPage(PdfOutlineNode node) {
    if (node.pageIndex != null) {
      return node.pageIndex;
    }
    for (final PdfOutlineNode child in node.children) {
      final int? page = _outlineTargetPage(child);
      if (page != null) {
        return page;
      }
    }
    return null;
  }

  Widget _pdfOutlineTile(PdfOutlineNode node, String path, int depth) {
    final bool hasKids = node.children.isNotEmpty;
    // Collapsed keys are stored as `c$path`; default is expanded (Evince-like).
    final bool open = hasKids && !_pdfOutlineExpanded.contains('c$path');
    final int? page = _outlineTargetPage(node);
    final bool selected =
        page != null && page == _pdf.pageIndex && node.pageIndex == page;

    void toggleExpand() {
      _updateNavigationState(() {
        final String key = 'c$path';
        if (_pdfOutlineExpanded.contains(key)) {
          _pdfOutlineExpanded.remove(key);
        } else {
          _pdfOutlineExpanded.add(key);
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Material(
          color: selected
              ? _accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: page == null
                ? (hasKids ? toggleExpand : null)
                : () => _pdf.goToPage(page),
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: 4.0 + depth * 12.0,
                end: 4,
                top: 6,
                bottom: 6,
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: hasKids
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            onPressed: toggleExpand,
                            icon: Icon(
                              open ? Icons.expand_more : Icons.chevron_right,
                              color: _officeTheme.chromeText.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: Text(
                      node.title.trim().isEmpty
                          ? (_t(
                              '(Untitled)',
                              StudioStrings.de('(Untitled)'),
                              '(بدون عنوان)',
                            ))
                          : node.title.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: depth == 0 ? 13 : 12,
                        fontWeight: depth == 0
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _officeTheme.chromeText,
                      ),
                    ),
                  ),
                  if (page != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Text(
                        '${page + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          color: _officeTheme.chromeText.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (open)
          for (int i = 0; i < node.children.length; i++)
            _pdfOutlineTile(node.children[i], '$path.$i', depth + 1),
      ],
    );
  }

  Widget _slideNav() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StudioPaneTitle(
          text: _t(
            'Slide sorter',
            StudioStrings.de('Slide sorter'),
            'فارز الشرائح',
          ),
          accent: _accent,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double cardW = math.max(80, constraints.maxWidth - 16);
              final double previewH = cardW * 405 / 720;
              return ReorderableListView.builder(
                padding: const EdgeInsets.all(8),
                buildDefaultDragHandles: false,
                itemCount: _slides.presentation.slides.length,
                proxyDecorator:
                    (Widget child, int index, Animation<double> anim) {
                      return Material(
                        elevation: 6,
                        color: Colors.transparent,
                        child: child,
                      );
                    },
                onReorderItem: (int from, int to) {
                  if (!_canMutate) {
                    return;
                  }
                  _slides.reorderSlide(from, to);
                },
                itemBuilder: (BuildContext context, int i) {
                  return _slideSorterCard(
                    key: ObjectKey(_slides.presentation.slides[i]),
                    index: i,
                    previewHeight: previewH,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _slideSorterCard({
    required Key key,
    required int index,
    required double previewHeight,
  }) {
    final PmlSlide slide = _slides.presentation.slides[index];
    final bool on = index == _slides.activeSlideIndex;
    final bool hidden = slide.hidden;
    final bool dark = _look != SuiteLook.light;
    final Color card = dark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF);
    final Color mat = dark ? const Color(0xFF1A1A1A) : const Color(0xFFB8B8B8);
    final Color frame = on
        ? _accent
        : (hidden
              ? (dark ? const Color(0xFF7A7A7A) : const Color(0xFF6A6A6A))
              : (dark ? const Color(0xFFD0D0D0) : const Color(0xFF1F1F1F)));
    final Color slideStroke = dark
        ? const Color(0xFF000000)
        : const Color(0xFF111111);
    return ReorderableDragStartListener(
      key: key,
      index: index,
      enabled: _canMutate,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: card,
          elevation: on ? 5 : 2,
          shadowColor: const Color(0x88000000),
          child: InkWell(
            onTap: () => _slides.setActiveSlide(index),
            onSecondaryTapDown: (TapDownDetails details) {
              _slides.setActiveSlide(index);
              _showSlideSorterMenu(details.globalPosition, index);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: frame, width: on ? 3 : 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            color: hidden ? const Color(0xFF777777) : _accent,
                            fontWeight: FontWeight.bold,
                            decoration: hidden
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                        if (hidden)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 4),
                            child: Icon(
                              Icons.visibility_off,
                              size: 12,
                              color: _accent,
                            ),
                          ),
                        const Spacer(),
                        if (!slide.transition.isNone)
                          Icon(Icons.animation, size: 12, color: _accent),
                        if (slide.animations.isNotEmpty)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 4),
                            child: Text(
                              '${slide.animations.length}',
                              style: TextStyle(
                                fontSize: 10,
                                color: _accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(5, 0, 5, 5),
                    child: ColoredBox(
                      color: mat,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: slideStroke, width: 1.5),
                          ),
                          child: SizedBox(
                            height: previewHeight,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                Opacity(
                                  opacity: hidden ? 0.42 : 1,
                                  child: IgnorePointer(
                                    child: SlideStage(
                                      slide: slide,
                                      preview: true,
                                      config: _config.copyWith(
                                        mode: OfficeInteractionMode.viewing,
                                        showSlideHandles: false,
                                        showRulers: false,
                                      ),
                                    ),
                                  ),
                                ),
                                if (hidden)
                                  const ColoredBox(
                                    color: Color(0x33000000),
                                    child: Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.visibility_off,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSlideSorterMenu(Offset globalPosition, int index) {
    OfficeContextMenu.dismiss(_slideSorterMenu);
    _slideSorterMenu = OfficeContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      actions: OfficeContextMenu.slideSorter(controller: _slides, index: index),
      onSelect: (String id) {
        _slideSorterMenu = null;
        switch (id) {
          case 'copySlide':
            _slides.copySlide(index);
          case 'pasteSlide':
            _slides.pasteSlide(afterIndex: index);
          case 'duplicateSlide':
            _slides.duplicateSlide(index);
          case 'hideSlide':
            _slides.setSlideHidden(index, true);
          case 'showSlide':
            _slides.setSlideHidden(index, false);
        }
      },
    );
  }

  Widget _statusBar() {
    final String detail = switch (_app) {
      SuiteApp.word =>
        '${_t('Page', StudioStrings.de('Page'), 'صفحة')} ${_word.visiblePageIndex + 1}'
            ' ${_t('of', StudioStrings.de('of'), 'من')} ${_word.pageCount}'
            ' · ${_t('Paragraph', StudioStrings.de('Paragraph'), 'فقرة')} ${_word.documentCaret.paragraphIndex + 1}'
            ' · ${_word.document.paragraphs.length} '
            '${_t('paragraphs', StudioStrings.de('paragraphs'), 'فقرات')}'
            ' · $_wordCount ${_t('words', StudioStrings.de('words'), 'كلمة')}'
            '${_word.selectedVisual != null ? ' · ${_word.selectedVisual!.visual.title}' : ''}'
            '${WordComment.roots(_word.document).isEmpty ? '' : ' · ${WordComment.roots(_word.document).length} ${_t('comments', StudioStrings.de('comments'), 'تعليقات')}'}'
            '${_word.isDirty ? ' · •' : ''}',
      SuiteApp.excel =>
        '${_sheet.sheet.name}!${_sheet.selectionAddress}'
            '${_sheet.cellEditor.editing ? (_t(' · editing cell', StudioStrings.de(' · editing cell'), ' · تحرير الخلية')) : ''}'
            ' · ${_sheet.workbook.sheets.length} '
            '${_t('sheets', StudioStrings.de('sheets'), 'أوراق')}'
            '${_sheet.selectedDrawing != null ? ' · ${_sheet.selectedDrawing!.visual.title}' : ''}'
            '${_sheet.isDirty ? ' · •' : ''}',
      SuiteApp.powerpoint =>
        '${_t('Slide', StudioStrings.de('Slide'), 'شريحة')} ${_slides.activeSlideIndex + 1}'
            '/${_slides.presentation.slides.length}'
            '${_slides.isPresenting ? (_t(' · slideshow · Esc to exit', StudioStrings.de(' · slideshow · Esc to exit'), ' · عرض الشرائح · Esc للخروج')) : ''}'
            '${!_slides.slide.transition.isNone ? ' · ${PmlMotionCatalog.transitionLabel(_slides.slide.transition.kind, arabic: _arabic)}' : ''}'
            '${_slides.slide.animations.isNotEmpty ? ' · ${_slides.slide.animations.length} ${_t('fx', StudioStrings.de('fx'), 'حركة')}' : ''}'
            '${_slides.selected != null ? ' · ${_slides.selected!.name}' : ''}'
            '${_slides.editingText ? (_t(' · editing text', StudioStrings.de(' · editing text'), ' · تحرير النص')) : ''}'
            '${_slides.slide.hidden ? (_t(' · hidden', StudioStrings.de(' · hidden'), ' · مخفية')) : ''}'
            '${_slides.isDirty ? ' · •' : ''}',
      SuiteApp.pdf =>
        '${_t('Page', StudioStrings.de('Page'), 'صفحة')} ${_pdf.pageIndex + 1}/${_pdf.pageCount}'
            '${_pdfNightMode ? (_t(' · night', StudioStrings.de(' · night'), ' · ليلي')) : ''}'
            '${_pdfSwipeHorizontal ? (_t(' · horizontal', StudioStrings.de(' · horizontal'), ' · أفقي')) : ''}'
            '${_pdfPageSnap ? (_t(' · snap', StudioStrings.de(' · snap'), ' · محاذاة')) : ''}'
            '${_pdfEvents.last.isEmpty ? '' : ' · ${_pdfEvents.last}'}'
            '${_pdf.isDirty ? ' · •' : ''}',
    };
    return Material(
      color: _accent,
      child: SizedBox(
        height:
            (_savePhase == _SavePhase.saving || _opening ? 34 : 26) +
            _extraChromeTextHeight(11),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _opening
                            ? _openStatusLabel
                            : (_isSaving
                                  ? _saveStatusLabel
                                  : '$_modeLabel · $detail'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    InkWell(
                      onTap: () => _setZoom(_viewScale - 0.1),
                      child: const Icon(
                        Icons.remove,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '$_zoomPercent%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _setZoom(_viewScale + 0.1),
                      child: const Icon(
                        Icons.add,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        _app == SuiteApp.pdf
                            ? (_t(
                                'PDF document',
                                StudioStrings.de('PDF document'),
                                'مستند PDF',
                              ))
                            : _active.semanticsLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_savePhase == _SavePhase.saving || _opening)
              LinearProgressIndicator(
                value: (_opening ? _openProgress : _saveProgress).clamp(
                  0.0,
                  1.0,
                ),
                minHeight: 4,
                backgroundColor: const Color(0x33FFFFFF),
                color: Colors.white,
              ),
          ],
        ),
      ),
    );
  }

  int get _wordCount => _word.documentStats.words;
}

/// Draft identity includes the thread object, because IDs can be reused after
/// a deletion or when another document is opened.
class _CommentReplyDraft {
  _CommentReplyDraft(this.root);

  final WmlComment root;
  final GlobalKey<_CommentReplyComposerState> key =
      GlobalKey<_CommentReplyComposerState>();
  String text = '';
}

class _CommentReplyComposer extends StatefulWidget {
  const _CommentReplyComposer({
    super.key,
    required this.draft,
    required this.proofing,
    required this.isCurrent,
    required this.arabic,
    required this.dark,
    required this.textColor,
    required this.accent,
    required this.onPost,
  });

  final _CommentReplyDraft draft;
  final WordProofingSession proofing;
  final bool Function() isCurrent;
  final bool arabic;
  final bool dark;
  final Color textColor;
  final Color accent;
  final bool Function() onPost;

  @override
  State<_CommentReplyComposer> createState() => _CommentReplyComposerState();
}

class _CommentReplyComposerState extends State<_CommentReplyComposer> {
  late final _DraftProofingTextController _text;
  final FocusNode _focus = FocusNode(debugLabel: 'studio-comment-reply');
  late TextEditingValue _observedValue;
  late Object _configuration;
  Timer? _checkTimer;
  WordDraftProofingResult? _result;
  int _generation = 0;
  int _findingIndex = 0;
  bool _checking = false;
  bool _checkError = false;
  bool _wasCurrent = false;
  bool _requestActive = false;
  bool _pendingCheck = false;

  bool get _composing =>
      _text.value.composing.isValid && !_text.value.composing.isCollapsed;

  bool get _canCheck =>
      mounted &&
      widget.isCurrent() &&
      widget.proofing.enabled &&
      !_composing &&
      _text.text.trim().isNotEmpty;

  List<OfficeProofingFinding> get _findings =>
      _result?.report.findings ?? const <OfficeProofingFinding>[];

  @override
  void initState() {
    super.initState();
    _text = _DraftProofingTextController(text: widget.draft.text);
    _observedValue = _text.value;
    _configuration = widget.proofing.draftConfigurationKey;
    _text.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
    widget.proofing.addListener(_onProofingChanged);
    _scheduleCheck(rebuild: false);
  }

  @override
  void didUpdateWidget(covariant _CommentReplyComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.proofing, widget.proofing)) {
      oldWidget.proofing.removeListener(_onProofingChanged);
      widget.proofing.addListener(_onProofingChanged);
    }
    final configuration = widget.proofing.draftConfigurationKey;
    if (configuration != _configuration || _wasCurrent != widget.isCurrent()) {
      _configuration = configuration;
      _scheduleCheck(rebuild: false);
    }
  }

  void _onTextChanged() {
    final previous = _observedValue;
    _observedValue = _text.value;
    widget.draft.text = _text.text;
    if (previous.text != _text.text ||
        previous.composing != _text.value.composing) {
      _scheduleCheck();
      return;
    }
    if (previous.selection != _text.selection && _findings.isNotEmpty) {
      final index = _findingAtCaret(_findings);
      if (index != null && index != _findingIndex) {
        setState(() => _findingIndex = index);
      }
    }
  }

  int? _findingAtCaret(List<OfficeProofingFinding> findings) {
    final offset = _text.selection.extentOffset;
    if (offset < 0) return null;
    final index = findings.indexWhere(
      (finding) => offset >= finding.start && offset <= finding.end,
    );
    return index < 0 ? null : index;
  }

  void _onFocusChanged() {
    if (_focus.hasFocus &&
        _result == null &&
        !_checking &&
        _checkTimer == null &&
        _canCheck) {
      _scheduleCheck();
    }
  }

  void _onProofingChanged() {
    final configuration = widget.proofing.draftConfigurationKey;
    if (configuration == _configuration) return;
    _configuration = configuration;
    _scheduleCheck();
  }

  void _scheduleCheck({bool rebuild = true}) {
    void update() {
      _checkTimer?.cancel();
      _checkTimer = null;
      _generation++;
      _checking = false;
      _checkError = false;
      _pendingCheck = false;
      _result = null;
      _findingIndex = 0;
      _text.findings = const [];
      _wasCurrent = widget.isCurrent();
      if (_canCheck) {
        _checkTimer = Timer(widget.proofing.debounce, _checkDraft);
      }
    }

    if (rebuild) {
      setState(update);
    } else {
      update();
    }
  }

  Future<void> _checkDraft() async {
    if (!_canCheck) {
      _scheduleCheck();
      return;
    }
    // Configured native providers are also serving the document. Keep only
    // one request in flight and check the latest debounced draft afterward.
    if (_requestActive) {
      setState(() {
        _checkTimer?.cancel();
        _checkTimer = null;
        _pendingCheck = true;
      });
      return;
    }
    _requestActive = true;
    _pendingCheck = false;
    final generation = ++_generation;
    final source = _text.text;
    final proofing = widget.proofing;
    final configuration = proofing.draftConfigurationKey;
    final draft = widget.draft;
    setState(() {
      _checkTimer?.cancel();
      _checkTimer = null;
      _checking = true;
      _checkError = false;
    });
    bool current() =>
        mounted &&
        generation == _generation &&
        identical(proofing, widget.proofing) &&
        identical(draft, widget.draft) &&
        source == _text.text &&
        configuration == proofing.draftConfigurationKey;
    try {
      final result = await proofing.checkDraft(source);
      if (!current()) return;
      if (!_canCheck) {
        _scheduleCheck();
        return;
      }
      setState(() {
        _checking = false;
        _checkError = result == null;
        if (result != null &&
            proofing.isDraftResultCurrent(result, text: source)) {
          _result = result;
          _text.findings = result.report.findings;
          _findingIndex = _findingAtCaret(result.report.findings) ?? 0;
        }
      });
    } on Object {
      if (!current()) return;
      setState(() {
        _checking = false;
        _checkError = true;
      });
    } finally {
      _requestActive = false;
      if (mounted && _pendingCheck) {
        _pendingCheck = false;
        unawaited(_checkDraft());
      }
    }
  }

  void _applySuggestion(
    WordDraftProofingResult result,
    OfficeProofingFinding finding,
    String replacement,
  ) {
    if (!_canCheck ||
        !identical(result, _result) ||
        !result.report.findings.contains(finding) ||
        !finding.replacements.contains(replacement) ||
        !widget.proofing.isDraftResultCurrent(result, text: _text.text) ||
        finding.start < 0 ||
        finding.end < finding.start ||
        finding.end > _text.text.length ||
        _text.text.substring(finding.start, finding.end) !=
            finding.originalText) {
      return;
    }
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(finding.start, finding.end, replacement),
      selection: TextSelection.collapsed(
        offset: finding.start + replacement.length,
      ),
    );
    _focus.requestFocus();
  }

  void _stepFinding(int delta) {
    if (!mounted || _findings.isEmpty || !widget.isCurrent() || _composing) {
      return;
    }
    setState(() {
      _findingIndex = (_findingIndex + delta) % _findings.length;
    });
  }

  String get _checkStatus {
    if (!widget.proofing.enabled) {
      return widget.arabic
          ? 'تدقيق الرد متوقف مؤقتًا.'
          : 'Reply checking paused.';
    }
    if (_composing) {
      return widget.arabic
          ? 'أكمل الكتابة لتدقيق الرد.'
          : 'Finish typing to check this reply.';
    }
    if (_checkTimer != null) {
      return widget.arabic ? 'بانتظار توقف الكتابة…' : 'Waiting for a pause…';
    }
    if (_checking) {
      return widget.arabic ? 'جارٍ تدقيق الرد…' : 'Checking reply…';
    }
    if (_pendingCheck) {
      return widget.arabic ? 'بانتظار تدقيق الرد…' : 'Waiting to check reply…';
    }
    if (_checkError) {
      return widget.arabic
          ? 'تعذر إكمال تدقيق الرد. حاول مجددًا.'
          : 'The reply check could not finish. Try again.';
    }
    final report = _result?.report;
    if (report == null) {
      return widget.arabic
          ? 'لم يُدقّق الرد بعد.'
          : 'Reply has not been checked.';
    }
    if (!report.complete) {
      return widget.arabic
          ? '${_findings.length} اقتراحات؛ تدقيق الرد غير مكتمل.'
          : '${_findings.length} suggestions; reply check incomplete.';
    }
    if (_findings.isEmpty) {
      return widget.arabic
          ? 'لم يُعثر على أخطاء في الرد.'
          : 'No issues found in this reply.';
    }
    return widget.arabic
        ? '${_findings.length} اقتراحات في الرد.'
        : '${_findings.length} ${_findings.length == 1 ? 'suggestion' : 'suggestions'} in reply.';
  }

  Widget _proofingStatus() {
    final result = _result;
    final findings = _findings;
    final finding = findings.isEmpty
        ? null
        : findings[_findingIndex.clamp(0, findings.length - 1)];
    final overLimit = _text.text.length > WordProofingSession.maxDraftLength;
    final problems = overLimit
        ? (widget.arabic
              ? 'يتجاوز هذا الرد حد التدقيق المباشر (${WordProofingSession.maxDraftLength}). يمكن تدقيقه بعد النشر.'
              : 'This reply exceeds the live checking limit (${WordProofingSession.maxDraftLength}). Check it after posting.')
        : result?.report.results
              .where(
                (provider) => provider.status != OfficeProofingStatus.success,
              )
              .map((provider) => provider.message ?? provider.status.name)
              .toSet()
              .join(' ');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _checkStatus,
                    key: ValueKey<String>(
                      'studio-comment-draft-status-${widget.draft.root.id}',
                    ),
                    style: TextStyle(fontSize: 11, color: widget.textColor),
                  ),
                ),
              ),
              if (_checkError || (result != null && !result.report.complete))
                IconButton(
                  tooltip: widget.arabic ? 'تدقيق الرد' : 'Check reply',
                  onPressed: _canCheck ? _checkDraft : null,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 16),
                ),
            ],
          ),
          if (result != null &&
              !result.report.complete &&
              problems != null &&
              problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                problems,
                style: TextStyle(
                  fontSize: 10,
                  color: widget.textColor.withValues(alpha: 0.75),
                ),
              ),
            ),
          if (result != null && finding != null)
            Container(
              key: ValueKey<String>(
                'studio-comment-draft-suggestions-${widget.draft.root.id}',
              ),
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          finding.message,
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.textColor,
                          ),
                        ),
                      ),
                      if (findings.length > 1) ...[
                        IconButton(
                          key: ValueKey<String>(
                            'studio-comment-draft-previous-${widget.draft.root.id}',
                          ),
                          tooltip: widget.arabic
                              ? 'الاقتراح السابق'
                              : 'Previous reply suggestion',
                          onPressed: () => _stepFinding(-1),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.chevron_left, size: 16),
                        ),
                        Text(
                          '${_findingIndex + 1}/${findings.length}',
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.textColor,
                          ),
                        ),
                        IconButton(
                          key: ValueKey<String>(
                            'studio-comment-draft-next-${widget.draft.root.id}',
                          ),
                          tooltip: widget.arabic
                              ? 'الاقتراح التالي'
                              : 'Next reply suggestion',
                          onPressed: () => _stepFinding(1),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.chevron_right, size: 16),
                        ),
                      ],
                    ],
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (
                        var index = 0;
                        index < finding.replacements.length && index < 5;
                        index++
                      )
                        ActionChip(
                          key: ValueKey<String>(
                            'studio-comment-draft-replace-${widget.draft.root.id}-$index',
                          ),
                          tooltip: finding.replacements[index].isEmpty
                              ? (widget.arabic ? 'حذف' : 'Delete')
                              : finding.replacements[index],
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(
                              finding.replacements[index].isEmpty
                                  ? (widget.arabic ? 'حذف' : 'Delete')
                                  : finding.replacements[index],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _applySuggestion(
                            result,
                            finding,
                            finding.replacements[index],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void focusReply() {
    Scrollable.ensureVisible(
      context,
      alignment: 1,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    _focus.requestFocus();
  }

  void _post() {
    if (!mounted || !widget.isCurrent() || _composing) {
      return;
    }
    widget.draft.text = _text.text;
    if (widget.onPost()) {
      _text.clear();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _generation++;
    _checkTimer?.cancel();
    widget.proofing.removeListener(_onProofingChanged);
    _text.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _post,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _post,
    },
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            widget.arabic
                ? 'رد على ${widget.draft.root.author}'
                : 'Reply to ${widget.draft.root.author}',
            style: TextStyle(fontSize: 11, color: widget.textColor),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: ValueKey<String>(
                    'studio-comment-reply-${widget.draft.root.id}',
                  ),
                  controller: _text,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(fontSize: 12, color: widget.textColor),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.arabic ? 'كتابة رد…' : 'Write a reply…',
                    filled: true,
                    fillColor: widget.dark
                        ? const Color(0xFF1E1E1E)
                        : Colors.white,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey<String>(
                  'studio-comment-post-${widget.draft.root.id}',
                ),
                tooltip: widget.arabic
                    ? 'نشر الرد (Ctrl+Enter)'
                    : 'Post reply (Ctrl+Enter)',
                onPressed: _text.text.trim().isEmpty ? null : _post,
                icon: Icon(Icons.send, size: 16, color: widget.accent),
              ),
            ],
          ),
          if (_text.text.trim().isNotEmpty) _proofingStatus(),
        ],
      ),
    ),
  );
}

/// Presents validated draft findings without changing the TextField's text,
/// selection, composition, or undo history.
class _DraftProofingTextController extends TextEditingController {
  _DraftProofingTextController({super.text});

  List<OfficeProofingFinding> findings = const [];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (findings.isEmpty ||
        (value.composing.isValid && !value.composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final valid = findings
        .where(
          (finding) =>
              finding.start >= 0 &&
              finding.end > finding.start &&
              finding.end <= text.length &&
              text.substring(finding.start, finding.end) ==
                  finding.originalText,
        )
        .toList();
    final boundaries = <int>{0, text.length};
    for (final finding in valid) {
      boundaries.addAll([finding.start, finding.end]);
    }
    final sorted = boundaries.toList()..sort();
    return TextSpan(
      style: style,
      children: [
        for (var index = 0; index < sorted.length - 1; index++)
          TextSpan(
            text: text.substring(sorted[index], sorted[index + 1]),
            style: _findingStyle(
              valid
                  .where(
                    (finding) =>
                        finding.start <= sorted[index] &&
                        finding.end >= sorted[index + 1],
                  )
                  .firstOrNull,
            ),
          ),
      ],
    );
  }

  TextStyle? _findingStyle(OfficeProofingFinding? finding) => finding == null
      ? null
      : TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: switch (finding.category) {
            OfficeProofingCategory.spelling => const Color(0xFFC62828),
            OfficeProofingCategory.grammar => const Color(0xFF1565C0),
            OfficeProofingCategory.style => const Color(0xFFAD6800),
          },
        );
}
