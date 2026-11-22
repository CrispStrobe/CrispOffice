# Mail account workspace — integration and qualification

## Current status

**The frozen `9ce2b057` candidate is qualified: 8,040 passing test executions
across 302 suite executions, with zero failures or skips in accepted scopes.**
This comprises **4,859 fresh executions** and **3,181 retained executions** whose
relevant inputs are verified unchanged. The engine, editor and complete
110-suite Studio scope are accepted, and all 65 changed Dart paths pass strict
analysis/read-only formatting. Reconciliation with the newer main remains
pending; this is a complete pre-reconciliation checkpoint.

The current frozen candidate is
`9ce2b057ed8fac6bf6746a1700a6b3ca84f7f405`, tree
`0abc1d252dbbff5d70bc717c3740ee24673723ee`; local alias
`229d6f78c2b6f25e5d8304658c131659978fe63d` has the same tree. It includes main
`ab3457c98b6d9a0d1da8147db3048dfc50d174d3`. Main subsequently advanced to
`25850fd310910cb6d852f2e3c480dbc8697fe549`; that delta is being audited before
reconciliation. Qualification applies specifically to `9ce2b057`. This report does not claim
acceptance of the later main delta or a final merge.

Retained results are explicit: **2,722 earlier shared-Mail/store cases** plus
**459 cases from 14 complete, error-free Studio suites**. The latter came from
an 18-suite process that failed in four different files. Its original exit 1
and unsuccessful final reporter event remain unchanged. The 14 suites are
retained only after exact dependency and input checks; all 173 results from
the four failed files, including their earlier 164 passes, are replaced by
the fresh successful run. No suite or case is counted twice.

See [qualification.json](qualification.json),
[the source proof](receipts/final-frozen-source-proof.json),
[the scoped input binding](receipts/accepted-scopes-at-final-source.json) and
[the 14-suite carry-forward proof](receipts/studio-fourteen-suite-carry-forward.json).
The work advances explicit connected-account navigation across IMAP/SMTP,
Exchange EWS, Gmail and Microsoft 365 while preserving concurrent Word and
Zotero work. The [feature guide](../../roadmaps/mail/connected-account-navigation.md)
describes the user-facing contract and remaining desktop Mail roadmap.

## Remote intake and incremental preservation

Initial main was `659b81462224a40f50975cfbfca39f636538b836`.
[The initial inventory](initial-intake.json) captured 44 fork branches, the
100 latest updated pull-request heads and four upstream heads: 148 observations
of 114 distinct commits. No PR was open. The outstanding Word text-selector
and connected Mail navigation branches were integrated with their ancestry.

[The later inventory](late-intake.json) captured 46 fork branches, another
100 pull-request heads and four upstream heads. Across both intake boundaries,
**all 298 observations of 120 distinct commits are ancestors of the integrated
source checkpoint**. Later main
`4cc604810fb2f41ac7ba04cbed65cb76300bff59` and then
`b4f1150b18348f348489c93108158a397c922abe`, followed by
`ab3457c98b6d9a0d1da8147db3048dfc50d174d3`, were integrated before the replacement
gates. These main refreshes preserve additional Zotero/revision/table-border
coverage and the concurrent Mail account-removal/revision regressions. The
union retains one atomic selected-account refresh after the cache checks. See
[the first reconciliation decisions](receipts/main-merge-mail-reconciliation.json)
and [the later main union](receipts/main-b4-mail-reconciliation.json).
These are bounded intake snapshots, not a claim about branches created after
the recorded intake.

Remote work branch: `work/mail-account-workspace-20261122`.

