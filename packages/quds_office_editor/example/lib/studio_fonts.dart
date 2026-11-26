import 'dart:typed_data' show BytesBuilder;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_files.dart';
import 'studio_font_pack_host.dart';
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
        await OfficeHostFonts.registerInstalledFamily(
          family: entry.key,
          faces: <ByteData>[
            for (final face in entry.value) ByteData.sublistView(face.bytes),
          ],
        );
      } on Object {
        // Invalid or unavailable installed bytes keep the bundled fallback;
        // application-owned families retain their explicit ownership.
      }
    }
    // Optional open packs fill gaps only after exact Office/OS faces have
    // claimed their names. Installed packs therefore never override Office.
    await studioFontPackHost.registerInstalled();
    await _loadPlatformFamilies();
  }

  /// Loads a user-selected font locally for the current browser session.
  static Future<String?> importFont() async {
    const maxBytes = 16 * 1024 * 1024;
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      withReadStream: true,
      withData: false,
    );
    if (selection == null) return null;
    final file = selection.files.single;
    final stream = file.readStream;
    if (file.size < 12 || file.size > maxBytes || stream == null) {
      throw const FormatException('Unsupported font file.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length + chunk.length > maxBytes) {
        throw const FormatException('Unsupported font file.');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final font = SfntFont.parse(bytes);
    final family = font.familyName.trim();
    if (family.isEmpty ||
        family.length > 256 ||
        family.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('Invalid font family name.');
    }
    if (OfficeHostFonts.registeredFamily(family) == null) {
      await OfficeHostFonts.registerFamily(
        family: family,
        faces: [ByteData.sublistView(bytes)],
      );
    }
    return family;
  }

  static Future<void> _loadPlatformFamilies() async {
    if (kIsWeb) return;
    const channel = MethodChannel('crispoffice/font-catalog');
    try {
      final names = await channel.invokeListMethod<String>('availableFamilies');
      OfficeHostFonts.addPlatformFamilies(names ?? const <String>[]);
    } on MissingPluginException {
      // Embedded and test hosts may have no native catalog channel.
    } on PlatformException {
      // The bundled and registered families remain available.
    }
  }
}
