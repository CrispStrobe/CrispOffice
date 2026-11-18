import 'package:sqlite3/common.dart';

/// Used in both the calling context and the separately compiled Drift worker.
/// Browser virtual filesystems use rollback journals rather than native WAL.
void configureMailBrowserDatabase(CommonDatabase database) {
  database.execute('PRAGMA journal_mode = DELETE');
  database.execute('PRAGMA synchronous = FULL');
  database.execute('PRAGMA busy_timeout = 5000');
  database.execute('PRAGMA foreign_keys = ON');
}
