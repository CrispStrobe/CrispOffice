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
  final maximumBytes = math.min(4 * 1024 * 1024, budget.maxAttachmentBytes);
  final urls = candidates.take(math.min(8, budget.maxAttachments)).toSet();
  for (final uri in urls) {
    if (!isCurrent() || pixels <= 0) break;
    if (approvedMailLink(uri.toString()) != uri ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      continue;
    }
    try {
      final image = await _readImage(
        uri,
        client,
        isCurrent,
        maximumBytes,
        pixels,
      ).timeout(timeout);
      if (!isCurrent()) break;
      if (image != null) {
        loaded.add(image);
        pixels -= image.width * image.height;
      }
    } on TimeoutException {
      // Closing also cancels the timed-out body/headers operation.
      client.close();
      break;
    } on Object {
      // An optional image failure never replaces or retries the message body.
    }
  }
  return List.unmodifiable(loaded);
}

Future<MailInlineImage?> _readImage(
  Uri uri,
  http.Client client,
  bool Function() isCurrent,
  int maximumBytes,
  int availablePixels,
) async {
  final request = http.Request('GET', uri)..followRedirects = false;
  final response = await client.send(request);
  final mediaType = response.headers['content-type']
      ?.split(';')
      .first
      .trim()
      .toLowerCase();
  if (!isCurrent() ||
      response.statusCode != 200 ||
      (response.contentLength ?? 0) > maximumBytes ||
      (mediaType != 'image/png' && mediaType != 'image/jpeg')) {
    await response.stream.listen(null).cancel();
    return null;
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response.stream) {
    if (!isCurrent() || chunk.length > maximumBytes - bytes.length) {
      return null;
    }
    bytes.add(chunk);
  }
  if (!isCurrent()) return null;
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
