import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:web/web.dart' as web;

import 'morph_analysis.dart';
import 'morph_catalog.dart';
import 'morph_transport.dart';

ArabicMorphTransport createArabicMorphTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _WebTransport(
  workerUrl ?? Uri.base.resolve('proofing/arabic_morph_worker.mjs'),
);

/// A module Web Worker running the bundled WebAssembly analyzer. The verified
/// bundle bytes are posted to it once; the worker fetches only its own
/// same-origin code and Wasm assets. The parsed database occupies about
/// 320 MB of Wasm memory in the worker.
final class _WebTransport implements ArabicMorphTransport {
  _WebTransport(this.url);
  final Uri url;
  final _pending = <int, Completer<String>>{};
  final _decoder = ArabicAnalysisDecoder();
  web.Worker? _worker;
  bool _disposed = false;
  int _sequence = 0;
  int _generation = 0;

  web.Worker _start() {
    try {
      final generation = ++_generation;
      final worker = web.Worker(
        url.toString().toJS,
        web.WorkerOptions(type: 'module'),
      );
      worker.addEventListener(
        'message',
        ((web.MessageEvent event) {
          if (generation != _generation) return;
          final value = event.data;
          if (value == null || !value.isA<JSObject>()) return;
          final message = value as JSObject;
          final id = message.getProperty<JSAny?>('id'.toJS);
          final body = message.getProperty<JSAny?>('response'.toJS);
          final failure = message.getProperty<JSAny?>('unavailable'.toJS);
          final key = id != null && id.isA<JSNumber>()
              ? (id as JSNumber).toDartInt
              : null;
          if (key != null && body != null && body.isA<JSString>()) {
            _pending.remove(key)?.complete((body as JSString).toDart);
          }
          if (failure != null && failure.isA<JSString>()) {
            _pending
                .remove(key)
                ?.completeError(
                  ArabicMorphUnavailableException((failure as JSString).toDart),
                );
          }
          final fatal = message.getProperty<JSAny?>('fatal'.toJS);
          if (fatal != null &&
              fatal.isA<JSBoolean>() &&
              fatal.dartify() == true) {
            _fail(
              const ArabicMorphUnavailableException(
                'The failed Arabic morphology worker was reset.',
              ),
            );
          }
        }).toJS,
      );
      worker.addEventListener(
        'error',
        ((web.Event event) {
          if (generation != _generation) return;
          _fail(
            const ArabicMorphUnavailableException(
              'The local Arabic morphology browser worker could not load. '
              'Check the worker and Wasm asset paths.',
            ),
          );
        }).toJS,
      );
      return worker;
    } on Object {
      throw const ArabicMorphUnavailableException(
        'This browser could not start the local Arabic morphology worker.',
      );
    }
  }

  void _fail(Object error) {
    _generation++;
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    _worker?.terminate();
    _worker = null;
  }

  Future<String> _send(JSObject request, {JSArray<JSObject>? transfer}) {
    if (_disposed) {
      return Future.error(
        const ArabicMorphUnavailableException(
          'Arabic morphology worker is disposed.',
        ),
      );
    }
    final worker = _worker ??= _start();
    final id = ++_sequence;
    final result = Completer<String>();
    _pending[id] = result;
    try {
      final envelope = JSObject()
        ..setProperty('id'.toJS, id.toJS)
        ..setProperty('request'.toJS, request);
      if (transfer == null) {
        worker.postMessage(envelope);
      } else {
        worker.postMessage(envelope, transfer);
      }
    } on Object {
      _fail(
        const ArabicMorphUnavailableException(
          'The local Arabic morphology browser worker could not receive the '
          'request.',
        ),
      );
    }
    return result.future;
  }

  static Map<String, Object?> _success(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['status'] != 'success') {
      throw ArabicMorphUnavailableException(
        decoded is Map<String, Object?> && decoded['message'] is String
            ? decoded['message']! as String
            : 'The Arabic morphology worker failed.',
      );
    }
    return decoded;
  }

  @override
  Future<Map<String, Object?>> open(MorphDatabase database) async {
    if (database is! MorphDatabaseBytes) {
      throw const ArabicMorphUnavailableException(
        'The browser Arabic morphology worker opens verified bundle bytes.',
      );
    }
    // The buffers are transferred, not copied: the worker owns the only
    // copy of the 78 MB database bytes from here on.
    final buffers = <JSObject>[];
    final files = <JSAny>[
      for (final entry in database.files.entries)
        JSObject()
          ..setProperty('name'.toJS, entry.key.toJS)
          ..setProperty('bytes'.toJS, _bytes(entry.value, buffers)),
    ].toJS;
    final request = JSObject()
      ..setProperty('op'.toJS, 'open'.toJS)
      ..setProperty('manifestSha256'.toJS, database.bundle.manifest.sha256.toJS)
      ..setProperty('files'.toJS, files);
    final body = _success(await _send(request, transfer: buffers.toJS));
    return (body['info'] as Map).cast<String, Object?>();
  }

  static JSUint8Array _bytes(Uint8List data, List<JSObject> buffers) {
    final array = data.toJS;
    final buffer = array.getProperty<JSObject>('buffer'.toJS);
    if (!buffers.any((b) => identical(b, buffer))) buffers.add(buffer);
    return array;
  }

  @override
  Future<List<List<ArabicAnalysis>?>> analyze(List<String> words) async {
    if (words.isEmpty) return const [];
    final request = JSObject()
      ..setProperty('op'.toJS, 'analyze'.toJS)
      ..setProperty('words'.toJS, [for (final w in words) w.toJS].toJS);
    final body = _success(await _send(request));
    final results = body['results'];
    if (results is! List<Object?> || results.length != words.length) {
      throw const FormatException('Malformed Arabic morphology response.');
    }
    return [
      for (final item in results) item == null ? null : _decoder.decode(item),
    ];
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _fail(
      const ArabicMorphUnavailableException(
        'Arabic morphology worker was disposed.',
      ),
    );
  }
}
