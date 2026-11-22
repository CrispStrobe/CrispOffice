# Mail account workspace — integration and qualification

## Current status

**The integrated `df8571cb` candidate is qualified: 8,249 passing test executions
across 307 suite executions, with zero failures or skips in accepted scopes.**
This comprises **5,393 fresh executions** and **2,856 retained executions**
whose relevant inputs are proved unchanged. Main `25850fd3` is integrated
and the source is saved remotely. The current frozen source is
`df8571cb70e8677660ce6843c26de017f5524c52`, tree
`696f6bbb5c6deef20e2939ec477b2767dd56bfc1`; local alias
`594a7e502181e6ce2467f1c3163318bfa79a8733` has the same tree.
Its parents are the preserved pre258 evidence checkpoint `b25acd58` and main
`25850fd310910cb6d852f2e3c480dbc8697fe549`.

Fresh gates pass **2,761 Mail core/store/transport/UI cases**, **94 changed
engine-boundary cases**, and **2,538 cases across all 113 Studio Mail
suites**. Retained results are exactly 2,805 engine cases from 64 unchanged
suites and 51 editor cases from three unchanged suites. Transitive source,
configuration and resource inputs are verified against the frozen union.
All **95 changed Dart paths** are covered by strict analysis/read-only
formatting: 57 fresh paths and 38 unchanged engine paths.

All older 2,722 Mail and 2,368 Studio results have zero current credit; the
Archive changes are covered by the fresh replacement gates. The full pre258 qualification
of 8,040 cases is preserved as source-bound history at `b25acd58`, including its
explicit 14-suite retention proof. No historical test is counted twice.

See [qualification.json](qualification.json),
[the current source proof](receipts/post258-frozen-source-proof.json),
[the final aggregate](receipts/post258-final-aggregate.json),
[fresh raw-reporter/input audit](receipts/post258-completed-cohorts.json), and
[retained engine/editor proof](receipts/post258-retained-engine-editor.json).
The work advances [connected-account navigation](../../roadmaps/mail/connected-account-navigation.md)
and integrates [remembered Archive destinations](../../roadmaps/mail/remembered-archive.md).
Full desktop-client parity remains an open roadmap goal.

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
`ab3457c98b6d9a0d1da8147db3048dfc50d174d3`, were integrated before their replacement
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
| `b25acd58cb31f1910e96a031b465bfeb5a683e35` | Complete source-bound pre258 evidence: 8,040 passing executions |
| `df8571cb70e8677660ce6843c26de017f5524c52` | Main `25850fd3`, remembered Archive destinations and preserved account/Outbox ownership |

Each checkpoint was published with a non-forced expected-head ref update after
checking that the remote Git tree equals the local tree. Source branches were
not deleted or rewritten. GitHub Actions, statuses and queue state were not
queried or awaited; no workflow or repository protection was changed.

## Current validation accounting

### Fresh gates on the integrated source

| Cohort | Passed | Suites | Status |
| --- | ---: | ---: | --- |
| Mail core, Dart VM | 659 | 29 | Passed |
| Mail SQLite store, Dart VM | 1,187 | 52 | Passed |
| Store browser-error classification, Node | 3 | 1 | Passed |
| Mail transport, Dart VM | 612 | 23 | Passed |
| Mail transport JavaScript boundaries, Node | 6 | 3 | Passed |
| Shared Mail UI, Flutter | 294 | 18 | Passed |
| **Fresh Mail subtotal** | **2,761** | **126** | **Zero failures or skips** |
| Changed engine boundary-formatting entrypoint | 94 | 1 | Passed; replaces its previous 94 cases |
| Complete Studio Mail scope | 2,538 | 113 | Passed fresh; replaces every earlier Studio case |

Every completed fresh process exited zero and produced one successful final
reporter event. Independent LF-byte parsing verifies the full declared suite
inventory, complete per-test lifecycle, exact case inventories and no failures,
skips, orphan completions, duplicate IDs or malformed JSON records. Known
literal `Running build hooks...` prefixes are recorded explicitly rather than
silently accepting arbitrary non-JSON output.