| Published checkpoint | Preserved increment |
| --- | --- |
| `77f8ede7e1bd3e08094a4bcc1a09aa911cce4b10` | Initial main and outstanding Word/Mail ancestry |
| `f4516c13937b9ce5cec771bf331dc91d9f37105d` | Atomic expected-record account refresh and optional host capability |
| `0c836fe7555e6fec4e2e2a0b05c43024bc054975` | Native account identity fences and late-owner draining |
| `08c487722f5c931fca831c0cd133a2f6a5e533b9` | Guarded provider sign-in and account handoff |
| `fb8d637210b54c5ede44aa73557076864dda6995` | Later Office branch union and strict handoff cleanup |
| `068c46395a58c67a9537874b6a2030008296793e` | Opaque Word field-boundary revision preservation |
| `180a1267d99cc2d4a139976b57b64a4f61db278a` | Retained observer/owner cleanup, ordinary Disconnect and first-snapshot recovery |
| `3e57fda4de6317c4a547f69220d7ed83802fd19f` | Source reconciliation with main `4cc60481` |
| `d09c3c0eda381d96e1dc28dea96e0026a75bbb01` | Partial qualification records and the first evidence archive |
| `8403ddfd202637e1ebe7c4350d5e765347ef7023` | Stale connected-toolbar callback rejection and bound Refresh/More mailbox |
| `415265e46c7679531adbe97211d064146a26561a` | Main `b4f1150b`, modal same-session cancellation and preserved pending evidence |
| `7c2f6e744b3489460035bbbb358d46e22e58ce20` | Pinned formatter normalization with an explicit AST/hash bridge |
| `800c3dfd56b169831222d53a02e2b7b83f4f1857` | Main `ab3457c9`, table-border work, nine provider regressions and preserved partial evidence |
| `8bbe6bcb9d22681a765e85c8fc4a80859221b042` | Close/Disconnect submission preservation, late-owner recovery and durable outcome draining |
| `64a238c9ce6a72264d91dd8b22dcfc35d0cf5ce9` | Full Outbox-dialog operation ownership seam and EWS outcome-receipt retention |
| `460c9050b2e0a23301061944324f301a69945388` | Native immediate/dialog/legacy send ownership and four gated SQLite cases across both hosts |
| `e6487fc634ec45298f161432bb0396865190d5bb` | Nonnullable retry-fixture binding caught by strict analysis; assertions unchanged |
| `9ce2b057ed8fac6bf6746a1700a6b3ca84f7f405` | Four test-entrypoint corrections: typed tooltip lookup, bounded dismissal settlement and serialized replacement-session assertions |

Each checkpoint was published with a non-forced expected-head ref update after
checking that the remote Git tree equals the local tree. Source branches were
not deleted or rewritten. GitHub Actions, statuses and queue state were not
queried or awaited; no workflow or repository protection was changed.

## Validation accounting

### Retained results with unchanged inputs

The earlier normal local runs remain applicable to the integrated source:
all 571 captured shared-Mail inputs and all 170 captured store inputs match
their before/after manifests and the current source bytes. The carry-forward
audit also found no added or removed scoped paths. This is **2,722 retained
passing test executions across 124 suites, with zero failures or skips**; it
is not 2,722 fresh executions on the final checkpoint.

| Retained cohort | Passed | Suites | Execution boundary |
| --- | ---: | ---: | --- |
| Mail core | 648 | 28 | Dart VM at `f4516c13` |
| Mail transport | 612 | 23 | Dart VM at `f4516c13` |
| Shared Mail UI | 294 | 18 | Flutter at `f4516c13` |
| Transport JavaScript boundaries | 6 | 3 | Node at `f4516c13` |
| Mail SQLite store | 1,159 | 51 | Dart VM; includes real interruption recovery |
| Store browser-error classification | 3 | 1 | Node |
| **Retained total** | **2,722** | **124** | **Exact relevant-input equality verified** |

[The original carry-forward audit](receipts/carry-forward-audit.json),
[the latest-main input audit](receipts/retained-mail-after-ab.json),
[the final checkpoint rehash](receipts/accepted-scopes-at-final-source.json),
[independent raw-reporter recount](receipts/retained-raw-reporter-audit.json)
and [store receipt](receipts/mail-store-qualification.json) record the evidence.
The recount requires one successful final reporter event, no error events,
no unfinished tests and no malformed JSON events. Hidden loader/setup events
are excluded. Two different parameter rows in Mail core share a display name;
they have distinct test IDs and are not duplicate executions.

### Qualified fresh gates

| Gate | Cases passed | Suites | Disposition |
| --- | ---: | ---: | --- |
| Word/VBA engine | 1,831 | 20 | Accepted |
| Zotero/ODT/revision/style/table engine | 1,068 | 45 | Accepted |
| Editor Zotero integration | 51 | 3 | Accepted on the frozen candidate |
| Repaired Studio Mail files | 173 | 4 | Accepted fresh run; replaces every result from those previously failed files |
| Remaining Studio Mail files | 1,736 | 92 | Accepted fresh run on the same frozen candidate |
| **Fresh total** | **4,859** | **164** | **Zero failures or skips** |

