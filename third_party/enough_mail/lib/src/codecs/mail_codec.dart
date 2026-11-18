import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:enough_convert/koi8.dart';
import 'package:enough_convert/latin.dart';
import 'package:enough_convert/windows.dart';

import '../mail_conventions.dart';
import '../mime_diagnostics.dart';
import '../private/util/ascii_runes.dart';
import 'base64_mail_codec.dart';
import 'quoted_printable_mail_codec.dart';

/// The used header encoding mechanism
enum HeaderEncoding {
  /// Q encoding similar to QuotedPrintable
  Q,

  /// Base64 encoding
  B,

  /// No encoding
  none,
}

/// Encodes and decodes base-64 and quoted printable encoded texts
///
/// Compare https://tools.ietf.org/html/rfc2045#page-19
/// and https://tools.ietf.org/html/rfc2045#page-23 for details
abstract class MailCodec {
  /// Creates a new mail codec
  const MailCodec();

  /// No transfer encoding
  static const String contentTransferEncodingNone = 'none';

  /// Typical maximum length of a single text line
  static const String _encodingEndSequence = '?=';
  static final _headerEncodingExpression = RegExp(
    r'\=\?.+?\?.+?\?.+?\?\=',
  ); // the question marks after plus make this regular expression non-greedy
  static final _emptyHeaderEncodingExpression = RegExp(r'\=\?.+?\?.+?\?\?\=');

  /// UTF8 encoding
  static const encodingUtf8 = convert.Utf8Codec(allowMalformed: true);

  /// ISO-8859-1 encoding
  static const encodingLatin1 = convert.Latin1Codec(allowInvalid: true);

