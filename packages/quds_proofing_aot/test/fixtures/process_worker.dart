// Test-only worker. It deliberately exercises protocol failures and never loads
// AOT or opens a network connection.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final String mode = Platform.environment['QUDS_TEST_MODE'] ?? 'echo';
  final String? marker = Platform.environment['QUDS_TEST_MARKER'];
  if (marker != null) File(marker).writeAsStringSync('$pid');
  if (mode == 'unsolicited') {
    stdout.writeln('{"id":0,"result":[]}');
    await stdout.flush();
  }
  await for (final String line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final Map<String, Object?> request =
        jsonDecode(line) as Map<String, Object?>;
    final Object? id = request['id'];
    if (mode == 'hang') {
      await Future<void>.delayed(const Duration(days: 1));
    }
    if (mode == 'delay') {
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    if (mode == 'crash') exit(7);
    if (mode == 'stderr-flood') {
      stderr.add(List<int>.filled(8192, 120));
      await stderr.flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final Object output = switch (mode) {
      'wrong-id' => <String, Object?>{'id': 4000, 'result': <Object?>[]},
      'double-payload' => <String, Object?>{
        'id': id,
        'result': <Object?>[],
        'error': 'private response',
      },
      'missing-payload' => <String, Object?>{'id': id},
      'float-id' => <String, Object?>{
        'id': (id as int).toDouble(),
        'result': 1,
      },
      'unknown-field' => <String, Object?>{
        'id': id,
        'result': 1,
        'secret': 'private response',
      },
      'non-object' => <int>[1, 2],
      'engine-error' => <String, Object?>{
        'id': id,
        'error': 'private document text must not be exposed',
        'code': 'engineFailure',
      },
      'engine-limit' => <String, Object?>{
        'id': id,
        'error': 'private limit detail',
        'code': 'limit',
      },
      'unsupported' => <String, Object?>{
        'id': id,
        'error': 'private locale detail',
        'code': 'unsupportedLanguage',
      },
      _ => <String, Object?>{
        'id': id,
        'result': <String, Object?>{
          'request': request,
          'pid': pid,
          'arguments': arguments,
          'rml': Platform.environment['RML'],
          'extra': Platform.environment['QUDS_TEST_EXTRA'],
        },
      },
    };
    final String encoded = jsonEncode(output);
    if (mode == 'flood') {
      stdout.add(List<int>.filled(8192, 120));
    } else if (mode == 'invalid-utf8') {
      stdout.add(<int>[0xc0, 0x80, 10]);
    } else if (mode == 'invalid-json') {
      stdout.writeln('private text {');
    } else if (mode == 'truncated') {
      stdout.write(encoded);
      await stdout.flush();
      exit(0);
    } else if (mode == 'split-bytes') {
      for (final int byte in utf8.encode('$encoded\n')) {
        stdout.add(<int>[byte]);
        await stdout.flush();
      }
    } else if (mode == 'duplicate') {
      stdout.write('$encoded\n$encoded\n');
    } else {
      stdout.writeln(encoded);
    }
    await stdout.flush();
  }
}
