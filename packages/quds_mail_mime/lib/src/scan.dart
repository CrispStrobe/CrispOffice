part of 'codec.dart';

extension _RangeScanner on _Reader {
  _Part scan(int start, int end, String path, int depth) {
    currentPath = path;
    cancellation?.throwIfCancelled();
    if (++partCount > budget.maxParts) {
      reject(
        MailDiagnosticCode.partCountLimit,
        'The MIME part count limit was exceeded.',
        partCount,
        budget.maxParts,
      );
    }
    if (depth > budget.maxNestingDepth) {
      reject(
        MailDiagnosticCode.nestingLimit,
        'The MIME nesting limit was exceeded.',
        depth,
        budget.maxNestingDepth,
      );
    }
    var offset = start;
    var fieldBytes = 0;
    var foundSeparator = false;
    final buffer = StringBuffer();
    final invalidHeaders = <String>{};
    final seenStructuralHeaders = <String>{};
    var headerName = '';
    while (offset < end) {
      final lineStart = offset;
      var lineEnd = offset;
      while (lineEnd < end && bytes[lineEnd] != 10 && bytes[lineEnd] != 13) {
        if (lineEnd - start > budget.maxHeaderBytes) {
          reject(
            MailDiagnosticCode.headerLimit,
            'The header block limit was exceeded.',
            lineEnd - start,
            budget.maxHeaderBytes,
          );
        }
        if (lineEnd - lineStart > budget.maxHeaderFieldBytes) {
          reject(
            MailDiagnosticCode.headerFieldLimit,
            'A logical header field exceeds its limit.',
            lineEnd - lineStart,
            budget.maxHeaderFieldBytes,
          );
        }
        lineEnd++;
      }
      offset = lineEnd;
      if (offset < end && bytes[offset] == 13) offset++;
      if (offset < end && bytes[offset] == 10) offset++;
      if (lineEnd == lineStart) {
        foundSeparator = true;
        break;
      }
      final continuation = bytes[lineStart] == 32 || bytes[lineStart] == 9;
      if (!continuation) fieldBytes = 0;
      fieldBytes += offset - lineStart;
      if (fieldBytes > budget.maxHeaderFieldBytes) {
        reject(
          MailDiagnosticCode.headerFieldLimit,
          'A logical header field exceeds its limit.',
          fieldBytes,
          budget.maxHeaderFieldBytes,
        );
      }
      if (headerBytes + offset - start > budget.maxHeaderBytes) {
        reject(
          MailDiagnosticCode.headerLimit,
          'The header block limit was exceeded.',
          headerBytes + offset - start,
          budget.maxHeaderBytes,
        );
      }
      final lineBytes = Uint8List.sublistView(bytes, lineStart, lineEnd);
      String line;
      var validUtf8 = true;
      try {
        line = utf8.decode(lineBytes, allowMalformed: false);
      } on FormatException {
        line = latin1.decode(lineBytes);
        note(
          MailDiagnosticCode.malformedEncoding,
          'An unencoded header is not valid UTF-8; use original source.',
        );
        validUtf8 = false;
      }
      if (!continuation) {
        final colon = line.indexOf(':');
        if (colon < 1 ||
            !RegExp(r'^[!-9;-~]+$').hasMatch(line.substring(0, colon))) {
          malformed('A header field name or separator is invalid.');
        }
        headerName = line.substring(0, colon).toLowerCase();
        if ({
              'content-type',
              'content-disposition',
              'content-transfer-encoding',
            }.contains(headerName) &&
            !seenStructuralHeaders.add(headerName)) {
          malformed('Duplicate structural MIME headers are ambiguous.');
        }
      } else if (headerName.isEmpty) {
        malformed('A folded header has no preceding field.');
      }
      if (!validUtf8) invalidHeaders.add(headerName);
      if (!_validEncodedWords(line)) invalidHeaders.add(headerName);
      buffer
        ..write(line)
        ..write('\r\n');
    }
    headerBytes += offset - start;
    if (headerBytes > budget.maxHeaderBytes) {
      reject(
        MailDiagnosticCode.headerLimit,
        'The cumulative header limit was exceeded.',
        headerBytes,
        budget.maxHeaderBytes,
      );
    }
    if (!foundSeparator) {
      note(
        MailDiagnosticCode.truncatedMessage,
        'The message ends before the header/body separator.',
      );
    }
    buffer.write('\r\n');
    final headers = mime.MimeMessage.parseFromText(buffer.toString());
    final part = _Part(path, headers, offset, end);
    part.invalidHeaders.addAll(invalidHeaders);
    // Force lazy header/parameter decoding inside this part's diagnostic scope.
    final type = headers.getHeaderContentType();
    headers.getHeaderContentDisposition();
    if (part.mediaType.startsWith('multipart/')) {
      final boundary = type?.boundary;
      if (boundary == null ||
          boundary.isEmpty ||
          boundary.length > 70 ||
          boundary.codeUnits.any((v) => v < 32 || v > 126) ||
          boundary.endsWith(' ')) {
        malformed('A multipart boundary is absent or invalid.');
      }
      final transfer = headers
          .getHeaderValue('content-transfer-encoding')
          ?.trim()
          .toLowerCase();
      if (transfer != null && !{'7bit', '8bit', 'binary'}.contains(transfer)) {
        note(
          MailDiagnosticCode.unsupportedTransferEncoding,
          'Encoded multipart containers are unsupported; use original source.',
        );
        throw const _Stop(MailParseStatus.unsupported);
      }
      final marker = ascii.encode('--$boundary');
      int? childStart;
      var closed = false;
      var cursor = offset;
      while (cursor < end) {
        cancellation?.throwIfCancelled();
        final lineStart = cursor;
        while (cursor < end && bytes[cursor] != 10 && bytes[cursor] != 13) {
          cursor++;
        }
        final lineEnd = cursor;
        if (cursor < end && bytes[cursor] == 13) cursor++;
        if (cursor < end && bytes[cursor] == 10) cursor++;
        if (lineEnd - lineStart < marker.length) continue;
        var matches = true;
        for (var i = 0; i < marker.length; i++) {
          if (bytes[lineStart + i] != marker[i]) {
            matches = false;
            break;
          }
        }
        if (!matches) continue;
        var rest = lineStart + marker.length;
        final closing =
            rest + 1 < lineEnd && bytes[rest] == 45 && bytes[rest + 1] == 45;
        if (closing) rest += 2;
        while (rest < lineEnd && (bytes[rest] == 32 || bytes[rest] == 9)) {
          rest++;
        }
        if (rest != lineEnd) {
          continue; // A prefix inside content is not a delimiter.
        }
        if (childStart != null) {
          var childEnd = lineStart;
          // The CRLF introducing a boundary belongs to that delimiter, not the
          // preceding payload (RFC 2046). All other payload octets are retained.
          if (childEnd > childStart && bytes[childEnd - 1] == 10) childEnd--;
          if (childEnd > childStart && bytes[childEnd - 1] == 13) childEnd--;
          part.children.add(
            scan(
              childStart,
              childEnd,
              '$path.${part.children.length + 1}',
              depth + 1,
            ),
          );
          currentPath = path;
        }
        if (closing) {
          closed = true;
          break;
        }
        childStart = cursor;
      }
      if (!closed) {
        note(
          MailDiagnosticCode.truncatedMessage,
          'A multipart closing delimiter is missing.',
        );
        if (childStart != null && childStart < end) {
          part.children.add(
            scan(
              childStart,
              end,
              '$path.${part.children.length + 1}',
              depth + 1,
            ),
          );
        }
      }
      if (part.children.isEmpty) {
        malformed('A multipart message contains no readable parts.');
      }
    }
    return part;
  }