All **6,342 workspace inputs, 6,200 resolved-package inputs and four runtime
inputs** match before, after, between completed cohorts and at independent
verification. Tracked Git blobs match the frozen checkpoint. Commands, stderr,
raw JSONL, case inventories and artifact hashes are retained in the evidence.
The [independent audit](receipts/post258-completed-cohorts.json) links each
completed cohort to its exact reporter and input-manifest hashes.

The full Studio run passes **2,538 cases across exactly 113 suites**
in one normal Flutter process, with exit zero and a successful final
reporter event. All **6,236 captured workspace inputs**
match before, after and at independent verification. The 6,192 inputs
shared with the broader Mail snapshot also match; the 44 Studio-only
package publication documents are independently unchanged. Every discovered `*mail*_test.dart`
entrypoint is observed exactly once, including the saved-Mail and workspace
shortcut suites. See [the Studio receipt](receipts/post258-studio-qualification.json)
and [independent raw audit](receipts/post258-studio-raw-audit.json).

| Accepted accounting group | Passing cases | Suite executions |
| --- | ---: | ---: |
| Fresh Mail, changed engine boundary and complete Studio scope | 5,393 | 240 |
| Retained unchanged engine and editor scopes | 2,856 | 67 |
| **Accepted total at `df8571cb`** | **8,249** | **307** |

The [final aggregate](receipts/post258-final-aggregate.json) verifies unique
scope/platform, repository suite path and test-ID identities. The previous
94 engine-boundary cases, all previous 2,722 Mail cases and all previous
2,368 Studio cases are excluded before fresh replacement. Portability
adapter checks remain separate. No display-name coincidence adds or
removes a real parameterized test execution.

### Retained engine and editor scopes

| Retained scope | Passing cases | Suites | Evidence boundary |
| --- | ---: | ---: | --- |
| Word/VBA/Zotero/ODT/revision/style/table engine, excluding changed boundary test | 2,805 | 64 | Successful original 65-suite gate, with all 94 changed-entrypoint cases removed |
| Editor Zotero integration | 51 | 3 | Successful original editor gate; reachable source and configuration unchanged |
| **Retained total** | **2,856** | **67** | **No fresh executions claimed** |

The engine production library is unchanged by main 258. Its only executable
delta is one boundary-test entrypoint using independent constant expectations;
that entire 94-case suite is rerun fresh. A CHANGELOG paragraph also moved.
The retained engine graph reaches 494 repository Dart files; the editor graph
reaches 505. Complete import/export/part graphs follow all conditional URI
branches. Neither retained scope can reach the changed test entrypoint.
All 207 captured fixture/macro resources and 11 scoped configuration inputs
are unchanged, as are the pinned runtime and locked dependencies.

The original engine run captured 1,421 inputs. Only the excluded boundary
entrypoint differs. The editor's earlier broad workspace snapshot includes
changed Mail files, but its actual dependency graph reaches none of them;
the proof does not pretend the entire repository tree stayed identical.
Original successful reporter lifecycles, exact retained case lists, graph
hashes and current-source bindings are preserved in
[the retention receipt](receipts/post258-retained-engine-editor.json).
An [independent review](receipts/post258-retention-independent-review.json)
recomputed both closures and exactly matched the retained raw-case multisets.
No AST normalization bridge is required for these retained scopes.

### Static coverage

All 57 fresh paths pass `dart analyze --fatal-infos --fatal-warnings` and
read-only formatting. The other 38 engine paths retain their passing analysis
and format results by exact path, engine-production and configuration equality.
The two sets are disjoint and their union exactly matches all 95 Dart paths
changed from initial main. The pinned formatter also examined the full union
without changes. See [the fresh static receipt](receipts/post258-static-qualification.json)
and [independent path/input audit](receipts/post258-static-union-audit.json).

## Preserved integration behavior

The final main union retains the atomic account compare-and-set implementation
and its regression test byte-for-byte. Selected-account refresh validates the
same identity, revision and connection timestamp in one SQLite write; a stale
request cannot recreate a removed or replaced shortcut or consume metadata on
conflict. See [the exact CAS preservation record](receipts/post258-cas-preservation.json).

Native and EWS admission still serialize draft-store opening, restoration,
cache selection and account refresh. A failed observer or owner close remains
held until explicit cleanup succeeds. Observer retirement starts before waiting
for a pending first snapshot, and generation/identity fences reject stale
callbacks. Full send operations retain their exact owner through the final
durable outcome receipt, including compose, manual/scheduled Outbox and
acknowledged retry paths. A network reply alone does not end ownership.

