import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:quds_mail_core/quds_mail_core.dart';

import 'archive_models.dart';
import 'errors.dart';

/// Independent export bounds. A host may choose smaller limits without changing
/// the archive's storage quota. Manifest limits apply to encoded UTF-8 bytes.
final class MailArchiveExportLimits {
  const MailArchiveExportLimits({
    this.maxMessages = 10000,
    this.maxManifestBytes = 16 * 1024 * 1024,
    this.maxMessageBytes = 32 * 1024 * 1024,
    this.maxTotalBytes = 1024 * 1024 * 1024,
    this.maxOrigins = 20000,
    this.maxFailures = 50,
  });

  final int maxMessages;
  final int maxManifestBytes;
  final int maxMessageBytes;
  final int maxTotalBytes;
  final int maxOrigins;
  final int maxFailures;

  bool get isValid =>
      maxMessages > 0 &&
      maxMessages <= 100000 &&
      maxManifestBytes > 0 &&
      maxManifestBytes <= 64 * 1024 * 1024 &&
      maxMessageBytes > 0 &&
      maxMessageBytes <= 256 * 1024 * 1024 &&
      maxTotalBytes >= maxMessageBytes &&
      maxTotalBytes <= 4 * 1024 * 1024 * 1024 * 1024 &&
      maxOrigins > 0 &&
      maxOrigins <= 200000 &&
      maxFailures >= 0 &&
      maxFailures <= 1000;
}

/// One original and its provenance at the time the selection was frozen.
/// File names are derived from [id], never from subjects or origin labels.
final class MailArchiveExportItem {
  MailArchiveExportItem({
    required this.id,
    required this.byteLength,
    required List<MailArchiveOrigin> origins,
  }) : origins = List.unmodifiable(origins);

  final String id;
  final int byteLength;
  final List<MailArchiveOrigin> origins;
}

/// A bounded, immutable selection. Later imports cannot shift the export pages.
/// The profile identifies the local archive; it is not a credential or signature.
final class MailArchiveExportPlan {
  MailArchiveExportPlan({
    required this.profile,
    required this.createdAt,
    required List<MailArchiveExportItem> items,
  }) : items = List.unmodifiable(items);

  final MailProfileId profile;
  final DateTime createdAt;
  final List<MailArchiveExportItem> items;

  int get totalBytes => items.fold(0, (total, item) => total + item.byteLength);
}

enum MailArchiveExportStatus { completed, partial, cancelled, failed }

enum MailArchiveExportPhase { started, message, finished }

final class MailArchiveExportFailure {
  const MailArchiveExportFailure({required this.ordinal, required this.code});
  final int ordinal;
  final MailProblemCode code;
}

/// Progress deliberately excludes IDs, paths, addresses, subjects and queries.
final class MailArchiveExportProgress {
  const MailArchiveExportProgress({
    required this.phase,
    required this.planned,
    required this.written,
    required this.existing,
    required this.failed,
    required this.bytes,
    required this.elapsedMicroseconds,
    required this.observerErrors,
    this.status,
    this.problem,
  });

  final MailArchiveExportPhase phase;
  final int planned;
  final int written;
  final int existing;
  final int failed;

  /// Bytes of newly published and already present originals verified this run.
  final int bytes;
  final int elapsedMicroseconds;
  final int observerErrors;
  final MailArchiveExportStatus? status;
  final MailProblemCode? problem;

  int get processed => written + existing + failed;

  Map<String, Object> toJson() => {
    'phase': phase.name,
    'planned': planned,
    'written': written,
    'existing': existing,
    'failed': failed,
    'bytes': bytes,
    'elapsedMicroseconds': elapsedMicroseconds,
    'observerErrors': observerErrors,
    if (status != null) 'status': status!.name,
    if (problem != null) 'problem': problem!.name,
  };
}

typedef MailArchiveExportProgressSink =
    void Function(MailArchiveExportProgress progress);

final class MailArchiveExportReport {
  MailArchiveExportReport({
    required this.status,
    required this.planned,
    required this.written,
    required this.existing,
    required this.failed,
    required this.bytes,
    required this.elapsedMicroseconds,
    required this.observerErrors,
    required List<MailArchiveExportFailure> failures,
    required this.droppedFailures,
    this.directoryPath,
    this.problem,
  }) : failures = List.unmodifiable(failures);

  final MailArchiveExportStatus status;
  final int planned;
  final int written;
  final int existing;
  final int failed;
  final int bytes;
  final int elapsedMicroseconds;
  final int observerErrors;
  final List<MailArchiveExportFailure> failures;
  final int droppedFailures;

  /// User-facing destination, intentionally absent from progress diagnostics.
  /// A cancelled or partial export can be resumed from this directory.
  final String? directoryPath;
  final MailProblem? problem;

  int get processed => written + existing + failed;
}

Never _invalid([MailProblemCode code = MailProblemCode.invalidInput]) =>
    throw MailStoreStorageException(code);

bool _label(String value, {int max = 1024, bool empty = false}) =>
    (empty || value.trim().isNotEmpty) &&
    value.length <= max &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

