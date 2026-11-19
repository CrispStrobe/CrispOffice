import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_archive_host.dart';
import 'studio_mail_archive_directory_import.dart';
import 'studio_mail_archive_restore.dart';
import 'studio_mail_archive_restore_progress.dart';
import 'studio_mail_archive_restore_strings.dart';
import 'studio_mail_archive_strings.dart';
import 'studio_strings.dart';

export 'studio_mail_archive_host.dart';

const studioMailArchiveAvailable = true;

/// Local durable archive. Each asynchronous completion checks its owner and
/// generation; closing this dialog cancels work without deleting archived mail.
class StudioMailArchiveDialog extends StatefulWidget {
  const StudioMailArchiveDialog({
    super.key,
    required this.strings,
    this.store,
    this.openArchive,
    this.files,
    this.limits = const MailArchiveLimits(),
    this.closeStoreOnDispose = true,
    this.diagnosticSink,
  }) : assert(store == null || openArchive == null);

  final StudioStrings strings;
  final StudioMailArchiveStore? store;
  final StudioMailArchiveOpener? openArchive;
  final StudioMailArchiveFiles? files;
  final MailArchiveLimits limits;
  final bool closeStoreOnDispose;
  final MailArchiveLogSink? diagnosticSink;

  @override
  State<StudioMailArchiveDialog> createState() =>
      _StudioMailArchiveDialogState();
}

class _StudioMailArchiveDialogState extends State<StudioMailArchiveDialog> {
  final _query = TextEditingController();
  final _source = TextEditingController();
  final _folder = TextEditingController();
  final _sentSince = TextEditingController();
  final _sentThrough = TextEditingController();
  final _archivedSince = TextEditingController();
  final _archivedThrough = TextEditingController();
  final _minSize = TextEditingController();
  final _maxSize = TextEditingController();
  StudioMailArchiveStore? _store;
  late final StudioMailArchiveFiles _files;
  MailArchiveSearchPage? _page;
  MailArchiveStats? _stats;
  MailArchiveSearchRequest _request = const MailArchiveSearchRequest();
  List<MailArchiveSavedSearch> _saved = const [];
  String? _selectedSearch;
  MailArchiveSearchHit? _selected;
  MailReaderController? _reader;
  List<MailArchiveOrigin> _origins = const [];
  List<MailArchiveIntegrityIssue> _issues = const [];
  List<MailArchiveRestoreFailure> _restoreFailures = const [];
  int _restoreDroppedFailures = 0;
  String? _error;
  String? _notice;
  String? _exportDirectory;
  String? _previewError;
  bool _opening = false;
  bool _searching = false;
  bool _previewLoading = false;
  bool _working = false;
  bool _verbose = false;
  bool _indexAttachments = false;
  bool _includeSubfolders = true;
  bool? _hasAttachments;
  MailArchiveSort _sort = MailArchiveSort.archivedNewest;
  int _lifetime = 0;
  int _searchGeneration = 0;
  int _previewGeneration = 0;
  int _metadataGeneration = 0;
  int _processed = 0;
  MailCancellationSource? _cancellation;

  StudioStrings get s => widget.strings;
  bool get _ready => _store != null && !_opening && !_working;
  int get _pageSize => widget.limits.maxPageSize.clamp(1, 50);

