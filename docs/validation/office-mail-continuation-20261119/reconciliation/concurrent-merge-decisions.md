# Concurrent continuation reconciliation

The first published integration was `3119a459`, with both initial unmerged
frontier tips as parents. The implementation checkpoint was `70e5745d`.
The next remote checkpoint, `ec8bd9cf`, also retains PR #194 at `4b8b9e2e`,
PR #193 at `4ed8154a` and PR #192 at `d00bd397` as actual ancestors. Each tree
was read back from the remote and compared with the intended local tree.

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
