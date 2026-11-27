import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

/// One explicit image-loading action. A retired reader cancels its owned client.
///
/// Callers supply only URLs exposed by the inert reader projection. Downloads
/// are streamed under byte, pixel, request-count and whole-request deadlines.
/// Explicit requests can follow two redirects within the original origin.
/// No cookies, credentials or message text are supplied.
final class StudioMailRemoteImageLoader {
  StudioMailRemoteImageLoader({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 15),
    this.maxImageBytes = 4 * 1024 * 1024,
    this.maxTotalBytes = 16 * 1024 * 1024,
  }) : _clientFactory = clientFactory ?? http.Client.new {
    if (timeout <= Duration.zero ||
        maxImageBytes < 1 ||
        maxImageBytes > 4 * 1024 * 1024 ||
        maxTotalBytes < 1 ||
        maxTotalBytes > 16 * 1024 * 1024) {
      throw ArgumentError('Invalid remote image loading bounds.');
    }
  }

  final http.Client Function() _clientFactory;
  final Duration timeout;
  final int maxImageBytes;
  final int maxTotalBytes;
  http.Client? _client;
  StreamIterator<List<int>>? _body;
  bool _started = false;
  bool _cancelled = false;
  int _downloadedBytes = 0;

  void cancel() {
    _cancelled = true;
    final client = _client;
    if (client != null) _close(client);
    final body = _body;
    if (body != null) unawaited(_cancelBody(body));
  }

  /// Runs an explicit action against a captured reader, with its remaining
  /// decoded-byte and pixel budgets. Navigation and body-mode changes retire it.
  /// The original MIME ownership and any earlier admitted images are retained.
  Future<int> loadInto(
    MailReaderController reader, {
    required bool Function() isCurrent,
  }) async {
    final result = reader.result;
    final revision = reader.revision;
    bool current() =>
        !reader.isDisposed &&
        identical(reader.result, result) &&
        reader.revision == revision &&
        isCurrent();
    if (!current() || reader.presentation.rejected) return 0;
    final message = result.message!;
    var usedBytes = 0;
    for (final body in [message.body.plainText, message.body.html]) {
      if (body != null) usedBytes += utf8.encode(body).length;
    }
    for (final attachment in message.attachments) {
      usedBytes += attachment.content.length;
    }
    var usedPixels = 0;
    for (final image in reader.presentation.images) {
      usedPixels += image.width * image.height;
      if (image.attachment.partPath.startsWith('remote:')) {
        usedBytes += image.attachment.content.length;
      }
    }
    final images = await _load(
      reader.presentation.remoteImageUrls,
      isCurrent: current,
      maxImagePixels: reader.budget.maxImagePixels - usedPixels,
      byteLimit: math.min(maxImageBytes, reader.budget.maxAttachmentBytes),
      totalLimit: math.min(
        maxTotalBytes,
        reader.budget.maxDecodedBytes - usedBytes,
      ),
    );
    if (!current()) return 0;
    return reader.addImages(images, expectedResult: result);
  }

  Future<List<MailInlineImage>> load(
    Iterable<Uri> urls, {
    required bool Function() isCurrent,
    int maxImagePixels = 16 * 1024 * 1024,
  }) => _load(
    urls,
    isCurrent: isCurrent,
    maxImagePixels: maxImagePixels,
    byteLimit: maxImageBytes,
    totalLimit: maxTotalBytes,
  );

  Future<List<MailInlineImage>> _load(
    Iterable<Uri> urls, {
    required bool Function() isCurrent,
    required int maxImagePixels,
    required int byteLimit,
    required int totalLimit,
  }) async {
    if (_started) throw StateError('An image loader can run only once.');
    _started = true;
    if (maxImagePixels < 1 || byteLimit < 1 || totalLimit < 1) return const [];
    bool current() => !_cancelled && isCurrent();
    final loaded = <MailInlineImage>[];
    final seen = <Uri>{};
    var pixels = 0;
    for (final uri in urls.take(8)) {
      if (!current()) return const [];
      if (!seen.add(uri) ||
          approvedMailLink(uri.toString()) == null ||
          uri.scheme != 'https' && uri.scheme != 'http') {
        continue;
      }
      if (_downloadedBytes >= totalLimit || pixels >= maxImagePixels) break;
      final client = _clientFactory();
      _client = client;
      var timedOut = false;
      try {
        final attachment =
            await _fetch(
              client,
              uri,
              () => !timedOut && current(),
              byteLimit: byteLimit,
              totalLimit: totalLimit,
            ).timeout(
              timeout,
              onTimeout: () {
                timedOut = true;
                _close(client);
                final body = _body;
                if (body != null) unawaited(_cancelBody(body));
                return null;
              },
            );
        if (!current()) return const [];
        if (attachment == null) continue;
        final dimensions = mailRasterDimensions(attachment);
        if (dimensions == null ||
            dimensions.$1 * dimensions.$2 > maxImagePixels - pixels) {
          continue;
        }
        pixels += dimensions.$1 * dimensions.$2;
        loaded.add(
          MailInlineImage(
            attachment: attachment,
            width: dimensions.$1,
            height: dimensions.$2,
          ),
        );
      } on Object {
        // Optional remote content never replaces a readable decoded message.
      } finally {
        _close(client);
        if (identical(_client, client)) _client = null;
      }
    }
    return current() ? List.unmodifiable(loaded) : const [];
  }

  Future<MailAttachment?> _fetch(
    http.Client client,
    Uri uri,
    bool Function() isCurrent, {
    required int byteLimit,
    required int totalLimit,
  }) async {
    var target = uri;
    http.StreamedResponse response;
    for (var redirects = 0; ; redirects++) {
      final request = http.Request('GET', target)..followRedirects = false;
      response = await client.send(request);
      if (!isCurrent() ||
          !const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        break;
      }
      await _discard(response);
      final location = response.headers['location'];
      if (redirects == 2 || location == null || location.length > 8192) {
        return null;
      }
      final next = approvedMailLink(target.resolve(location).toString());
      if (next == null ||
          next.scheme != uri.scheme ||
          next.origin != uri.origin) {
        return null;
      }
      target = next;
    }
    final mediaType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    final generic =
        mediaType == null ||
        mediaType.isEmpty ||
        mediaType == 'application/octet-stream';
    final declared = response.contentLength;
    if (!isCurrent() ||
        response.statusCode != 200 ||
        (!generic &&
            mediaType != 'image/png' &&
            mediaType != 'image/jpeg' &&
            mediaType != 'image/jpg') ||
        (declared != null &&
            (declared > byteLimit ||
                declared > totalLimit - _downloadedBytes))) {
      unawaited(_discard(response));
      return null;
    }
    final body = StreamIterator<List<int>>(response.stream);
    _body = body;
    final bytes = BytesBuilder(copy: true);
    try {
      while (await body.moveNext()) {
        if (!isCurrent()) return null;
        final chunk = body.current;
        _downloadedBytes += chunk.length;
        if (chunk.length > byteLimit - bytes.length ||
            _downloadedBytes > totalLimit) {
          return null;
        }
        bytes.add(chunk);
      }
      if (!isCurrent()) return null;
      final content = bytes.takeBytes();
      final type = generic
          ? _rasterMediaType(content)
          : mediaType == 'image/jpg'
          ? 'image/jpeg'
          : mediaType;
      if (type == null) return null;
      return MailAttachment(
        partPath: 'remote:$uri',
        mediaType: type,
        displayName: 'Image',
        content: MailBytes(content),
      );
    } finally {
      if (identical(_body, body)) _body = null;
      unawaited(_cancelBody(body));
    }
  }

  static String? _rasterMediaType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        const [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ].asMap().entries.every((entry) => bytes[entry.key] == entry.value)) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    return null;
  }

  static void _close(http.Client client) {
    try {
      client.close();
    } on Object {
      // Optional-resource cleanup cannot replace the decoded message.
    }
  }

  static Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.listen((_) {}).cancel();
    } on Object {
      // A late response still owns a stream even after its client was closed.
    }
  }

  static Future<void> _cancelBody(StreamIterator<List<int>> body) async {
    try {
      await body.cancel();
    } on Object {
      // A backend cancellation failure does not escape the optional action.
    }
  }
}

void showStudioMailImageResult(
  BuildContext context,
  MailReaderController reader,
  int loaded,
) {
  if (reader.presentation.remoteImageUrls.isEmpty) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        loaded == 0
            ? reader.labels.externalImagesUnavailable
            : reader.labels.someExternalImagesUnavailable,
      ),
    ),
  );
}
