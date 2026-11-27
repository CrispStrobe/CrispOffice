import 'package:flutter/foundation.dart';

import 'studio_diagnostics_sink.dart'
    if (dart.library.io) 'studio_diagnostics_sink_io.dart';

enum StudioDiagnosticEvent {
  started,
  mailRequested,
  mailMounted,
  mailCredentialLoadStarted,
  mailCredentialLoadFinished,
  mailCredentialLoadFailed,
  frameworkError,
  isolateError,
}

var _errorsRemaining = 24;
var _installed = false;

void installStudioDiagnostics() {
  if (_installed) return;
  _installed = true;
  recordStudioDiagnostic(StudioDiagnosticEvent.started);
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    _recordError(
      StudioDiagnosticEvent.frameworkError,
      details.exception,
      details.stack,
    );
    previousFlutterHandler?.call(details);
  };
  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    _recordError(StudioDiagnosticEvent.isolateError, error, stack);
    return previousPlatformHandler?.call(error, stack) ?? false;
  };
}

void recordStudioDiagnostic(StudioDiagnosticEvent event) {
  if (_installed) writeStudioDiagnostic(<String, Object>{'event': event.name});
}

final _safeType = RegExp(r'^[A-Za-z_][A-Za-z_0-9]{0,79}$');
final _packageFrame = RegExp(
  r'^#\d+\s+[\w.$<> ()-]+\(package:[A-Za-z_0-9/.-]+:\d+(?::\d+)?\)$',
);

void _recordError(
  StudioDiagnosticEvent event,
  Object error,
  StackTrace? stack,
) {
  if (_errorsRemaining == 0) return;
  _errorsRemaining--;
  final type = error.runtimeType.toString();
  // Exception text, file paths and log payloads can carry account data.
  writeStudioDiagnostic(<String, Object>{
    'event': event.name,
    if (_safeType.hasMatch(type)) 'type': type,
    'frames': (stack?.toString().split('\n') ?? const <String>[])
        .where((line) => line.length < 220 && _packageFrame.hasMatch(line))
        .take(16)
        .toList(growable: false),
  });
}