  @override
  void initState() {
    super.initState();
    _files = widget.files ?? NativeStudioMailArchiveFiles();
    _store = widget.store;
    if (_store != null) {
      unawaited(_refresh());
    } else {
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    _lifetime++;
    _searchGeneration++;
    _previewGeneration++;
    _metadataGeneration++;
    _cancellation?.cancel(MailCancellationReason.disposed);
    for (final controller in [
      _query,
      _source,
      _folder,
      _sentSince,
      _sentThrough,
      _archivedSince,
      _archivedThrough,
      _minSize,
      _maxSize,
    ]) {
      controller.dispose();
    }
    _reader?.dispose();
    final store = _store;
    if (store != null && widget.closeStoreOnDispose) unawaited(_close(store));
    super.dispose();
  }

  Future<void> _close(StudioMailArchiveStore store) async {
    try {
      store.diagnostics = null;
    } on Object {
      // Diagnostic cleanup must not prevent release of the archive owner.
    }
    try {
      await store.close();
    } on Object {
      // Closing must never publish an exception into an already disposed host.
    }
  }

  bool _current(int generation, [StudioMailArchiveStore? store]) =>
      mounted &&
      generation == _lifetime &&
      (store == null || identical(store, _store));

  Future<MailResult<T>> _safe<T>(
    Future<MailResult<T>> Function() action,
  ) async {
    try {
      return await action();
    } on MailCancelled {
      return const MailFailure(MailProblem(MailProblemCode.cancelled));
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
  }

  Future<void> _open() async {
    if (_opening || _store != null) return;
    final generation = _lifetime;
    setState(() {
      _opening = true;
      _error = null;
    });
    final result = await _safe(
      () =>
          widget.openArchive?.call() ??
          openStudioMailArchive(limits: widget.limits),
    );
    if (!_current(generation)) {
      if (result case MailSuccess(value: final store)) await _close(store);
      return;
    }
    switch (result) {
      case MailSuccess(value: final store):
        setState(() {
          _store = store;
          _opening = false;
        });
        _setDiagnostics(_verbose);
        await _refresh();
      case MailFailure(problem: final problem):
        setState(() {
          _opening = false;
          _error = s.archiveProblem(problem.code);
        });
    }
  }

  void _setDiagnostics(bool value) {
    setState(() => _verbose = value);
    try {
      _store?.diagnostics = value
          ? MailArchiveDiagnostics(
              verbose: true,
              sink: (event) {
                if (!mounted || !_verbose) return;
                try {
                  if (widget.diagnosticSink case final sink?) {
                    sink(event);
                  } else {
                    debugPrint('[mail.archive] ${jsonEncode(event.toJson())}');
                  }
                } on Object {
                  // Diagnostic consumers cannot interrupt archive operations.
                }
              },
            )
          : null;
    } on Object {
      setState(() => _error = s.archiveProblem(MailProblemCode.storageFailure));
    }
  }

  Future<void> _refresh() async {
    await _search(request: _request.page(offset: 0, limit: _pageSize));
    if (mounted) await _refreshMetadata();
  }

  Future<void> _refreshMetadata() async {
    final store = _store;
    if (store == null) return;
    final generation = _lifetime;
    final metadata = ++_metadataGeneration;
    final stats = await _safe(store.statistics);
    if (!_current(generation, store) || metadata != _metadataGeneration) return;
    final searches = await _safe(store.listSearches);
    if (!_current(generation, store) || metadata != _metadataGeneration) return;
    setState(() {
      switch (stats) {
        case MailSuccess(value: final value):
          _stats = value;
        case MailFailure(problem: final problem):
          _error = s.archiveProblem(problem.code);
      }
      switch (searches) {
        case MailSuccess(value: final value):
          _saved = value;
          if (!_saved.any((item) => item.name == _selectedSearch)) {
            _selectedSearch = null;
          }
        case MailFailure(problem: final problem):
          _error = s.archiveProblem(problem.code);
      }
    });
  }

  DateTime? _date(String text, {bool inclusiveEnd = false}) {
    if (text.trim().isEmpty) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
    if (match == null) throw const FormatException('Invalid date.');
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime.utc(year, month, day);
    if (year < 1 ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      throw const FormatException('Invalid calendar date.');
    }
    return inclusiveEnd ? date.add(const Duration(days: 1)) : date;
  }

  int? _size(String text) {
    if (text.trim().isEmpty) return null;
    if (!RegExp(r'^\d{1,12}$').hasMatch(text.trim())) {
      throw const FormatException('Invalid size.');
    }
    return int.parse(text.trim());
  }

  MailArchiveSearchRequest _buildRequest() {
    MailArchiveQuery.parse(_query.text);
    final request = MailArchiveSearchRequest(
      query: _query.text,
      source: _source.text.trim().isEmpty ? null : _source.text.trim(),
      folder: _folder.text.trim().isEmpty ? null : _folder.text.trim(),
      includeSubfolders: _includeSubfolders,
      sentSince: _date(_sentSince.text),
      sentBefore: _date(_sentThrough.text, inclusiveEnd: true),
      archivedSince: _date(_archivedSince.text),
      archivedBefore: _date(_archivedThrough.text, inclusiveEnd: true),
      minBytes: _size(_minSize.text),
      maxBytes: _size(_maxSize.text),
      hasAttachments: _hasAttachments,
      sort: _sort,
      limit: _pageSize,
    );
    if (request.sentSince != null &&
            request.sentBefore != null &&
            !request.sentSince!.isBefore(request.sentBefore!) ||
        request.archivedSince != null &&
            request.archivedBefore != null &&
            !request.archivedSince!.isBefore(request.archivedBefore!) ||
        request.minBytes != null &&
            request.maxBytes != null &&
            request.minBytes! > request.maxBytes!) {
      throw const FormatException('Invalid range.');
    }
    return request;
  }

  Future<void> _search({MailArchiveSearchRequest? request}) async {
    final store = _store;
    if (store == null || _working) return;
    final generation = _lifetime;
    final search = ++_searchGeneration;
    MailArchiveSearchRequest next;
    try {
      next = request ?? _buildRequest();
    } on Object {
      setState(() {
        _error = s.archiveQueryInvalid;
        _searching = false;
      });
      return;
    }
    final previous = _reader;
    setState(() {
      _searching = true;
      _error = null;
      _page = null;
      _selected = null;
      _reader = null;
      _origins = const [];
      _previewGeneration++;
      _previewLoading = false;
    });
    _retire(previous);
    final result = await _safe(() => store.search(next));
    if (!_current(generation, store) || search != _searchGeneration) return;
    setState(() {
      _searching = false;
      switch (result) {
        case MailSuccess(value: final value):
          _page = value;
          _request = next;
        case MailFailure(problem: final problem):
          _error = s.archiveProblem(problem.code);
      }
    });
  }

  void _retire(MailReaderController? reader) {
    if (reader == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
  }

  Future<void> _select(MailArchiveSearchHit hit) async {
    final store = _store;
    if (store == null || _working) return;
    final generation = _lifetime;
    final preview = ++_previewGeneration;
    final previous = _reader;
    setState(() {
      _selected = hit;
      _reader = null;
      _origins = const [];
      _previewError = null;
      _previewLoading = true;
    });
    _retire(previous);
    final original = await _safe(() => store.loadOriginal(hit.entry.id));
    if (!_current(generation, store) || preview != _previewGeneration) return;
    final origins = await _safe(() => store.listOrigins(hit.entry.id));
    if (!_current(generation, store) || preview != _previewGeneration) return;
    MailReaderController? reader;
    String? error;
    switch (original) {
      case MailSuccess(value: final bytes?):
        try {
          reader = MailReaderController.fromBytes(
            bytes.bytes,
            codec: const QudsMimeCodec(),
            budget: MailReadBudget(maxRawBytes: widget.limits.maxMessageBytes),
          );
        } on Object {
          error = s.archiveProblem(MailProblemCode.invalidInput);
        }
      case MailSuccess():
        error = s.archiveProblem(MailProblemCode.unavailable);
      case MailFailure(problem: final problem):
        error = s.archiveProblem(problem.code);
    }
    setState(() {
      _reader = reader;
      _previewError = error;
      _previewLoading = false;
      switch (origins) {
        case MailSuccess(value: final values):
          _origins = values;
        case MailFailure(problem: final problem):
          _previewError ??= s.archiveProblem(problem.code);
      }
    });
  }

  Future<void> _work(
    Future<void> Function(StudioMailArchiveStore, MailCancellationToken, int)
    action,
  ) async {
    final store = _store;
    if (!_ready || store == null || _searching) return;
    final generation = _lifetime;
    final cancellation = MailCancellationSource();
    _cancellation = cancellation;
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
      _processed = 0;
      _issues = const [];
      _restoreFailures = const [];
      _restoreDroppedFailures = 0;
    });
    try {
      await action(store, cancellation.token, generation);
    } on MailCancelled {
      if (_current(generation, store)) {
        setState(() => _notice = s.archiveProblem(MailProblemCode.cancelled));
      }
    } on Object {
      if (_current(generation, store)) {
        setState(
          () => _error = s.archiveProblem(MailProblemCode.storageFailure),
        );
      }
    } finally {
      if (_current(generation, store)) {
        setState(() {
          _working = false;
          _cancellation = null;
        });
      }
    }
  }

  Future<void> _import() async {
    if (!_ready || _searching) return;
    final options = await showDialog<_ImportOptions>(
      context: context,
      builder: (_) =>
          _ArchiveImportDialog(strings: s, indexAttachments: _indexAttachments),
    );
    if (!mounted || options == null || !_ready) return;
    setState(() => _indexAttachments = options.indexAttachments);
    await _work((store, cancellation, generation) async {
      final files = await _files.pickFiles();
      if (!_current(generation, store) ||
          cancellation.isCancelled ||
          files == null) {
        return;
      }
      if (files.length > 1000) {
        setState(
          () => _error = s.archiveProblem(MailProblemCode.quotaExceeded),
        );
        return;
      }
      var imported = 0, duplicates = 0, failed = 0, warnings = 0;
      for (final file in files) {
        if (cancellation.isCancelled || !_current(generation, store)) break;
        var ordinal = 0;
        try {
          await for (final result in _files.readMessages(
            file,
            maxMessageBytes: widget.limits.maxMessageBytes,
            cancellation: cancellation,
            dialect: options.dialect,
          )) {
            if (cancellation.isCancelled || !_current(generation, store)) break;
            ordinal++;
            switch (result) {
              case MailFailure(problem: final problem):
                failed++;
                setState(() => _error = s.archiveProblem(problem.code));
              case MailSuccess(value: final bytes):
                if (bytes.length > widget.limits.maxMessageBytes) {
                  failed++;
                  setState(
                    () => _error = s.archiveProblem(
                      MailProblemCode.quotaExceeded,
                    ),
                  );
                  break;
                }
                final parsed = const QudsMimeCodec().parse(
                  bytes,
                  budget: MailReadBudget(
                    maxRawBytes: widget.limits.maxMessageBytes,
                  ),
                  cancellation: cancellation,
                );
                final message = parsed.message;
                if (message == null ||
                    parsed.status == MailParseStatus.cancelled) {
                  failed++;
                  setState(
                    () =>
                        _error = s.archiveProblem(MailProblemCode.invalidInput),
                  );
                  break;
                }
                final stored = await _safe(
                  () => store.archiveMessage(
                    message,
                    origin: MailArchiveOrigin(
                      source: options.source,
                      folder: options.folder,
                      sourceMessageId: '${file.name}:$ordinal',
                    ),
                    indexAttachmentText: options.indexAttachments,
                    cancellation: cancellation,
                  ),
                );
                if (!_current(generation, store)) return;
                switch (stored) {
                  case MailSuccess(value: final value):
                    if (value.duplicate) {
                      duplicates++;
                    } else {
                      imported++;
                    }
                    if (parsed.status != MailParseStatus.complete ||
                        value.entry.indexTruncated ||
                        value.entry.attachmentTextSkipped > 0) {
                      warnings++;
                    }
                  case MailFailure(problem: final problem):
                    if (problem.code != MailProblemCode.cancelled) failed++;
                    setState(() => _error = s.archiveProblem(problem.code));
                }
            }
            setState(() => _processed = imported + duplicates + failed);
            // Yield between records so cancellation and paint remain responsive.
            await Future<void>.delayed(Duration.zero);
          }
        } on Object {
          if (!_current(generation, store)) return;
          failed++;
          setState(
            () => _error = s.archiveProblem(MailProblemCode.unavailable),
          );
        }
      }
      if (_current(generation, store)) {
        setState(
          () => _notice = s.archiveImportSummary(
            imported,
            duplicates,
            failed,
            warnings,
            cancellation.isCancelled,
          ),
        );
      }
    });
    if (mounted) {
      final operationError = _error;
      await _refresh();
      if (mounted && _error == null && operationError != null) {
        setState(() => _error = operationError);
      }
    }
  }

  Future<void> _importDirectory() async {
    if (!_ready || _searching) return;
    final options = await showDialog<_ImportOptions>(
      context: context,
      builder: (_) => _ArchiveImportDialog(
        strings: s,
        indexAttachments: _indexAttachments,
        directory: true,
      ),
    );
    if (!mounted || options == null || !_ready) return;
    setState(() => _indexAttachments = options.indexAttachments);
    await _work((store, cancellation, generation) async {
      final path = await _files.pickDirectory();
      if (!_current(generation, store) ||
          cancellation.isCancelled ||
          path == null) {
        return;
      }
      final report = await importStudioMailDirectory(
        store: store,
        files: _files,
        directory: path,
        source: options.source,
        folder: options.folder,
        indexAttachmentText: options.indexAttachments,
        dialect: options.dialect,
        recursive: options.recursive,
        maxMessageBytes: widget.limits.maxMessageBytes,
        maxMessages: widget.limits.maxMessages,
        cancellation: cancellation,
        onProgress: (progress) {
          if (!_current(generation, store)) return;
          setState(() => _processed = progress.processed);
          if (_verbose) {
            debugPrint(
              '[mail.archive.directory] ${jsonEncode(progress.toJson())}',
            );
          }
        },
      );
      if (!_current(generation, store)) return;
      setState(() {
        _notice = s.archiveDirectorySummary(
          report.status,
          report.progress.saved,
          report.progress.duplicates,
          report.progress.failed,
          report.progress.skipped,
          report.progress.scanErrors,
          report.progress.limited,
          report.progress.warnings,
        );
        if (report.problem != null) {
          _error = s.archiveProblem(report.problem!.code);
        }
      });
    });
    if (mounted) {
      final operationError = _error;
      await _refresh();
      if (mounted && _error == null && operationError != null) {
        setState(() => _error = operationError);
      }
    }
  }

  Future<void> _restoreExport() async {
    await _work((store, cancellation, generation) async {
      final path = await _files.pickDirectory();
      if (!_current(generation, store) ||
          cancellation.isCancelled ||
          path == null) {
        return;
      }
      final inspected = await _safe(
        () => store.inspectRestore(path, cancellation: cancellation),
      );
      if (!_current(generation, store) || cancellation.isCancelled) return;
      if (inspected case MailFailure(:final problem)) {
        setState(() => _error = s.archiveProblem(problem.code));
        return;
      }
      final plan = (inspected as MailSuccess<MailArchiveRestorePlan>).value;
      if (!mounted) return;
      final options = await showDialog<StudioMailArchiveRestoreOptions>(
        context: context,
        builder: (_) => StudioMailArchiveRestoreDialog(
          strings: s,
          plan: plan,
          indexAttachmentText: _indexAttachments,
        ),
      );
      if (!_current(generation, store) ||
          cancellation.isCancelled ||
          options == null) {
        return;
      }
      setState(() => _indexAttachments = options.indexAttachmentText);
      final report = await store.restoreExport(
        plan,
        indexAttachmentText: options.indexAttachmentText,
        resume: options.resume,
        cancellation: cancellation,
        onProgress: (progress) {
          if (!_current(generation, store)) return;
          setState(() {
            _processed = progress.processed;
            _notice = s.archiveRestoreCounts(
              progress.saved,
              progress.duplicates,
              progress.failed,
              progress.planned,
              progress.originsAdded,
              progress.bytes,
              progress.indexWarnings,
              resumed: progress.resumed,
              resumedBytes: progress.resumedBytes,
              resumedIndexWarnings: progress.resumedIndexWarnings,
            );
          });
          if (_verbose) {
            debugPrint(
              '[mail.archive.restore] ${jsonEncode(progress.toJson())}',
            );
          }
        },
      );
      if (!_current(generation, store)) return;
      setState(() {
        _processed = report.processed;
        _notice = s.archiveRestoreSummary(report);
        _restoreFailures = report.failures;
        _restoreDroppedFailures = report.droppedFailures;
        if (report.problem case final problem?) {
          _error = s.archiveProblem(problem.code);
        }
      });
    });
    if (mounted) {
      final operationError = _error;
      await _refresh();
      if (mounted && _error == null && operationError != null) {
        setState(() => _error = operationError);
      }
    }
  }

  Future<void> _restoreProgress() => _work((
    store,
    cancellation,
    generation,
  ) async {
    final result = await _safe(store.listRestoreCheckpoints);
    if (!_current(generation, store) || cancellation.isCancelled) return;
    if (result case MailFailure(:final problem)) {
      setState(() => _error = s.archiveProblem(problem.code));
      return;
    }
    final checkpoints =
        (result as MailSuccess<List<MailArchiveRestoreCheckpoint>>).value;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => StudioMailArchiveRestoreProgressDialog(
        strings: s,
        checkpoints: checkpoints,
        onForget: (manifestSha256) async {
          if (!_current(generation, store) || cancellation.isCancelled) {
            return const MailFailure(MailProblem(MailProblemCode.cancelled));
          }
          return _safe(
            () => store.forgetRestoreCheckpoint(
              manifestSha256,
              cancellation: cancellation,
            ),
          );
        },
      ),
    );
  });

