/// Host-neutral Mail contracts. This entry has no Flutter, socket or file APIs.
library;

export 'src/model/bytes.dart';
export 'src/model/capabilities.dart';
export 'src/model/compose_settings.dart';
export 'src/model/identity.dart';
export 'src/model/message.dart';
export 'src/model/parse.dart';
export 'src/model/result.dart';
export 'src/ports/codec.dart';
export 'src/ports/hosts.dart';
export 'src/ports/membership.dart';
export 'src/ports/mutation_receipt.dart';
export 'src/ports/provider.dart';
export 'src/ports/repository.dart';
export 'src/search/conversations.dart';
export 'src/search/header_search.dart';
export 'src/search/saved_header_search.dart';
export 'src/sync/body_download.dart';
export 'src/sync/bulk_flags.dart';
export 'src/sync/cancellation.dart';
export 'src/sync/coordinator.dart';
export 'src/sync/outbox.dart';
export 'src/sync/runner.dart';
