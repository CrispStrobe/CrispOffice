# Mail account workspace — integration and qualification

## Current status

**Partial qualification: only the complete Studio Mail gate is still pending.**
Engine qualification passed 2,594 cases, editor integration passed 51 cases,
and all 47 changed Dart paths passed their analysis/format checks. The engine
record includes an explicit one-test-file normalization bridge. This report
does not yet claim final overall acceptance or a completed merge to main.

The final source checkpoint is
`7c2f6e744b3489460035bbbb358d46e22e58ce20`, tree
`fe9761f081cf89038ed69fbcddfbf3de08d1daca`. Local baseline
`128a49df722662c904335f6dbbc2e8990a1266db` has exactly the same tree.
Documentation can advance independently of this frozen source boundary. See
[qualification.json](qualification.json), [the source proof](receipts/integrated-source-proof.json)
and [the checkpoint alias](receipts/final-source-alias.json).

The work advances connected-account navigation, with explicit sign-in and one
foreground account across IMAP/SMTP, Exchange EWS, Gmail and Microsoft 365. It
also preserves concurrent Word and Zotero work. See
[the feature guide](../../roadmaps/mail/connected-account-navigation.md) for
the user-facing behavior and the remaining desktop Mail roadmap.

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
`b4f1150b18348f348489c93108158a397c922abe` were integrated before the replacement
final gates. These main refreshes preserve additional Zotero/revision coverage and
unions the concurrent Mail account-removal/revision regressions; it retains
one atomic selected-account refresh after the cache checks. See
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
[the latest-main input audit](receipts/retained-mail-after-b4.json),
[independent raw-reporter recount](receipts/retained-raw-reporter-audit.json)
and [store receipt](receipts/mail-store-qualification.json) record the evidence.
The recount requires one successful final reporter event, no error events,
no unfinished tests and no malformed JSON events. Hidden loader/setup events
are excluded. Two different parameter rows in Mail core share a display name;
they have distinct test IDs and are not duplicate executions.

### Fresh qualification results

| Gate | Cases passed | Suites | Disposition |
| --- | ---: | ---: | --- |
| Word/VBA engine | 1,831 | 20 | Passed |
| Zotero/ODT/revision/run/style engine | 763 | 32 | Passed |
| Editor Zotero integration | 51 | 3 | Passed on the final source |
| Studio Mail acceptance | Pending | 110 expected | Complete run in progress without fail-fast |
| **Completed fresh runs so far** | **2,645** | **55** | **Zero failures or skips in these credited cohorts** |

Engine qualification also passed the VM/Node Split corpus and DOCX/DOCM BAS
smoke. Those portability executions are separate from the Dart test counts.
Strict analysis and read-only formatting cover all 47 changed Dart files:
32 engine paths and 15 Mail/editor paths, exactly matching the changed-path
union from initial main. See [the engine summary](receipts/final-engine-summary.md),
[combined engine receipt](receipts/final-engine-qualification.json),
[independent reporter recount](receipts/final-engine-raw-audit.json),
[editor receipt](receipts/editor-zotero-qualification.json) and
[Mail/editor static receipt](receipts/mail-static-qualification.json).

The editor run captured 6,220 inputs; all were identical before, after and at
the independent verification. Provider navigation is expected to contain 127
cases and native navigation 50. Those remain scope checks until the full
Studio gate completes successfully, with exact suite coverage and unchanged
captured inputs.

#### Engine source normalization

The VM/analysis stage ran at `415265e4`; the final format/portability stage ran
at `7c2f6e74`. Each stage captured 1,415 inputs that remained byte-identical
throughout that stage. Between stages, **1,414 inputs are byte-identical**.
The sole changed input is
`packages/quds_office_engine/test/word_zotero_boundary_formatting_test.dart`.
The pinned formatter folds one map literal and removes its optional trailing
comma. Production source is unchanged.

The bridge verifies exact original/final file hashes, identical recursive
parsed ASTs, identical AST-rendered source and zero parser diagnostics. The
complete token inventories intentionally differ by that one optional comma;
every other token and comment matches. Raw token equality is not claimed.
The independent audit also compared the entire before/after input inventories
and both raw source files. See [the bridge](receipts/engine-normalization-bridge.json)
and [independent normalization audit](receipts/engine-normalization-audit.json).

The original two VM runs and strict analysis completed successfully. Their
combined runner then stopped at the read-only format mismatch. Seven remaining
format/portability commands completed on the normalized source, without
repeating either VM tests or analysis. **The 2,594 VM cases are counted once**.
The original format mismatch, normalization proof and portability runs add no
VM test credit. Both original and normalized source manifests and raw outputs
are retained.

The older 2,585-case engine gate remains prior-source evidence: latest main
changed three captured inputs, including production `word_zotero.dart`, and
added nine instruction-side style cases. The replacement 2,594-case gate covers
that change. See [the input delta](receipts/b4-engine-input-delta-from-prior.json)
and [merge record](receipts/b4-engine-merge-resolution-plan.json).

Do not add earlier Word 1,458, intermediate engine 2,544, preceding engine
2,585, focused 82, provider-development 103, repeated editor 51, bootstrap or
failed Studio attempt counts to the final total. The 103-case provider
run also observed three concurrent Word input changes. Repeated and superseded
runs are diagnostic evidence, not independent passing credit.

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
conformance corpus on the final source matched VM and Node raw bytes: **174 adapter cases across
Word, Excel and PowerPoint**, SHA-256
`7836c5c824b9585d17b7818f1dc7271e061340ec0202acda8f30121d9ced9e8b`.
These adapter cases are recorded separately from the Dart test counts.

The BAS smoke emits ordinary `jsonEncode`: VM integral doubles such as `0.0`
and JavaScript `0` are compared after normalizing only finite integral numeric
representations and sorting JSON keys. Strings, booleans, arrays, structure
and values must otherwise agree. The final DOCX/DOCM smoke receipts
have equal canonical JSON, SHA-256
`0bbdfe5579a2604573d57f2c20727b1bd986d5c2c76b190572be633079bc4480`.
Their raw bytes do not match. An independent comparison of those outputs
found exactly 58 integral-number encoding differences and zero other
differences; see [the final portability audit](receipts/final-portability-audit.json).
The same raw smoke hashes appeared in the preceding diagnostic comparison;
the final source was executed and independently compared again. Both the original
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
and runners. The archive is being refreshed for the final source; it will add
the completed editor/Studio/static gates once Studio settles.

| Archive directory | Evidence role |
| --- | --- |
| `shared-mail/`, `mail-store/` | Retained 2,722 passing cases and exact-input carry-forward evidence |
| `incoming-engine-original-vm-analysis/` | Original 2,594 VM cases, strict analysis, manifests and initial format mismatch |
| `incoming-engine/` | Combined engine receipt, AST/token/source proof, final format and portability checks |
| `development/` | Superseded engine runs, both failed Studio attempts, earlier editor/static runs and diagnostic probes |
| `runners/`, `runtime/`, `integration/` | Reproduction scripts, pinned runtime/package hashes and intake/source audits |

Receipt paths and commands preserve their original workspace locations. In the
archive, `incoming-engine/` corresponds to `final-b4-engine-formatted`, and
`incoming-engine-original-vm-analysis/` corresponds to `final-b4-engine`.
Commands and environments are recorded verbatim. Source manifests, raw proof
inputs and the Dart normalization script are included. Compiled JavaScript is
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
