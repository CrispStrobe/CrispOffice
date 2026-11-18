import 'dart:typed_data';

import '../model/parse.dart';
import '../sync/cancellation.dart';

/// A byte-only saved-message codec. Composition is a separate optional port:
/// implementing a reader never implies that sending or building MIME works.
abstract interface class MailCodec {
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  });
}
