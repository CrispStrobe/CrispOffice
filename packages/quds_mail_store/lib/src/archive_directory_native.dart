import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';

/// Resource bounds for a streaming filesystem walk. The root itself counts as
/// one inspected entry. Bytes count accepted EML/MBOX file sizes, not directory
/// entries, unsupported files, or files rejected by a per-file limit.
final class MailArchiveDirectoryLimits {
  const MailArchiveDirectoryLimits({
    this.maxEntries = 100000,
    this.maxFiles = 10000,
    this.maxDepth = 32,
    this.maxPendingDirectories = 64,
    this.maxTotalFileBytes = 4 * 1024 * 1024 * 1024,
    this.maxEmlBytes = 32 * 1024 * 1024,
    this.maxPathCodeUnits = 4096,
    this.maxRootComponents = 128,
  });

  final int maxEntries;
  final int maxFiles;

  /// Maximum nested directory depth. The selected root has depth zero.
  final int maxDepth;

  /// Maximum open directory iterators in the depth-first traversal.
  final int maxPendingDirectories;
  final int maxTotalFileBytes;
  final int maxEmlBytes;

  /// Applies separately to absolute paths and portable relative metadata.
  final int maxPathCodeUnits;
  final int maxRootComponents;

  bool get isValid =>
      maxEntries > 0 &&
      maxFiles >= 0 &&
      maxDepth >= 0 &&
      maxPendingDirectories > 0 &&
      maxTotalFileBytes >= 0 &&
      maxEmlBytes >= 0 &&
      maxPathCodeUnits > 0 &&
      maxRootComponents > 0;
}

enum MailArchiveDirectoryFileKind { eml, mbox }

enum MailArchiveDirectoryOutcome {
  file,
  directory,
  skipped,
  error,
  limited,
  completed,
  cancelled,
}

/// Diagnostics deliberately exclude operating-system messages and paths.
enum MailArchiveDirectoryIssue {
  invalidLimits,
  invalidPath,
  inaccessible,
  rootNotDirectory,
  symbolicLink,
  unsupportedFile,
  nonRegularFile,
  recursionDisabled,
  invalidMetadata,
  entryLimit,
  fileLimit,
  depthLimit,
  pendingDirectoryLimit,
  totalBytesLimit,
  emlBytesLimit,
  pathLimit,
  rootComponentLimit,
}

final class MailArchiveDirectoryProgress {
  const MailArchiveDirectoryProgress({
    required this.entriesInspected,
    required this.directoriesVisited,
    required this.filesAccepted,
    required this.acceptedBytes,
    required this.skippedEntries,
    required this.errorEntries,
    required this.limitedEntries,
  });

  final int entriesInspected;
  final int directoriesVisited;
  final int filesAccepted;
  final int acceptedBytes;
  final int skippedEntries;
  final int errorEntries;
  final int limitedEntries;
}

/// One inspected file/directory, explicit rejection, or terminal walk outcome.
///
/// [absolutePath] is present only for validated portable metadata. It is an
/// explicit filesystem input for the caller, never diagnostic text. For a file,
/// [relativePath] is its root-relative path with '/' separators and
/// [relativeFolder] is its parent folder ('' for files directly in the root).
/// Names are never rewritten: backslashes, control characters, and traversal
/// components are rejected to avoid conflating distinct provenance paths.
///
/// A [MailArchiveDirectoryOutcome.completed] walk can contain rejected entries;
/// inspect [progress] to report
/// partial results. File/depth/path/iterator limits reject individual entries;
/// entry-count, accepted-file-count and aggregate-byte limits stop the walk.
final class MailArchiveDirectoryEntry {
  const MailArchiveDirectoryEntry({
    required this.outcome,
    required this.progress,
    this.absolutePath,
    this.relativePath,
    this.relativeFolder,
    this.kind,
    this.byteLength,
    this.issue,
    this.terminal = false,
  });

  final MailArchiveDirectoryOutcome outcome;
  final MailArchiveDirectoryProgress progress;
  final String? absolutePath;
  final String? relativePath;
  final String? relativeFolder;
  final MailArchiveDirectoryFileKind? kind;
  final int? byteLength;
  final MailArchiveDirectoryIssue? issue;
  final bool terminal;