Remembered Archive destinations add an account-local exact folder preference
for IMAP, EWS and Microsoft 365. The saved folder is validated against a fresh
provider catalog **before confirmation**. After confirmation, the saved
revision and destination are reloaded **before dispatch** into the durable
Move journal. Settings support save, change, clear and missing-folder repair.
Gmail retains its Inbox-label removal behavior. Schema 17 persistence preserves
migration/journal data and account-removal cleanup.

The bounded independent native/EWS reviews found no additional concrete defect
in the union; reviews supply no test-case credit. Their ownership reasoning and
the root's resolution decisions are recorded in
[the cross-review summary](receipts/post258-cross-review-summary.json) and
[merge-resolution receipt](receipts/post258-root-merge-resolution.json).

## Historical qualification and repairs

The complete pre258 source `9ce2b057` qualified **8,040 passing executions
across 302 suite executions**: 2,899 engine, 51 editor, 2,368 Studio and 2,722
earlier Mail cases. Within its Studio total, 459 cases from 14 independent,
fully successful suites were retained from an 18-suite process that failed
in four other files. All 173 cases in those four files were replaced by a
fresh run, and another 92-suite fresh process passed 1,736 cases. The original
18-suite process retains exit 1 and `done.success = false`.

That complete source-bound report is saved at `b25acd58`; its
[qualification JSON](receipts/pre258-qualification.json) and original README
remain in the evidence. Main258 changes Mail production inputs, so **none of
the old 2,722 Mail or 2,368 Studio results—including the 459-case subset—is
credited to the current union**. Only the explicitly proved 2,805 engine and
51 editor cases carry forward. Older failed, interrupted and superseded runs
remain diagnostic evidence, with no current passing credit.

| Preserved diagnostic | Observed result and repair boundary |
| --- | --- |
| Studio attempt 1 | 132 passes/1 error, child exit 1; retained Refresh callback dereferenced a cleared mailbox. Bound mailbox and identity/generation guards fixed it. |
| Studio attempt 2 | 564 passes/1 error by LF recount; child exit unavailable after parser exception. Captured same-session Disconnect was rejected during modal review, so three moves stayed on the previous provider; no new-session dispatch was shown. Cancellation semantics were repaired. |
| Studio attempt 3 | All 110 suites, 2,329 passes/22 errors/0 skips, child exit 1. Lifecycle and setup/capability/fixture corrections were qualified by subsequent source-bound runs. |
| Studio attempt 4 | Deliberately interrupted after 318 passes/0 observed errors and eight started suites; no final reporter event. Session exit 130, Flutter child exit unavailable. Review found Outbox outcome ownership ended before the final local receipt. |
| Static attempt 5 | Nullable retry-fixture variable found before Studio tests started; nonnullable binding preserved assertions. |
| Studio attempt 6 | 623 passes/9 failures across 18 suites, child exit 1. Four typed tooltip captures, four bounded route-settlement waits and the strict replacement-session assertion were corrected in four test entrypoints. |

Raw JSONL must be framed using **ASCII LF bytes only**. Python `str.splitlines()`
incorrectly split U+0085, U+2028 and U+2029 embedded in three real attachment
filename test names. In attempt 2, their successful IDs 569–571 restore the
incomplete 561 subtotal to 564; they are not hooks or hidden loaders. Attempt 3
similarly restores 2,326 to 2,329. Original raw files and superseded parser
receipts remain preserved. The repaired runner saves child exit status before
parsing and rejects genuinely incomplete or unmatched lifecycles. See
[the framing audit](receipts/studio-reporter-lf-framing-audit.json).

The first incoming engine gate found six stale citation-text fixture
expectations and one parser defect losing opaque `rPrChange` history on field
boundaries. Explicit expected-text overrides retain independent formatting and
structure assertions; parser repair preserves complete original boundary run
properties. Original fixture bytes were unchanged, and five regressions were
added. Later incoming empty-code-run provenance and nine instruction-side
style exclusions remain covered. See [the repair notes](receipts/zotero-repair-notes.json).

