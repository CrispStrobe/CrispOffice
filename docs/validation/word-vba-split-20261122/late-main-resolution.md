# Late main Mail overlap

The late main history at `4cc60481` carries another fix for stale selected-account
catalog refreshes. Its observable contract is the same guarded refresh already
qualified in the combined branch at `c971ad0e`: a removed or revised shortcut
must not be recreated by an asynchronous connection completion, and a stale
connection must release its owner without dispatching another account.

The implementations place the guarded refresh at different points. Main moves
it before draft-owner adoption; the combined branch performs it after the cache
awaits, immediately before fulfilling the selected connection intent. The latter
placement is retained deliberately:

- Existing tests validate the selected record after every cache/save/observation
  await as well as after factory and load awaits.
- An early atomic refresh advances the record revision. The current
  `rememberSelected` API returns no refreshed record receipt. Continuing to
  validate the old receipt would reject our own successful write; clearing it
  early would weaken the later selected-record guards.
- The final guarded refresh already fixes the stale-write problem on main. It
  compares the expected record in the transaction, checks host/session identity,
  and does not fulfill the connection intent until refresh succeeds.
- A stale candidate that was already adopted is retired through the existing
  observer, durable-receipt, transport, and exclusive-owner release path. Failed
  release remains held for explicit recovery and blocks another account.

No second refresh is added. The native and provider production source remains
the qualified implementation, with all post-await identity checks and explicit
owner recovery preserved. The merge retains all new regressions from main:
fresh catalog registration, removed/revised selected shortcuts in native and
three provider routes, legacy directories without atomic-write support, and
expiration while selected-account validation is pending.

Both directory fixtures now name the counter distinction explicitly:
`rememberAttempts` counts calls, including a blocked or rejected CAS;
`remembers` counts successful catalog writes; `selectedRemembers` counts selected
refresh attempts. A rejected CAS must leave the successful-write count and the
exact replacement record unchanged. Duplicate automatically merged
`rememberSelected` methods are removed. Ordinary fixture writes remain available
while a selected write is held so existing concurrent-revision probes retain
their intended race.

There are eleven added Mail cases and no removed cases. Six-suite acceptance
will be rerun after the completed main merge and parser fix are frozen; this
document records merge decisions, not a test outcome.
