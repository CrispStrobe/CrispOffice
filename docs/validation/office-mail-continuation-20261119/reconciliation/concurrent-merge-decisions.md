# Concurrent continuation reconciliation

The first published integration was `3119a459`, with both initial unmerged
frontier tips as parents. The implementation checkpoint was `70e5745d`.
The next remote checkpoint, `ec8bd9cf`, also retains PR #194 at `4b8b9e2e`,
PR #193 at `4ed8154a` and PR #192 at `d00bd397` as actual ancestors. Each tree
was read back from the remote and compared with the intended local tree.

The bounded refresh (11:38:37–11:38:45 UTC) found later PR #193 at `4cf5831d`,
PR #192 at `79e77725` and `codex/office-final-union-20261119` at `47ce5f72`.
They are actual ancestors of the next published checkpoint, `b434cf1e`.
The independent graph receipt accounts for 467 actual refs: 439 ancestors,
28 historical equivalents and zero unaccounted refs; all 14 historical proofs
were recomputed. Four generated GitHub merge-preview refs are preserved in the
raw capture but are not treated as independent product branches.

Remote main subsequently advanced to `666e9a2e` through the integration branch
and added Mail reply, forward and mark-read actions. It is an actual parent of
published checkpoint `e1b94285`. Reconciliation retained all existing stronger
source and tests: relative to `dfb28229`, the merge initially introduced only
109 changed lines in `studio_mail_native.dart` and `studio_mail_strings.dart`.
Follow-up action repairs and regressions are qualified under a later source.

The final bounded capture ran from 12:23:58 to 12:24:05 UTC. Its five later
captured heads reduce to four frontier commits: `e77d0dab`, `5a910773`,
`0f16754c` and `0601d279`; `22ffa8bd` is an ancestor of `0601d279`.
All four are actual parents of published checkpoint `1c415fef`. That checkpoint
retains their original qualification archives and incomplete attempts without
adding historical results to the current gate. The separately preserved
`continuation-0601d279.md` keeps the overlapping resume report intact.

Unique late source changes retained are the SMTP abort override that settles a
pending command before transport close, the reader's bounded body-only text
projection, and consistent numeric morphology feature text on VM and JavaScript.
The SMTP change retains the stronger final-250 and command-failure guards.
The reader projection excludes envelope and attachment summaries; current reply
drafts remain explicitly plain-text-only. The morphology repair preserves
fractions, exponents and negative zero while normalizing finite integer double
text. Current Word semantics and stronger Mail tests take precedence over the
older overlapping versions. Unique pending-footer, Arabic tooltip-detail and
nonselectable-INBOX fallback assertions are retained in the canonical suites.

These are preservation checkpoints, not assertions that their incomplete
combined test/UI adaptations passed. Fresh accepted execution identity and
results are recorded separately in the final report.

## Word and proofing

The PR #192 tree contained older Word language behavior that would write or
clear both language slots. The stronger existing active-script behavior was
retained from `10bd0cc4` / `70e5745d` in `word_proofing_language.dart` and
`word_deserializer.dart`.

PR #193's `office_controller.dart`, `wml_run_edit.dart` and
`word_style_cascade.dart` add a distinct repair: splitting a Latin selection
from a mixed-script run can change its effective language even if stored
properties are unchanged. The controller now keeps that split, and adjacent
runs with different effective script routes cannot coalesce as an apparent
no-op. Its boundary, undo/redo and save/reopen regressions are retained.

PR #194's text-control tests retain active-slot expectations and partial
Latin/Arabic selection cases; its engine proofing-language tests retain differing
language/complex-script-marker merge guards. Existing explicit complex-script
formatting can still merge across scripts when semantics agree.

The later `79e77725` adds an explicit `activeLanguageOnly` option and more precise
inspection of selected fragments. The reconciled editor defaults that option to
`true`, preserving the current selected-script behavior. An explicit `false`
supports intentional two-slot changes/resets. A mixed selection changes both
slots only when the selected fragments use both; an explicit complex-script
marker still routes the whole selected fragment through its complex-script slot.
The lower-level deserializer retains its existing parameter defaults. Incoming
slot, reset, metadata-preservation and history cases are retained, with deliberate
two-slot editor cases now explicitly requesting that mode. The 193 split and
coalescing repairs remain intact.

The final union also retains the About dialog's direct external URL launch and
four mocked-platform regressions. Capability prechecks no longer suppress the
launch attempt. Review status tests retain all three languages, enlarged text,
compact/transition widths, pending and paused state, and reachable pane actions.
Their fixtures synchronize view metrics and render constraints on resize.
The merge verification caught incomplete test hunks; the two affected suites
were reconstructed from their exact incoming bodies before qualification.

The later Arabic token-continuation boundaries, decomposed spelling coverage,
and Hunspell final-progress cancellation check are retained. Publisher changes
update wording with their matching tests; the restricted upload allowlist and
hash/readback safeguards remain intact.

## Studio Mail

The native/browser conditional entry, canonical saved reader, bounded exact UID
loader, Word-based composer and fixed localized feedback from `70e5745d` take
precedence over older overlapping host implementations. Incoming saved/session
regressions are adapted to those interfaces; their original source remains in
the incoming parents. The separate test-reconciliation mapping records their
coverage dispositions.

Incoming transport abort ownership is retained: both low-level transports are
aborted independently from high-level disconnect, each cleanup error is
contained, and stale connection completion repeats cleanup. Only selectable
inboxes can be adopted. Discovery uses the credential snapshot captured before
the await.

PR #192's serial submission/follow-up transaction and public
`MailSendPostSubmissionException` are retained. The Studio host accepts that
confirmation only from the same current client and session, clears the draft,
and displays fixed feedback that explicitly forbids resending. Other attempted
submissions remain uncertain with a retained draft and explicit retry
acknowledgement. No Sent append is requested by this foreground host.

Controlled SMTP review found additional false-acceptance paths: preliminary
1xx, final 220, and premature positive DATA replies followed by RSET. The repair
rejects recorded command failures regardless of reply class and requires final
250 acceptance before the high-level transaction can certify submission.
Original failures and successful controls are retained as development evidence;
the frozen gate reruns the complete selected SMTP suites. MPL notices accompany
all new vendored files and the changes are listed in `QUDS_PATCHES.md`.

## Evidence and limits

Incoming reports, incomplete attempts, local checkpoint bundles and runtime
receipts remain under their original dated directories. Their execution counts
are never added to the current gate. Captured refs have a bounded observation
time and are independently classified as ancestors or proven historical
equivalents. No Actions state is queried or awaited.

The foreground host is not the durable repository-driven Mail workspace. Folder,
envelope and SMTP operations retain the high-level client's limits and reconnect
behavior. Real-provider accounts, installed-platform sessions, actual browser
storage and external Word/LibreOffice interoperability remain separate gates.
