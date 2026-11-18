// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Portable MIME parsing and codecs without sockets or filesystem builders.
///
/// This surface intentionally does not export `mime.dart`, `codecs.dart`,
/// `MessageBuilder`, protocol clients, or any `dart:io` type. Parsing remains
/// a whole-message operation: callers must impose byte/part/decode limits.
library;

export 'src/codecs/base64_mail_codec.dart';
export 'src/codecs/date_codec.dart';
export 'src/codecs/mail_codec.dart';
export 'src/codecs/quoted_printable_mail_codec.dart';
export 'src/exception.dart';
export 'src/imap/message_sequence.dart';
export 'src/mail_address.dart';
export 'src/mail_conventions.dart';
export 'src/media_type.dart';
export 'src/message_flags.dart';
export 'src/mime_data.dart';
export 'src/mime_diagnostics.dart';
export 'src/mime_message.dart';
