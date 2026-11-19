import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_archive_host.dart';
import 'studio_mail_archive_strings.dart';
import 'studio_strings.dart';

/// Runs a selected, immutable mailbox against an archive owned by the host.
typedef StudioMailArchiveFolderRunner =
    Future<MailArchiveRunReport> Function(
      SqliteMailArchive archive,
      MailArchiveProfile profile, {
      MailCancellationToken? cancellation,
      MailArchiveProgressSink? onProgress,
    });

typedef StudioMailArchiveFolderOpener =
    Future<MailResult<SqliteMailArchive>> Function({
      MailArchiveDiagnostics? diagnostics,
    });

/// Injectable complete operation. A result retains all confirmed local commits.
typedef StudioMailArchiveFolderWriter =
    Future<MailArchiveRunReport> Function(
      MailArchiveProfile profile, {
      required MailCancellationToken cancellation,
      MailArchiveProgressSink? onProgress,
      required bool verboseDiagnostics,
    });

String _fingerprint(Object value) =>
    MailBytes(Uint8List.fromList(utf8.encode(jsonEncode(value)))).sha256;

/// Stable across account reconnects; never incorporates ephemeral session IDs.
String studioArchiveFolderProfileId(
  String backend,
  String source,
  String mailboxIdentity,
) => 'studio-mailbox:${_fingerprint([backend, source, mailboxIdentity])}';

/// Provider IDs may be opaque and very long. Hash only values that cannot fit
/// safely in the bounded provenance field, retaining ordinary readable IDs.
String studioArchiveSourceMessageId(String value) =>
    value.length <= 1024 && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)
    ? value
    : 'sha256:${_fingerprint(value)}';

void _safeDebug(String category, Map<String, Object> event) {
  try {
    debugPrint('mail_archive_$category ${jsonEncode(event)}');
  } on Object {
    // Diagnostic observers cannot change a committed archive result.
  }
}

MailArchiveRunReport _failedReport(
  MailProblem problem, {
  MailArchiveRunProgress? progress,
  required bool cancelled,
}) => MailArchiveRunReport(
  status: cancelled
      ? MailArchiveRunStatus.cancelled
      : (progress?.saved ?? 0) + (progress?.duplicates ?? 0) > 0
      ? MailArchiveRunStatus.partial
      : MailArchiveRunStatus.failed,
  pages: progress?.pages ?? 0,
  processed: progress?.processed ?? 0,
  saved: progress?.saved ?? 0,
  duplicates: progress?.duplicates ?? 0,
  failed: progress?.failed ?? 0,
  bytes: progress?.bytes ?? 0,
  elapsedMicroseconds: progress?.elapsedMicroseconds ?? 0,
  observerErrors: progress?.observerErrors ?? 0,
  failures: const [],
  droppedFailures: progress?.failed ?? 0,
  problem: problem,
);

/// Open, save source settings, archive, and close one owned connection. Profile
/// settings contain no credentials. Unexpected failures are sanitized, and a
/// late close failure never turns a committed report into an apparent retry.
Future<MailArchiveRunReport> archiveStudioMailFolder({
  required StudioMailArchiveFolderRunner runner,
  required MailArchiveProfile profile,
  required MailCancellationToken cancellation,
  MailArchiveProgressSink? onProgress,
  bool verboseDiagnostics = false,
  StudioMailArchiveFolderOpener? openArchive,
}) async {
  SqliteMailArchive? archive;
  MailArchiveRunProgress? progress;
  var runningProvider = false;
  try {
    cancellation.throwIfCancelled();
    if (profile.kind != MailArchiveProfileKind.mailbox ||
        profile.includeSubfolders) {
      return _failedReport(
        const MailProblem(MailProblemCode.unsupported),
        cancelled: false,
      );
    }
    final diagnostics = verboseDiagnostics
        ? MailArchiveDiagnostics(
            verbose: true,
            sink: (event) => _safeDebug('store', event.toJson()),
          )
        : null;
    final opened =
        await (openArchive?.call(diagnostics: diagnostics) ??
            openStudioMailSqliteArchive(diagnostics: diagnostics));
    if (opened case MailFailure(problem: final problem)) {
      return _failedReport(problem, cancelled: cancellation.isCancelled);
    }
    archive = (opened as MailSuccess<SqliteMailArchive>).value;
    cancellation.throwIfCancelled();
    final saved = await archive.saveProfile(profile);
    if (saved case MailFailure(problem: final problem)) {
      return _failedReport(problem, cancelled: cancellation.isCancelled);
    }
    cancellation.throwIfCancelled();
    runningProvider = true;
    return await runner(
      archive,
      profile,
      cancellation: cancellation,
      onProgress: (event) {
        progress = event;
        if (verboseDiagnostics) _safeDebug('run', event.toJson());
        onProgress?.call(event);
      },
    );
  } on MailCancelled {
    return _failedReport(
      const MailProblem(MailProblemCode.cancelled),
      progress: progress,
      cancelled: true,
    );
  } on Object {
    return _failedReport(
      MailProblem(
        runningProvider
            ? MailProblemCode.providerFailure
            : MailProblemCode.storageFailure,
      ),
      progress: progress,
      cancelled: cancellation.isCancelled,
    );
  } finally {
    try {
      await archive?.close();
    } on Object {
      if (verboseDiagnostics) {
        _safeDebug('close', {'problem': MailProblemCode.storageFailure.name});
      }
    }
  }
}

