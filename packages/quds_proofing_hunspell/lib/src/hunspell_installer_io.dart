import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'hunspell_catalog.dart';

final class HunspellInstallException implements Exception {
  const HunspellInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cooperative cancellation for a running download.
final class HunspellInstallCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get cancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);
}

void _checkCancellation(HunspellInstallCancellation? cancellation) {
  if (cancellation?.cancelled ?? false) {
    throw const HunspellInstallException('Download cancelled.');
  }
}

/// Progress callback: bytes received so far of [total].
typedef HunspellDownloadProgress = void Function(int received, int total);

/// Explicit, user-initiated installation of pinned dictionary bundles into a
/// private per-user directory owned by the host.
///
/// Every file is streamed into a private staging directory and admitted only
/// when its length and SHA-256 equal the compiled-in pins. The complete tree
/// is published with one rename into `<root>/hunspell/<revision>-<id>` and
/// verified again; removal renames before deleting, so a partial tree is
/// never seen as installed. Network access happens only in [install].
final class HunspellInstaller {
  HunspellInstaller(
    this.root, {
    HttpClient Function()? httpClientFactory,
    Uri Function(HunspellBundleDownload bundle, HunspellArtifact artifact)?
    resolveUrl,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _resolveUrl = resolveUrl ?? ((bundle, artifact) => bundle.url(artifact));

  final Directory root;
  final HttpClient Function() _httpClientFactory;

  /// Source of each file; a mirror may replace the Hub URL, the pins may not.
  final Uri Function(HunspellBundleDownload, HunspellArtifact) _resolveUrl;

  Directory _directory(HunspellBundleDownload bundle) =>
      Directory('${root.path}/hunspell/${bundle.revision}-${bundle.id}');

  /// The verified installed dictionary, or null when absent. A tree that
  /// fails verification is reported as an error, never used.
  Future<HunspellDictionaryFiles?> installed(
    HunspellBundleDownload bundle,
  ) async {
    final directory = _directory(bundle);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    await _verify(directory, bundle);
    return _files(directory, bundle);
  }

  Future<HunspellDictionaryFiles> install(
    HunspellBundleDownload bundle, {
    HunspellDownloadProgress? onProgress,
    HunspellInstallCancellation? cancellation,
  }) async {
    _checkCancellation(cancellation);
    final existing = await installed(bundle);
    _checkCancellation(cancellation);
    if (existing != null) return existing;
    final parent = Directory('${root.path}/hunspell')
      ..createSync(recursive: true);
    if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const HunspellInstallException(
        'The dictionary directory is linked or not a directory.',
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
      // Cancellation is admitted until the synchronous publication point.
      _checkCancellation(cancellation);
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

  /// Removes an installed dictionary. Dispose providers using it first.
  Future<void> remove(HunspellBundleDownload bundle) async {
    final directory = _directory(bundle);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    final trash = Directory(
      '${root.path}/hunspell/.removing-${bundle.id}-${DateTime.now().microsecondsSinceEpoch}',
    );
    directory.renameSync(trash.path);
    trash.deleteSync(recursive: true);
  }

  HunspellDictionaryFiles _files(
    Directory directory,
    HunspellBundleDownload bundle,
  ) => HunspellDictionaryFiles(
    affPath: '${directory.path}/${bundle.aff.file}',
    dicPath: '${directory.path}/${bundle.dic.file}',
  );

  Future<void> _verify(
    Directory directory,
    HunspellBundleDownload bundle,
  ) async {
    final expected = {
      for (final artifact in bundle.files) artifact.file: artifact,
    };
    final entries = directory.listSync(followLinks: false);
    if (entries.length != expected.length) {
      throw const HunspellInstallException(
        'The dictionary directory has unexpected files.',
      );
    }
    for (final entry in entries) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final artifact = expected[name];
      if (artifact == null || entry is! File) {
        throw HunspellInstallException('Unexpected dictionary entry: $name');
      }
      if (entry.lengthSync() != artifact.bytes ||
          (await sha256.bind(entry.openRead()).first).toString() !=
              artifact.sha256) {
        throw HunspellInstallException('Dictionary file changed: $name');
      }
    }
  }

  Future<void> _download(
    Uri url,
    File target,
    HunspellArtifact artifact, {
    HunspellInstallCancellation? cancellation,
    void Function(int)? onBytes,
  }) async {
    _checkCancellation(cancellation);
    final client = _httpClientFactory();
    void abort() => client.close(force: true);
    cancellation?.addListener(abort);
    try {
      _checkCancellation(cancellation);
      final request = await client.getUrl(url);
      _checkCancellation(cancellation);
      final response = await request.close();
      _checkCancellation(cancellation);
      if (response.statusCode != HttpStatus.ok) {
        throw HunspellInstallException(
          'Download of ${artifact.file} failed with HTTP ${response.statusCode}.',
        );
      }
      final sink = target.openWrite();
      final digest = _DigestSink();
      final hashing = sha256.startChunkedConversion(digest);
      var length = 0;
      try {
        await for (final chunk in response) {
          _checkCancellation(cancellation);
          length += chunk.length;
          if (length > artifact.bytes) {
            throw HunspellInstallException(
              '${artifact.file} is larger than pinned.',
            );
          }
          hashing.add(chunk);
          sink.add(chunk);
          onBytes?.call(chunk.length);
          _checkCancellation(cancellation);
        }
      } finally {
        await sink.close();
      }
      hashing.close();
      _checkCancellation(cancellation);
      if (length != artifact.bytes ||
          digest.value.toString() != artifact.sha256) {
        throw HunspellInstallException(
          '${artifact.file} does not match its pinned SHA-256.',
        );
      }
    } on Object {
      // Closing an active client may surface a transport exception instead.
      _checkCancellation(cancellation);
      rethrow;
    } finally {
      cancellation?.removeListener(abort);
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
