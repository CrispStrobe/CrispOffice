# Mail account workspace — integration and qualification

## Current status

**Partial qualification: the full Studio Mail acceptance run is still in
progress.** The final integrated engine, editor integration and static gates
have passed. This document does not yet claim a fully qualified final tree or
a completed merge to main.

The integrated source checkpoint is
`3e57fda4de6317c4a547f69220d7ed83802fd19f`, tree
`f410d8165bc8af58df6f1154905878ea4b63875b`. Local test baseline
`e6b5c23e3d0dfee29fb86fe1a5f6132b3f34de3d` has exactly the same tree.
Documentation can advance independently of this frozen source boundary. See
[qualification.json](qualification.json) for the machine-readable state and
[the source proof](receipts/integrated-source-proof.json) for exact hashes and
ancestry checks.

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
`4cc604810fb2f41ac7ba04cbed65cb76300bff59` was also integrated before the final
gates. The main refresh preserves additional Zotero/revision coverage and
unions the concurrent Mail account-removal/revision regressions; it retains
one atomic selected-account refresh after the cache checks. See
[the reconciliation decisions](receipts/main-merge-mail-reconciliation.json).
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
| `3e57fda4de6317c4a547f69220d7ed83802fd19f` | Final source reconciliation with main `4cc60481` |

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

[The carry-forward audit](receipts/carry-forward-audit.json),
[independent raw-reporter recount](receipts/retained-raw-reporter-audit.json)
and [store receipt](receipts/mail-store-qualification.json) record the evidence.
The recount requires one successful final reporter event, no error events,
no unfinished tests and no malformed JSON events. Hidden loader/setup events
are excluded. Two different parameter rows in Mail core share a display name;
they have distinct test IDs and are not duplicate executions.

### Fresh final-source gates

| Gate | Scope | Current disposition |
| --- | --- | --- |
| Word/VBA engine | 20 VM suites | Passed: 1,831 cases |
| Zotero/ODT/revision/run/style engine | 32 VM suites | Passed: 754 cases |
| Engine VM/Node portability | Split corpus and DOCX/DOCM BAS smoke | Passed; separate from test counts |
| Editor Zotero integration | 3 controller suites | Passed: 51 cases |
| Studio Mail acceptance | All 110 `*mail*_test.dart` suites in the example | Pending |
| Changed Dart analysis/format | All 47 changed Dart paths (32 engine and 15 other) | Passed: strict analysis and read-only format |

The completed engine gate contributes **2,585 fresh passing test executions
across 52 suites**, with zero failures or skips. All ten commands exited zero,
strict analysis and read-only formatting passed, and all 1,415 captured inputs
were identical before and after the gate. The independently recounted raw
reporters match the expected suite inventories. See
[the engine summary](receipts/final-engine-summary.md),
[complete receipt](receipts/final-engine-qualification.json) and
[independent recount](receipts/final-engine-raw-audit.json).

The editor controller gate adds **51 fresh passing cases across three suites**;
all 6,220 captured inputs remained unchanged. See its
[receipt](receipts/editor-zotero-qualification.json) and
[independent recount](receipts/editor-zotero-raw-audit.json). Completed fresh
execution therefore totals **2,636 cases across 55 suites** so far. The
[remaining static receipt](receipts/mail-static-qualification.json) completes
strict analysis and read-only formatting for all 47 changed Dart files.

The provider host union is expected to include 127 cases and native navigation
50; those are scope checks, not completed acceptance results in this partial
report. Studio counts become final only after successful reporter completion,
expected-suite coverage and before/after input equality.

Do not add earlier Word 1,458, intermediate engine 2,544, focused 82,
provider-development 103, bootstrap or repeated navigation runs to the final
totals. They overlap later coverage or ran against earlier source. The
103-case provider development run also observed three concurrent Word input
changes and is explicitly not a final integrated-source gate.

## Repairs and portability evidence

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
credit.

Portability uses the output contract of each tool. The canonical Split
conformance corpus matched VM and Node raw bytes: **174 adapter cases across
Word, Excel and PowerPoint**, SHA-256
`7836c5c824b9585d17b7818f1dc7271e061340ec0202acda8f30121d9ced9e8b`.
These adapter cases are recorded separately from the Dart test counts.

The BAS smoke emits ordinary `jsonEncode`: VM integral doubles such as `0.0`
and JavaScript `0` are compared after normalizing only finite integral numeric
representations and sorting JSON keys. Strings, booleans, arrays, structure
and values must otherwise agree. The complete final DOCX/DOCM smoke receipts
have equal canonical JSON, SHA-256
`0bbdfe5579a2604573d57f2c20727b1bd986d5c2c76b190572be633079bc4480`.
Their raw bytes do not match. An independent comparison of the final outputs
found exactly 58 integral-number encoding differences and zero other
differences; see [the final portability audit](receipts/final-portability-audit.json).
The final raw output hashes also match the preceding diagnostic comparison. Both the original
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
inventories, source manifests, commands, runtime hashes, diagnostic failures
and runners. This partial archive includes the completed engine and retained
Mail evidence. Editor/static receipts are available alongside this report;
the archive will be refreshed with editor/Studio/static results after the
Studio gate completes. Commands and environments are recorded verbatim in the
individual receipts. The archived runners select the expected suite sets and
check input invariance. Compiled JavaScript is a reproducible intermediate;
its source, compile command, output hash and raw execution receipts are
retained. No GitHub Actions output is used as test evidence.

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
