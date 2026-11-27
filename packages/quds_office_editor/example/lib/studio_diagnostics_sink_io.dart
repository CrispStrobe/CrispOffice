import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'studio_native_paths.dart';

const _maxBytes = 128 * 1024;

void writeStudioDiagnostic(Map<String, Object> entry) {
  try {
    final directory = Directory(
      p.join(studioPrivateDataDirectory(), 'diagnostics'),
    )..createSync(recursive: true);
    final file = File(p.join(directory.path, 'session.jsonl'));
    final line = utf8.encode(
      '${jsonEncode({'utc': DateTime.now().toUtc().toIso8601String(), 'pid': pid, ...entry})}\n',
    );
    if (file.existsSync() && file.lengthSync() + line.length > _maxBytes) {
      file.renameSync(p.join(directory.path, 'session.previous.jsonl'));
    }
    // Flush these infrequent milestones before entering code that may fault.
    file.writeAsBytesSync(line, mode: FileMode.append, flush: true);
  } on FileSystemException {
    // Diagnostics must never prevent application startup or error reporting.
  }
}