  /// ASCII encoding
  static const encodingAscii = convert.AsciiCodec(allowInvalid: true);
  static final _charsetCodecsByName =
      <String, convert.Encoding Function(bool allowInvalid)>{
        'utf-8': (allowInvalid) =>
            convert.Utf8Codec(allowMalformed: allowInvalid),
        'utf8': (allowInvalid) =>
            convert.Utf8Codec(allowMalformed: allowInvalid),
        'latin-1': (allowInvalid) =>
            convert.Latin1Codec(allowInvalid: allowInvalid),
        'iso-8859-1': (allowInvalid) =>
            convert.Latin1Codec(allowInvalid: allowInvalid),
        'iso8859-1': (allowInvalid) =>
            convert.Latin1Codec(allowInvalid: allowInvalid),
        'iso-8859-2': (allowInvalid) => Latin2Codec(allowInvalid: allowInvalid),
        'iso8859-2': (allowInvalid) => Latin2Codec(allowInvalid: allowInvalid),
        'iso-8859-3': (allowInvalid) => Latin3Codec(allowInvalid: allowInvalid),
        'iso8859-3': (allowInvalid) => Latin3Codec(allowInvalid: allowInvalid),
        'iso-8859-4': (allowInvalid) => Latin4Codec(allowInvalid: allowInvalid),
        'iso8859-4': (allowInvalid) => Latin4Codec(allowInvalid: allowInvalid),
        'iso-8859-5': (allowInvalid) => Latin5Codec(allowInvalid: allowInvalid),
        'iso8859-5': (allowInvalid) => Latin5Codec(allowInvalid: allowInvalid),
        'iso-8859-6': (allowInvalid) => Latin6Codec(allowInvalid: allowInvalid),
        'iso8859-6': (allowInvalid) => Latin6Codec(allowInvalid: allowInvalid),
        'iso-8859-7': (allowInvalid) => Latin7Codec(allowInvalid: allowInvalid),
        'iso8859-7': (allowInvalid) => Latin7Codec(allowInvalid: allowInvalid),
        'iso-8859-8': (allowInvalid) => Latin8Codec(allowInvalid: allowInvalid),
        'iso8859-8': (allowInvalid) => Latin8Codec(allowInvalid: allowInvalid),
        'iso-8859-9': (allowInvalid) => Latin9Codec(allowInvalid: allowInvalid),
        'iso8859-9': (allowInvalid) => Latin9Codec(allowInvalid: allowInvalid),
        'iso-8859-10': (allowInvalid) =>
            Latin10Codec(allowInvalid: allowInvalid),
        'iso8859-10': (allowInvalid) =>
            Latin10Codec(allowInvalid: allowInvalid),
        'iso-8859-11': (allowInvalid) =>
            Latin11Codec(allowInvalid: allowInvalid),
        'iso8859-11': (allowInvalid) =>
            Latin11Codec(allowInvalid: allowInvalid),
        // iso-8859-12 does not exist...
        'iso-8859-13': (allowInvalid) =>
            Latin13Codec(allowInvalid: allowInvalid),
        'iso8859-13': (allowInvalid) =>
            Latin13Codec(allowInvalid: allowInvalid),
        'iso-8859-14': (allowInvalid) =>
            Latin14Codec(allowInvalid: allowInvalid),
        'iso8859-14': (allowInvalid) =>
            Latin14Codec(allowInvalid: allowInvalid),
        'iso-8859-15': (allowInvalid) =>
            Latin15Codec(allowInvalid: allowInvalid),
        'iso8859-15': (allowInvalid) =>
            Latin15Codec(allowInvalid: allowInvalid),
        'iso-8859-16': (allowInvalid) =>
            Latin16Codec(allowInvalid: allowInvalid),
        'iso8859-16': (allowInvalid) =>
            Latin16Codec(allowInvalid: allowInvalid),
        'windows-1250': (allowInvalid) =>
            Windows1250Codec(allowInvalid: allowInvalid),
        'cp1250': (allowInvalid) =>
            Windows1250Codec(allowInvalid: allowInvalid),
        'cp-1250': (allowInvalid) =>
            Windows1250Codec(allowInvalid: allowInvalid),
        'windows-1251': (allowInvalid) =>
            Windows1251Codec(allowInvalid: allowInvalid),
        'cp1251': (allowInvalid) =>
            Windows1251Codec(allowInvalid: allowInvalid),
        'windows-1252': (allowInvalid) =>
            Windows1252Codec(allowInvalid: allowInvalid),
        'cp1252': (allowInvalid) =>
            Windows1252Codec(allowInvalid: allowInvalid),
        'cp-1252': (allowInvalid) =>
            Windows1252Codec(allowInvalid: allowInvalid),
        'windows-1253': (allowInvalid) =>
            Windows1253Codec(allowInvalid: allowInvalid),
        'cp1253': (allowInvalid) =>
            Windows1253Codec(allowInvalid: allowInvalid),
        'cp-1253': (allowInvalid) =>
            Windows1253Codec(allowInvalid: allowInvalid),
        'windows-1254': (allowInvalid) =>
            Windows1254Codec(allowInvalid: allowInvalid),
        'cp1254': (allowInvalid) =>
            Windows1254Codec(allowInvalid: allowInvalid),
        'cp-1254': (allowInvalid) =>
            Windows1254Codec(allowInvalid: allowInvalid),
        'windows-1256': (allowInvalid) =>
            Windows1256Codec(allowInvalid: allowInvalid),
        'cp1256': (allowInvalid) =>
            Windows1256Codec(allowInvalid: allowInvalid),
        'cp-1256': (allowInvalid) =>
            Windows1256Codec(allowInvalid: allowInvalid),
        'koi8': (allowInvalid) => Koi8rCodec(allowInvalid: allowInvalid),
        'koi8-r': (allowInvalid) => Koi8rCodec(allowInvalid: allowInvalid),
        'koi8-u': (allowInvalid) => Koi8uCodec(allowInvalid: allowInvalid),
        'us-ascii': (allowInvalid) =>
            convert.AsciiCodec(allowInvalid: allowInvalid),
        'ascii': (allowInvalid) =>
            convert.AsciiCodec(allowInvalid: allowInvalid),
      };
  static final _textDecodersByName =
      <
        String,
        String Function(
          String text,
          convert.Encoding encoding, {
          required bool isHeader,
        })
      >{
        'q': quotedPrintable.decodeText,
        'quoted-printable': quotedPrintable.decodeText,
        'b': base64.decodeText,
        'base64': base64.decodeText,
        'base-64': base64.decodeText,
        '7bit': decodeOnlyCodec,
        '8bit': decodeOnlyCodec,
        contentTransferEncodingNone: decodeOnlyCodec,
      };

