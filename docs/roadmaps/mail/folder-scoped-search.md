# Saved-search exact folder sets — 22 November 2026

## User workflow

In **Search saved mail**, choose the retained account scope and then **Choose
folders…**. This explicit action opens each account's existing native local
store and reads its already saved browse and synchronization folder inventory.
No credential, provider request or body fetch occurs.

Choose one or more folders per account and **Use selected folders**. This
changes the current local search scope, not any message or provider state.
**All retained folders** deliberately restores the original account-wide
behavior. A named search saved with an explicit folder set captures immutable
**(account ID, mailbox ID)** pairs, not display names. Reopening a saved search
rechecks those pairs against current local data and current account identities.

- Removing a folder, forgetting or redirecting an account, or using a legacy
  host that cannot enforce scoped discovery **never** widens a saved search.
  The affected account reports incomplete coverage, and no automatic refresh
  starts for incomplete searches.
- The picker displays a previously selected but now missing folder as
  unavailable. Deselect it and choose another retained folder explicitly, or
  choose **All retained folders** explicitly; then update the named definition.
- Account edits, query edits and folder edits invalidate in-flight searches.
  Searching across accounts uses one existing owner at a time and closes it
  before acquiring the next. The picker verifies identities before acquiring
  local stores and again before publishing a selection.
- Scoped results retain the original account-local message keys and remote
  identities. Duplicate observations in browse and synchronized membership
  sources count once. Only matching folder provenance is displayed.

## Compatibility and persistence

Old MailSavedHeaderSearch records have null folderScopes, meaning all retained
folders in their fixed account set. Schema **11** adds a mode marker and an
ordered folder table to the host directory profile. Opening schemas 1–10
upgrades them transactionally; no migration rewrites messages, browse/sync
memberships, saved bodies, drafts, credentials or Outbox payloads. An exact
folder set requires 1–200 distinct pairs and at least one folder per captured
account. The same optimistic revision counter guards updates and deletions.

SQL applies folder restrictions to **both** saved memberships and browsed
window memberships before counts, candidate paging and continuation checks.
Account and mailbox IDs are always bound as SQL parameters. A continuation
carries a folder-scope fingerprint and rejects reuse with another folder set
or account/query/owner revision. SQL preflight and metadata budgets still
protect large or malformed content.

The optional StudioMailScopedHeaderSearchStore port preserves existing
hosts' account-wide StudioMailCachedHeaderSearchStore contract. Scoped
discovery on a host without the opt-in port reports **unsupported**, not a
fallback search. Studio's native SQLite adapter implements the new port.

## Qualification and next parity boundaries

Source checkpoints and focused regression tests cover immutable and invalid
model scopes, persistence/revision rollback, schema 11 migration expectations,
SQL membership filtering and continuation mismatches, missing-folder denial,
legacy adapter denial, and the folder picker. **Dart and Flutter executables
were unavailable in the editing environment; these new tests were committed
but were not run here.** Existing earlier validation records describe their
own completed runs and should not be used as evidence for this new increment.
GitHub Actions queue completion is not a merge gate.

This is a local retained-header workflow. It does **not** index body text or
attachments, query a provider server, search never-synchronized folders,
subscribe to repository-wide change events, continuously synchronize mail, or
implement provider-side virtual folders. These remain follow-on increments
toward Outlook, Thunderbird and eM Client capability parity.