The fresh engine gate ran all 65 suites on exact current engine inputs in two
normal VM processes. Its 39 changed Dart paths passed read-only formatting
before tests and strict analysis afterward. All ten commands exited zero,
every declared suite and test lifecycle completed, and raw reporter counts
match the full case inventories. The independent audit also verifies all
command-output hashes and the complete declared source inventory. See
[the engine summary](receipts/final-ab-engine-summary.md),
[qualification](receipts/final-ab-engine-qualification.json),
[raw-reporter audit](receipts/final-ab-engine-raw-audit.json) and
[scope audit](receipts/final-ab-engine-scope-audit.json).

Engine execution began at `800c3dfd` and ended after the Mail-only `8bbe6bcb`
checkpoint. Those repository trees differ. All **1,421 engine/transitive/config
inputs** are byte-identical before, after and at the current candidate; engine
library/test/tool bytes also match integrated main `ab3457c9`. The manifest
SHA-256 is
`7efde2fa97ad094c16cc8f76df6ad9cdd4670133992cdcedeed9ee5dd4e7543f`.
Mail host/editor files are outside this scope and receive no acceptance from
these engine executions. No normalization bridge is needed for this gate.

All **65 changed Dart paths** pass strict analysis and read-only formatting:
39 engine and 26 Mail/editor paths. Their disjoint union exactly matches the
changes from initial main. All 26 host static input hashes match before,
after and at the current candidate. See
[the static receipt](receipts/mail-static-final-qualification.json) and
[independent union audit](receipts/final-static-union-audit.json).

The earlier 25-path analysis found one nullable retry-fixture variable before
any Studio tests started. A nonnullable final queued entry fixed that type
error without changing assertions. Its
[failed analysis receipt](receipts/mail-static-attempt-05-qualification.json)
remains diagnostic evidence. Later corrections add the cloud-test entrypoint
to the changed-file union, giving the current 26 host paths.

The editor run and four-file repaired run each capture **6,224 inputs**, all
unchanged before, after and at independent verification. The repaired run
passes all 173 cases, including the four previously unsettled route-dismissal
cases, four real-SQLite receipt/owner cases and the stronger native replacement
session contract. See [the editor receipt](receipts/editor-zotero-final-qualification.json),
[editor raw audit](receipts/editor-zotero-final-raw-audit.json),
[four-file receipt](receipts/studio-four-fresh-qualification.json) and
[four-file raw audit](receipts/studio-four-fresh-raw-audit.json).

### Retained successful Studio suites from a failed process

The preceding 18-suite process ran 632 substantive cases: 623 passed and nine
failed. It exited 1 and reported `done.success = false`. All failures belong
to four entrypoint files. **Only the other 14 complete suites, containing 459
successful cases, are retained.** Each retained suite has the expected declared
root-group case count, complete successful test/loader/hook lifecycles, no
errors and no skips. The original process is never relabeled as successful.

Between that execution and `9ce2b057`, exactly the four excluded test
entrypoints changed; all other 6,220 captured input bytes match. A transitive
Dart import/export/part audit follows 3,896 source files, including 865 repository
files and all conditional branches. None reaches or names an excluded
entrypoint. The retained entrypoints, production, support, fixtures, config,
locked dependencies and runtime remain unchanged. The four-file diff changes
only test lookup, settlement waits and same-session ownership assertions; it
changes no shared resource or fixture. The complete graph, hashes, source
manifests and raw reporters are preserved in
[the carry-forward proof](receipts/studio-fourteen-suite-carry-forward.json).

All **173 cases** from the four excluded files are replaced by the fresh run,
including their old 164 passes. The final Studio accounting is therefore
**14 retained suites + 4 fresh repaired suites + 92 fresh remaining suites**,
with exactly 110 unique paths. The final actual count is **459 retained +
1,909 fresh (173 + 1,736) = 2,368 Studio cases**. Both fresh processes exited
zero with successful final reporter events; all 6,224 input maps match before,
after, between fresh runs and at final verification. The retained graph's
source hashes also match. See [the accepted-scope plan](receipts/studio-final-accepted-scopes.json)
and [the authoritative aggregate](receipts/studio-final-aggregate.json).

