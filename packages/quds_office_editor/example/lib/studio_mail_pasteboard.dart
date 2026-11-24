import 'dart:typed_data';

import 'package:flutter/services.dart';

/// One file-like item read from the macOS pasteboard.
final class StudioMailPasteboardItem {
  const StudioMailPasteboardItem({
    required this.name,
    required this.bytes,
    this.mediaType,
  });

  final String name;
  final Uint8List bytes;
  final String? mediaType;
}

/// Reads file URLs or an image from the native pasteboard.
///
/// Flutter's Clipboard API cannot expose Finder file promises or image types.
/// The macOS runner implements a bounded read; every other platform returns an
/// empty list rather than pretending the pasteboard is empty.
final class StudioMailPasteboard {
  const StudioMailPasteboard();

  static const MethodChannel _channel = MethodChannel(
    'crispoffice/mail_pasteboard',
  );

  Future<List<StudioMailPasteboardItem>> read() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('read');
      if (raw == null) return const [];
      final items = <StudioMailPasteboardItem>[];
      for (final value in raw.take(8)) {
        if (value is! Map) continue;
        final name = value['name'];
        final bytes = value['bytes'];
        final mediaType = value['mediaType'];
        if (name is! String ||
            bytes is! Uint8List ||
            name.isEmpty ||
            bytes.isEmpty) {
          continue;
        }
        items.add(
          StudioMailPasteboardItem(
            name: name,
            bytes: bytes,
            mediaType: mediaType is String ? mediaType : null,
          ),
        );
      }
      return List.unmodifiable(items);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      throw const StudioMailPasteboardException();
    }
  }
}

final class StudioMailPasteboardException implements Exception {
  const StudioMailPasteboardException();
}