  @override
  String toString() =>
      'MailArchiveDirectoryEntry(${outcome.name}, '
      '${issue?.name ?? 'none'}, terminal=$terminal)';
}

/// Enumerate EML and MBOX files without loading a directory tree or file bytes.
///
/// The walk uses OS enumeration order and is not a stable filesystem snapshot.
/// Every directory iterator, including a paused ancestor, is closed when the
/// consumer cancels. Links are rejected, including links in the selected root's
/// ancestor components. Ancestors are rechecked before directory advancement
/// and before/after file metadata reads. Unsupported files remain visible as
/// skipped entries; their contents are never read.
///
/// Dart path APIs do not offer an atomic open-relative-to-directory operation.
/// These checks do not defend against hostile concurrent replacement between
/// a check and an OS call. The importing host must enforce its own bounded read
/// and revalidate a file before reading it; enumeration is not a read lease.
Stream<MailArchiveDirectoryEntry> enumerateMailArchiveDirectory(
  Directory root, {
  MailArchiveDirectoryLimits limits = const MailArchiveDirectoryLimits(),
  MailCancellationToken? cancellation,
  bool recursive = true,
}) async* {
  final walk = _DirectoryWalkProgress();
  final stack = <_DirectoryFrame>[];
  try {
    cancellation?.throwIfCancelled();
    if (!limits.isValid) {
      yield walk.event(
        MailArchiveDirectoryOutcome.error,
        issue: MailArchiveDirectoryIssue.invalidLimits,
        terminal: true,
      );
      return;
    }
    final rootProblem = _rootPathProblem(root.path, limits);
    if (rootProblem != null) {
      yield walk.event(
        _isMetadataLimit(rootProblem)
            ? MailArchiveDirectoryOutcome.limited
            : MailArchiveDirectoryOutcome.error,
        issue: rootProblem,
        terminal: true,
      );
      return;
    }
    final absoluteRoot = p.normalize(p.absolute(root.path));
    if (absoluteRoot.length > limits.maxPathCodeUnits ||
        p.split(absoluteRoot).length > limits.maxRootComponents) {
      yield walk.event(
        MailArchiveDirectoryOutcome.limited,
        issue: absoluteRoot.length > limits.maxPathCodeUnits
            ? MailArchiveDirectoryIssue.pathLimit
            : MailArchiveDirectoryIssue.rootComponentLimit,
        terminal: true,
      );
      return;
    }
    walk.entriesInspected++;
    final rootType = await _checkedType(absoluteRoot, cancellation);
    if (rootType.issue != null ||
        rootType.type != FileSystemEntityType.directory) {
      final issue =
          rootType.issue ?? MailArchiveDirectoryIssue.rootNotDirectory;
      yield walk.event(
        issue == MailArchiveDirectoryIssue.symbolicLink
            ? MailArchiveDirectoryOutcome.skipped
            : MailArchiveDirectoryOutcome.error,
        issue: issue,
        terminal: true,
      );
      return;
    }
    stack.add(_DirectoryFrame(absoluteRoot, '', 0));
    walk.directoriesVisited++;
    yield walk.event(
      MailArchiveDirectoryOutcome.directory,
      absolutePath: absoluteRoot,
      relativePath: '',
      relativeFolder: '',
    );

    while (stack.isNotEmpty) {
      // Also yield to timer/UI cancellation while traversing unsupported files.
      await Future<void>.delayed(Duration.zero);
      cancellation?.throwIfCancelled();
      final frame = stack.last;
      final directoryType = await _checkedType(
        frame.absolutePath,
        cancellation,
      );
      if (directoryType.issue != null ||
          directoryType.type != FileSystemEntityType.directory) {
        final issue =
            directoryType.issue ?? MailArchiveDirectoryIssue.invalidMetadata;
        await stack.removeLast().close();
        yield walk.event(
          issue == MailArchiveDirectoryIssue.symbolicLink
              ? MailArchiveDirectoryOutcome.skipped
              : MailArchiveDirectoryOutcome.error,
          issue: issue,
          absolutePath: frame.absolutePath,
          relativePath: frame.relativePath,
          relativeFolder: _parentRelative(frame.relativePath),
        );
        continue;
      }

      bool hasNext;
      try {
        hasNext = await frame.iterator.moveNext();
      } on FileSystemException {
        cancellation?.throwIfCancelled();
        await stack.removeLast().close();
        yield walk.event(
          MailArchiveDirectoryOutcome.error,
          issue: MailArchiveDirectoryIssue.inaccessible,
          absolutePath: frame.absolutePath,
          relativePath: frame.relativePath,
          relativeFolder: _parentRelative(frame.relativePath),
        );
        continue;
      }
      cancellation?.throwIfCancelled();
      if (!hasNext) {
        await stack.removeLast().close();
        continue;
      }
      // Pull at most one extra descriptor to distinguish a fully enumerated
      // directory from a stopped walk. Do not inspect it after the entry cap.
      if (walk.entriesInspected >= limits.maxEntries) {
        yield walk.event(
          MailArchiveDirectoryOutcome.limited,
          issue: MailArchiveDirectoryIssue.entryLimit,
          terminal: true,
        );
        return;
      }
      walk.entriesInspected++;
      final name = p.basename(frame.iterator.current.path);
      if (!_validComponent(name)) {
        yield walk.event(
          MailArchiveDirectoryOutcome.error,
          issue: MailArchiveDirectoryIssue.invalidMetadata,
        );
        continue;
      }
      final absoluteSeparator = frame.absolutePath.endsWith(p.separator)
          ? 0
          : 1;
      final relativeSeparator = frame.relativePath.isEmpty ? 0 : 1;
      if (name.length + frame.absolutePath.length + absoluteSeparator >
              limits.maxPathCodeUnits ||
          name.length + frame.relativePath.length + relativeSeparator >
              limits.maxPathCodeUnits) {
        yield walk.event(
          MailArchiveDirectoryOutcome.limited,
          issue: MailArchiveDirectoryIssue.pathLimit,
        );
        continue;
      }
      final absolutePath = p.join(frame.absolutePath, name);
      final relativePath = frame.relativePath.isEmpty
          ? name
          : '${frame.relativePath}/$name';
      final type = await _checkedType(absolutePath, cancellation);
      if (type.issue != null) {
        yield walk.event(
          type.issue == MailArchiveDirectoryIssue.symbolicLink
              ? MailArchiveDirectoryOutcome.skipped
              : MailArchiveDirectoryOutcome.error,
          issue: type.issue,
          absolutePath: absolutePath,
          relativePath: relativePath,
          relativeFolder: frame.relativePath,
        );
        continue;
      }
      if (type.type == FileSystemEntityType.directory) {
        final issue = !recursive
            ? MailArchiveDirectoryIssue.recursionDisabled
            : frame.depth >= limits.maxDepth
            ? MailArchiveDirectoryIssue.depthLimit
            : stack.length >= limits.maxPendingDirectories
            ? MailArchiveDirectoryIssue.pendingDirectoryLimit
            : null;
        if (issue != null) {
          yield walk.event(
            issue == MailArchiveDirectoryIssue.recursionDisabled
                ? MailArchiveDirectoryOutcome.skipped
                : MailArchiveDirectoryOutcome.limited,
            issue: issue,
            absolutePath: absolutePath,
            relativePath: relativePath,
            relativeFolder: frame.relativePath,
          );
          continue;
        }
        stack.add(_DirectoryFrame(absolutePath, relativePath, frame.depth + 1));
        walk.directoriesVisited++;
        yield walk.event(
          MailArchiveDirectoryOutcome.directory,
          absolutePath: absolutePath,
          relativePath: relativePath,
          relativeFolder: frame.relativePath,
        );
        continue;
      }
      if (type.type != FileSystemEntityType.file) {
        yield walk.event(
          MailArchiveDirectoryOutcome.skipped,
          issue: MailArchiveDirectoryIssue.nonRegularFile,
          absolutePath: absolutePath,
          relativePath: relativePath,
          relativeFolder: frame.relativePath,
        );
        continue;
      }
      final kind = switch (p.extension(name).toLowerCase()) {
        '.eml' => MailArchiveDirectoryFileKind.eml,
        '.mbox' => MailArchiveDirectoryFileKind.mbox,
        _ => null,
      };
      if (kind == null) {
        yield walk.event(
          MailArchiveDirectoryOutcome.skipped,
          issue: MailArchiveDirectoryIssue.unsupportedFile,
          absolutePath: absolutePath,
          relativePath: relativePath,
          relativeFolder: frame.relativePath,
        );
        continue;
      }
      if (walk.filesAccepted >= limits.maxFiles) {
        yield walk.event(
          MailArchiveDirectoryOutcome.limited,
          issue: MailArchiveDirectoryIssue.fileLimit,
          absolutePath: absolutePath,
          relativePath: relativePath,
          relativeFolder: frame.relativePath,
          kind: kind,
          terminal: true,
        );
        return;
      }
      final FileStat stat;
      try {
        stat = await FileStat.stat(absolutePath);
      } on FileSystemException {
        cancellation?.throwIfCancelled();
        yield walk.event(
          MailArchiveDirectoryOutcome.error,
          issue: MailArchiveDirectoryIssue.inaccessible,
          absolutePath: absolutePath,
          relativePath: relativePath,
          relativeFolder: frame.relativePath,
          kind: kind,
        );
        continue;
      }
      final checked = await _checkedType(absolutePath, cancellation);
      if (checked.issue != null ||
          checked.type != FileSystemEntityType.file ||
          stat.type != FileSystemEntityType.file ||
          stat.size < 0) {
        final issue =
            checked.issue ?? MailArchiveDirectoryIssue.invalidMetadata;
        yield walk.event(
          issue == MailArchiveDirectoryIssue.symbolicLink
              ? MailArchiveDirectoryOutcome.skipped
              : MailArchiveDirectoryOutcome.error,
          issue: issue,
          absolutePath: absolutePath,
          relativePath: relativePath,
          relativeFolder: frame.relativePath,
          kind: kind,
        );
        continue;
      }
      final issue =
          kind == MailArchiveDirectoryFileKind.eml &&
              stat.size > limits.maxEmlBytes
          ? MailArchiveDirectoryIssue.emlBytesLimit
          : stat.size > limits.maxTotalFileBytes - walk.acceptedBytes
          ? MailArchiveDirectoryIssue.totalBytesLimit
          : null;
      if (issue != null) {
        final terminal = issue == MailArchiveDirectoryIssue.totalBytesLimit;
        yield walk.event(
          MailArchiveDirectoryOutcome.limited,
          issue: issue,
          absolutePath: absolutePath,
          relativePath: relativePath,
          relativeFolder: frame.relativePath,
          kind: kind,
          byteLength: stat.size,
          terminal: terminal,
        );
        if (terminal) return;
        continue;
      }
      walk.filesAccepted++;
      walk.acceptedBytes += stat.size;
      yield walk.event(
        MailArchiveDirectoryOutcome.file,
        absolutePath: absolutePath,
        relativePath: relativePath,
        relativeFolder: frame.relativePath,
        kind: kind,
        byteLength: stat.size,
      );
    }
    cancellation?.throwIfCancelled();
    yield walk.event(MailArchiveDirectoryOutcome.completed, terminal: true);
  } on MailCancelled {
    yield walk.event(MailArchiveDirectoryOutcome.cancelled, terminal: true);
  } on FileSystemException {
    yield walk.event(
      MailArchiveDirectoryOutcome.error,
      issue: MailArchiveDirectoryIssue.inaccessible,
      terminal: true,
    );
  } finally {
    for (final frame in stack.reversed) {
      await frame.close();
    }
  }
}