The earlier prediction of 2,365 missed three incoming router cases: that suite
grew from five to eight. The actual per-suite inventory shows 17 added cases
since attempt 3: nine provider, three router, one EWS accepted-cleanup and four
Outbox owner cases. See [the inventory delta](receipts/studio-case-inventory-delta.json).
Predictions are replaced by observed counts.

| Accounting group | Passing cases | Suite executions |
| --- | ---: | ---: |
| Fresh engine, editor and 96 Studio suites | 4,859 | 164 |
| Retained earlier Mail core/store/transport/shared UI | 2,722 | 124 |
| Retained 14 independent successful Studio suites | 459 | 14 |
| **Accepted total at `9ce2b057`** | **8,040** | **302** |

The older 2,722 retained Mail cases remain separate from the 459 retained
Studio cases. Portability adapter checks are also separate and are not added
to this total.

### Superseded engine and development evidence

The preceding 2,594-case gate was qualified at `7c2f6e74`. Its VM tests and
analysis ran at `415265e4`, followed by a one-test-file formatter normalization
and the remaining format/portability checks. The bridge proves identical
recursive ASTs and AST-rendered source, zero parser diagnostics and exact
before/after file hashes. The formatter also removed one optional trailing
map comma; complete token inventories intentionally differ by that token,
while every other token and comment matches. No token-byte or whitespace-only
identity is claimed. The VM cases were counted once, with no rerun solely for
formatting. That valid historical proof remains in
[the bridge](receipts/engine-normalization-bridge.json) and
[independent normalization audit](receipts/engine-normalization-audit.json).

Main `ab3457c9` subsequently changed production readers/serializers and added
table-border behavior. The fresh 2,899-case gate therefore **replaces** the
2,594-case result for current-source acceptance. Both original and normalized
historical evidence are retained as diagnostics. The older 2,585-case gate,
initial Word 1,458, intermediate engine 2,544, focused 82, provider-development
103 and repeated earlier editor 51 runs add no final cases. Studio attempts
1–4 contribute zero. The sole exception for a failed process is the explicitly
proved 14-suite subset of attempt 6 above; all four failed suite files are fully
replaced. The 103-case provider run also observed three concurrent Word input changes.

## Repairs and portability evidence

The first Studio attempt exited with 132 passing cases and one error, with all
6,220 inputs unchanged. The existing EWS Disconnect/failed-observer regression
exposed a retained Refresh callback reading a mailbox that Disconnect had
cleared. Binding the mailbox and guarding callback identity fixed that null
assertion. See [the first repair record](receipts/studio-repair-notes.json) and
[failed-run receipt](receipts/studio-first-attempt-qualification.json).

The second attempt recorded 564 substantive passes and one error. The new
callback guard rejected an intentionally captured same-session Disconnect
during an ordinary modal bulk-action review; confirming then moved messages on
**the previous provider**, before any reconnect. It did not demonstrate
commands entering a new session. The correction preserves identity checks while
allowing that cancellation; the account chooser raises its navigation fence
at entry so account handoff stays protected. The existing regression was not
weakened. See [the modal-cancel repair](receipts/studio-modal-cancel-repair-notes.json).

That attempt also exposed a Python receipt-parser error. `str.splitlines()`
split valid JSON strings at U+0085, U+2028 and U+2029 inside three unsafe-filename
test names, then the parser raised `KeyError: 569`. The original JSONL is valid
when split only on ASCII LF. Cases 569, 570 and 571 are three real successful
attachment-filename tests; their starts were present in the raw bytes. Correct
LF framing restores all three, changing the earlier incomplete subtotal of
561 to **564 passing cases**. The superseded reconstruction is retained.

The child exit code was not persisted before that original parser exception
and remains unavailable. Raw reporters, stderr and unchanged before/after
manifests are preserved. The corrected runner persists the child exit code
first, uses LF framing and reports genuinely unmatched visible completions as
errors. It runs the complete next cohort without fail-fast. See
[the corrected diagnostic receipt](receipts/studio-second-attempt-qualification.json)
and [the framing audit](receipts/studio-reporter-lf-framing-audit.json).
Neither failed attempt contributes final passing credit.

