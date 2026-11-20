# Final peer-main reconciliation and publication acceptance

**Accepted publication source:
[`44f3f61f`](https://github.com/CrispStrobe/quds_office_suite/commit/44f3f61fa7d812971e973f1763ac8e04eb39785a),
tree `9ad9555b01e5c0a0872f868356c232e669a8b977`.** All production changes are saved in
[`64da2318`](https://github.com/CrispStrobe/quds_office_suite/commit/64da231816b1b3ddab35e0e12d50d885bf24f75f);
the following checkpoint corrects one new test's loader construction without
changing production or assertions. Final remote main/branch tree equality and
ancestry are recorded on [PR #275](https://github.com/CrispStrobe/quds_office_suite/pull/275).

The [previous main qualification](main-reconciliation.md) remains bound to
`00d44a69`. The full source intake remains frozen at 320 refs and its stated
cutoff. This final supplement accounts for main's subsequent advance to
`0a2afc41bae4e719b77657a7e2d8d3e7ec02849b` through peer bulk-mail PR #273. Its complete history and original raw
evidence are retained as ancestors/artifacts, alongside our earlier mail,
Word/font and Zotero reconciliations.

## Bounded semantic union

The peer branch carried a parallel implementation of foreground bulk mail.
We kept the accepted single execution engine, both public entry points, typed
native capability, frozen selections, full identity/lease checks and all
existing regression suites. Review identified the following additions and
corrections, which are now incorporated.

### Mail quota handling and status

A certified `quotaExceeded` rejection stops remaining dispatch with
`MailBulkFlagStopReason.rateLimited`. The rejected message remains Failed and
remaining messages remain Not attempted. The exact problem object, including
its optional `retryAfter`, remains attached. A quota reply with missing or
contradictory mutation evidence remains Uncertain; uncertainty still takes
precedence over concurrent cancellation, scope change or quota metadata.
Core `requiresRefresh` remains uncertainty-only, while hosts continue requiring
refresh for certified stale scope.

Gmail/Graph HTTP 429 flag-update responses now use their documented rejection
contract as no-mutation evidence. This is scoped to flag application and retains
the existing submission outcome rules. Unfamiliar post-dispatch failures remain
uncertain. The official
[Graph throttling guidance](https://learn.microsoft.com/en-us/graph/throttling)
and [Gmail error guidance](https://developers.google.com/workspace/gmail/api/guides/handle-errors)
are recorded in the core review. The previous conservative 429 expectation was
changed deliberately for that documented contract; all existing send assertions
and unfamiliar-failure protections remain.

English, German and Arabic status/details show the rate-limit reason and the
provider's delay, rounded up to whole seconds. The delay is guidance; it does
not schedule or automatically retry a command. Stale-scope refresh wording is
neutral about outcome certainty, and its receipt cannot be dismissed to clear
the refresh requirement. Provider quota cases are added alongside every stale
scope case; the native typed-host case additionally checks the unattempted tail,
rounded delay, details and absence of hidden message reads.

The exact peer provider-result suite contributes three quota cases. Six new
runner/coordinator cases preserve uncertainty precedence, stop-problem identity
and the pending tail. Explicit unsupported-provider evidence assertions are
retained. Three real-font EN/DE/AR receipt/detail probes append six new captures
to the existing 20; no existing visual scenario was removed.

### Word visual occurrences and border provenance

The independent peer fixtures exposed four remaining failures in the earlier
source: distinct header/footer nodes sharing an image asset were lost; a tall
inline-only header overlapped the body; and an omitted direct border width
failed to inherit the style's width. These were reproduced before the repair.

Deduplication now follows authored `WmlVisual` occurrence identity. One node
represented through both inline and separate-header paths paints once. Two
distinct nodes remain two occurrences even when they share an image asset,
identical bytes and the same placement; transparent images can composite
differently when painted twice. Tall inline header images now contribute to
body clearance. The previously fixed continuous-section body-frame prefix,
footer pagination, distinct placements and incremental/full equivalence remain.

Two earlier fixture assumptions were corrected explicitly: the one-occurrence
fixture now shares the same `WmlVisual` node, and the distinct-copy fixture keeps
both authored nodes. Original source-bound results remain in the archive.
All 12 prior cases remain; three new repeated-node/transparency cases bring that
suite to 15. Both incoming peer Word suites are retained unchanged.

Table import records whether a direct border width was authored. An omitted
width inherits its table style; an explicit width remains authoritative. The
existing conditional-run cascade, direct/nested-table precedence and sparse
spacing provenance are retained. The original usable-width Indic fixture keeps
all its cluster, ownership and save/reopen assertions. The two incoming font
regressions and the test-only Zotero braces correction are retained exactly.
No compiler, dependency, lockfile or authentication changes were introduced.

## Final local acceptance

Cohorts overlap and must not be summed into a unique-test total. Core/Word
commands ran on the production checkpoint and match the final source exactly
for every captured input. The full Flutter commands ran after the test-only
construction correction. The archive's source verifier independently replays
these bindings against `44f3f61fa7d812971e973f1763ac8e04eb39785a`.

| Cohort | Result | Archive evidence |
| --- | --- | --- |
| Full portable mail core, Dart VM | **214 passed** | `peer-main/core/receipt.json`, `core-vm.log` |
| Four bulk suites, JavaScript/Node | **120 passed** | Same receipt, `bulk-node.log` |
| Native IMAP, EWS and cloud provider boundaries | **195 passed** | Same receipt, `transport-boundaries.log` |
| Unsupported providers, JavaScript/Node | **6 passed** | Same receipt, `unsupported-node.log` |
| Seven connected/cached Studio mail suites | **378 passed in one invocation** | `peer-main/hosts/receipt.json`, `hosts.log` |
| Full shared mail UI | **161 passed** | Same receipt, `ui.log` |
| Localized mail visual probes | **13 passed**, 26 captures | Same receipt and `visual-comparison.json` |
| Combined Word VM | **929 passed** | `peer-main/word/word-vm.json` |
| Portable Word JavaScript/Node | **787 passed** | `peer-main/word/word-node.json` |
| Focused surrounding import/layout coverage | **244 passed** | `peer-main/word/focused-vm.json` |
| Actual eight-/thirteen-operation BAS fixtures | VM/JS results equal | `peer-main/word/*-vm-js-comparison.json` |
| Affected Zotero table/protocol supplement | **165 VM / 117 Node passed** | `peer-main/zotero/qualification.json` |
| Editor/Zotero/layout/proofing, 14 suites | **378 passed, 8 existing skips** across 362-pass editor and 16-pass Studio runs | `peer-main/hosts/receipt.json` |
| System-font discovery fixtures | **9 passed**, including two incoming alias regressions | Same receipt, `font-tests.log` |
| Analysis and formatting | Core/transport and scoped Word, Zotero, hosts, editor and fonts clean; **19 later changed Dart files, zero formatter changes**; whitespace clean | Per-domain logs and `peer-main/final-checks/receipt.json` |

The eight skipped editor fixtures are existing image-only cases without editable
paragraphs. All Zotero editor cases execute. The previous 282/175 Zotero and
893/751 Word runs remain historical at `00d44`; the affected Zotero paths and
complete Word cohorts above qualify this later source. The expensive unchanged
1,500-citation case is not represented as rerun after the final Word changes.

### Preserved diagnostics

The first final host invocation retained 335 passes and one loading failure.
A new test's cascade attached `bulkAnswer` to its page value instead of its fake
loader. Separating those assignments changed no production or assertions.
The original invocation remains failed; a complete successful 378-case rerun
provides acceptance. Its exact source/fixture applicability proof is preserved.

The four peer Word failures and an earlier probe that overlapped a temporary
merge-conflict state are also preserved separately. The latter is a source-
transition diagnostic, not evidence of a product failure. Earlier baseline
failures and intermediate successful runs retain their original attribution.

## Incremental preservation and reproducibility

| Remote checkpoint | Purpose |
| --- | --- |
| [`54b4263b`](https://github.com/CrispStrobe/quds_office_suite/commit/54b4263b3d89af49436b0626b3ca8875db9a712d) | Preserve complete new main PR #273 history, original evidence and complementary Word suites |
| [`64da2318`](https://github.com/CrispStrobe/quds_office_suite/commit/64da231816b1b3ddab35e0e12d50d885bf24f75f) | Bounded mail/Word semantic union and complete regression source |
| [`44f3f61f`](https://github.com/CrispStrobe/quds_office_suite/commit/44f3f61fa7d812971e973f1763ac8e04eb39785a) | Native quota fixture construction correction; production unchanged |

The final evidence commit follows these saved source checkpoints. The final
peer-delta proof classifies all 19 Dart differences from `00d44` to `64da` with
two additions and no deletions. The fixture proof checks the one later test
construction correction and unchanged action/assertion suffix; all 816
production-library files remain identical between `64da` and `44f3`.

[late-evidence.tar.gz](late-evidence.tar.gz) preserves both late-source stages,
commands, logs, source hashes, visual captures and reconciliation proofs. It is
4,736,442 bytes with SHA256 `1ab839ebdeb86599af507d623f98d224620fdd533ff870118a58a8134e8711b8`.
[late-evidence-members.json](late-evidence-members.json) accounts for every
member, and [late-source-applicability.json](late-source-applicability.json)
distinguishes accepted, historical and failed cohorts. Equal PNGs refer to exact
immutable baseline members; new or changed captures remain in the late archive.
BAS comparisons are recomputed from the bound raw outputs. Representative
[English results](visuals/en-receipt.png) and [Arabic details](visuals/ar-receipt-details.png)
show the reviewed mixed-outcome UI at enlarged text scale. Numeric retry-delay
wording is covered by widget assertions, not these mixed-outcome captures.

```sh
python3 docs/validation/mail-bulk-flags-20261120/verify_evidence.py
python3 docs/validation/mail-bulk-flags-20261120/verify_intake.py
python3 docs/validation/mail-bulk-flags-20261120/verify_late_evidence.py
```

The baseline archive and verifier are unchanged. Verification reads local Git
objects and archives without extracting or executing archive members. Remote
updates use expected-head leases without force. GitHub Actions, workflow runs
and status endpoints were neither queried nor awaited; no synthetic status was
created. PR #275 records the observed merge/tree/ancestry check.

This is still foreground mail mutation. Durable sessions, a remote-command
journal, offline/restart recovery and reliable cache reconciliation remain the
next milestone. Live provider accounts, real sends, installed platform packages,
macOS discovery and installed Zotero/Word/LibreOffice or browser/WASM acceptance
remain outside the qualified scope.
