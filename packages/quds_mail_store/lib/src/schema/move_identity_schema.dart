/// Exact replacement identities returned by acknowledged moves. Historical
/// uncertain receipts never acquire a guessed transition during migration.
final schemaV15 = List<String>.unmodifiable([
  '''CREATE TABLE move_identity_transitions (
    account TEXT NOT NULL, batch TEXT NOT NULL,
    position INTEGER NOT NULL CHECK(typeof(position)='integer' AND position BETWEEN 0 AND 999),
    destination_remote TEXT NOT NULL
      CHECK(typeof(destination_remote)='text' AND length(CAST(destination_remote AS BLOB)) BETWEEN 1 AND 32768),
    destination_message TEXT NOT NULL
      CHECK(typeof(destination_message)='text' AND length(CAST(destination_message AS BLOB)) BETWEEN 1 AND 8192),
    recorded_at INTEGER NOT NULL
      CHECK(typeof(recorded_at)='integer' AND recorded_at BETWEEN 0 AND 8640000000000000),
    cache_projected INTEGER NOT NULL CHECK(typeof(cache_projected)='integer' AND cache_projected IN (0,1)),
    PRIMARY KEY(account,batch,position),
    FOREIGN KEY(account,batch,position) REFERENCES flag_batch_items(account,batch,position) ON DELETE CASCADE
  )''',
  // This counter is independent of mailbox rows so cleanup/recreation cannot
  // make an old cursor stamp valid again. Provider cursor bytes stay unchanged.
  '''CREATE TABLE mailbox_move_revisions (
    account TEXT NOT NULL REFERENCES accounts(id), mailbox TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK(typeof(revision)='integer' AND revision BETWEEN 1 AND 9007199254740991),
    PRIMARY KEY(account,mailbox)
  )''',
  for (final event in ['INSERT', 'UPDATE', 'DELETE'])
    'CREATE TRIGGER move_identity_${event.toLowerCase()} '
        'AFTER $event ON move_identity_transitions BEGIN '
        'UPDATE store_profile SET flag_observation_epoch=flag_observation_epoch+1; '
        'END',
]);
