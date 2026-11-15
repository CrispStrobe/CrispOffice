import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_office_engine/quds_office_engine.dart';

import 'studio_zotero_local_stub.dart'
    if (dart.library.io) 'studio_zotero_local_io.dart'
    as local;

bool get studioZoteroDesktopAvailable => local.studioZoteroLocalSupported;

/// The example keeps credentials in memory. Production hosts can provide
/// their own proxy-aware transport and optional secure credential storage.
Future<ZoteroHttpResponse> studioZoteroTransport(
  ZoteroHttpRequest request,
) async {
  final uri = request.uri;
  final desktop =
      uri.scheme == 'http' &&
      uri.host == 'localhost' &&
      uri.port == 23119 &&
      uri.path.startsWith('/api/') &&
      studioZoteroDesktopAvailable;
  final online =
      uri.scheme == 'https' && uri.host == 'api.zotero.org' && uri.port == 443;
  if ((!online && !desktop) ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      request.method != 'GET' ||
      (desktop &&
          (uri.pathSegments.any(
                (part) =>
                    part == '.' ||
                    part == '..' ||
                    part.contains('/') ||
                    part.contains('\\'),
              ) ||
              uri.queryParameters.keys.any(
                (name) => name.toLowerCase() == 'key',
              ) ||
              request.headers.entries.any(
                (entry) =>
                    !const {
                      'zotero-api-version',
                      'zotero-allowed-request',
                      'zotero-server-id',
                    }.contains(entry.key.toLowerCase()) ||
                    RegExp(r'[\x00-\x1f\x7f]').hasMatch(entry.value),
              )))) {
    throw StateError('Unsupported Zotero request.');
  }
  if (desktop) {
    final headers = request.headers.map(
      (name, value) => MapEntry(name.toLowerCase(), value),
    );
    if (headers['zotero-api-version'] != '3' ||
        headers['zotero-allowed-request'] != '1') {
      throw StateError('Unsupported Zotero desktop headers.');
    }
  }
  final client = desktop
      ? local.createStudioZoteroLocalClient()
      : http.Client();
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