/// The dialog is a deliberate selected-folder action. Cancellation leaves it
/// visible until the operation returns its final committed counts.
class StudioArchiveFolderButton extends StatefulWidget {
  const StudioArchiveFolderButton({
    super.key,
    required this.strings,
    required this.source,
    required this.folder,
    required this.profileId,
    required this.sessionKey,
    required this.runner,
    this.writer,
    this.enabled = true,
    this.onDialogChanged,
  });

  final StudioStrings strings;
  final String source;
  final String folder;
  final String profileId;
  final Object sessionKey;
  final StudioMailArchiveFolderRunner runner;
  final StudioMailArchiveFolderWriter? writer;
  final bool enabled;
  final ValueChanged<bool>? onDialogChanged;

  @override
  State<StudioArchiveFolderButton> createState() =>
      _StudioArchiveFolderButtonState();
}

class _StudioArchiveFolderButtonState extends State<StudioArchiveFolderButton> {
  MailCancellationSource? _cancellation;
  bool _open = false;

  @override
  void didUpdateWidget(StudioArchiveFolderButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessionKey, widget.sessionKey) ||
        oldWidget.profileId != widget.profileId ||
        oldWidget.source != widget.source ||
        oldWidget.folder != widget.folder) {
      _cancellation?.cancel(MailCancellationReason.accountChanged);
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel(MailCancellationReason.disposed);
    super.dispose();
  }

  Future<void> _show() async {
    if (_open || !widget.enabled) return;
    final cancellation = MailCancellationSource();
    _cancellation = cancellation;
    final runner = widget.runner;
    final writer =
        widget.writer ??
        (
          profile, {
          required cancellation,
          onProgress,
          required verboseDiagnostics,
        }) => archiveStudioMailFolder(
          runner: runner,
          profile: profile,
          cancellation: cancellation,
          onProgress: onProgress,
          verboseDiagnostics: verboseDiagnostics,
        );
    final profile = MailArchiveProfile(
      id: widget.profileId,
      name: widget.folder.length <= 256
          ? widget.folder
          : String.fromCharCodes(widget.folder.runes.take(128)),
      source: widget.source,
      folder: widget.folder,
      kind: MailArchiveProfileKind.mailbox,
      includeSubfolders: false,
    );
    setState(() => _open = true);
    widget.onDialogChanged?.call(true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ArchiveFolderDialog(
          strings: widget.strings,
          profile: profile,
          writer: writer,
          cancellation: cancellation,
        ),
      );
    } finally {
      cancellation.cancel(MailCancellationReason.disposed);
      if (identical(_cancellation, cancellation)) _cancellation = null;
      if (mounted) {
        setState(() => _open = false);
        widget.onDialogChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('archive-selected-folder'),
    tooltip: widget.strings.archiveSelectedFolder,
    onPressed: widget.enabled && !_open ? _show : null,
    icon: const Icon(Icons.drive_folder_upload_outlined),
  );
}

class _ArchiveFolderDialog extends StatefulWidget {
  const _ArchiveFolderDialog({
    required this.strings,
    required this.profile,
    required this.writer,
    required this.cancellation,
  });
  final StudioStrings strings;
  final MailArchiveProfile profile;
  final StudioMailArchiveFolderWriter writer;
  final MailCancellationSource cancellation;

  @override
  State<_ArchiveFolderDialog> createState() => _ArchiveFolderDialogState();
}

class _ArchiveFolderDialogState extends State<_ArchiveFolderDialog> {
  bool _indexAttachments = false;
  bool _verbose = false;
  bool _running = false;
  bool _cancelRequested = false;
  bool _started = false;
  MailArchiveRunProgress? _progress;
  MailArchiveRunReport? _report;
  final _logs = <String>[];
  StudioStrings get s => widget.strings;

  @override
  void dispose() {
    widget.cancellation.cancel(MailCancellationReason.disposed);
    super.dispose();
  }