The earlier 2,594-case engine gate combined passing VM/analysis results with a
one-test formatter normalization and remaining format/portability checks.
Its proof has identical recursive AST and AST-rendered source with zero parser
diagnostics. One optional map trailing comma was removed; other tokens/comments
match, so no whitespace-only or full-token-byte identity is claimed. That
[normalization bridge](receipts/engine-normalization-bridge.json) is valid
historical evidence, superseded by the later 2,899-case engine scope. The older
2,585, 2,544, initial Word 1,458, focused 82 and provider-development 103 counts
add no cases. The provider 103 run also observed three concurrent Word inputs
change, so it remains development evidence only.

## Portability

The unchanged accepted engine tools/resources retain the complete VM/Node
portability receipts. The canonical Split corpus is raw-byte identical for
**174 adapter cases across Word, Excel and PowerPoint**, SHA-256
`7836c5c824b9585d17b7818f1dc7271e061340ec0202acda8f30121d9ced9e8b`.
Those adapter cases are separate from the Dart test totals.

The BAS smoke uses ordinary `jsonEncode`, so VM integral doubles such as `0.0`
and JavaScript `0` differ in raw bytes. Only finite integral numeric
representations are normalized; all strings, booleans, arrays, structure and
values must otherwise agree. DOCX/DOCM output has exactly 58 such encoding
differences and zero other semantic differences. Canonical SHA-256 is
`0bbdfe5579a2604573d57f2c20727b1bd986d5c2c76b190572be633079bc4480`.
The [independent portability audit](receipts/final-ab-portability-audit.json),
raw outputs and earlier overly strict comparison remain available. This is
retained evidence on unchanged inputs, not a fresh portability execution.

## Evidence and reproduction

[Runtime provenance](runtime-provenance.json) records the unchanged official
Flutter 3.47.8 / Dart 3.13.7 SDK and Node 24.22.3. All 204 required hosted package
archives match lockfile hashes; enforced-lockfile restoration left the
repository lockfile unchanged. No SDK, test framework or compiler source was
patched to obtain results.

Small source/qualification receipts are kept under `receipts/`.
The [archive](local-evidence.tar.xz) contains **676 files**
(5,194,160 bytes); [its index](evidence-index.json) records every
member size and SHA-256. Archive SHA-256:
`f450f0c9fe9d9f5ddefeb53fd53bf555f45d21a9c4f1855523b4a42f595fb9c4`.
It preserves current raw reporters, complete inventories, exact input
manifests, commands, runtime hashes, all diagnostics and reproduction
scripts, including the complete historical pre258 report. Historical
files add no duplicate test credit.

| Archive directory | Evidence role |
| --- | --- |
| `post258-mail/` | Six fresh Mail cohorts plus the separately counted 94-case boundary suite |
| `post258-studio/`, `post258-static/` | Complete 113-suite Studio gate and 57 fresh static paths |
| `post258-retained/`, `post258-audit/` | Retained engine/editor dependency graphs, case lists, source binding and independent recounts |
| `incoming-engine/`, `editor-zotero/` | Original accepted raw results underpinning retained engine/editor cases |
| `shared-mail/`, `mail-store/`, `studio-mail/`, `studio-carry-forward/` | Historical pre258 Mail/Studio results and prior 14-suite proof; no current case credit |
| `development/` | Earlier engine runs, all failed/interrupted Studio runs, parser diagnostics and complete pre258 report |
| `integration/`, `runners/`, `runtime/` | Exact intake, source/merge audits, reproducible scripts and pinned environment hashes |

Original receipt paths and commands retain their workspace locations. In the
archive, `incoming-engine/` maps to `final-ab-engine`; older b4 normalization
labels map to `development/engine-b4-original-vm-analysis/` and
`development/engine-b4-normalized/`. Compiled JavaScript is a reproducible
intermediate; source, commands, hashes and execution receipts are retained.
No GitHub Actions output is used as evidence.

## Scope and remaining acceptance

No real account credentials, user mail, provider mutations or outbound messages
were used. Live-provider and installed-platform acceptance remain open, as do
simultaneous background accounts, unified live folders and full Outlook,
Thunderbird or eM Client parity. Node execution does not establish browser UI
acceptance. A concrete native SQLite owner memoizes a failed close future;
owners that cannot later close successfully may require a host restart.
Custom owners can recover in process only when their explicit retry succeeds.
This report does not claim the final remote-main merge before it is verified.
