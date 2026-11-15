import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_office_engine/quds_office_engine.dart';

/// The example keeps credentials in memory. Production hosts can provide
/// their own proxy-aware transport and optional secure credential storage.
Future<ZoteroHttpResponse> studioZoteroTransport(
  ZoteroHttpRequest request,
) async {
  if (request.uri.scheme != 'https' ||
      request.uri.host != 'api.zotero.org' ||
      request.uri.port != 443 ||
      request.uri.userInfo.isNotEmpty) {
    throw StateError('Unsupported Zotero request.');
  }
  final client = http.Client();
  StreamIterator<List<int>>? body;
  var active = true;
  Future<ZoteroHttpResponse> read() async {
    final response = await client.send(
      http.Request('GET', request.uri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll(request.headers),
    );
    if (!active) {
      await response.stream.listen((_) {}).cancel();
      throw StateError('The Zotero request expired.');
    }
    final bytes = BytesBuilder(copy: false);
    body = StreamIterator(response.stream);
    if ((response.contentLength ?? 0) > 8 * 1024 * 1024) {
      throw StateError('The Zotero response is too large.');
    }
    while (await body!.moveNext()) {
      if (!active) throw StateError('The Zotero request expired.');
      if (bytes.length + body!.current.length > 8 * 1024 * 1024) {
        throw StateError('The Zotero response is too large.');
      }
      bytes.add(body!.current);
    }
    return ZoteroHttpResponse(
      statusCode: response.statusCode,
      body: utf8.decode(bytes.takeBytes()),
      headers: response.headers,
    );
  }

  try {
    return await read().timeout(const Duration(seconds: 20));
  } finally {
    active = false;
    if (body != null) unawaited(body!.cancel().catchError((Object _) {}));
    client.close();
  }
}
