import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'hunspell_catalog.dart';
import 'hunspell_transport.dart';

HunspellTransport createHunspellTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _WebTransport(
  workerUrl ?? Uri.base.resolve('proofing/hunspell_worker.mjs'),
);

/// A module Web Worker running the bundled WebAssembly engine. Dictionary
/// bytes are posted to it once; the worker fetches only its own same-origin
/// code and Wasm assets.
final class _WebTransport implements HunspellTransport {
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
          if (id is num && body is String) {
            _pending.remove(id.toInt())?.complete(body);
          }
          if (failure is String) {
            final pending = id is num ? _pending.remove(id.toInt()) : null;
            pending?.completeError(HunspellUnavailableException(failure));
          }
          if (value['fatal'] == true) {
            _fail(
              const HunspellUnavailableException(
                'The failed Hunspell worker was reset.',
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
            const HunspellUnavailableException(
              'The local Hunspell browser worker could not load. Check the worker and Wasm asset paths.',
            ),
          );
        }).toJS,
      );
      return worker;
    } on Object {
      throw const HunspellUnavailableException(
        'This browser could not start the local Hunspell worker.',
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

  Future<String> _send(JSAny request) {
    if (_disposed) {
      return Future.error(
        const HunspellUnavailableException('Hunspell worker is disposed.'),
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
      worker.postMessage(envelope);
    } on Object {
      _fail(
        const HunspellUnavailableException(
          'The local Hunspell browser worker could not receive the request.',
        ),
      );
    }
    return result.future;
  }

  @override
  Future<void> open(HunspellDictionary dictionary) async {
    if (dictionary is! HunspellDictionaryBytes) {
      throw const HunspellUnavailableException(
        'The browser Hunspell worker opens verified dictionary bytes.',
      );
    }
    final request = JSObject()
      ..setProperty('op'.toJS, 'open'.toJS)
      ..setProperty('aff'.toJS, dictionary.aff.toJS)
      ..setProperty('dic'.toJS, dictionary.dic.toJS);
    await _send(request);
  }

  @override
  Future<String> check(List<String> words, List<bool> suggest) =>
      _send({'op': 'check', 'words': words, 'suggest': suggest}.jsify()!);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _fail(const HunspellUnavailableException('Hunspell worker was disposed.'));
  }
}
