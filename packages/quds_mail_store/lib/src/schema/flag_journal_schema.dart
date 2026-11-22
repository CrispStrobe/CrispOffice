/// Durable foreground flag receipts. These tables contain intent and evidence,
/// never credentials, payload bytes or a background work queue.
const schemaV6 = <String>[
  '''CREATE TABLE flag_batches (
    account TEXT NOT NULL REFERENCES accounts(id), id TEXT NOT NULL,
    mailbox TEXT NOT NULL, provider TEXT NOT NULL, action TEXT NOT NULL,
    created_at INTEGER NOT NULL CHECK(created_at BETWEEN 0 AND 8640000000000000),
    updated_at INTEGER NOT NULL CHECK(updated_at BETWEEN 0 AND 8640000000000000),
    revision INTEGER NOT NULL CHECK(revision BETWEEN 1 AND 9007199254740991),
    complete INTEGER NOT NULL CHECK(complete IN (0,1)),
    interrupted INTEGER NOT NULL CHECK(interrupted IN (0,1)),
    item_count INTEGER NOT NULL CHECK(item_count BETWEEN 1 AND 1000),
    stop_reason TEXT, problem_code TEXT, retry_after_us INTEGER,
    persistence_problem TEXT,
    mutation_possible INTEGER CHECK(mutation_possible IS NULL OR mutation_possible IN (0,1)),
    PRIMARY KEY(account,id)
  )''',
  '''CREATE TABLE flag_batch_items (
    account TEXT NOT NULL, batch TEXT NOT NULL,
    position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 999),
    remote TEXT NOT NULL, subject TEXT NOT NULL,
    state TEXT NOT NULL CHECK(state IN ('unattempted','applying','confirmed','failed','uncertain')),
    problem_code TEXT, retry_after_us INTEGER,
    mutation_possible INTEGER CHECK(mutation_possible IS NULL OR mutation_possible IN (0,1)),
    PRIMARY KEY(account,batch,position), UNIQUE(account,batch,remote),
    FOREIGN KEY(account,batch) REFERENCES flag_batches(account,id) ON DELETE CASCADE
  )''',
  'CREATE INDEX flag_batch_history ON flag_batches(account,created_at DESC,id DESC)',
];

/// Additive observation evidence and a persisted fence for late provider reads.
/// Epoch triggers include cache writes, commands and authentication transitions;
/// an unrelated mutation may conservatively require another foreground check.
final schemaV7 = List<String>.unmodifiable([
  '''ALTER TABLE store_profile ADD COLUMN flag_observation_epoch INTEGER NOT NULL DEFAULT 0
    CHECK(typeof(flag_observation_epoch)='integer' AND flag_observation_epoch BETWEEN 0 AND 9007199254740991)''',
  '''CREATE TABLE flag_item_resolutions (
    account TEXT NOT NULL, batch TEXT NOT NULL,
    position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 999),
    kind TEXT NOT NULL CHECK(kind IN ('matches','differs','missing','identityChanged')),
    checked_at INTEGER NOT NULL CHECK(checked_at BETWEEN 0 AND 8640000000000000),
    PRIMARY KEY(account,batch,position),
    FOREIGN KEY(account,batch,position) REFERENCES flag_batch_items(account,batch,position) ON DELETE CASCADE
  )''',
  for (final table in [
    'accounts',
    'local_accounts',
    'messages',
    'mailbox_views',
    'pending_operations',
    'flag_batches',
    'flag_batch_items',
    'flag_item_resolutions',
  ])
    for (final event in ['INSERT', 'UPDATE', 'DELETE'])
      'CREATE TRIGGER flag_observation_${table}_${event.toLowerCase()} '
          'AFTER $event ON $table BEGIN '
          'UPDATE store_profile SET flag_observation_epoch=flag_observation_epoch+1; '
          'END',
]);

/// Keep membership commands in the existing durable journal without changing
/// earlier receipts. A destination is an exact folder ID in the batch account.
const schemaV13 = <String>[
  '''ALTER TABLE flag_batches ADD COLUMN destination TEXT
    CHECK((action='move' AND destination IS NOT NULL AND
      typeof(destination)='text' AND length(CAST(destination AS BLOB)) BETWEEN 1 AND 4096 AND
      destination!=mailbox) OR
      (action!='move' AND destination IS NULL))''',
];
