"""Exercise the actual rich-template DDL in Python SQLite, not Dart or Drift."""

from pathlib import Path
import hashlib
import json
import re
import sqlite3
import sys


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]
source_path = root / "packages/quds_mail_store/lib/src/schema/database.dart"
source = source_path.read_text()


def statements(name):
    block = source.split("const " + name + " = <String>[", 1)[1].split("];", 1)[0]
    return re.findall("'''(.*?)'''", block, re.S)


schema21 = statements("schemaV21")
schema22 = statements("schemaV22")
assert len(schema21) == 3
assert len(schema22) == 1
db = sqlite3.connect(":memory:")
db.execute(
    "CREATE TABLE account_compose_settings("
    "account TEXT PRIMARY KEY, revision INTEGER NOT NULL, "
    "signature TEXT NOT NULL, signature_new INTEGER NOT NULL, "
    "signature_replies INTEGER NOT NULL)"
)
for sql in schema21:
    db.execute(sql)
db.execute(
    "INSERT INTO account_compose_settings VALUES(?,?,?,?,?,?)",
    ("account", 7, "signature", 0, 0, None),
)
legacy = "<b>literal</b>\r\nمرحبا 📨"
db.execute(
    "INSERT INTO account_message_templates("
    "account,position,id,name,name_key,to_text,cc_text,bcc_text,subject,body) "
    "VALUES(?,?,?,?,?,?,?,?,?,?)",
    ("account", 0, "legacy", "Legacy", "legacy", "", "",
     "private@example.test", "subject", legacy),
)
db.execute("PRAGMA user_version=21")
db.commit()
before = db.execute("SELECT * FROM account_message_templates").fetchall()

# Force a transaction rollback after executing the real additive DDL.
db.execute("BEGIN")
for sql in schema22:
    db.execute(sql)
db.execute("PRAGMA user_version=22")
db.rollback()
assert db.execute("PRAGMA user_version").fetchone()[0] == 21
assert "body_html" not in [
    row[1] for row in db.execute("PRAGMA table_info(account_message_templates)")
]
assert db.execute("SELECT * FROM account_message_templates").fetchall() == before

# Retry and commit: existing text and revision remain byte-for-byte unchanged.
db.execute("BEGIN")
for sql in schema22:
    db.execute(sql)
db.execute("PRAGMA user_version=22")
db.commit()
assert db.execute("PRAGMA user_version").fetchone()[0] == 22
assert db.execute(
    "SELECT CAST(body AS BLOB),body_html FROM account_message_templates"
).fetchone() == (legacy.encode("utf-8"), None)
assert db.execute("SELECT revision FROM account_compose_settings").fetchone() == (7,)
for bad in [b"binary", "x" * 262145]:
    try:
        db.execute("UPDATE account_message_templates SET body_html=?", (bad,))
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("Invalid HTML SQL type/size admitted")
    db.rollback()
assert db.execute(
    "SELECT body,body_html FROM account_message_templates"
).fetchone() == (legacy, None)
assert list(db.execute("PRAGMA foreign_key_check")) == []
db.close()

print(json.dumps({
    "result": "passed",
    "scope": (
        "Actual schemaV21/schemaV22 SQL via Python sqlite3 in an isolated "
        "compose-table fixture; not Dart/Drift or whole-schema execution"
    ),
    "sqlite_version": sqlite3.sqlite_version,
    "checks": [
        "additive nullable column",
        "rollback removes column and restores user_version",
        "legacy literal body preserved byte-for-byte",
        "settings revision unchanged",
        "binary column rejected",
        "SQL byte ceiling enforced",
        "foreign_key_check empty",
    ],
    "schema_source_path": "packages/quds_mail_store/lib/src/schema/database.dart",
    "schema_source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
    "schema_v22_sql_sha256": hashlib.sha256(
        ("\n".join(schema22) + "\n").encode("utf-8")
    ).hexdigest(),
}, indent=2))