bool _folder(String value) {
  if (!_label(value, max: 4096) || value.contains('\\')) return false;
  final parts = value.split('/');
  return !parts.any((part) => part == '.' || part == '..') &&
      value == '/${parts.where((part) => part.isNotEmpty).join('/')}';
}

Map<String, Object> _manifestEnvelope(
  Map<String, Object> payload,
  String digest,
) => {
  'format': 'crispoffice-mail-export',
  'version': 1,
  'payload': payload,
  'sha256': digest,
};

Map<String, Object> _payload(
  MailArchiveExportPlan plan,
  MailArchiveExportLimits limits,
) {
  if (!limits.isValid ||
      !_label(plan.profile.hostId) ||
      !_label(plan.profile.value)) {
    _invalid();
  }
  if (plan.items.length > limits.maxMessages) {
    _invalid(MailProblemCode.quotaExceeded);
  }
  final items = <Map<String, Object>>[];
  final payload = <String, Object>{
    'hostId': plan.profile.hostId,
    'profileId': plan.profile.value,
    'createdAtMs': plan.createdAt.toUtc().millisecondsSinceEpoch,
    'items': items,
  };
  final ids = <String>{};
  var total = 0, origins = 0;
  // Count exact JSON for bounded pieces before building a large payload. This
  // prevents oversized origin lists from first allocating an unbounded string.
  // The envelope already includes empty array brackets and a 64-byte digest;
  // add only array elements and the commas between them below.
  var manifestBytes = utf8
      .encode(jsonEncode(_manifestEnvelope(payload, '0' * 64)))
      .length;
  if (manifestBytes > limits.maxManifestBytes) {
    _invalid(MailProblemCode.quotaExceeded);
  }
  for (final item in plan.items) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(item.id) ||
        !ids.add(item.id) ||
        item.byteLength <= 0 ||
        item.origins.isEmpty) {
      _invalid();
    }
    total += item.byteLength;
    origins += item.origins.length;
    if (item.byteLength > limits.maxMessageBytes ||
        total > limits.maxTotalBytes ||
        origins > limits.maxOrigins) {
      _invalid(MailProblemCode.quotaExceeded);
    }
    final encodedOrigins = <Map<String, Object>>[];
    final encodedItem = <String, Object>{
      'id': item.id,
      'bytes': item.byteLength,
      'origins': encodedOrigins,
    };
    manifestBytes +=
        utf8.encode(jsonEncode(encodedItem)).length + (items.isEmpty ? 0 : 1);
    if (manifestBytes > limits.maxManifestBytes) {
      _invalid(MailProblemCode.quotaExceeded);
    }
    final uniqueOrigins = <String>{};
    for (final origin in item.origins) {
      if (!_label(origin.source) ||
          !_folder(origin.folder) ||
          !_label(origin.sourceMessageId, empty: true)) {
        _invalid();
      }
      final encoded = <String, Object>{
        'source': origin.source,
        'folder': origin.folder,
        'sourceMessageId': origin.sourceMessageId,
      };
      final text = jsonEncode(encoded);
      if (!uniqueOrigins.add(text)) _invalid();
      manifestBytes +=
          utf8.encode(text).length + (encodedOrigins.isEmpty ? 0 : 1);
      if (manifestBytes > limits.maxManifestBytes) {
        _invalid(MailProblemCode.quotaExceeded);
      }
      encodedOrigins.add(encoded);
    }
    items.add(encodedItem);
  }
  return payload;
}

/// Versioned manifest with an unsigned corruption-detection digest. Neither the
/// digest nor local provenance establishes authenticity or legal retention.
/// Throws a content-free storage exception on malformed or over-budget input.
String encodeMailArchiveExportManifest(
  MailArchiveExportPlan plan,
  MailArchiveExportLimits limits,
) {
  final payload = _payload(plan, limits);
  final result = jsonEncode(
    _manifestEnvelope(
      payload,
      crypto.sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
    ),
  );
  if (utf8.encode(result).length > limits.maxManifestBytes) {
    _invalid(MailProblemCode.quotaExceeded);
  }
  return result;
}

Map<String, Object?> _map(Object? value, Set<String> keys) {
  if (value is! Map<String, Object?> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    _invalid();
  }
  return value;
}

String _string(Object? value) {
  if (value is! String) _invalid();
  return value;
}

int _integer(Object? value) {
  if (value is! int) _invalid();
  return value;
}

