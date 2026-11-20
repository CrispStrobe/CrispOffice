import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'morph_catalog.dart';

final class MorphInstallException implements Exception {
  const MorphInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cooperative cancellation for a running download.
final class MorphInstallCancellation {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Progress callback: bytes received so far of [total].
typedef MorphDownloadProgress = void Function(int received, int total);

/// Explicit, user-initiated installation of pinned morphology bundles into a
/// private per-user directory owned by the host.
///
/// Every file is streamed into a private staging directory and admitted only
/// when its length and SHA-256 equal the compiled-in pins. The complete tree
/// is published with one rename into `<root>/arabic_morph/<revision>-<id>` and
/// verified again; removal renames before deleting, so a partial tree is
/// never seen as installed. Network access happens only in [install].
final class MorphInstaller {
  MorphInstaller(
    this.root, {
    HttpClient Function()? httpClientFactory,
    Uri Function(MorphBundleDownload bundle, MorphArtifact artifact)?
    resolveUrl,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _resolveUrl = resolveUrl ?? ((bundle, artifact) => bundle.url(artifact));

  final Directory root;
  final HttpClient Function() _httpClientFactory;

  /// Source of each file; a mirror may replace the Hub URL, the pins may not.
  final Uri Function(MorphBundleDownload, MorphArtifact) _resolveUrl;

  Directory _directory(MorphBundleDownload bundle) =>
      Directory('${root.path}/arabic_morph/${bundle.revision}-${bundle.id}');

  /// The verified installed bundle, or null when absent. A tree that
  /// fails verification is reported as an error, never used.
  Future<MorphDatabaseFiles?> installed(MorphBundleDownload bundle) async {
    final directory = _directory(bundle);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    await _verify(directory, bundle);
    return _files(directory, bundle);
  }

  Future<MorphDatabaseFiles> install(
    MorphBundleDownload bundle, {
    MorphDownloadProgress? onProgress,
    MorphInstallCancellation? cancellation,
  }) async {
    final existing = await installed(bundle);
    if (existing != null) return existing;
    final parent = Directory('${root.path}/arabic_morph')
      ..createSync(recursive: true);
    if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const MorphInstallException(
        'The morphology directory is linked or not a directory.',
      );
    }
    final staging = parent.createTempSync('.staging-');
    try {
      var received = 0;
      for (final artifact in bundle.files) {
        await _download(
          _resolveUrl(bundle, artifact),
          File('${staging.path}/${artifact.file}'),
          artifact,
          cancellation: cancellation,
          onBytes: (count) {
            received += count;
            onProgress?.call(received, bundle.totalBytes);
          },
        );
      }
      await _verify(staging, bundle);
      final destination = _directory(bundle);
      try {
        staging.renameSync(destination.path);
      } on FileSystemException {
        // Another installer may have finished first; accept only a verified tree.
        if (await installed(bundle) == null) rethrow;
      }
      await _verify(destination, bundle);
      return _files(destination, bundle);
    } finally {
      if (staging.existsSync()) {
        try {
          staging.deleteSync(recursive: true);
        } on FileSystemException {
          // A leftover private staging directory is never treated as installed.
        }
      }
    }
  }

  /// Removes every installed bundle other than [keep] and [alsoKeep] (for
  /// example the earlier `noprob` text bundle once the binary proofing bundle
  /// replaced it, or an earlier context model) and leftovers of interrupted
  /// removals. Staging directories of a running installation are left alone.
  /// Returns the removed entry names.
  Future<List<String>> removeOtherBundles(
    MorphBundleDownload keep, {
    Iterable<MorphBundleDownload> alsoKeep = const [],
  }) async {
    final parent = Directory('${root.path}/arabic_morph');
    if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return const [];
    }
    final current = {
      for (final b in [keep, ...alsoKeep]) '${b.revision}-${b.id}',
    };
    final removed = <String>[];
    for (final entry in parent.listSync(followLinks: false)) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (current.contains(name) || name.startsWith('.staging-')) continue;
      if (name.startsWith('.removing-') ||
          RegExp(r'^[0-9a-f]{40}-[A-Za-z0-9._-]+$').hasMatch(name)) {
        try {
          entry.deleteSync(recursive: true);
          removed.add(name);
        } on FileSystemException {
          // Retried on the next refresh; a stale tree is never opened.
        }
      }
    }
    return removed;
  }

  /// Removes an installed bundle. Dispose analyzers using it first.
  Future<void> remove(MorphBundleDownload bundle) async {
    final directory = _directory(bundle);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    final trash = Directory(
      '${root.path}/arabic_morph/.removing-${bundle.id}-${DateTime.now().microsecondsSinceEpoch}',
    );
    directory.renameSync(trash.path);
    trash.deleteSync(recursive: true);
  }

  MorphDatabaseFiles _files(Directory directory, MorphBundleDownload bundle) =>
      MorphDatabaseFiles(
        bundle,
        manifestPath: '${directory.path}/${bundle.manifest.file}',
      );

  Future<void> _verify(Directory directory, MorphBundleDownload bundle) async {
    final expected = {
      for (final artifact in bundle.files) artifact.file: artifact,
    };
    final entries = directory.listSync(followLinks: false);
    if (entries.length != expected.length) {
      throw const MorphInstallException(
        'The morphology directory has unexpected files.',
      );
    }
    for (final entry in entries) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final artifact = expected[name];
      if (artifact == null || entry is! File) {
        throw MorphInstallException(
          'Unexpected morphology bundle entry: $name',
        );
      }
      if (entry.lengthSync() != artifact.bytes ||
          (await sha256.bind(entry.openRead()).first).toString() !=
              artifact.sha256) {
        throw MorphInstallException('Morphology bundle file changed: $name');
      }
    }
  }

  Future<void> _download(
    Uri url,
    File target,
    MorphArtifact artifact, {
    MorphInstallCancellation? cancellation,
    void Function(int)? onBytes,
  }) async {
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw MorphInstallException(
          'Download of ${artifact.file} failed with HTTP ${response.statusCode}.',
        );
      }
      final sink = target.openWrite();
      final digest = _DigestSink();
      final hashing = sha256.startChunkedConversion(digest);
      var length = 0;
      try {
        await for (final chunk in response) {
          if (cancellation?.cancelled ?? false) {
            throw const MorphInstallException('Download cancelled.');
          }
          length += chunk.length;
          if (length > artifact.bytes) {
            throw MorphInstallException(
              '${artifact.file} is larger than pinned.',
            );
          }
          hashing.add(chunk);
          sink.add(chunk);
          onBytes?.call(chunk.length);
        }
      } finally {
        await sink.close();
      }
      hashing.close();
      if (length != artifact.bytes ||
          digest.value.toString() != artifact.sha256) {
        throw MorphInstallException(
          '${artifact.file} does not match its pinned SHA-256.',
        );
      }
    } finally {
      client.close(force: true);
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
