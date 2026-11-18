/// Transactional Mail storage with injected SQLite execution.
///
/// Native filesystem and browser worker setup have separate public entries.
library;

export 'src/errors.dart' show MailStoreStorageException, mailStoreProblem;
export 'src/models.dart';
export 'src/repository.dart';
