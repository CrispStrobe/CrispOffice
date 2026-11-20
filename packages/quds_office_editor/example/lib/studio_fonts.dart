import 'dart:typed_data';

import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_files.dart';
import 'studio_pdf_faces.dart';

/// Studio extras on top of [OfficeHostFonts].
///
/// Core Liberation / Noto faces ship inside `quds_office_editor`. Cairo and
/// Tajawal ship with this example so PDF samples embed Arabic-capable faces.
abstract final class StudioFonts {
  static Future<void> register() async {
    await OfficeHostFonts.ensureRegistered();
    await StudioFiles.installBundledAssets();
    await StudioPdfFaces.ensureLoaded();
    await StudioPdfFaces.registerFlutterFaces();
    // Prefer the exact Office/OS faces installed on this machine. They are
    // loaded at runtime and remain optional on web or minimal systems.
    final system = await OfficeSystemFonts.load();
    final byFamily = <String, List<OfficeSystemFontFace>>{};
    for (final face in system) {
      byFamily
          .putIfAbsent(face.family, () => <OfficeSystemFontFace>[])
          .add(face);
    }
    for (final entry in byFamily.entries) {
      try {
        await OfficeHostFonts.registerFamily(
          family: entry.key,
          faces: <ByteData>[
            for (final face in entry.value) ByteData.sublistView(face.bytes),
          ],
          hasItalic: entry.value.any((face) => face.italic),
        );
      } on Object {
        // Bundled compatibility aliases keep their existing ownership.
      }
    }
  }
}
