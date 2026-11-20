import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readStudioMailFile(String path) => File(path).readAsBytes();

/// A selected attachment is read through a bounded stream. The extra byte lets
/// the caller detect a file that grew after the picker reported its length.
Stream<List<int>> openStudioMailAttachmentFile(
  String path, {
  required int maxBytes,
}) => File(path).openRead(0, maxBytes + 1);