  // Every encoding _textDecodersByName knows must appear here too. A missing
  // entry is not a decode failure the caller can see: decodeBinary falls
  // back to the undecoded source and only prints, so an attachment in that
  // encoding is silently written out corrupt.
  static final _binaryDecodersByName = <String, Uint8List Function(String)>{
    'b': base64.decodeData,
    'base64': base64.decodeData,
    'base-64': base64.decodeData,
    'q': quotedPrintable.decodeData,
    'quoted-printable': quotedPrintable.decodeData,
    'binary': decodeBinaryTextData,
    '7bit': decode8BitTextData,
    '8bit': decode8BitTextData,
    contentTransferEncodingNone: decode8BitTextData,
  };

  /// bas64 mail codec
  static const base64 = Base64MailCodec();

  /// quoted printable mail codec
  static const quotedPrintable = QuotedPrintableMailCodec();

  /// Encodes the specified text in the chosen codec's format.
  ///
  /// [text] specifies the text to be encoded.
  /// [codec] the optional codec, which defaults to utf8.
  /// Set [wrap] to false in case you do not want to wrap lines.
  String encodeText(
    String text, {
    convert.Codec codec = encodingUtf8,
    bool wrap = true,
  });

  /// Encodes the header text in the chosen codec's only if required.
  ///
  /// [text] specifies the text to be encoded.
  /// Set the optional [fromStart] to true in case the encoding should
  /// start at the beginning of the text and not in the middle.
  String encodeHeader(String text, {bool fromStart = false});

  /// Encodes the given [part] text.
  Uint8List decodeData(String part);

  /// Decodes the given [part] text with the given [codec].
  ///
  /// [isHeader] is set to the `true` when this text originates from a header
  String decodeText(
    String part,
    convert.Encoding codec, {
    bool isHeader = false,
  });

  /// Decodes the given header [input] value.
  static String? decodeHeader(final String? input) {
    if (input == null || input.isEmpty) {
      return input;
    }
    // unwrap any lines:
    var cleaned = input.replaceAll('\r\n ', '');
    // remove any spaces between 2 encoded words:
    final containsEncodedWordsWithSpace = cleaned.contains('?= =?');
    final containsEncodedWordsWithTab = cleaned.contains('?=\t=?');
    final containsEncodedWordsWithoutSpace =
        !containsEncodedWordsWithSpace && cleaned.contains('?==?');
    if (containsEncodedWordsWithSpace ||
        containsEncodedWordsWithTab ||
        containsEncodedWordsWithoutSpace) {
      final match = _headerEncodingExpression.firstMatch(cleaned);
      if (match != null) {
        final sequence = match.group(0) ?? '';
        final separatorIndex = sequence.indexOf('?', 3);
        final endIndex = separatorIndex + 3;
        final startSequence = sequence.substring(0, endIndex);
        final searchText = containsEncodedWordsWithSpace
            ? '?= $startSequence'
            : containsEncodedWordsWithTab
            ? '?=\t$startSequence'
            : '?=$startSequence';
        if (startSequence.endsWith('?B?') || startSequence.endsWith('?b?')) {
          // in base64 encoding there are 2 cases:
          // 1. individual parts can end  with the padding character "=":
          //    - in that case we just remove the
          //      space between the encoded words
          // 2. individual words do not end with a padding character:
          //    - in that case we combine the words
          if (cleaned.contains('=$searchText')) {
            if (containsEncodedWordsWithSpace) {
              cleaned = cleaned.replaceAll('?= =?', '?==?');
            } else if (containsEncodedWordsWithTab) {
              cleaned = cleaned.replaceAll('?=\t=?', '?==?');
            }
          } else {
            cleaned = cleaned.replaceAll(searchText, '');
          }
        } else {
          // "standard case" - just fuse the sequences together
          cleaned = cleaned.replaceAll(searchText, '');
        }
      }
    }
    final buffer = StringBuffer();
    _decodeHeaderImpl(cleaned, buffer);

    return buffer.toString();
  }

