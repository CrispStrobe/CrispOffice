import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'harper_transport.dart';

HarperTransport createHarperTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) =>
    _WebTransport(workerUrl ?? Uri.base.resolve('proofing/harper_worker.mjs'));

final class _WebTransport implements HarperTransport {
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
          final value = event.data.dartify();
          if (value is! Map<Object?, Object?>) return;
          final id = value['id'];
          final body = value['response'];
          final failure = value['unavailable'];
          if (id is int && body is String) _pending.remove(id)?.complete(body);
          if (failure is String) _fail(HarperUnavailableException(failure));
          if (value['fatal'] == true) {
            _fail(
              const HarperUnavailableException(
                'The failed Harper worker was reset.',
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
            const HarperUnavailableException(
              'The local Harper browser worker could not load. Check the worker and Wasm asset paths.',
            ),
          );
        }).toJS,
      );
      worker.addEventListener(
        'messageerror',
        ((web.Event event) {
          if (generation != _generation) return;
          _fail(
            const HarperUnavailableException(
              'The local Harper browser worker returned an unreadable message.',
            ),
          );
        }).toJS,
      );
      return worker;
    } on Object {
      throw const HarperUnavailableException(
        'This browser could not start the local Harper worker.',
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

  @override
  Future<String> check(String request) {
    if (_disposed)
      return Future.error(
        const HarperUnavailableException('Harper worker is disposed.'),
      );
    final worker = _worker ??= _start();
    final id = ++_sequence;
    final result = Completer<String>();
    _pending[id] = result;
    try {
      worker.postMessage({'id': id, 'request': request}.jsify());
    } on Object {
      _fail(
        const HarperUnavailableException(
          'The local Harper browser worker could not receive the request.',
        ),
      );
    }
    return result.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _fail(const HarperUnavailableException('Harper worker was disposed.'));
  }
}
