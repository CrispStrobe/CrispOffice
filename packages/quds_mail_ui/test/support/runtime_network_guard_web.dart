import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('fetch')
external JSFunction get _fetch;
@JS('fetch')
external set _fetch(JSFunction value);
@JS('XMLHttpRequest.prototype.open')
external JSFunction get _xhrOpen;
@JS('XMLHttpRequest.prototype.open')
external set _xhrOpen(JSFunction value);
@JS('HTMLImageElement.prototype')
external JSObject get _imagePrototype;
@JS('HTMLIFrameElement.prototype')
external JSObject get _framePrototype;
@JS('HTMLScriptElement.prototype')
external JSObject get _scriptPrototype;
@JS('HTMLLinkElement.prototype')
external JSObject get _linkPrototype;
@JS('HTMLSourceElement.prototype')
external JSObject get _sourcePrototype;
@JS('Object.getOwnPropertyDescriptor')
external JSObject _getDescriptor(JSObject target, JSString name);
@JS('Object.defineProperty')
external void _defineProperty(
  JSObject target,
  JSString name,
  JSObject descriptor,
);

/// Installed after test bootstrap. Denies fetch/XHR and remote image, iframe,
/// script, stylesheet and source assignments; permits in-memory data/blob rasters.
final class RuntimeNetworkGuard {
  int attempts = 0;
  Future<void> run(Future<void> Function() body) async {
    final fetch = _fetch, xhr = _xhrOpen;
    final properties = <(JSObject, String, JSObject)>[];
    JSAny? denyFetch(JSAny? input, JSAny? options) {
      attempts++;
      throw StateError('Outbound fetch disabled by reader qualification.');
    }

    _fetch = denyFetch.toJS;
    void denyXhr(JSAny? method, JSAny? url, JSAny? async) {
      attempts++;
      throw StateError('Outbound XHR disabled by reader qualification.');
    }

    _xhrOpen = denyXhr.toJS;
    for (final (prototype, name) in [
      (_imagePrototype, 'src'),
      (_imagePrototype, 'srcset'),
      (_framePrototype, 'src'),
      (_scriptPrototype, 'src'),
      (_linkPrototype, 'href'),
      (_sourcePrototype, 'src'),
      (_sourcePrototype, 'srcset'),
    ]) {
      final descriptor = _getDescriptor(prototype, name.toJS);
      properties.add((prototype, name, descriptor));
      final setter = descriptor.getProperty<JSFunction>('set'.toJS);
      final replacement = JSObject();
      replacement.setProperty('configurable'.toJS, true.toJS);
      replacement.setProperty(
        'get'.toJS,
        descriptor.getProperty<JSAny?>('get'.toJS),
      );
      replacement.setProperty(
        'set'.toJS,
        ((JSObject target, JSString value) {
          final text = value.toDart;
          if (!text.startsWith('data:') &&
              !text.startsWith('blob:') &&
              text.isNotEmpty) {
            attempts++;
            throw StateError(
              'Remote element resource disabled by reader qualification.',
            );
          }
          setter.callAsFunction(target, value);
        }).toJSCaptureThis,
      );
      _defineProperty(prototype, name.toJS, replacement);
    }
    try {
      await body();
    } finally {
      _fetch = fetch;
      _xhrOpen = xhr;
      for (final (prototype, name, descriptor) in properties) {
        _defineProperty(prototype, name.toJS, descriptor);
      }
    }
  }

  void probe() {
    try {
      _fetch.callAsFunction(null, 'https://runtime-probe.invalid/'.toJS);
    } on Object {
      /* The deliberate positive control is denied. */
    }
  }
}
