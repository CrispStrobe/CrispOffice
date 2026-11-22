/// Latest current-state evidence, separate from historical command outcomes.
/// Evidence never makes an uncertain membership command eligible for cleanup.
final schemaV14 = List<String>.unmodifiable([
  '''CREATE TABLE membership_item_observations (
    account TEXT NOT NULL, batch TEXT NOT NULL,
    position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 999),
    kind TEXT NOT NULL CHECK(kind IN ('present','missing','identityChanged')),
    mailboxes TEXT NOT NULL
      CHECK(typeof(mailboxes)='text' AND length(CAST(mailboxes AS BLOB)) BETWEEN 2 AND 262144),
    deletion_mailbox TEXT
      CHECK(deletion_mailbox IS NULL OR (typeof(deletion_mailbox)='text' AND
        length(CAST(deletion_mailbox AS BLOB)) BETWEEN 1 AND 8192)),
    is_deleted INTEGER
      CHECK(is_deleted IS NULL OR (typeof(is_deleted)='integer' AND is_deleted IN (0,1))),
    checked_at INTEGER NOT NULL CHECK(checked_at BETWEEN 0 AND 8640000000000000),
    CHECK(kind='present' OR
      (mailboxes='[]' AND deletion_mailbox IS NULL AND is_deleted IS NULL)),
    PRIMARY KEY(account,batch,position),
    FOREIGN KEY(account,batch,position) REFERENCES flag_batch_items(account,batch,position) ON DELETE CASCADE
  )''',
  // Add membership-specific write fences without altering the released v7
  // schema. Direct membership/cursor changes must also retire an in-flight
  // observation, including an empty synchronization page.
  for (final table in [
    'membership_item_observations',
    'memberships',
    'mailbox_view_members',
    'mailboxes',
    'cursors',
    'mailbox_sync_state',
    'tombstones',
  ])
    for (final event in ['INSERT', 'UPDATE', 'DELETE'])
      'CREATE TRIGGER membership_observation_${table}_${event.toLowerCase()} '
          'AFTER $event ON $table BEGIN '
          'UPDATE store_profile SET flag_observation_epoch=flag_observation_epoch+1; '
          'END',
]);
