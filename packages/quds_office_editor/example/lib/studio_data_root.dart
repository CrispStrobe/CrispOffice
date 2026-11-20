import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The platform's private application-support directory on iOS and Android,
/// resolved once at startup by [initializeStudioDataRoot]. Native backend
/// hosts are created synchronously later and read it through
/// `studioPrivateDataDirectory()`. Null elsewhere and before initialization.
String? studioMobileDataRoot;

/// Resolves [studioMobileDataRoot] (iOS: the sandbox container's
/// `Library/Application Support`; Android: `Context.getFilesDir()`).
Future<void> initializeStudioDataRoot() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android)) {
    return;
  }
  try {
    studioMobileDataRoot = (await getApplicationSupportDirectory()).path;
  } on Object {
    // Fall back to the synchronous derivation in studio_native_paths.dart.
  }
}