  Future<void> _start() async {
    if (_started) return;
    final initial = widget.profile;
    final profile = MailArchiveProfile(
      id: initial.id,
      name: initial.name,
      source: initial.source,
      folder: initial.folder,
      kind: MailArchiveProfileKind.mailbox,
      includeSubfolders: false,
      indexAttachmentText: _indexAttachments,
    );
    setState(() {
      _started = true;
      _running = true;
    });
    final MailArchiveRunReport report;
    try {
      widget.cancellation.token.throwIfCancelled();
      report = await widget.writer(
        profile,
        cancellation: widget.cancellation.token,
        verboseDiagnostics: _verbose,
        onProgress: (progress) {
          if (!mounted || !_running) return;
          setState(() {
            _progress = progress;
            if (_verbose) {
              _logs.add(jsonEncode(progress.toJson()));
              if (_logs.length > 60) _logs.removeAt(0);
            }
          });
        },
      );
    } on MailCancelled {
      if (!mounted) return;
      _finish(
        _failedReport(
          const MailProblem(MailProblemCode.cancelled),
          progress: _progress,
          cancelled: true,
        ),
      );
      return;
    } on Object {
      if (!mounted) return;
      _finish(
        _failedReport(
          const MailProblem(MailProblemCode.providerFailure),
          progress: _progress,
          cancelled: widget.cancellation.token.isCancelled,
        ),
      );
      return;
    }
    if (!mounted) return;
    _finish(report);
  }

  void _finish(MailArchiveRunReport report) => setState(() {
    _running = false;
    _report = report;
  });

  void _cancel() {
    if (!_running || _cancelRequested) return;
    widget.cancellation.cancel();
    setState(() => _cancelRequested = true);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final progress = _progress;
    return PopScope(
      canPop: !_running,
      child: Directionality(
        textDirection: s.language == StudioLanguage.ar
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: AlertDialog(
          scrollable: true,
          title: Text(s.archiveSelectedFolder),
          content: SizedBox(
            width: 540,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${s.archiveSource}: ${widget.profile.source}'),
                const SizedBox(height: 8),
                Text('${s.archiveFolder}: ${widget.profile.folder}'),
                const SizedBox(height: 12),
                Text(s.archiveFolderHelp),
                const SizedBox(height: 8),
                Text(
                  s.archiveFolderLimits,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                CheckboxListTile(
                  key: const ValueKey('archive-folder-attachment-text'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.archiveIndexAttachmentText),
                  subtitle: Text(s.archiveAttachmentHelp),
                  value: _indexAttachments,
                  onChanged: _started
                      ? null
                      : (value) =>
                            setState(() => _indexAttachments = value ?? false),
                ),
                CheckboxListTile(
                  key: const ValueKey('archive-folder-verbose'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.archiveDiagnostics),
                  subtitle: Text(s.archiveDiagnosticsHelp),
                  value: _verbose,
                  onChanged: _started
                      ? null
                      : (value) => setState(() => _verbose = value ?? false),
                ),
                if (_running) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    _cancelRequested
                        ? s.archiveFolderCancelling
                        : s.archiveWorking,
                  ),
                ],
                if (progress != null || report != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.archiveFolderCounts(
                      report?.saved ?? progress!.saved,
                      report?.duplicates ?? progress!.duplicates,
                      report?.failed ?? progress!.failed,
                      report?.pages ?? progress!.pages,
                      report?.bytes ?? progress!.bytes,
                    ),
                    key: const ValueKey('archive-folder-counts'),
                  ),
                ],
                if (report != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.archiveFolderStatus(report.status),
                    key: const ValueKey('archive-folder-status'),
                  ),
                  if (report.problem != null)
                    Text(s.archiveProblem(report.problem!.code)),
                  if (report.failures.isNotEmpty || report.droppedFailures > 0)
                    ExpansionTile(
                      key: const ValueKey('archive-folder-failures'),
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        s.archiveFolderItemFailures(
                          report.failures.length,
                          report.droppedFailures,
                        ),
                      ),
                      children: [
                        for (final failure in report.failures)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              s.archiveFolderFailure(
                                failure.ordinal,
                                failure.stage,
                              ),
                            ),
                            subtitle: Text(s.archiveProblem(failure.code)),
                          ),
                      ],
                    ),
                ],
                if (_logs.isNotEmpty)
                  ExpansionTile(
                    key: const ValueKey('archive-folder-log-panel'),
                    title: Text(s.archiveDiagnostics),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      SelectableText(
                        _logs.join('\n'),
                        key: const ValueKey('archive-folder-log'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            if (_running)
              TextButton(
                key: const ValueKey('archive-folder-cancel'),
                onPressed: _cancelRequested ? null : _cancel,
                child: Text(s.archiveCancel),
              )
            else
              TextButton(
                key: const ValueKey('archive-folder-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(s.close),
              ),
            if (!_started)
              FilledButton(
                key: const ValueKey('archive-folder-start'),
                onPressed: _start,
                child: Text(s.archiveFolderStart),
              ),
          ],
        ),
      ),
    );
  }
}
