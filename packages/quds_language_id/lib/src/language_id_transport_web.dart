import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'language_id_transport.dart';

LanguageIdTransport createLanguageIdTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _WebTransport(
  workerUrl ?? Uri.base.resolve('proofing/language_id_worker.mjs'),
);

/// A module Web Worker running the bundled WebAssembly classifier. The
/// verified model bytes are posted once; the worker fetches only its own
/// same-origin code and Wasm assets.
final class _WebTransport implements LanguageIdTransport {
  _WebTransport(this.url);
  final Uri url;
  final _pending = <int, Completer<String>>{};
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
                  LanguageIdUnavailableException((failure as JSString).toDart),
                );
          }
          final fatal = message.getProperty<JSAny?>('fatal'.toJS);
          if (fatal != null &&
              fatal.isA<JSBoolean>() &&
              fatal.dartify() == true) {
            _fail(
              const LanguageIdUnavailableException(
                'The failed language identifier worker was reset.',
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
            const LanguageIdUnavailableException(
              'The local language identifier worker could not load. Check '
              'the worker and Wasm asset paths.',
            ),
          );
        }).toJS,
      );
      return worker;
    } on Object {
      throw const LanguageIdUnavailableException(
        'This browser could not start the local language identifier.',
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

  Future<String> _send(JSObject request) {
    if (_disposed) {
      return Future.error(
        const LanguageIdUnavailableException(
          'The language identifier is disposed.',
        ),
      );
    }
    final worker = _worker ??= _start();
    final id = ++_sequence;
    final result = Completer<String>();
    _pending[id] = result;
    try {
      worker.postMessage(
        JSObject()
          ..setProperty('id'.toJS, id.toJS)
          ..setProperty('request'.toJS, request),
      );
    } on Object {
      _fail(
        const LanguageIdUnavailableException(
          'The local language identifier worker could not receive the '
          'request.',
        ),
      );
    }
    return result.future;
  }

  static Map<String, Object?> _success(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['status'] != 'success') {
      throw LanguageIdUnavailableException(
        decoded is Map<String, Object?> && decoded['message'] is String
            ? decoded['message']! as String
            : 'The language identifier worker failed.',
      );
    }
    return decoded;
  }

  @override
  Future<void> open(Uint8List model) async {
    final request = JSObject()
      ..setProperty('op'.toJS, 'open'.toJS)
      ..setProperty('model'.toJS, Uint8List.fromList(model).toJS);
    _success(await _send(request));
  }

  @override
  Future<List<List<(String, double)>>> detect(List<String> texts, int k) async {
    if (texts.isEmpty) return const [];
    final request = JSObject()
      ..setProperty('op'.toJS, 'detect'.toJS)
      ..setProperty('k'.toJS, k.toJS)
      ..setProperty('texts'.toJS, [for (final t in texts) t.toJS].toJS);
    final body = _success(await _send(request));
    final results = body['results'];
    if (results is! List<Object?> || results.length != texts.length) {
      throw const FormatException('Malformed language identifier response.');
    }
    return [
      for (final guesses in results)
        [
          for (final pair in guesses! as List<Object?>)
            (
              (pair! as List<Object?>)[0]! as String,
              ((pair as List<Object?>)[1]! as num).toDouble(),
            ),
        ],
    ];
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _fail(
      const LanguageIdUnavailableException(
        'The language identifier was disposed.',
      ),
    );
  }
}
