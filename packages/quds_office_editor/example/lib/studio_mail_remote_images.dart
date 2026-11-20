import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

/// Loads only inert image candidates after the host's explicit user action.
/// The caller owns [client] and must close it when its reader is retired.
Future<List<MailInlineImage>> loadStudioMailRemoteImages({
  required Iterable<Uri> candidates,
  required http.Client client,
  required bool Function() isCurrent,
  required MailReadBudget budget,
  required int availablePixels,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final loaded = <MailInlineImage>[];
  var pixels = availablePixels;
  var remainingBytes = budget.maxDecodedBytes;
  final maximumBytes = math.min(
    StudioMailRemoteImageLoader.maxResponseBytes,
    budget.maxAttachmentBytes,
  );
  final urls = candidates
      .take(
        math.min(StudioMailRemoteImageLoader.maxImages, budget.maxAttachments),
      )
      .toSet();
  for (final uri in urls) {
    if (!isCurrent() || pixels <= 0 || remainingBytes <= 0) break;
    if (approvedMailLink(uri.toString()) != uri ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      continue;
    }
    try {
      final image = await _readImage(
        uri,
        client,
        isCurrent,
        math.min(maximumBytes, remainingBytes),
        pixels,
        timeout,
      );
      if (!isCurrent()) break;
      if (image != null) {
        loaded.add(image);
        pixels -= image.width * image.height;
        remainingBytes -= image.attachment.content.length;
      }
    } on TimeoutException {
      client.close();
      break;
    } on Object {
      // An optional image failure never replaces or retries the message body.
    }
  }
  return List.unmodifiable(loaded);
}

/// Compatibility host for callers that own a reader rather than an HTTP client.
/// Both entry points use the same bounded request and raster-admission loop.
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
    final client = _FactoryImageClient(_createClient);
    try {
      final images = await loadStudioMailRemoteImages(
        candidates: reader.presentation.remoteImageUris,
        client: client,
        isCurrent: current,
        budget: reader.budget,
        availablePixels:
            reader.budget.maxImagePixels -
            reader.presentation.images.fold<int>(
              0,
              (sum, image) => sum + image.width * image.height,
            ),
        timeout: timeout,
      );
      if (!current()) return 0;
      // The reader owns final cumulative admission with both decoded bodies,
      // original attachments and images accepted by previous explicit actions.
      return reader.addImages(images);
    } finally {
      client.close();
    }
  }
}

final class _FactoryImageClient extends http.BaseClient {
  _FactoryImageClient(this.createClient);
  final http.Client Function() createClient;
  http.Client? _active;
  bool _closed = false;

  void _closeActive() {
    try {
      _active?.close();
    } on Object {
      // Optional resource cleanup cannot replace a retained reader outcome.
    }
    _active = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) throw StateError('Remote image loader is closed.');
    _closeActive();
    final client = createClient();
    _active = client;
    return client.send(request);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _closeActive();
  }
}

Future<void> _discardImageBody(http.StreamedResponse response) async {
  try {
    await response.stream.listen((_) {}).cancel();
  } on Object {
    // A late backend cancellation error must not escape an optional action.
  }
}

Future<void> _cancelImageBody(StreamIterator<List<int>> body) async {
  try {
    await body.cancel();
  } on Object {
    // A late backend cancellation error must not escape an optional action.
  }
}

Future<MailInlineImage?> _readImage(
  Uri uri,
  http.Client client,
  bool Function() isCurrent,
  int maximumBytes,
  int availablePixels,
  Duration timeout,
) async {
  StreamIterator<List<int>>? body;
  var active = true;
  Future<MailInlineImage?> read() async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await client.send(request);
    final mediaType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (!active ||
        !isCurrent() ||
        response.statusCode != 200 ||
        (response.contentLength ?? 0) > maximumBytes ||
        (mediaType != 'image/png' && mediaType != 'image/jpeg')) {
      unawaited(_discardImageBody(response));
      return null;
    }
    final iterator = StreamIterator<List<int>>(response.stream);
    body = iterator;
    final bytes = BytesBuilder(copy: true);
    while (await iterator.moveNext()) {
      if (!active || !isCurrent()) return null;
      final chunk = iterator.current;
      if (chunk.length > maximumBytes - bytes.length) return null;
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
    if (dimensions == null || dimensions.$1 * dimensions.$2 > availablePixels) {
      return null;
    }
    return MailInlineImage(
      attachment: attachment,
      width: dimensions.$1,
      height: dimensions.$2,
    );
  }

  try {
    // One deadline covers headers and the complete body. Its finally also
    // cancels a stalled body when a test/backend close alone cannot do so.
    return await read().timeout(timeout);
  } finally {
    active = false;
    final iterator = body;
    if (iterator != null) unawaited(_cancelImageBody(iterator));
  }
}
