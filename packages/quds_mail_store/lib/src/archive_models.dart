import 'package:quds_mail_core/quds_mail_core.dart';

/// Bounds apply before allocation and mutation. Physical disk errors remain
/// authoritative; these logical limits do not reserve disk space.
final class MailArchiveLimits {
  const MailArchiveLimits({
    this.maxMessageBytes = 32 * 1024 * 1024,
    this.maxArchiveBytes = 1024 * 1024 * 1024,
    this.maxMessages = 100000,
    this.maxOrigins = 200000,
    this.maxMetadataCodeUnits = 2 * 1024 * 1024,
    this.maxIndexCodeUnits = 256 * 1024,
    this.maxAttachmentTextBytes = 1024 * 1024,
    this.maxPageSize = 200,
    this.maxSavedSearches = 100,
    this.maxProfiles = 100,
  });

  final int maxMessageBytes;
  final int maxArchiveBytes;
  final int maxMessages;
  final int maxOrigins;
  final int maxMetadataCodeUnits;
  final int maxIndexCodeUnits;
  final int maxAttachmentTextBytes;
  final int maxPageSize;
  final int maxSavedSearches;
  final int maxProfiles;

  bool get isValid =>
      maxMessageBytes > 0 &&
      maxArchiveBytes >= maxMessageBytes &&
      maxMessages > 0 &&
      maxOrigins >= maxMessages &&
      maxMetadataCodeUnits > 0 &&
      maxIndexCodeUnits > 0 &&
      maxAttachmentTextBytes > 0 &&
      maxPageSize > 0 &&
      maxPageSize <= 1000 &&
      maxSavedSearches > 0 &&
      maxProfiles > 0;
}

/// Provenance is separate from content: the same bytes may occur in multiple
/// sources/folders. These values are display metadata, never filesystem paths.
final class MailArchiveOrigin {
  const MailArchiveOrigin({
    required this.source,
    this.folder = '/',
    this.sourceMessageId = '',
  });

  final String source;
  final String folder;
  final String sourceMessageId;
}

final class MailArchiveEntry {
  const MailArchiveEntry({
    required this.id,
    required this.envelope,
    required this.archivedAt,
    required this.byteLength,
    required this.attachmentCount,
    required this.indexTruncated,
    required this.attachmentTextIndexed,
    required this.attachmentTextSkipped,
  });

  /// SHA-256 of the exact original MIME bytes, not the Message-ID header.
  final String id;
  final MailEnvelope envelope;
  final DateTime archivedAt;
  final int byteLength;
  final int attachmentCount;
  final bool indexTruncated;
  final int attachmentTextIndexed;
  final int attachmentTextSkipped;
}

final class MailArchiveImportResult {
  const MailArchiveImportResult({
    required this.entry,
    required this.duplicate,
    required this.originAdded,
    int? originsAdded,
  }) : originsAdded = originsAdded ?? (originAdded ? 1 : 0);
  final MailArchiveEntry entry;
  final bool duplicate;
  final bool originAdded;

  /// Newly committed provenance records. All requested origins are atomic with
  /// the original and index; existing origins do not increase this count.
  final int originsAdded;
}

enum MailArchiveSort { archivedNewest, sentNewest, sentOldest, subject }

/// Date lower bounds are inclusive and upper bounds exclusive. Size bounds are
/// inclusive bytes. Unknown sent dates do not match a sent-date constraint.
final class MailArchiveSearchRequest {
  const MailArchiveSearchRequest({
    this.query = '',
    this.source,
    this.folder,
    this.includeSubfolders = true,
    this.sentSince,
    this.sentBefore,
    this.archivedSince,
    this.archivedBefore,
    this.minBytes,
    this.maxBytes,
    this.hasAttachments,
    this.sort = MailArchiveSort.archivedNewest,
    this.limit = 50,
    this.offset = 0,
  });

  final String query;
  final String? source;
  final String? folder;
  final bool includeSubfolders;
  final DateTime? sentSince;
  final DateTime? sentBefore;
  final DateTime? archivedSince;
  final DateTime? archivedBefore;
  final int? minBytes;
  final int? maxBytes;
  final bool? hasAttachments;
  final MailArchiveSort sort;
  final int limit;
  final int offset;

