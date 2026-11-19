/// Transactional Mail storage with injected SQLite execution.
///
/// Native filesystem and browser worker setup have separate public entries.
library;

export 'src/archive_export_models.dart';
export 'src/archive_models.dart';
export 'src/archive_query.dart';
export 'src/archive_repository.dart';
export 'src/archive_restore_checkpoint_models.dart';
export 'src/archive_restore_models.dart';
export 'src/archive_runner.dart';
export 'src/errors.dart' show MailStoreStorageException, mailStoreProblem;
export 'src/models.dart';
export 'src/repository.dart';
