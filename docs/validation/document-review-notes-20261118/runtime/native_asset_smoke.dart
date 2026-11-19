// SQLite is a pinned dependency of the Mail store workspace member.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';

void main() {
  final database = sqlite3.openInMemory();
  try {
    database.execute('CREATE VIRTUAL TABLE probe USING fts5(content)');
    database.execute('INSERT INTO probe(content) VALUES (?)', [
      'native review',
    ]);
    final rows = database.select(
      "SELECT content FROM probe WHERE probe MATCH 'review'",
    );
    if (rows.length != 1 || rows.single['content'] != 'native review') {
      throw StateError('Native SQLite FTS5 round trip failed');
    }
    print('SQLite ${sqlite3.version.libVersion}: in-memory FTS5 passed');
  } finally {
    database.close();
  }
}
