import 'dart:typed_data';

import 'package:quds_language_id/quds_language_id.dart';

/// Compile the public identifier through the actual browser libraries.
///
/// This probe binds the conditional web transport and its JavaScript interop.
/// Its deliberately invalid fixture model is never a browser/Worker/Wasm
/// acceptance test; the qualification driver compiles it without executing it.
Future<void> main() async {
  final identifier = Cld3LanguageIdentifier(model: Uint8List(0));
  await identifier.identify(const ['A browser compilation probe.']);
  await identifier.dispose();
}
