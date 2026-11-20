import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'studio_mail_attachment.dart';
import 'studio_mail_file.dart';

/// A fixed, redacted failure. File paths and platform error text are not UI.
final class StudioMailAttachmentReadFailure implements Exception {
  const StudioMailAttachmentReadFailure();

  @override
  String toString() => 'The selected attachment could not be read completely.';
}

final class StudioMailAttachmentReadCancelled implements Exception {
  const StudioMailAttachmentReadCancelled();
}

/// One cancellable file-selection transaction. A failed selection publishes no
/// partial attachments and cannot mutate the previous immutable draft bundle.
final class StudioMailAttachmentLoader {
  StudioMailAttachmentLoader({this.readTimeout = const Duration(seconds: 30)});

  final Duration readTimeout;
  bool _cancelled = false;
  StreamIterator<List<int>>? _active;
  bool _reading = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final active = _active;
    if (active != null) unawaited(_cancelStream(active));
  }

  void _checkCurrent() {
    if (_cancelled) {
      throw const StudioMailAttachmentReadCancelled();
    }
  }

  Future<StudioMailAttachments> read(
    List<PlatformFile> files, {
    StudioMailAttachments existing = const StudioMailAttachments.empty(),
  }) async {
    _checkCurrent();
    if (_reading || readTimeout <= Duration.zero) {
      throw const StudioMailAttachmentReadFailure();
    }
    if (files.length > StudioMailAttachments.maxCount - existing.items.length) {
      throw const StudioMailAttachmentException(
        StudioMailAttachmentProblem.tooMany,
      );
    }
    var declaredBytes = existing.totalBytes;
    // Admit the complete selection before opening a single stream.
    for (final file in files) {
      StudioMailAttachment.validateName(file.name);
      if (file.size < 0) throw const StudioMailAttachmentReadFailure();
      if (file.size > StudioMailAttachments.maxTotalBytes - declaredBytes) {
        throw const StudioMailAttachmentException(
          StudioMailAttachmentProblem.tooLarge,
        );
      }
      declaredBytes += file.size;
    }

    _reading = true;
    try {
      final result = <StudioMailAttachment>[...existing.items];
      var actualBytes = existing.totalBytes;
      for (final file in files) {
        _checkCurrent();
        final remaining = StudioMailAttachments.maxTotalBytes - actualBytes;
        final bytes = await _readFile(file, remaining);
        _checkCurrent();
        result.add(StudioMailAttachment(name: file.name, bytes: bytes));
        actualBytes += bytes.length;
      }
      return StudioMailAttachments.from(result);
    } on StudioMailAttachmentException {
      rethrow;
    } on StudioMailAttachmentReadCancelled {
      rethrow;
    } on Object {
      _checkCurrent();
      throw const StudioMailAttachmentReadFailure();
    } finally {
      _reading = false;
    }
  }

  Future<Uint8List> _readFile(PlatformFile file, int remaining) async {
    // Some picker implementations return bytes even with withData:false.
    // Check their actual length before taking the owned snapshot.
    if (file.bytes case final bytes?) {
      if (bytes.length > remaining) {
        throw const StudioMailAttachmentException(
          StudioMailAttachmentProblem.tooLarge,
        );
      }
      if (bytes.length != file.size) {
        throw const StudioMailAttachmentReadFailure();
      }
      return bytes;
    }

    final stream =
        file.readStream ??
        (file.path == null
            ? null
            : openStudioMailAttachmentFile(file.path!, maxBytes: remaining));
    if (stream == null) throw const StudioMailAttachmentReadFailure();
    final iterator = StreamIterator<List<int>>(stream);
    _active = iterator;
    final bytes = BytesBuilder(copy: true);
    final elapsed = Stopwatch()..start();
    try {
      while (true) {
        _checkCurrent();
        final timeLeft = readTimeout - elapsed.elapsed;
        if (timeLeft <= Duration.zero) {
          throw const StudioMailAttachmentReadFailure();
        }
        // StreamIterator.cancel completes a pending moveNext immediately;
        // cancellation does not wait for the platform's teardown future.
        final hasNext = await iterator.moveNext().timeout(timeLeft);
        _checkCurrent();
        if (!hasNext) break;
        final chunk = iterator.current;
        if (chunk.length > remaining - bytes.length) {
          throw const StudioMailAttachmentException(
            StudioMailAttachmentProblem.tooLarge,
          );
        }
        if (chunk.length > file.size - bytes.length) {
          throw const StudioMailAttachmentReadFailure();
        }
        bytes.add(chunk);
      }
      if (bytes.length != file.size) {
        throw const StudioMailAttachmentReadFailure();
      }
      return bytes.takeBytes();
    } finally {
      elapsed.stop();
      if (identical(_active, iterator)) _active = null;
      // A platform stream's delayed teardown must not hold a closed composer.
      unawaited(_cancelStream(iterator));
    }
  }

  static Future<void> _cancelStream(StreamIterator<List<int>> iterator) async {
    try {
      await iterator.cancel();
    } on Object {
      // The immutable selection result is independent of stream cleanup.
    }
  }
}