  Future<void> _bulkExport({bool resume = false}) async {
    if (!_ready || _searching) return;
    final request = _request;
    await _work((store, cancellation, generation) async {
      MailArchiveExportPlan? plan;
      if (!resume) {
        final result = await _safe(
          () => store.planExport(request, cancellation: cancellation),
        );
        if (!_current(generation, store) || cancellation.isCancelled) return;
        if (result case MailFailure(:final problem)) {
          setState(() => _error = s.archiveProblem(problem.code));
          return;
        }
        plan = (result as MailSuccess<MailArchiveExportPlan>).value;
      }
      if (!mounted ||
          !_current(generation, store) ||
          cancellation.isCancelled) {
        return;
      }
      final choose = await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: s.language == StudioLanguage.ar
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: AlertDialog(
            scrollable: true,
            title: Text(resume ? s.archiveResumeExport : s.archiveBulkExport),
            content: Text(
              resume
                  ? s.archiveResumeHelp
                  : s.archiveBulkHelp(plan!.items.length, plan.totalBytes),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(s.archiveCancel),
              ),
              FilledButton(
                key: const ValueKey('archive-choose-export-directory'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(s.archiveChooseDirectory),
              ),
            ],
          ),
        ),
      );
      if (!_current(generation, store) ||
          cancellation.isCancelled ||
          choose != true) {
        return;
      }
      final path = await _files.pickDirectory();
      if (!_current(generation, store) ||
          cancellation.isCancelled ||
          path == null) {
        return;
      }
      void progress(MailArchiveExportProgress progress) {
        if (!_current(generation, store)) return;
        setState(() {
          _processed = progress.processed;
          _notice = s.archiveBulkCounts(
            progress.written,
            progress.existing,
            progress.failed,
            progress.planned,
          );
        });
        if (_verbose) {
          debugPrint('[mail.archive.export] ${jsonEncode(progress.toJson())}');
        }
      }

      final report = resume
          ? await _files.resumeExport(
              path,
              profile: store.profile,
              loadOriginal: store.loadOriginal,
              cancellation: cancellation,
              onProgress: progress,
            )
          : await _files.exportPlan(
              plan!,
              path,
              loadOriginal: store.loadOriginal,
              cancellation: cancellation,
              onProgress: progress,
            );
      if (!_current(generation, store)) return;
      setState(() {
        _processed = report.processed;
        _notice = s.archiveBulkSummary(
          report.status,
          report.written,
          report.existing,
          report.failed,
          report.planned,
        );
        _exportDirectory = report.directoryPath;
        if (report.problem != null) {
          _error = s.archiveProblem(report.problem!.code);
        }
      });
    });
  }

  Future<void> _maintain(bool rebuild) async {
    await _work((store, cancellation, generation) async {
      String? cursor;
      var count = 0, issueCount = 0;
      final issues = <MailArchiveIntegrityIssue>[];
      while (!cancellation.isCancelled && _current(generation, store)) {
        final result = await _safe(
          () => rebuild
              ? store.rebuildIndex(
                  afterId: cursor,
                  limit: 25,
                  cancellation: cancellation,
                  codec: const QudsMimeCodec(),
                  indexAttachmentText: _indexAttachments,
                )
              : store.verifyIntegrity(
                  afterId: cursor,
                  limit: 25,
                  cancellation: cancellation,
                ),
        );
        if (!_current(generation, store)) return;
        if (result case MailFailure(problem: final problem)) {
          setState(() => _error = s.archiveProblem(problem.code));
          break;
        }
        final page = (result as MailSuccess<MailArchiveMaintenancePage>).value;
        count += page.processed;
        issueCount += page.issues.length;
        issues.addAll(page.issues.take(100 - issues.length));
        setState(() {
          _processed = count;
          _issues = List.unmodifiable(issues);
        });
        if (!page.hasMore) break;
        if (page.nextAfterId == null ||
            page.nextAfterId == cursor ||
            page.processed < 1) {
          setState(
            () => _error = s.archiveProblem(MailProblemCode.storageFailure),
          );
          break;
        }
        cursor = page.nextAfterId;
        await Future<void>.delayed(Duration.zero);
      }
      if (_current(generation, store)) {
        setState(
          () => _notice = s.archiveMaintenanceSummary(
            count,
            issueCount,
            cancellation.isCancelled,
          ),
        );
      }
    });
    if (mounted) await _refreshMetadata();
  }

  Future<void> _export() async {
    final selected = _selected;
    if (selected == null) return;
    await _work((store, cancellation, generation) async {
      final result = await _safe(() => store.loadOriginal(selected.entry.id));
      if (!_current(generation, store) || cancellation.isCancelled) return;
      switch (result) {
        case MailSuccess(value: final bytes?):
          // Hash-only names cannot turn message subjects into filesystem paths.
          final exported = await _safe(
            () => _files.exportOriginal(
              '${selected.entry.id}.eml',
              bytes,
              cancellation: cancellation,
            ),
          );
          if (!_current(generation, store)) return;
          switch (exported) {
            case MailSuccess(value: true):
              setState(() => _notice = s.archiveExported);
            case MailSuccess():
              break;
            case MailFailure(problem: final problem):
              setState(() => _error = s.archiveProblem(problem.code));
          }
        case MailSuccess():
          setState(
            () => _error = s.archiveProblem(MailProblemCode.unavailable),
          );
        case MailFailure(problem: final problem):
          setState(() => _error = s.archiveProblem(problem.code));
      }
    });
  }

  Future<void> _saveSearch() async {
    if (!_ready) return;
    final MailArchiveSearchRequest request;
    try {
      request = _buildRequest();
    } on Object {
      setState(() => _error = s.archiveQueryInvalid);
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _ArchiveSearchNameDialog(strings: s),
    );
    if (!mounted || name == null) return;
    await _work((store, cancellation, generation) async {
      final result = await _safe(
        () => store.saveSearch(
          MailArchiveSavedSearch(name: name, request: request),
        ),
      );
      if (!_current(generation, store)) return;
      setState(() {
        switch (result) {
          case MailSuccess():
            _selectedSearch = name;
            _notice = s.archiveSearchSaved;
          case MailFailure(problem: final problem):
            _error = s.archiveProblem(problem.code);
        }
      });
    });
    if (mounted) await _refreshMetadata();
  }

  Future<void> _removeSearch() async {
    final name = _selectedSearch;
    if (name == null) return;
    await _work((store, cancellation, generation) async {
      final result = await _safe(() => store.removeSearch(name));
      if (!_current(generation, store)) return;
      setState(() {
        switch (result) {
          case MailSuccess():
            _selectedSearch = null;
            _notice = s.archiveSearchRemoved;
          case MailFailure(problem: final problem):
            _error = s.archiveProblem(problem.code);
        }
      });
    });
    if (mounted) await _refreshMetadata();
  }

  String _dateText(DateTime? value, {bool exclusiveEnd = false}) {
    if (value == null) return '';
    final date = exclusiveEnd
        ? value.toUtc().subtract(const Duration(days: 1))
        : value.toUtc();
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _loadSearch(MailArchiveSavedSearch saved) {
    final request = saved.request;
    setState(() {
      _selectedSearch = saved.name;
      _query.text = request.query;
      _source.text = request.source ?? '';
      _folder.text = request.folder ?? '';
      _includeSubfolders = request.includeSubfolders;
      _sentSince.text = _dateText(request.sentSince);
      _sentThrough.text = _dateText(request.sentBefore, exclusiveEnd: true);
      _archivedSince.text = _dateText(request.archivedSince);
      _archivedThrough.text = _dateText(
        request.archivedBefore,
        exclusiveEnd: true,
      );
      _minSize.text = request.minBytes == null ? '' : '${request.minBytes!}';
      _maxSize.text = request.maxBytes == null ? '' : '${request.maxBytes!}';
      _hasAttachments = request.hasAttachments;
      _sort = request.sort;
    });
    unawaited(_search(request: request.page(offset: 0, limit: _pageSize)));
  }

  void _resetFilters() {
    setState(() {
      for (final controller in [
        _query,
        _source,
        _folder,
        _sentSince,
        _sentThrough,
        _archivedSince,
        _archivedThrough,
        _minSize,
        _maxSize,
      ]) {
        controller.clear();
      }
      _selectedSearch = null;
      _includeSubfolders = true;
      _hasAttachments = null;
      _sort = MailArchiveSort.archivedNewest;
    });
    unawaited(_search());
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Directionality(
      textDirection: s.language == StudioLanguage.ar
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.archiveTitle, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: s.close,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .52,
                ),
                child: SingleChildScrollView(
                  child: _controls(constraints.maxWidth),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _content(constraints.maxWidth)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _controls(double width) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.archiveStorageNotice,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_stats case final stats?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              s.archiveStats(
                stats.messages,
                stats.rawBytes,
                stats.indexedMessages,
              ),
              key: const ValueKey('archive-stats'),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('archive-import'),
              onPressed: _ready && !_searching ? _import : null,
              icon: const Icon(Icons.archive_outlined),
              label: Text(s.archiveImport),
            ),
            OutlinedButton.icon(
              key: const ValueKey('archive-import-directory'),
              onPressed: _ready && !_searching ? _importDirectory : null,
              icon: const Icon(Icons.folder_open),
              label: Text(s.archiveImportDirectory),
            ),
            OutlinedButton.icon(
              key: const ValueKey('archive-restore-export'),
              onPressed: _ready && !_searching ? _restoreExport : null,
              icon: const Icon(Icons.restore_page_outlined),
              label: Text(s.archiveRestoreExport),
            ),
            OutlinedButton.icon(
              key: const ValueKey('archive-bulk-export'),
              onPressed: _ready && !_searching ? () => _bulkExport() : null,
              icon: const Icon(Icons.drive_folder_upload_outlined),
              label: Text(s.archiveBulkExport),
            ),
            TextButton.icon(
              key: const ValueKey('archive-restore-progress'),
              onPressed: _ready && !_searching ? _restoreProgress : null,
              icon: const Icon(Icons.history),
              label: Text(s.archiveRestoreProgress),
            ),
            TextButton.icon(
              key: const ValueKey('archive-resume-export'),
              onPressed: _ready && !_searching
                  ? () => _bulkExport(resume: true)
                  : null,
              icon: const Icon(Icons.play_arrow_outlined),
              label: Text(s.archiveResumeExport),
            ),
            TextButton.icon(
              key: const ValueKey('archive-verify'),
              onPressed: _ready && !_searching ? () => _maintain(false) : null,
              icon: const Icon(Icons.verified_outlined),
              label: Text(s.archiveVerify),
            ),
            TextButton.icon(
              key: const ValueKey('archive-rebuild'),
              onPressed: _ready && !_searching ? () => _maintain(true) : null,
              icon: const Icon(Icons.manage_search),
              label: Text(s.archiveRebuild),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('archive-query'),
                controller: _query,
                enabled: !_working,
                maxLength: 1024,
                decoration: InputDecoration(
                  labelText: s.archiveSearch,
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            IconButton(
              key: const ValueKey('archive-search'),
              onPressed: _ready ? () => _search() : null,
              tooltip: s.archiveSearch,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        ExpansionTile(
          key: const ValueKey('archive-filter-panel'),
          title: Text(s.archiveFilters),
          tilePadding: EdgeInsets.zero,
          children: [
            _filters(width - 24),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                s.archiveSearchHelp,
                key: const ValueKey('archive-query-help'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              key: const ValueKey('archive-save-search'),
              onPressed: _ready && !_searching ? _saveSearch : null,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(s.archiveSaveSearch),
            ),
            if (_saved.isNotEmpty)
              PopupMenuButton<MailArchiveSavedSearch>(
                key: const ValueKey('archive-saved-searches'),
                enabled: _ready,
                tooltip: s.archiveSavedSearches,
                onSelected: _loadSearch,
                itemBuilder: (_) => [
                  for (final item in _saved)
                    PopupMenuItem(
                      value: item,
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _selectedSearch ?? s.archiveSavedSearches,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (_selectedSearch != null)
              IconButton(
                key: const ValueKey('archive-delete-search'),
                tooltip: s.archiveDeleteSearch,
                onPressed: _ready && !_searching ? _removeSearch : null,
                icon: const Icon(Icons.bookmark_remove_outlined),
              ),
          ],
        ),
        ExpansionTile(
          title: Text(s.archiveIndexingOptions),
          tilePadding: EdgeInsets.zero,
          children: [
            SwitchListTile(
              key: const ValueKey('archive-index-attachments'),
              contentPadding: EdgeInsets.zero,
              title: Text(s.archiveIndexAttachmentText),
              subtitle: Text(s.archiveRebuildHelp),
              value: _indexAttachments,
              onChanged: _working
                  ? null
                  : (value) => setState(() => _indexAttachments = value),
            ),
          ],
        ),
        ExpansionTile(
          title: Text(s.archiveDiagnostics),
          tilePadding: EdgeInsets.zero,
          children: [
            SwitchListTile(
              key: const ValueKey('archive-diagnostics'),
              contentPadding: EdgeInsets.zero,
              title: Text(s.archiveDiagnostics),
              subtitle: Text(s.archiveDiagnosticsHelp),
              value: _verbose,
              onChanged: _setDiagnostics,
            ),
          ],
        ),
        if (_opening || _searching || _working)
          const LinearProgressIndicator(minHeight: 2),
        if (_working)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text('${s.archiveWorking} ${s.archiveProgress(_processed)}'),
              TextButton(
                key: const ValueKey('archive-cancel'),
                onPressed: () => _cancellation?.cancel(),
                child: Text(s.archiveCancel),
              ),
            ],
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(
              _error!,
              key: const ValueKey('archive-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_exportDirectory != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.archiveExportDestination),
                SelectableText(
                  _exportDirectory!,
                  key: const ValueKey('archive-export-directory'),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(
              _notice!,
              key: const ValueKey('archive-notice'),
            ),
          ),
        if (_restoreFailures.isNotEmpty || _restoreDroppedFailures > 0)
          ExpansionTile(
            key: const ValueKey('archive-restore-failures'),
            title: Text(s.archiveRestoreFailures),
            children: [
              Text(
                s.archiveFolderItemFailures(
                  _restoreFailures.length,
                  _restoreDroppedFailures,
                ),
              ),
              for (final failure in _restoreFailures)
                ListTile(
                  dense: true,
                  title: Text(s.archiveRestoreItem(failure.ordinal)),
                  subtitle: Text(s.archiveProblem(failure.code)),
                ),
            ],
          ),
        if (_issues.isNotEmpty)
          ExpansionTile(
            title: Text(s.archiveIntegrityIssues),
            children: [
              for (final issue in _issues)
                ListTile(
                  dense: true,
                  title: Text(s.archiveIntegrityIssue(issue.code)),
                  subtitle: Text(
                    issue.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        if (_store == null && !_opening)
          TextButton(
            key: const ValueKey('archive-retry'),
            onPressed: _open,
            child: Text(s.archiveRetry),
          ),
      ],
    ),
  );

  Widget _filters(double width) {
    final fieldWidth = width >= 600 ? (width - 12) / 2 : width;
    Widget field(
      String key,
      String label,
      TextEditingController controller, {
      bool numeric = false,
    }) => SizedBox(
      width: fieldWidth,
      child: TextField(
        key: ValueKey(key),
        controller: controller,
        enabled: !_working,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        maxLength: numeric ? 12 : 256,
      ),
    );
    return Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            field('archive-source', s.archiveSource, _source),
            field('archive-folder', s.archiveFolder, _folder),
            field('archive-sent-since', s.archiveSentSince, _sentSince),
            field('archive-sent-through', s.archiveSentThrough, _sentThrough),
            field('archive-stored-since', s.archiveStoredSince, _archivedSince),
            field(
              'archive-stored-through',
              s.archiveStoredThrough,
              _archivedThrough,
            ),
            field(
              'archive-min-size',
              s.archiveMinSize,
              _minSize,
              numeric: true,
            ),
            field(
              'archive-max-size',
              s.archiveMaxSize,
              _maxSize,
              numeric: true,
            ),
            SizedBox(
              width: fieldWidth,
              child: DropdownButtonFormField<int>(
                key: ValueKey(
                  'archive-attachments-${_hasAttachments?.toString() ?? 'any'}',
                ),
                initialValue: _hasAttachments == null
                    ? 0
                    : _hasAttachments!
                    ? 1
                    : 2,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.archiveAttachments),
                items: [
                  DropdownMenuItem(value: 0, child: Text(s.archiveAny)),
                  DropdownMenuItem(
                    value: 1,
                    child: Text(s.archiveWithAttachments),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text(s.archiveWithoutAttachments),
                  ),
                ],
                onChanged: _working
                    ? null
                    : (value) => setState(
                        () => _hasAttachments = value == 0 ? null : value == 1,
                      ),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: DropdownButtonFormField<MailArchiveSort>(
                key: ValueKey('archive-sort-${_sort.name}'),
                initialValue: _sort,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.archiveSort),
                items: [
                  DropdownMenuItem(
                    value: MailArchiveSort.archivedNewest,
                    child: Text(s.archiveNewestStored),
                  ),
                  DropdownMenuItem(
                    value: MailArchiveSort.sentNewest,
                    child: Text(s.archiveNewestSent),
                  ),
                  DropdownMenuItem(
                    value: MailArchiveSort.sentOldest,
                    child: Text(s.archiveOldestSent),
                  ),
                  DropdownMenuItem(
                    value: MailArchiveSort.subject,
                    child: Text(s.subject),
                  ),
                ],
                onChanged: _working
                    ? null
                    : (value) => setState(
                        () => _sort = value ?? MailArchiveSort.archivedNewest,
                      ),
              ),
            ),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.archiveSubfolders),
          value: _includeSubfolders,
          onChanged: _working
              ? null
              : (value) => setState(() => _includeSubfolders = value ?? true),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _ready ? _resetFilters : null,
            child: Text(s.archiveClearFilters),
          ),
        ),
      ],
    );
  }

  Widget _content(double width) {
    if (_store == null) return const SizedBox.shrink();
    if (width < 900) {
      return _selected == null ? _results() : _preview(compact: true);
    }
    return Row(
      children: [
        SizedBox(width: width * .38, child: _results()),
        const VerticalDivider(width: 1),
        Expanded(child: _preview(compact: false)),
      ],
    );
  }

  Widget _results() {
    final page = _page;
    return Column(
      children: [
        if (page != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  key: const ValueKey('archive-previous'),
                  tooltip: s.archivePrevious,
                  onPressed: _ready && !_searching && page.offset > 0
                      ? () => _search(
                          request: _request.page(
                            offset: (page.offset - _request.limit).clamp(
                              0,
                              page.total,
                            ),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  s.archivePage(
                    page.hits.isEmpty ? 0 : page.offset + 1,
                    page.offset + page.hits.length,
                    page.total,
                  ),
                  key: const ValueKey('archive-page-count'),
                ),
                IconButton(
                  key: const ValueKey('archive-next'),
                  tooltip: s.archiveNext,
                  onPressed: _ready && !_searching && page.hasMore
                      ? () => _search(
                          request: _request.page(
                            offset: page.offset + page.hits.length,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        Expanded(
          child: page == null || page.hits.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _searching ? s.archiveWorking : s.archiveNoResults,
                    ),
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('archive-results'),
                  itemCount: page.hits.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final hit = page.hits[index];
                    final envelope = hit.entry.envelope;
                    return Material(
                      color: _selected?.entry.id == hit.entry.id
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Colors.transparent,
                      child: InkWell(
                        key: ValueKey('archive-hit-${hit.entry.id}'),
                        onTap: _ready ? () => _select(hit) : null,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                envelope.subject.isEmpty
                                    ? s.archiveNoSubject
                                    : envelope.subject,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                envelope.from
                                    .map(
                                      (address) =>
                                          address.displayName ??
                                          address.address,
                                    )
                                    .join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _dateText(envelope.sentAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (hit.preview.isNotEmpty)
                                Text(
                                  hit.preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _preview({required bool compact}) {
    final selected = _selected;
    if (selected == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(s.noMessage),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (compact)
                TextButton.icon(
                  key: const ValueKey('archive-back'),
                  onPressed: () {
                    final previous = _reader;
                    setState(() {
                      _selected = null;
                      _reader = null;
                      _previewGeneration++;
                      _previewLoading = false;
                    });
                    _retire(previous);
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: Text(s.archiveBack),
                ),
              TextButton.icon(
                key: const ValueKey('archive-export'),
                onPressed: _ready && !_searching ? _export : null,
                icon: const Icon(Icons.save_alt),
                label: Text(s.archiveExport),
              ),
            ],
          ),
        ),
        if (_origins.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _origins
                  .map((origin) => '${origin.source} · ${origin.folder}')
                  .join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (selected.entry.indexTruncated ||
            selected.entry.attachmentTextSkipped > 0)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(s.archiveLimitedIndex),
          ),
        if (_previewError != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _previewError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _previewLoading
              ? const Center(child: CircularProgressIndicator())
              : _reader == null
              ? const SizedBox.shrink()
              : MailMessageView(
                  controller: _reader!,
                  compact: compact,
                  textDirection: s.language == StudioLanguage.ar
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                ),
        ),
      ],
    );
  }
}

final class _ImportOptions {
  const _ImportOptions(
    this.source,
    this.folder,
    this.indexAttachments,
    this.dialect, [
    this.recursive = true,
  ]);
  final String source;
  final String folder;
  final bool indexAttachments;
  final MailMboxDialect dialect;
  final bool recursive;
}

class _ArchiveImportDialog extends StatefulWidget {
  const _ArchiveImportDialog({
    required this.strings,
    required this.indexAttachments,
    this.directory = false,
  });
  final StudioStrings strings;
  final bool indexAttachments;
  final bool directory;
  @override
  State<_ArchiveImportDialog> createState() => _ArchiveImportDialogState();
}

class _ArchiveImportDialogState extends State<_ArchiveImportDialog> {
  late final TextEditingController _source;
  final _folder = TextEditingController(text: '/');
  late bool _attachments;
  MailMboxDialect _dialect = MailMboxDialect.mboxrd;
  bool _recursive = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _source = TextEditingController(text: widget.strings.archiveLocalFiles);
    _attachments = widget.indexAttachments;
  }

  @override
  void dispose() {
    _source.dispose();
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Directionality(
      textDirection: s.language == StudioLanguage.ar
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          widget.directory ? s.archiveImportDirectory : s.archiveImport,
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.archiveImportHelp),
              if (widget.directory) ...[
                const SizedBox(height: 8),
                Text(s.archiveDirectoryHelp),
                CheckboxListTile(
                  key: const ValueKey('archive-import-recursive'),
                  contentPadding: EdgeInsets.zero,
                  value: _recursive,
                  title: Text(s.archiveSubfolders),
                  onChanged: (value) =>
                      setState(() => _recursive = value ?? true),
                ),
              ],
              TextField(
                key: const ValueKey('archive-import-source'),
                controller: _source,
                maxLength: 256,
                decoration: InputDecoration(labelText: s.archiveSource),
              ),
              TextField(
                key: const ValueKey('archive-import-folder'),
                controller: _folder,
                maxLength: 256,
                decoration: InputDecoration(labelText: s.archiveFolder),
              ),
              DropdownButtonFormField<MailMboxDialect>(
                key: const ValueKey('archive-mbox-dialect'),
                initialValue: _dialect,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.archiveMboxFormat),
                items: [
                  for (final dialect in MailMboxDialect.values)
                    DropdownMenuItem(value: dialect, child: Text(dialect.name)),
                ],
                onChanged: (value) =>
                    setState(() => _dialect = value ?? MailMboxDialect.mboxrd),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  s.archiveMboxHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('archive-import-attachments'),
                contentPadding: EdgeInsets.zero,
                value: _attachments,
                title: Text(s.archiveIndexAttachmentText),
                subtitle: Text(s.archiveAttachmentHelp),
                onChanged: (value) =>
                    setState(() => _attachments = value ?? false),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.archiveCancel),
          ),
          FilledButton(
            key: const ValueKey('archive-choose-files'),
            onPressed: () {
              if (_source.text.trim().isEmpty ||
                  _folder.text.trim().isEmpty ||
                  RegExp(
                    r'[\x00-\x1f\x7f]',
                  ).hasMatch('${_source.text}${_folder.text}')) {
                setState(
                  () => _error = s.archiveProblem(MailProblemCode.invalidInput),
                );
                return;
              }
              Navigator.of(context).pop(
                _ImportOptions(
                  _source.text.trim(),
                  _folder.text.trim(),
                  _attachments,
                  _dialect,
                  _recursive,
                ),
              );
            },
            child: Text(
              widget.directory
                  ? s.archiveChooseDirectory
                  : s.archiveChooseFiles,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveSearchNameDialog extends StatefulWidget {
  const _ArchiveSearchNameDialog({required this.strings});
  final StudioStrings strings;
  @override
  State<_ArchiveSearchNameDialog> createState() =>
      _ArchiveSearchNameDialogState();
}

class _ArchiveSearchNameDialogState extends State<_ArchiveSearchNameDialog> {
  final _name = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.strings.archiveSaveSearch),
    content: TextField(
      key: const ValueKey('archive-search-name'),
      controller: _name,
      autofocus: true,
      maxLength: 128,
      decoration: InputDecoration(labelText: widget.strings.archiveSearchName),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(widget.strings.archiveCancel),
      ),
      FilledButton(
        key: const ValueKey('archive-confirm-save-search'),
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_name.text.trim()),
        child: Text(widget.strings.save),
      ),
    ],
  );
}
