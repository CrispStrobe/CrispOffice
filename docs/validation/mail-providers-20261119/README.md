# CrispOffice mail provider qualification — 19 November 2026

**Qualified: 994 tests passed, with zero unresolved failures or skips.** This
matrix combines the frozen full run with one corrected test cohort, as described
below. The original failed attempt remains intact and is not represented as a
passing run. Strict analysis, formatting, macOS network entitlements, Flutter
web compilation, native-import exclusion and JavaScript syntax checks passed.

## Qualified source and scope

The full-run source is
[`e3212327954ac144847a7c06b5d2420f00debab3`](https://github.com/CrispStrobe/quds_office_suite/commit/e3212327954ac144847a7c06b5d2420f00debab3),
with Git tree `030e701c19f5a01b2e3ca54ddc67229871295527`. The final qualified source
is [`34153224a63112de3006335ae36cf9b2f744f513`](https://github.com/CrispStrobe/quds_office_suite/commit/34153224a63112de3006335ae36cf9b2f744f513),
tree `d7491007d718299e4b9e90bfecf8cba34c62cb5a`. Its sole source difference is one
explicit `topK: 3` argument in an inherited language-identification test; all
production files are unchanged. Each authenticated remote checkpoint was fetched
and read back before qualification, with exact committed tree identity. The
final evidence and documentation commit adds no product or test changes to
`34153224`.

The work is tracked in
[PR #200](https://github.com/CrispStrobe/quds_office_suite/pull/200) on
`codex/mail-providers-20261119`. No GitHub Actions runs, checks or statuses were
queried or awaited for qualification. The existing workflow definitions were
extended for future execution; the results below come from local commands.

The implementation adds native desktop Gmail API and Microsoft Graph providers,
system-browser OAuth with PKCE, secure Yahoo/iCloud/Fastmail IMAP/SMTP presets,
and guarded Studio setup, mailbox and composer integration. It preserves the
existing on-premises-first EWS provider and the incoming native credential
storage and proofing changes. See the [setup and API guide](../../roadmaps/mail/cloud-providers.md).

## Final local results

| Test cohort | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Mail core, native VM | 54 | 0 | 0 |
| Mail MIME, native VM | 32 | 0 | 0 |
| Mail SQLite store, native VM | 118 | 0 | 0 |
| Mail transport, native VM | 373 | 0 | 0 |
| JavaScript/Node transport boundaries | 13 | 0 | 0 |
| Shared mail UI widgets | 33 | 0 | 0 |
| Studio mail/saved-mail, all 14 test files | 209 | 0 | 0 |
| Language-ID unit and synthetic native transport, corrected cohort | 22 | 0 | 0 |
| Engine language identification and calibration | 36 | 0 | 0 |
| Engine thesaurus | 25 | 0 | 0 |
| Editor proofing/thesaurus widgets | 75 | 0 | 0 |
| Studio language-identification widgets | 4 | 0 | 0 |
| **Qualified matrix** | **994** | **0** | **0** |

The native mail subtotal is **577**; the complete mail/Node/mail-UI/Studio subtotal
is **832**. The transport total includes **146 cloud-specific native cases**.
Counts are derived from raw JSON reporters, excluding hidden harness events and
without pooling development runs or superseded passes.

The [full-run receipt](final/receipt.json) records **993 passed, one failed, zero
skipped** at `e3212327`. Its only failure was an inherited fixture that assumed a
three-candidate limit after the calibrated production default had changed to
five. Four valid candidates were therefore correctly accepted by production
code. The test now explicitly requests three candidates, preserving its original
overflow-rejection assertion without changing the production default or guard.

The [corrective receipt](correction/receipt.json) records a fresh **22 passed,
zero failed, zero skipped** for the complete affected cohort at `34153224`, plus
clean strict language-ID analysis and formatting. It verifies the same test case
identities, the one-file source delta and identical runtime inputs, then
**replaces** the earlier cohort once. The earlier 21 passing cases are not added
again. Every reused gate passed, and all of its source files and runtime inputs
remain identical to the full-run snapshot.

Both executions preserved their own source, HEAD, runtime and lockfile exactly.
The manifests cover **4,334 tracked product/test files**. The full-run source
manifest digest is `7c9dce69595316ab3ede21caadde46f56eff6ad764a393cb3bb27058f6e6d0ea`;
the corrected source digest is
`13bbce663ea3da2c587bf17126b899d419d3a8a199f6212ebe596ecdbc910ec1`. Both use runtime
manifest digest `89a4c7bd995379bdeffda84184393345b1081ccfac4f9109aabb609e90ba6549`.
Independent evidence review reconciled raw counts, transcript hashes, source
Git-blob identity, all 14 Studio files and the web dependency closure.

Additional passing gates include strict analysis for transport, Studio, mail UI,
incoming editor/thesaurus code and language identification; formatting; both
macOS entitlement plists; actual Flutter web frontend and JavaScript backend
compilation; and Node syntax validation. The generated web dependency closure
contains **1,761 inputs**, all required web entry paths and none of the forbidden
native mail, credential, cloud or EWS implementation paths.

## What the tests exercise

The cloud transport tests use injectable HTTP/token ports, controllable streams
and real local HTTP OAuth callbacks. They exercise PKCE and state validation,
invalid callback limits, cancellation and deadlines, refresh coalescing and
rotation, missing/revoked scopes, throttling, bounded payloads, redirects,
malformed responses, connection and response-stream cleanup, and logging sinks
that throw. Structured diagnostics deliberately accept only fixed enums and
numeric metrics; sentinel checks cover credentials and message content.

Provider tests cover verified mailbox ownership, case-sensitive identities,
Gmail labels and history, Graph folders and delta, account-bound continuation
links, MIME retrieval, confirmed mutations, frozen-envelope validation and
hidden recipients. Definite send rejections remain rejected; potentially
accepted requests with lost or ambiguous responses remain uncertain and are
never replayed automatically. Graph's empty 202 response is treated as provider
acceptance for processing, not delivery.

SQLite/coordinator regressions exercise atomic page/cursor commit, rollback on
malformed pages, stale cursor rejection and preserving other Gmail label
memberships. Node tests exercise public unsupported-platform boundaries without
calling native transports, token sources or browser launchers.

Studio tests cover OAuth setup, connection and session lifetimes, stale results,
provider presets, localized retry feedback, browsing, actions, drafts and send
uncertainty. The incoming secure-storage integration is tested through an
injectable platform seam: validation, save/clear failure reporting, Remember
opt-out, ordering across dialog instances, late loads, and resource ownership
during a slow credential save. Existing tests were updated to select the
intended setup controls after Remember/STARTTLS controls increased form height.

The matrix also runs focused proofing, thesaurus and language-identification
regressions for the incoming histories. A reproduced thesaurus cache race was
corrected: clearing the cache while asynchronous relation data loads must reject
the stale result before it can be returned or cached. Synthetic language-native
tests compile the tracked C++ allocation fixture; they do not qualify an absent
production language-identification library.

## History reconciliation and incremental publication

The bounded fork-head/PR-head capture was taken at **2026-11-19 14:19:57 UTC**;
the upstream capture was taken at **14:05:29 UTC**. The
[final integration audit](final-integration.json) accounts for **223 references**:
**200 ancestors** and **23 historical equivalents**, with **zero unaccounted
references** and **14 freshly verified exact equivalence proofs**. Historical
equivalents refer to already integrated source deltas, not dropped work.

Preserved recent heads include:

| History | Captured commit |
| --- | --- |
| Fork `main`, including native credential storage and proofing updates | `07b815a79d011f88b048900e22aa6544f44f2758` |
| EWS PR #197 | `f20b3c61d28918cd75526c64852c41fae943acf3` |
| Validation recovery PR #198 | `58e1de23c60f0f822bbcb23ce38ee1e2bf26265c` |
| Paragraph language identification | `107155216505590e2eabfb93fc67cb908ad6173d` |
| Arabic morphology/binary work | `555fc99fdeb8ef7f3043513203cb16b243a4a9d7` |

The source was saved incrementally to the remote feature branch:

| Checkpoint | Remote commit | Verified Git tree |
| --- | --- | --- |
| Initial history integration | `f2131f3813d042fc6f3b16813c5ba0937e6ff0ec` | `87c0a8fdf1e570b70b9e1359fa56d332888536ef` |
| Provider implementation | `b5eb7b81a02123446e9737e40e2a2e9e1631f7d8` | `d56e71d7ff285fda57120a61f5bd95035efaa70b` |
| Newer-main/branch reconciliation | `0812a07e07856b885853b203089bc085d0ce9c57` | `0154e86310bece75131fb912aa2c73526a102c45` |
| Final lifecycle correction and full-run source freeze | `e3212327954ac144847a7c06b5d2420f00debab3` | `030e701c19f5a01b2e3ca54ddc67229871295527` |
| Explicit inherited test limit and corrected source freeze | `34153224a63112de3006335ae36cf9b2f744f513` | `d7491007d718299e4b9e90bfecf8cba34c62cb5a` |

Each publication verified uploaded Git blob hashes, exact tree identity,
expected previous branch head and remote readback. Updates were non-forced.
The integrated publication has the captured main, recovery and paragraph heads
as explicit parents, while preserving earlier EWS ancestry. Git-data publication
creates authenticated remote commit identities; local pre-publication merge
identities in the audit therefore differ from these durable remote commits.

The original [integration snapshot](integration.json) remains as a dated record;
its earlier advancing-head observations are superseded by the final audit.
Remote `main` was rechecked before the source freeze and still matched the
captured `07b815a7`. A final main/head check precedes the requested merge.

## Runtime and replay

Qualification uses **Flutter 3.47.8 / Dart 3.13.7**, with the official Flutter
archive verified against SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The incoming secure-storage dependency update is preserved. The frozen root
lockfile SHA-256 is
`72a5a52654a1484f4df646c631b4d1ea47e96025a671beff045eecf2b9e78e82`;
it was not regenerated during qualification.

The [full-run evidence index](final/README.md) and
[correction index](correction/README.md) contain the exact command matrix,
counts, checksums and replay instructions. The committed runner requires a
resolved workspace, the pinned runtime, native SQLite support, Node, Python and
a C++ compiler. It builds only the synthetic native fixture and generated web
artifacts in scratch space. It never resolves dependencies, edits product files,
contacts GitHub/CI or automatically retries a failed gate.

Every attempt requires a new output directory. Raw standard output, standard
error, per-command arguments, working directories, exit codes and parsed test
cases are retained. Before/after manifests cover tracked product/test files,
the lockfile and the runtime/compiler artifacts used by the run. Counts exclude
hidden harness events, skips and deliberately excluded acceptance suites.

## Acceptance boundaries

- **Live provider acceptance remains unverified.** No Gmail/Microsoft app
  registrations, mailbox credentials or on-premises Exchange endpoint were
  supplied. The read-only cloud probe is provided for deployment acceptance.
- Google requires the deployment's Desktop client registration and applicable
  restricted-scope consent/verification. Microsoft requires a native public
  client registration, the documented localhost redirect and delegated Graph
  permissions. Organizational policies can require administrator approval.
- Cloud tokens, downloaded messages and drafts are session-only. Optional
  IMAP/SMTP credential remembering uses the platform secure-storage adapter;
  installed Keychain/credential-manager acceptance was not performed here.
- Gmail Move is intentionally unsupported because the shared move operation
  lacks a source-label identity. Other label memberships are preserved. Shared
  or delegated mailboxes, national Microsoft clouds, folder creation, contacts,
  calendars and a durable Studio outbox are not added.
- The macOS client/server entitlement check validates the plist configuration;
  it is not a signed application build or installed sandbox/browser acceptance.
- Web verification is actual Flutter compiler output, native-import exclusion
  and JavaScript syntax validation. It does not claim browser interaction or a
  full distributable platform build.
- Production language-identification native-library acceptance is excluded;
  the separately compiled allocation fixture supports only synthetic transport
  and lifecycle tests.
