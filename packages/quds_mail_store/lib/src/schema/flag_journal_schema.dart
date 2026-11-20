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