The third attempt ran all 110 suites to completion and exited with child code
1: **2,329 passes, 22 errors and no skips**, with all 6,220 inputs unchanged.
The original parser reported 2,326 passes; LF framing restores the same three
attachment-name cases. Both original and corrected receipts are preserved.
Nine errors were covered by incoming fixture corrections: three Delete tests
needed an explicit capability, four local-cache tests needed the retained-empty
message, and two setup/lifecycle tests needed deterministic native account
setup. Other failures required lifecycle, submission-preservation or setup
contract repair. Classification alone supplies no passing credit. See
[the full failed-run receipt](receipts/studio-third-attempt-qualification.json)
and [the authoritative LF summary](receipts/studio-third-attempt-lf-summary.json).

The fourth attempt selected 13 repaired suites at `8bbe6bcb` and was
intentionally interrupted after 318 substantive passes, zero observed errors
and eight started suites. There is no final reporter event. The execution
session returned 130; the Flutter child exit code was not persisted and is
unavailable. All 6,224 captured inputs matched before and after interruption.
It contributes zero passing credit. See
[the interruption record](receipts/studio-fourth-attempt-interruption.json) and
[independent LF recount](receipts/studio-fourth-attempt-lf-summary.json).

That interruption preserves a review boundary: manual, scheduled and
acknowledged Outbox-dialog attempts share a helper that commits the outcome
*after* awaiting the provider. Tracking only the network callback would end
ownership too early. The full-operation fix registers the exact owner before invoking
the complete helper and retains it through its final local receipt, with
independent provider-response and receipt-write gates in four SQLite
regressions across EWS and native. The source review found no further issue in
that changed boundary, and all four SQLite cases passed in the corrected
four-file run. See
[the bounded source review](receipts/outbox-ownership-review.json). A
persisted submitting marker already recovers conservatively as uncertain;
the identified defect loses the actual late outcome receipt and releases the
owner early. It is not evidence of an automatic replay.

The sixth Studio attempt is the preserved 18-suite diagnostic described above:
623 passes, nine failures, exit 1 and all 6,224 inputs unchanged. Four new SQLite
cases selected a `RawTooltip` and cast it to `IconButton` before reaching the
send path; the typed button finder now reaches the intended callback. Four
cloud/EWS cases needed a bounded wait for dismissal after their gated cleanup
had completed. The native session case now asserts that reconnect remains
blocked until retired send storage settles, while preserving uncertainty and
preventing dispatch from the new session. The four-file fresh rerun passes
all 173 cases, with every old assertion retained or strengthened. See
[the original failed receipt](receipts/studio-sixth-attempt-qualification.json)
and [the exact test-only delta](receipts/fixture-only-source-delta.json).
The 14-suite exception is accounted separately; the failed process stays failed.

The first incoming engine gate exposed seven Zotero failures: six expectations
compared refreshed citation text against the unmodified source fixture, and
one parser defect discarded opaque `rPrChange` history on field boundaries.
The fixture helper now accepts explicit citation-text overrides while
retaining the other formatting and structural assertions. The parser retains
the complete original run properties on field-boundary nodes, while ordinary
text revisions retain their existing handling. Original fixture bytes were
not changed. Five additional regressions cover the boundary kinds and a mixed
text/marker run across repeated saves. Incoming real empty-code-run revision
provenance, copying and accept/reject checks also survived the final merge.
See [the repair record](receipts/zotero-repair-notes.json). The failed run and
the focused repair run remain diagnostic evidence, not additional passing
credit. The later main also adds nine instruction-side style exclusion
regressions and preserves the original golden snapshot before Refresh, the
non-cascading expected-text helper and all raw-boundary history checks.

Portability uses the output contract of each tool. The canonical Split
conformance corpus on the accepted engine scope matched VM and Node raw bytes: **174 adapter cases across
Word, Excel and PowerPoint**, SHA-256
`7836c5c824b9585d17b7818f1dc7271e061340ec0202acda8f30121d9ced9e8b`.
These adapter cases are recorded separately from the Dart test counts.