MailArchiveDirectoryIssue? _rootPathProblem(
  String path,
  MailArchiveDirectoryLimits limits,
) {
  if (path.length > limits.maxPathCodeUnits) {
    return MailArchiveDirectoryIssue.pathLimit;
  }
  if (path.isEmpty || _containsControl(path)) {
    return MailArchiveDirectoryIssue.invalidPath;
  }
  final components = p.split(path);
  if (components.length > limits.maxRootComponents) {
    return MailArchiveDirectoryIssue.rootComponentLimit;
  }
  if (components.contains('..') ||
      (!Platform.isWindows && path.contains(r'\'))) {
    return MailArchiveDirectoryIssue.invalidPath;
  }
  return null;
}

bool _containsControl(String value) => value.codeUnits.any(
  (unit) =>
      unit < 0x20 ||
      (unit >= 0x7f && unit <= 0x9f) ||
      (unit >= 0x202a && unit <= 0x202e) ||
      (unit >= 0x2066 && unit <= 0x2069),
);

bool _validComponent(String name) =>
    name.isNotEmpty &&
    name != '.' &&
    name != '..' &&
    !name.contains('/') &&
    !name.contains(r'\') &&
    !_containsControl(name);

bool _isMetadataLimit(MailArchiveDirectoryIssue issue) =>
    issue == MailArchiveDirectoryIssue.pathLimit ||
    issue == MailArchiveDirectoryIssue.rootComponentLimit;

String _parentRelative(String path) {
  final separator = path.lastIndexOf('/');
  return separator < 0 ? '' : path.substring(0, separator);
}

Future<({FileSystemEntityType? type, MailArchiveDirectoryIssue? issue})>
_checkedType(String path, MailCancellationToken? cancellation) async {
  final components = p.split(path);
  var current = components.first;
  FileSystemEntityType? type;
  for (var index = 0; index < components.length; index++) {
    cancellation?.throwIfCancelled();
    if (index > 0) current = p.join(current, components[index]);
    try {
      // Keep metadata IO asynchronous so a large tree cannot block the UI.
      // ignore: avoid_slow_async_io
      type = await FileSystemEntity.type(current, followLinks: false);
    } on FileSystemException {
      cancellation?.throwIfCancelled();
      return (type: null, issue: MailArchiveDirectoryIssue.inaccessible);
    }
    cancellation?.throwIfCancelled();
    if (type == FileSystemEntityType.link) {
      return (type: null, issue: MailArchiveDirectoryIssue.symbolicLink);
    }
    if (type == FileSystemEntityType.notFound) {
      return (type: null, issue: MailArchiveDirectoryIssue.inaccessible);
    }
    if (index < components.length - 1 &&
        type != FileSystemEntityType.directory) {
      return (type: null, issue: MailArchiveDirectoryIssue.invalidMetadata);
    }
  }
  return (type: type, issue: null);
}

final class _DirectoryFrame {
  _DirectoryFrame(this.absolutePath, this.relativePath, this.depth)
    : iterator = StreamIterator(
        Directory(absolutePath).list(followLinks: false),
      );

  final String absolutePath;
  final String relativePath;
  final int depth;
  final StreamIterator<FileSystemEntity> iterator;

  Future<void> close() async {
    try {
      await iterator.cancel();
    } on FileSystemException {
      // No mutation occurred. Cancellation cleanup cannot send a diagnostic to
      // an already-cancelled consumer; never leak an OS exception containing a
      // filesystem path from cleanup.
    }
  }
}

final class _DirectoryWalkProgress {
  var entriesInspected = 0;
  var directoriesVisited = 0;
  var filesAccepted = 0;
  var acceptedBytes = 0;
  var skippedEntries = 0;
  var errorEntries = 0;
  var limitedEntries = 0;

  MailArchiveDirectoryEntry event(
    MailArchiveDirectoryOutcome outcome, {
    String? absolutePath,
    String? relativePath,
    String? relativeFolder,
    MailArchiveDirectoryFileKind? kind,
    int? byteLength,
    MailArchiveDirectoryIssue? issue,
    bool terminal = false,
  }) {
    switch (outcome) {
      case MailArchiveDirectoryOutcome.skipped:
        skippedEntries++;
      case MailArchiveDirectoryOutcome.error:
        errorEntries++;
      case MailArchiveDirectoryOutcome.limited:
        limitedEntries++;
      default:
        break;
    }
    return MailArchiveDirectoryEntry(
      outcome: outcome,
      absolutePath: absolutePath,
      relativePath: relativePath,
      relativeFolder: relativeFolder,
      kind: kind,
      byteLength: byteLength,
      issue: issue,
      terminal: terminal,
      progress: MailArchiveDirectoryProgress(
        entriesInspected: entriesInspected,
        directoriesVisited: directoriesVisited,
        filesAccepted: filesAccepted,
        acceptedBytes: acceptedBytes,
        skippedEntries: skippedEntries,
        errorEntries: errorEntries,
        limitedEntries: limitedEntries,
      ),
    );
  }
}
