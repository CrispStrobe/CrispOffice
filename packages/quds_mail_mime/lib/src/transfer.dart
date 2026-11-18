part of 'codec.dart';

extension _TransferDecoder on _Reader {
  Uint8List? payload(_Part part, {required bool isBody}) {
    currentPath = part.path;
    final source = Uint8List.sublistView(bytes, part.bodyStart, part.end);
    final encoding =
        part.headers
            .getHeaderValue('content-transfer-encoding')
            ?.trim()
            .toLowerCase() ??
        '7bit';
    final size = _decodedLength(source, encoding);
    if (size == null) return null;
    if (decodedBytes + size > budget.maxDecodedBytes) {
      reject(
        MailDiagnosticCode.decodedLimit,
        'The cumulative decoded payload limit was exceeded.',
        decodedBytes + size,
        budget.maxDecodedBytes,
      );
    }
    if (isBody && bodyBytes + size > budget.maxBodyBytes) {
      reject(
        MailDiagnosticCode.bodyLimit,
        'The cumulative body limit was exceeded.',
        bodyBytes + size,
        budget.maxBodyBytes,
      );
    }
    if (!isBody && size > budget.maxAttachmentBytes) {
      reject(
        MailDiagnosticCode.attachmentLimit,
        'An attachment exceeds its decoded size limit.',
        size,
        budget.maxAttachmentBytes,
      );
    }
    decodedBytes += size;
    if (isBody) bodyBytes += size;
    cancellation?.throwIfCancelled();
    return _decode(source, encoding, size);
  }

  int? _decodedLength(Uint8List source, String encoding) {
    if (encoding == '8bit' || encoding == 'binary') return source.length;
    if (encoding == '7bit') {
      if (source.any((byte) => byte > 127)) {
        note(
          MailDiagnosticCode.malformedEncoding,
          'A 7bit payload contains non-ASCII bytes; use original source.',
        );
        return null;
      }
      return source.length;
    }
    if (encoding == 'base64') {
      var count = 0;
      var padding = 0;
      var lastValue = 0;
      for (var i = 0; i < source.length; i++) {
        if ((i & 0xffff) == 0) cancellation?.throwIfCancelled();
        final value = source[i];
        if (_white(value)) continue;
        count++;
        if (value == 61) {
          padding++;
        } else {
          final digit = _base64Value(value);
          if (digit < 0 || padding != 0) return _badTransfer();
          lastValue = digit;
        }
      }
      if (count % 4 != 0 ||
          padding > 2 ||
          (padding == 1 && lastValue & 3 != 0) ||
          (padding == 2 && lastValue & 15 != 0)) {
        return _badTransfer();
      }
      return count ~/ 4 * 3 - padding;
    }
    if (encoding == 'quoted-printable') {
      var count = 0;
      for (var i = 0; i < source.length; i++) {
        if ((i & 0xffff) == 0) cancellation?.throwIfCancelled();
        final value = source[i];
        if (value == 61) {
          if (i + 1 < source.length && source[i + 1] == 10) {
            i++;
            continue;
          }
          if (i + 2 < source.length &&
              source[i + 1] == 13 &&
              source[i + 2] == 10) {
            i += 2;
            continue;
          }
          if (i + 2 >= source.length ||
              _hex(source[i + 1]) < 0 ||
              _hex(source[i + 2]) < 0) {
            return _badTransfer();
          }
          i += 2;
        } else if (value > 126 ||
            (value < 32 && value != 9 && value != 10 && value != 13)) {
          return _badTransfer();
        }
        count++;
      }
      return count;
    }
    note(
      MailDiagnosticCode.unsupportedTransferEncoding,
      'A transfer encoding is unsupported; use original source.',
    );
    return null;
  }

  int? _badTransfer() {
    note(
      MailDiagnosticCode.malformedEncoding,
      'A transfer payload is malformed; use original source.',
    );
    return null;
  }

  Uint8List _decode(Uint8List source, String encoding, int size) {
    if (encoding == '7bit' || encoding == '8bit' || encoding == 'binary') {
      return source;
    }
    final output = Uint8List(size);
    var position = 0;
    if (encoding == 'base64') {
      var accumulator = 0;
      var bits = 0;
      for (final value in source) {
        if (_white(value) || value == 61) continue;
        accumulator = (accumulator << 6) | _base64Value(value);
        bits += 6;
        if (bits >= 8) {
          bits -= 8;
          if (position < size) {
            output[position++] = (accumulator >> bits) & 0xff;
          }
          accumulator &= (1 << bits) - 1;
        }
      }
    } else {
      for (var i = 0; i < source.length; i++) {
        if (source[i] != 61) {
          output[position++] = source[i];
          continue;
        }
        if (source[i + 1] == 10) {
          i++;
          continue;
        }
        if (source[i + 1] == 13 && source[i + 2] == 10) {
          i += 2;
          continue;
        }
        output[position++] = (_hex(source[i + 1]) << 4) | _hex(source[i + 2]);
        i += 2;
      }
    }
    return output;
  }
}

bool _white(int value) =>
    value == 32 || value == 9 || value == 10 || value == 13;
int _hex(int value) => value >= 48 && value <= 57
    ? value - 48
    : value >= 65 && value <= 70
    ? value - 55
    : value >= 97 && value <= 102
    ? value - 87
    : -1;
int _base64Value(int value) => value >= 65 && value <= 90
    ? value - 65
    : value >= 97 && value <= 122
    ? value - 71
    : value >= 48 && value <= 57
    ? value + 4
    : value == 43
    ? 62
    : value == 47
    ? 63
    : -1;