  MailArchiveSearchRequest page({required int offset, int? limit}) =>
      MailArchiveSearchRequest(
        query: query,
        source: source,
        folder: folder,
        includeSubfolders: includeSubfolders,
        sentSince: sentSince,
        sentBefore: sentBefore,
        archivedSince: archivedSince,
        archivedBefore: archivedBefore,
        minBytes: minBytes,
        maxBytes: maxBytes,
        hasAttachments: hasAttachments,
        sort: sort,
        limit: limit ?? this.limit,
        offset: offset,
      );
}

final class MailArchiveSearchHit {
  const MailArchiveSearchHit({required this.entry, required this.preview});
  final MailArchiveEntry entry;
  final String preview;
}

final class MailArchiveSearchPage {
  MailArchiveSearchPage({
    required List<MailArchiveSearchHit> hits,
    required this.total,
    required this.offset,
  }) : hits = List.unmodifiable(hits);

  final List<MailArchiveSearchHit> hits;
  final int total;
  final int offset;
  bool get hasMore => offset + hits.length < total;
}

final class MailArchiveSavedSearch {
  const MailArchiveSavedSearch({required this.name, required this.request});
  final String name;
  final MailArchiveSearchRequest request;
}

enum MailArchiveProfileKind { files, mailbox }

/// Reusable source settings, without credentials. Removing a profile never
/// removes archived messages or provenance. Scheduling belongs to the host.
final class MailArchiveProfile {
  const MailArchiveProfile({
    required this.id,
    required this.name,
    required this.source,
    this.kind = MailArchiveProfileKind.files,
    this.folder = '/',
    this.includeSubfolders = true,
    this.indexAttachmentText = false,
  });

  final String id;
  final String name;
  final String source;
  final MailArchiveProfileKind kind;
  final String folder;
  final bool includeSubfolders;
  final bool indexAttachmentText;
}

final class MailArchiveStats {
  const MailArchiveStats({
    required this.messages,
    required this.rawBytes,
    required this.indexedMessages,
    required this.origins,
  });
  final int messages;
  final int rawBytes;
  final int indexedMessages;
  final int origins;
}

enum MailArchiveIntegrityCode {
  rawHashMismatch,
  metadataHashMismatch,
  missingIndex,
  indexMismatch,
  missingOrigin,
  exceedsReadLimit,
}

final class MailArchiveIntegrityIssue {
  const MailArchiveIntegrityIssue({required this.id, required this.code});
  final String id;
  final MailArchiveIntegrityCode code;
}

final class MailArchiveMaintenancePage {
  MailArchiveMaintenancePage({
    required this.processed,
    required this.nextAfterId,
    required this.hasMore,
    List<MailArchiveIntegrityIssue> issues = const [],
  }) : issues = List.unmodifiable(issues);
  final int processed;
  final String? nextAfterId;
  final bool hasMore;
  final List<MailArchiveIntegrityIssue> issues;
}

/// Fixed events and numeric metrics only: no mail text, addresses, paths, SQL,
/// credentials, arbitrary exception messages or user search terms are logged.
enum MailArchiveOperation {
  open,
  archive,
  search,
  planExport,
  load,
  origins,
  statistics,
  saveSearch,
  listSearches,
  removeSearch,
  saveProfile,
  listProfiles,
  removeProfile,
  verify,
  rebuild,
  close,
}

enum MailArchivePhase { started, progress, completed, failed }

final class MailArchiveDiagnostic {
  const MailArchiveDiagnostic({
    required this.operationId,
    required this.operation,
    required this.phase,
    required this.elapsedMicroseconds,
    this.items = 0,
    this.bytes = 0,
    this.problem,
  });
  final int operationId;
  final MailArchiveOperation operation;
  final MailArchivePhase phase;
  final int elapsedMicroseconds;
  final int items;
  final int bytes;
  final MailProblemCode? problem;

  Map<String, Object> toJson() => {
    'operationId': operationId,
    'operation': operation.name,
    'phase': phase.name,
    'elapsedMicroseconds': elapsedMicroseconds,
    'items': items,
    'bytes': bytes,
    if (problem != null) 'problem': problem!.name,
  };
}

typedef MailArchiveLogSink = void Function(MailArchiveDiagnostic event);

final class MailArchiveDiagnostics {
  const MailArchiveDiagnostics({required this.sink, this.verbose = false});
  final MailArchiveLogSink sink;
  final bool verbose;
}

enum MailArchiveCheckpoint { afterContent, afterIndex, beforeCommit }

typedef MailArchiveFaultInjector =
    Future<void> Function(MailArchiveCheckpoint checkpoint);
