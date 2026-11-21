import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
void main() {
  final database = sqlite3.openInMemory();
  try {
    database.execute('CREATE VIRTUAL TABLE smoke USING fts5(body)');
    database.execute('INSERT INTO smoke(body) VALUES (?)', ['ready']);
    final rows = database.select("SELECT body FROM smoke WHERE smoke MATCH 'ready'");
    if (rows.length != 1 || rows.single['body'] != 'ready') {
      throw StateError('SQLite FTS5 readiness probe failed');
    }
    print(jsonEncode({'sqlite3': sqlite3.version.toString(), 'fts5': 'ready'}));
  } finally {
    database.close();
  }
}
