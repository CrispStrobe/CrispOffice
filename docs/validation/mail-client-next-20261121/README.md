# Mail saved searches and conversation triage — 21 November 2026

## Intended increment

Continue the desktop-mail parity roadmap from main
`01517de8886ef7bd24947894be5dc823d0328869` with two connected organization
workflows: named, persistent cached-header searches and expandable loaded
conversation groups. Search definitions retain an explicit account scope and
run against current locally retained headers; they do not retain message
snapshots or continuation cursors. Conversation actions remain individual,
visible-message actions even when a group is collapsed.

The initial [intake audit](intake.md) and [machine-readable record](intake-audit.json)
cover all 27 current fork branches, the 100 newest pull-request heads and four
upstream branches. All are ancestors of the starting main; no open pull
requests or uncovered commits were found.

## Delivery and qualification plan

1. Preserve the intake and plan on remote `work/mail-client-next-20261121`.
2. Implement typed, bounded, revision-guarded saved-search persistence, then
   the native Studio user path with name/scope management and fresh searches.
3. Add accessible conversation folding while fencing stale callbacks and
   excluding hidden messages from checked bulk actions.
4. Run the affected real Dart, SQLite and Flutter tests locally, including
   the previously unexecuted conversation suites. Record actual results and
   source identity here; existing receipts are not new test results.
5. Reconcile later remote work, checkpoint the qualified source, and merge
   the finished pull request into remote main.

GitHub Actions are not an acceptance dependency and will not be awaited.
This initial checkpoint makes no test-pass or full-product-parity claim.