The BAS smoke emits ordinary `jsonEncode`: VM integral doubles such as `0.0`
and JavaScript `0` are compared after normalizing only finite integral numeric
representations and sorting JSON keys. Strings, booleans, arrays, structure
and values must otherwise agree. The replacement DOCX/DOCM smoke receipts
have equal canonical JSON, SHA-256
`0bbdfe5579a2604573d57f2c20727b1bd986d5c2c76b190572be633079bc4480`.
Their raw bytes do not match. An independent comparison of those outputs
found exactly 58 integral-number encoding differences and zero other
differences; see [the final portability audit](receipts/final-ab-portability-audit.json).
The same raw smoke hashes appeared in the preceding diagnostic comparison;
the accepted engine scope was executed and independently compared again. Both the original
overly strict raw-byte failure and the corrected comparison are retained in
[the development portability record](receipts/development-portability-comparison.json).

## Evidence and reproduction

[Runtime provenance](runtime-provenance.json) records the unchanged official
Flutter 3.47.8 / Dart 3.13.7 SDK and Node 24.22.3. All 204 required hosted
package archives match lockfile hashes; ordinary enforced-lockfile restoration
left the repository lockfile unchanged. No SDK, test framework or compiler
source was patched to obtain results.

Small qualification and source receipts are kept under `receipts/`.
[The evidence archive](local-evidence.tar.xz) and
[its hash index](evidence-index.json) retain raw JSON reporters, full case
inventories, source manifests, commands, runtime hashes, diagnostic attempts
and runners. The archive contains complete qualification for the frozen
`9ce2b057` candidate, including accepted fresh gates, the 14-suite dependency
proof, and every preserved failed/interrupted diagnostic. A later main merge
will require its own explicit source binding or affected-scope qualification.

| Archive directory | Evidence role |
| --- | --- |
| `shared-mail/`, `mail-store/` | Retained 2,722 passing cases and exact-input carry-forward evidence |
| `incoming-engine/` | Accepted 2,899-case/65-suite engine run, full manifests, static checks and portability receipts |
| `development/engine-b4-original-vm-analysis/`, `development/engine-b4-normalized/` | Superseded 2,594-case receipt, initial format mismatch and exact normalization proof |
| `development/` | Earlier engine runs, original failed/interrupted Studio processes, earlier editor/static runs and diagnostic probes |
| `studio-carry-forward/` | Exact 14-suite/459-case subset proof and dependency graph with 3,896 files; original 18-suite process remains failed |
| `studio-mail/`, `editor-zotero/`, `studio-mail-static/` | Fresh 4/92 Studio cohorts, final aggregate, editor 51 and 26-path host static checks |
| `runners/`, `runtime/`, `integration/` | Reproduction scripts, pinned runtime/package hashes and intake/source audits |

Receipt paths and commands preserve their original workspace locations. In the
archive, `incoming-engine/` corresponds to `final-ab-engine`. The two
`development/engine-b4-*` directories preserve the original and normalized
preceding gate. Commands and environments are recorded verbatim. Source
manifests, raw historical proof inputs and the Dart normalization script remain
included. Historical b4 receipts keep their original archive labels:
`incoming-engine-original-vm-analysis/` now maps to
`development/engine-b4-original-vm-analysis/`, and their old `incoming-engine/`
label maps to `development/engine-b4-normalized/`. Current accepted engine
receipts use `incoming-engine/` directly. Compiled JavaScript is
a reproducible intermediate; its source, compile command, hash and execution
receipts are retained. No GitHub Actions output is used as test evidence.

## Scope and remaining acceptance

The account store performs an atomic compare-and-set against identity,
revision and connection timestamp, so stale reconnects cannot recreate a
deleted or replaced shortcut. Hosts reject changed targets at asynchronous
boundaries, drain pending restoration, retain failed observer/owner handles
and block new ownership until explicit cleanup succeeds. Ordinary Disconnect
begins observer retirement before waiting for a first cache snapshot, avoiding
a restoration/close deadlock. A generation fence rejects callbacks while
cleanup still retains their resources.

No real account credentials, user mail, provider mutations or outbound messages
were used. Live-provider and installed-platform acceptance remain open, as do
simultaneous background accounts, unified live folders and full Outlook,
Thunderbird or eM Client parity. Node execution does not establish browser UI
acceptance. A concrete native SQLite owner memoizes a failed close future;
owners that cannot later close successfully may require a host restart.
Custom owners can recover in process only when their explicit retry succeeds.