  static void _decodeHeaderImpl(final String input, StringBuffer buffer) {
    RegExpMatch? match;
    var reminder = input;
    while ((match = _headerEncodingExpression.firstMatch(reminder)) != null) {
      final sequence = match?.group(0) ?? '';
      final separatorIndex = sequence.indexOf('?', 3);
      final characterEncodingName = sequence
          .substring('=?'.length, separatorIndex)
          .toLowerCase();
      final decoderName = sequence
          .substring(separatorIndex + 1, separatorIndex + 2)
          .toLowerCase();

      final codec = _charsetCodecsByName[characterEncodingName]?.call(true);
      if (codec == null) {
        MimeDiagnostics.report(MimeDiagnosticCode.unsupportedCharset);
        buffer.write(reminder);

        return;
      }
      final decoder = _textDecodersByName[decoderName];
      if (decoder == null) {
        MimeDiagnostics.report(MimeDiagnosticCode.unsupportedTransferEncoding);
        buffer.write(reminder);

        return;
      }
      if (match != null && match.start > 0) {
        buffer.write(reminder.substring(0, match.start));
      }
      final contentStartIndex = separatorIndex + 3;
      final part = sequence.substring(
        contentStartIndex,
        sequence.length - _encodingEndSequence.length,
      );
      String decoded;
      try {
        decoded = decoder(part, codec, isHeader: true);
      } catch (e) {
        // keep an undecodable encoded word as is instead of failing the
        // whole header, the input comes from untrusted senders
        MimeDiagnostics.report(MimeDiagnosticCode.malformedEncodedWord);
        decoded = sequence;
      }
      buffer.write(decoded);
      reminder = reminder.substring(match?.end ?? 0);
    }
    if (buffer.isEmpty &&
        reminder.startsWith('=?') &&
        _emptyHeaderEncodingExpression.hasMatch(reminder)) {
      return;
    }
    buffer.write(reminder);
  }

  /// Detects the encoding used in the given header [value].
  static HeaderEncoding detectHeaderEncoding(String value) {
    final match = _headerEncodingExpression.firstMatch(value);
    if (match == null) {
      return HeaderEncoding.none;
    }
    final group = match.group(0);

    return group?.contains('?B?') ?? group?.contains('?b?') ?? false
        ? HeaderEncoding.B
        : HeaderEncoding.Q;
  }

  /// Decodes the given binary [text]
  static Uint8List decodeBinary(
    final String text,
    final String? transferEncoding,
  ) {
    final tEncoding = transferEncoding ?? contentTransferEncodingNone;
    final decoder = _binaryDecodersByName[tEncoding.toLowerCase()];
    if (decoder == null) {
      MimeDiagnostics.report(MimeDiagnosticCode.unsupportedTransferEncoding);

      return Uint8List.fromList(text.codeUnits);
    }

    return decoder(text);
  }

  /// Decodes an explicitly declared charset without replacement characters.
  ///
  /// Returns null and emits a content-redacted diagnostic for unknown charsets
  /// or malformed byte sequences. This does not decode a transfer encoding.
  /// Callers must enforce input and cumulative output budgets first.
  static String? decodeCharsetStrict(Uint8List data, String charset) {
    final normalized = charset.trim().toLowerCase();
    final codec = _charsetCodecsByName[normalized]?.call(false);
    if (codec == null) {
      MimeDiagnostics.report(MimeDiagnosticCode.unsupportedCharset);

      return null;
    }
    try {
      return codec.decode(data);
    } on FormatException {
      MimeDiagnostics.report(MimeDiagnosticCode.malformedCharacterData);

      return null;
    }
  }

  /// Decodes the given [data]
  static String decodeAsText(
    final Uint8List data,
    final String? transferEncoding,
    final String? charset,
  ) {
    if (transferEncoding == null && charset == null) {
      // this could be a) UTF-8 or b) UTF-16 most likely:
      final utf8Decoded = encodingUtf8.decode(data, allowMalformed: true);
      if (utf8Decoded.contains('�')) {
        final comparison = String.fromCharCodes(data);
        if (!comparison.contains('�')) {
          return comparison;
        }
      }

      return utf8Decoded;
    }
    // there is actually just one interesting case:
    // when the transfer encoding is 8bit, the text needs to be decoded with
    // the specified charset.
    // Note that some mail senders also declare 7bit message encoding even when
    // UTF8 or other 8bit encodings are used.
    // In other cases the text is ASCII and the 'normal' decodeAnyText method
    // can be used.
    final transferEncodingLC = transferEncoding?.toLowerCase() ?? '8bit';
    if (transferEncodingLC == '8bit' ||
        transferEncodingLC == '7bit' ||
        transferEncodingLC == 'binary') {
      final cs = charset ?? 'utf8';
      final codec = _charsetCodecsByName[cs.toLowerCase()]?.call(true);
      if (codec == null) {
        MimeDiagnostics.report(MimeDiagnosticCode.unsupportedCharset);

        return encodingUtf8.decode(data, allowMalformed: true);
      }
      final decodedText = codec.decode(data);

      return decodedText;
    }
    final text = String.fromCharCodes(data);

    return decodeAnyText(text, transferEncoding, charset);
  }

