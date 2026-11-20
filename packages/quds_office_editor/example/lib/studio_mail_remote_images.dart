import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

/// Fetches only the reader's projected images after the host's explicit action.
final class StudioMailRemoteImageLoader {
  StudioMailRemoteImageLoader({
    http.Client Function()? createClient,
    this.timeout = const Duration(seconds: 15),
  }) : _createClient = createClient ?? http.Client.new {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
  }

  static const maxResponseBytes = 4 * 1024 * 1024;
  static const maxImages = 8;
  final http.Client Function() _createClient;
  final Duration timeout;

  Future<int> load(
    MailReaderController reader, {
    required bool Function() isCurrent,
  }) async {
    final revision = reader.revision;
    bool current() =>
        !reader.isDisposed && reader.revision == revision && isCurrent();
    if (!current() || reader.presentation.rejected) return 0;
    final urls = reader.presentation.remoteImageUrls.take(maxImages).toList();
    final loaded = <MailInlineImage>[];
    var bytes = 0;
    var pixels = reader.presentation.images.fold<int>(
      0,
      (sum, image) => sum + image.width * image.height,
    );
    for (final uri in urls) {
      if (!current()) return 0;
      final byteLimit = math.min(
        maxResponseBytes,
        math.min(
          reader.budget.maxAttachmentBytes,
          reader.budget.maxDecodedBytes - bytes,
        ),
      );
      final pixelLimit = reader.budget.maxImagePixels - pixels;
      if (byteLimit <= 0 || pixelLimit <= 0) break;
      final image = await _read(
        uri,
        byteLimit: byteLimit,
        pixelLimit: pixelLimit,
        isCurrent: current,
      );
      if (!current()) return 0;
      if (image == null) continue;
      loaded.add(image);
      bytes += image.attachment.content.length;
      pixels += image.width * image.height;
    }
    if (!current() || loaded.isEmpty) return 0;
    // The reader owns final cumulative admission, including the saved body,
    // attachments and remote images accepted by earlier explicit actions.
    return reader.addImages(loaded);
  }

  Future<MailInlineImage?> _read(
    Uri uri, {
    required int byteLimit,
    required int pixelLimit,
    required bool Function() isCurrent,
  }) async {
    if (approvedMailLink(uri.toString()) != uri ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !isCurrent()) {
      return null;
    }
    final client = _createClient();
    StreamIterator<List<int>>? body;
    var active = true;

    Future<MailInlineImage?> read() async {
      final response = await client.send(http.Request('GET', uri));
      if (!active || !isCurrent()) {
        unawaited(_discard(response));
        return null;
      }
      final mediaType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > byteLimit ||
          (mediaType != 'image/png' && mediaType != 'image/jpeg')) {
        unawaited(_discard(response));
        return null;
      }
      final iterator = StreamIterator<List<int>>(response.stream);
      body = iterator;
      final bytes = BytesBuilder(copy: true);
      while (await iterator.moveNext()) {
        if (!active || !isCurrent()) return null;
        final chunk = iterator.current;
        // Check before copying: Content-Length may be absent or inaccurate.
        if (chunk.length > byteLimit - bytes.length) return null;
        bytes.add(chunk);
      }
      if (!active || !isCurrent()) return null;
      final attachment = MailAttachment(
        partPath: 'remote:$uri',
        mediaType: mediaType!,
        displayName: uri.pathSegments.lastOrNull ?? 'Image',
        content: MailBytes(bytes.takeBytes()),
      );
      final dimensions = mailRasterDimensions(attachment);
      if (dimensions == null || dimensions.$1 * dimensions.$2 > pixelLimit) {
        return null;
      }
      return MailInlineImage(
        attachment: attachment,
        width: dimensions.$1,
        height: dimensions.$2,
      );
    }

    try {
      // One deadline covers both response headers and the complete body.
      return await read().timeout(timeout);
    } on Object {
      // A failed optional resource must not replace the decoded message.
      return null;
    } finally {
      active = false;
      final iterator = body;
      if (iterator != null) unawaited(_cancel(iterator));
      try {
        client.close();
      } on Object {
        // Cleanup failure must not replace an optional-resource outcome.
      }
    }
  }

  static Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.listen((_) {}).cancel();
    } on Object {
      // Resource cleanup cannot invalidate the retained reader.
    }
  }

  static Future<void> _cancel(StreamIterator<List<int>> body) async {
    try {
      await body.cancel();
    } on Object {
      // A late backend cancellation error does not escape the optional action.
    }
  }
}