  bool _validEncodedWords(String line) {
    var offset = 0;
    var valid = true;
    while (true) {
      final start = line.indexOf('=?', offset);
      if (start == -1) return valid;
      final end = line.indexOf('?=', start + 2);
      if (end == -1) {
        note(
          MailDiagnosticCode.malformedEncoding,
          'An encoded header word is incomplete; use original source.',
        );
        return false;
      }
      final sections = line.substring(start + 2, end).split('?');
      if (sections.length != 3 ||
          sections.first.isEmpty ||
          !{'b', 'q'}.contains(sections[1].toLowerCase()) ||
          sections[2].codeUnits.any((v) => v < 33 || v > 126)) {
        note(
          MailDiagnosticCode.malformedEncoding,
          'An encoded header word is malformed; use original source.',
        );
        valid = false;
      } else {
        final source = Uint8List.fromList(
          ascii.encode(
            sections[2].replaceAll(
              sections[1].toLowerCase() == 'q' ? '_' : '\x00',
              ' ',
            ),
          ),
        );
        final encoding = sections[1].toLowerCase() == 'b'
            ? 'base64'
            : 'quoted-printable';
        final size = _decodedLength(source, encoding);
        if (size == null) {
          valid = false;
        } else {
          final decoded = _decode(source, encoding, size);
          if (mime.MailCodec.decodeCharsetStrict(decoded, sections.first) ==
              null) {
            valid = false;
          }
        }
      }
      offset = end + 2;
    }
  }
}