  /// Decodes the given [text]
  static String decodeAnyText(
    final String text,
    final String? transferEncoding,
    final String? charset,
  ) {
    final transferEnc = transferEncoding ?? contentTransferEncodingNone;
    final decoder = _textDecodersByName[transferEnc.toLowerCase()];
    if (decoder == null) {
      MimeDiagnostics.report(MimeDiagnosticCode.unsupportedTransferEncoding);

      return text;
    }
    final cs = charset ?? 'utf8';
    final codec = _charsetCodecsByName[cs.toLowerCase()]?.call(true);
    if (codec == null) {
      MimeDiagnostics.report(MimeDiagnosticCode.unsupportedCharset);

      return text;
    }

    return decoder(text, codec, isHeader: false);
  }

  /// Decodes binary from the given text [part].
  static Uint8List decodeBinaryTextData(String part) =>
      Uint8List.fromList(part.codeUnits);

  /// Decodes the data from the given 8bit text [part]
  static Uint8List decode8BitTextData(final String part) =>
      Uint8List.fromList(part.replaceAll('\r\n', '').codeUnits);

  /// Is a noop
  static String decodeOnlyCodec(
    String part,
    convert.Encoding codec, {
    bool isHeader = false,
  }) => part;

  /// Wraps the text so that it stays within email's 76 characters
  /// per line convention.
  ///
  /// [text] the text that should be wrapped.
  /// Set [wrapAtWordBoundary] to true in case the text should be wrapped
  /// at word boundaries / spaces.
  static String wrapText(String text, {bool wrapAtWordBoundary = false}) {
    if (text.length <= MailConventions.textLineMaxLength) {
      return text;
    }
    final buffer = StringBuffer();
    final runes = text.runes.toList(growable: false);
    int? lastRune;
    int? lastSpaceIndex;
    var currentLineLength = 0;
    var currentLineStartIndex = 0;
    for (var runeIndex = 0; runeIndex < runes.length; runeIndex++) {
      final rune = runes[runeIndex];
      if (rune == AsciiRunes.runeLineFeed &&
          lastRune == AsciiRunes.runeCarriageReturn) {
        buffer.write(
          String.fromCharCodes(
            runes.sublist(currentLineStartIndex, runeIndex + 1),
          ),
        );
        currentLineLength = 0;
        currentLineStartIndex = runeIndex + 1;
        lastSpaceIndex = null;
      } else {
        if (wrapAtWordBoundary &&
            (rune == AsciiRunes.runeSpace || rune == AsciiRunes.runeTab)) {
          lastSpaceIndex = runeIndex;
        }
        currentLineLength++;
        if (currentLineLength >= MailConventions.textLineMaxLength) {
          // edge case: this could be in the middle of a \r\n sequence:
          if (rune == AsciiRunes.runeCarriageReturn &&
              runeIndex < runes.length - 1 &&
              runes[runeIndex + 1] == AsciiRunes.runeLineFeed) {
            lastRune = rune;
            continue; // the break will be handled in the next loop iteration
          }
          var endIndex = (wrapAtWordBoundary && lastSpaceIndex != null)
              ? lastSpaceIndex
              : runeIndex;
          if (endIndex < runes.length - 1) {
            endIndex++;
          }
          buffer
            ..write(
              String.fromCharCodes(
                runes.sublist(currentLineStartIndex, endIndex),
              ),
            )
            ..write('\r\n');
          currentLineLength = 0;
          currentLineStartIndex = endIndex;
          lastSpaceIndex = null;
        }
      }
      lastRune = rune;
    }

    if (currentLineStartIndex < runes.length) {
      buffer.write(String.fromCharCodes(runes.sublist(currentLineStartIndex)));
    }

    return buffer.toString();
  }
}
