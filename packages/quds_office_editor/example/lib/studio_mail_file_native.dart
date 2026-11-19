import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readStudioMailFile(String path) => File(path).readAsBytes();
