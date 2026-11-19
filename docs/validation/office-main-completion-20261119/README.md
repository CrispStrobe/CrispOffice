# Office completion and merge to main — 19 November 2026

## Work in progress

This continuation carries the existing Zotero work in PR #173 through a
reconciled, locally qualified merge to remote `main`. The user explicitly
authorized incremental remote checkpoints and the final merge. GitHub Actions
are not queried, dispatched or awaited.

The first published checkpoint, `17aa63ab`, combines the existing integration
branch `056414ba` with native Mail `fa284f22`. It preserves Notes `c320f283`,
thesaurus `df62b589`, Zotero annotations `17ec8cc8`, and their recorded evidence.
Checkpoint `5107eff6` also brings in concurrent integration `ebe0498a`, including
two Mail flag/schema test repairs. These are non-forced remote updates with an
expected previous head, verified by fetching the published object and comparing
its complete tree with the local integration.

## Scope of fresh qualification

The captured inventory contains 392 refs: 213 fork branches, 175 pull-request
heads, and four original-upstream branches. Independent accounting found 364
ancestors and 28 historical equivalents, with all 14 equivalence proofs freshly
recomputed and no unaccounted head. This is a bounded capture; concurrent updates
are inspected again before the final merge.

The Office engine, editor and Studio entries are byte/mode-identical to source
`39843ed4`, which has the separately recorded 2,018-case qualification. Those
historical cases are not counted as fresh results. The new code requiring
execution is Mail's nullable durable flags/schema-v3 migration, native IMAP
transport, and the shared protocol changes in the vendored `enough_mail` fork.

Review found and repaired handling of unsolicited FLAGS-only IMAP updates.
They no longer consume the requested message count or interrupt complete
literal responses. Later safely identified flags supersede an earlier snapshot;
missing literals and flag updates made ambiguous by expunge-driven sequence
changes fail safely instead of producing false tombstones or write success.
The focused regression records include a reproduced false-success case before
the correction. These development runs remain separate from final totals.

The first full protocol run also exposed a legacy exception-contract regression.
The distinct budget error now extends `FormatException`, preserving both the
existing parser contract and native Quds quota classification. Ordinary status
text containing the word FETCH is kept separate from message data. The runtime
replay helper now validates exact locked/workspace package names instead of a
historical fixed package count, including the newly added transport member.

The committed native plan selects 56 suites: three native transport suites, all
six MIME consumer suites, all four reader UI suites, and 43 shared protocol and
lifecycle suites. The separate Node plan selects seven suites: the transport's
unsupported-browser boundary and all six MIME suites. The existing complete
Mail Store gate additionally checks core/store VM and Node tests, static
analysis, formatting, runner controls and browser-entry/worker compilation.
Repeated VM/Node executions will be reported by platform, with distinct source
files counted separately.

The pinned Flutter 3.47.8 / Dart 3.13.7 runtime is restored from verified release
bytes and verified locked package archives. Locked resolution must retain the
existing dependency manifests and lockfile. Runtime recovery diagnostics remain
separate from application-test results. The final source, raw results, counts,
runtime bindings and independent audits will be recorded here after execution.

## Acceptance boundaries

The local transport fixture drives actual command/framing/literal parsers and
real SQLite transactions; it does not establish live-provider TLS/certificate,
OAuth-host, or disposable-account interoperability. Browser compilation and Node
tests do not establish actual browser lifecycle/storage acceptance. Existing
installed-desktop, live Zotero, Word/LibreOffice interoperability, and independent
linguistic acceptance boundaries retain their earlier scope.