/// Bound the decoder's prospective object graph without constructing it.
/// Version one has three fixed containers, two per message, one per origin;
/// counting keys and scalar values gives fourteen fixed tokens, five per
/// message, and six per origin. A malformed shape gets at most that same total
/// allocation budget, even when its per-array schema checks would run later.
void _preflightManifestJson(String encoded, MailArchiveExportLimits limits) {
  if (encoded.length > limits.maxManifestBytes) {
    _invalid(MailProblemCode.quotaExceeded);
  }
  final maxContainers = 3 + 2 * limits.maxMessages + limits.maxOrigins;
  final maxTokens = 14 + 5 * limits.maxMessages + 6 * limits.maxOrigins;
  // The longest legal string is a 4096-code-unit provenance folder. Every
  // code unit may be written as a six-character JSON Unicode escape.
  const maxStringEncodingUnits = 6 * 4096;
  var containers = 0, tokens = 0, depth = 0, utf8Bytes = 0;
  var quoted = false, escaped = false, scalar = false;
  var stringStart = 0, previousUnit = -1;
  for (var index = 0; index < encoded.length; index++) {
    final unit = encoded.codeUnitAt(index);
    // Match UTF-8's replacement of unpaired surrogates without allocating a
    // second, potentially three-times-larger encoding of malformed input.
    utf8Bytes += unit < 0x80
        ? 1
        : unit < 0x800
        ? 2
        : unit >= 0xdc00 &&
              unit <= 0xdfff &&
              previousUnit >= 0xd800 &&
              previousUnit <= 0xdbff
        ? 1
        : 3;
    previousUnit = unit;
    if (utf8Bytes > limits.maxManifestBytes) {
      _invalid(MailProblemCode.quotaExceeded);
    }
    if (quoted) {
      if (index - stringStart > maxStringEncodingUnits) {
        _invalid(MailProblemCode.quotaExceeded);
      }
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        quoted = false;
      }
    } else if (unit == 34) {
      if (++tokens > maxTokens) _invalid(MailProblemCode.quotaExceeded);
      quoted = true;
      scalar = false;
      stringStart = index + 1;
    } else if (unit == 91 || unit == 123) {
      if (++containers > maxContainers) {
        _invalid(MailProblemCode.quotaExceeded);
      }
      if (++depth > 12) _invalid();
      scalar = false;
    } else if (unit == 93 || unit == 125) {
      if (--depth < 0) _invalid();
      scalar = false;
    } else if (unit == 44 ||
        unit == 58 ||
        unit == 32 ||
        unit == 9 ||
        unit == 10 ||
        unit == 13) {
      scalar = false;
    } else if (!scalar) {
      if (++tokens > maxTokens) _invalid(MailProblemCode.quotaExceeded);
      scalar = true;
    }
  }
}

/// Decode only bounded, strict version-one manifests. Paths and file names are
/// not accepted from a manifest. The caller must enforce the byte bound before
/// reading a file; this check also protects callers with an in-memory string.
/// Encoded bytes, nesting, strings, containers and scalar/key tokens are bounded
/// before JSON decoding; configured message/origin budgets bound allocation even
/// for a shallow malformed array containing millions of tiny values.
MailArchiveExportPlan decodeMailArchiveExportManifest(
  String encoded,
  MailArchiveExportLimits limits,
) {
  if (!limits.isValid) _invalid();
  _preflightManifestJson(encoded, limits);
  try {
    final decoded = _map(jsonDecode(encoded), {
      'format',
      'version',
      'payload',
      'sha256',
    });
    if (decoded['format'] != 'crispoffice-mail-export') _invalid();
    if (_integer(decoded['version']) != 1) {
      _invalid(MailProblemCode.unsupported);
    }
    final payload = _map(decoded['payload'], {
      'hostId',
      'profileId',
      'createdAtMs',
      'items',
    });
    final sourceItems = payload['items'];
    if (sourceItems is! List<Object?>) _invalid();
    if (sourceItems.length > limits.maxMessages) {
      _invalid(MailProblemCode.quotaExceeded);
    }
    final items = <MailArchiveExportItem>[];
    var originCount = 0;
    for (final value in sourceItems) {
      final item = _map(value, {'id', 'bytes', 'origins'});
      final sourceOrigins = item['origins'];
      if (sourceOrigins is! List<Object?>) _invalid();
      originCount += sourceOrigins.length;
      if (originCount > limits.maxOrigins) {
        _invalid(MailProblemCode.quotaExceeded);
      }
      final origins = <MailArchiveOrigin>[];
      for (final value in sourceOrigins) {
        final origin = _map(value, {'source', 'folder', 'sourceMessageId'});
        origins.add(
          MailArchiveOrigin(
            source: _string(origin['source']),
            folder: _string(origin['folder']),
            sourceMessageId: _string(origin['sourceMessageId']),
          ),
        );
      }
      items.add(
        MailArchiveExportItem(
          id: _string(item['id']),
          byteLength: _integer(item['bytes']),
          origins: origins,
        ),
      );
    }
    final plan = MailArchiveExportPlan(
      profile: MailProfileId(
        _string(payload['profileId']),
        hostId: _string(payload['hostId']),
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _integer(payload['createdAtMs']),
        isUtc: true,
      ),
      items: items,
    );
    final canonical = _payload(plan, limits);
    final digest = crypto.sha256
        .convert(utf8.encode(jsonEncode(canonical)))
        .toString();
    if (digest != decoded['sha256']) _invalid(MailProblemCode.conflict);
    return plan;
  } on MailStoreStorageException {
    rethrow;
  } on Object {
    _invalid();
  }
}
