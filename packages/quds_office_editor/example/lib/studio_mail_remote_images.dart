import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

/// One explicit image-loading action. A retired reader cancels its owned client.
///
/// Callers supply only URLs exposed by the inert reader projection. Downloads
/// are streamed under byte, pixel, request-count and whole-request deadlines.
/// Redirects are not followed: loading one embedded URL cannot fetch a second
/// destination. No cookies, credentials or message text are supplied.
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
  bool _started = false;
  bool _cancelled = false;
  int _downloadedBytes = 0;

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  Future<List<MailInlineImage>> load(
    Iterable<Uri> urls, {
    required bool Function() isCurrent,
    int maxImagePixels = 16 * 1024 * 1024,
  }) async {
    if (_started) throw StateError('An image loader can run only once.');
    _started = true;
    if (maxImagePixels < 1) return const [];
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
      if (_downloadedBytes >= maxTotalBytes) break;
      final client = _clientFactory();
      _client = client;
      var timedOut = false;
      try {
        final attachment =
            await _fetch(client, uri, () => !timedOut && current()).timeout(
              timeout,
              onTimeout: () {
                timedOut = true;
                client.close();
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
        client.close();
        if (identical(_client, client)) _client = null;
      }
    }
    return current() ? List.unmodifiable(loaded) : const [];
  }

  Future<MailAttachment?> _fetch(
    http.Client client,
    Uri uri,
    bool Function() isCurrent,
  ) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await client.send(request);
    if (!isCurrent() || response.statusCode != 200) return null;
    final mediaType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (mediaType != 'image/png' && mediaType != 'image/jpeg') return null;
    final available = maxTotalBytes - _downloadedBytes;
    final declared = response.contentLength;
    if (declared != null &&
        (declared > maxImageBytes || declared > available)) {
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (!isCurrent()) return null;
      _downloadedBytes += chunk.length;
      if (chunk.length > maxImageBytes - bytes.length ||
          _downloadedBytes > maxTotalBytes) {
        return null;
      }
      bytes.add(chunk);
    }
    if (!isCurrent()) return null;
    return MailAttachment(
      partPath: 'remote:$uri',
      mediaType: mediaType!,
      displayName: 'Image',
      content: MailBytes(bytes.takeBytes()),
    );
  }
}
