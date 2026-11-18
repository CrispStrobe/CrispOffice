// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';

/// Content-redacted MIME diagnostics. No enum value contains source text.
enum MimeDiagnosticCode {
  /// A declared character set has no decoder.
  unsupportedCharset,

  /// A declared transfer encoding has no decoder.
  unsupportedTransferEncoding,

  /// An encoded header word could not be decoded.
  malformedEncodedWord,

  /// A header could not be projected.
  malformedHeader,

  /// An address or personal name could not be projected.
  malformedAddress,

  /// A date component or time zone could not be parsed.
  invalidDate,

  /// A requested MIME part identifier is malformed.
  invalidPartReference,

  /// The media subtype is not in the upstream enumeration.
  unrecognizedMediaSubtype,

  /// The transfer payload is malformed.
  malformedTransferPayload,

  /// Bytes are malformed for the explicitly selected character encoding.
  malformedCharacterData,

  /// An IMAP metadata field could not be parsed.
  malformedMetadata,
}

/// Receives a code, never a subject, address, body, token, or exception text.
typedef MimeDiagnosticHandler = void Function(MimeDiagnosticCode code);

/// Scopes diagnostics to one operation without changing a process-wide sink.
abstract final class MimeDiagnostics {
  static final Object _handlerKey = Object();

  /// Runs [operation] with a diagnostic callback inherited by its async work.
  ///
  /// Missing callbacks discard codes. The MIME parser never prints source
  /// content; callers choose how to turn codes into user-visible diagnostics.
  static T run<T>(
    T Function() operation, {
    required MimeDiagnosticHandler onDiagnostic,
  }) => runZoned<T>(
    operation,
    zoneValues: <Object, Object>{_handlerKey: onDiagnostic},
  );

  /// Emits a content-free code to the current operation's callback.
  static void report(MimeDiagnosticCode code) {
    final handler = Zone.current[_handlerKey] as MimeDiagnosticHandler?;
    handler?.call(code);
  }
}
