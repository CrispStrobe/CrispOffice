import 'dart:typed_data';

/// Browsers supply the user-selected file bytes through FilePicker.
/// A platform path is never treated as a URL or fetched over the network.
Future<Uint8List?> readStudioMailFile(String path) async => null;

/// Browser paths are never URLs. Only picker-supplied streams/bytes are read.
Stream<List<int>>? openStudioMailAttachmentFile(
  String path, {
  required int maxBytes,
}) => null;
