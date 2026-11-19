import 'dart:convert';
import 'dart:typed_data';

/// Indexing projection only. This never renders HTML, opens a URL, follows a
/// reference, or executes an attachment. Input work is bounded by the caller.
String archiveHtmlText(String input) {
  final out = StringBuffer();
  var position = 0;
  while (position < input.length) {
    if (input.codeUnitAt(position) != 60) {
      final next = input.indexOf('<', position);
      final end = next < 0 ? input.length : next;
      out.write(_entities(input.substring(position, end)));
      position = end;
      continue;
    }
    if (input.startsWith('<!--', position)) {
      final end = input.indexOf('-->', position + 4);
      if (end < 0) break;
      position = end + 3;
      out.write(' ');
      continue;
    }
    var quote = 0;
    var end = position + 1;
    for (; end < input.length; end++) {
      final char = input.codeUnitAt(end);
      if (quote != 0) {
        if (char == quote) quote = 0;
      } else if (char == 34 || char == 39) {
        quote = char;
      } else if (char == 62) {
        break;
      }
    }
    if (end == input.length) break;
    final tag = input.substring(position + 1, end).trim();
    position = end + 1;
    final name = RegExp(
      r'^([A-Za-z][A-Za-z0-9]*)\b',
    ).firstMatch(tag)?.group(1)?.toLowerCase();
    if (const {
      'script',
      'style',
      'iframe',
      'object',
      'template',
      'head',
    }.contains(name)) {
      final close = RegExp(
        '</\\s*$name\\s*>',
        caseSensitive: false,
      ).matchAsPrefix(input, position);
      if (close != null) {
        position = close.end;
      } else {
        final closing = RegExp(
          '</\\s*$name\\s*>',
          caseSensitive: false,
        ).firstMatch(input.substring(position));
        if (closing == null) break;
        position += closing.end;
      }
    }
    out.write(' ');
  }
  return out.toString();
}

String _entities(String input) => input.replaceAllMapped(
  RegExp(r'&(#x[0-9a-fA-F]{1,6}|#[0-9]{1,7}|amp|lt|gt|quot|apos|nbsp);'),
  (match) {
    final value = match.group(1)!;
    if (value.startsWith('#')) {
      final code = value.startsWith('#x')
          ? int.tryParse(value.substring(2), radix: 16)
          : int.tryParse(value.substring(1));
      if (code == null ||
          code < 1 ||
          code > 0x10ffff ||
          (code >= 0xd800 && code <= 0xdfff)) {
        return ' ';
      }
      return String.fromCharCode(code);
    }
    return switch (value) {
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      _ => ' ',
    };
  },
);

/// Strict UTF-8 or BOM-marked UTF-16; unsupported/malformed charsets are skipped
/// explicitly by the archive, while their original MIME remains intact.
String decodeArchiveTextAttachment(Uint8List bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if (bytes.length.isOdd) throw const FormatException();
    final little = bytes[0] == 0xff;
    final units = <int>[];
    for (var i = 2; i < bytes.length; i += 2) {
      units.add(
        little
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException();
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException();
      }
    }
    return String.fromCharCodes(units);
  }
  final start =
      bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf
      ? 3
      : 0;
  return utf8.decode(Uint8List.sublistView(bytes, start));
}

String archiveTextPrefix(String input, int limit) {
  if (input.length <= limit) return input;
  var end = limit;
  if (end > 0 &&
      input.codeUnitAt(end - 1) >= 0xd800 &&
      input.codeUnitAt(end - 1) <= 0xdbff) {
    end--;
  }
  return input.substring(0, end);
}
