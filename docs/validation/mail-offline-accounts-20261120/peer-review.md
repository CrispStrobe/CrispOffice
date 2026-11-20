# Independent review and corrections

The offline-account directory/hosts and the incoming Word ListFormat work were
reviewed independently. Reviews did not modify the frozen qualification source.
Corrections were prepared in isolated Git worktrees and integrated only after
the original local qualification finished.

## Mail metadata bounds

SQLite `length(TEXT)` counts Unicode code points and stops at an embedded NUL.
It was therefore insufficient to bound copied metadata, and the provider field
was missing from the initial preflight. The corrected preflight validates text
types and allowed providers, checks conservative UTF-8 byte ceilings before
selecting rows, and applies the exact combined Dart UTF-16 budget after decoding.
The byte budget is capped before multiplication to avoid integer overflow for
an unusually large host limit.

Regression cases use real SQLite files and an executor interceptor to prove
that oversized NUL-suffixed login/provider values never enter Dart query rows.
A valid emoji login written under a larger budget is refused under a lower
budget without being changed, and opens again under the original budget.

## Shortcut-removal generations

A per-row revision alone could be reused after removal and re-addition at an
identical timestamp. The corrected schema adds a persistent profile registration
counter. Each successful registration allocates a revision and writes the
counter and shortcut in one transaction. Shortcut removal never resets it.
The file-reopen case verifies that an old removal confirmation cannot erase a
newly registered shortcut; fault injection verifies counter and row rollback.

The directory-selection re-read is not an access-revocation transaction.
Removing a shortcut preserves local drafts. A shortcut already absent when
selection rechecks is refused; an already-started open still owns the same
immutable account identity and remains guarded by draft-store ownership.

## Word list metadata and semantics

Independent review of the captured incoming Word continuation found that a
namespace declaration could overwrite a foreign `w` binding or a foreign
attribute named `w`/`w1`. The fix matches declarations by exact qualified name
and preserves existing namespace bindings.

Stronger repeated-reopen regressions then exposed two related paths: freshly
imported `numId=0` suppression regenerated paragraph XML before retaining its
extension metadata, and a numbering projection lost inherited alternate native
prefixes. The style cascade now preserves fresh imported source and copies the
numbering node's namespace context into the effective projection.

Six new cases cover bullet application, number toggling and explicit removal,
including alternate native prefixes, foreign bindings and attribute collisions.
They assert correct list results and metadata retention over three save/reopen
cycles. All six fail against the original implementation. The accepted isolated
nine-file list/VBA/style/numbering/tab-stop cohort passes 267 cases. Its complete
retained evidence is included in the final evidence archive.

The final review found no remaining material blocker in the corrected
metadata bounds, registration counter, exact draft identity, native ownership,
save-only entry, separate warning behavior or additive migration. Runtime
qualification is recorded independently in the adjacent README and receipts.
