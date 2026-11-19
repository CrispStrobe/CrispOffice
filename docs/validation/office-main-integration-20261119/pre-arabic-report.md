# Preserved application checkpoint before Arabic rules

This report records the `ac1e4c8c` application qualification and its publication
through `5ec15bdd`. The later Arabic runtime merge is qualified separately;
its input changes do not rewrite the retained manifests or counts below.

# Office integration for remote main — 19 November 2026

The final integrated application, fixtures, execution harness and test-plan
source is **`ac1e4c8c788ea608402c2260488235c0189efcba`**. Both fresh local
qualification receipts bind to that same commit: **632 passing test executions,
562 distinct test cases and 47 distinct suites**. All 5,031 bound application,
fixture and qualification inputs remain exact in the final reconciliation. The
subsequent standalone Arabic bundle tooling has separate offline controls;
those controls are not added to the application case count.

This record accompanies the user-authorized integration into remote `main`
through PR #174 and PR #173, followed by this qualified cleanup continuation.
PR #174 merged as `d41000336c84b6ebfe6b35f7f8335140b5d46038`. The concurrent
PR #173 merge `55e262ef269634a0d618c0b5102dc9be5430a5f3` and its evidence
publication `b0a9bd3f1b46ac89021d1b7e49c32980ca4d181e` are also reconciled.
The [late-main review](socket-final/late_main_delta_review.json) identifies
exactly five bound differences; publication preserves all 5,031 qualified
`ac1e4c8c` input bytes and modes, including the cleanup assertions and plan.
Code and evidence were saved incrementally on
`codex/office-main-integration-20261119`, with expected-head guards and exact
remote commit/tree readback. **No GitHub Actions run was queried, dispatched or
awaited.** Release acceptance remains separately tracked below.

## Reconciliation and preserved Office work

The bounded integration inventory accounts for **409 actual references**:
213 fork branches, 175 PR heads, 17 tags and four upstream branches. Of these,
381 are ancestors and 28 have 14 independently reverified historical source
equivalence proofs. No missing objects or unaccounted references remain.

| Captured incoming work | Integrated head |
| --- | --- |
| Initial main at the first capture | `690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e` |
| Original PR #174, offline thesaurus | `df62b58975bab1f650879fc88f850550a3df5c13` |
| PR #175, Notes | `c320f28347f1cd292b848be2cf72998d41f8a6ac` |
| PR #172, latest captured Mail/TLS work | `700e5a35ce5f96e7abd1dc92d1a00d2110d40649` |
| PR #173, Zotero/TLS source captured for qualification | `022a974a96db23e22bc161f7d465e4b972e8c2a9` |

The [ancestry audit](socket-final/socket_ancestry_review.json) identifies its
input as a frozen snapshot of already-fetched fork refs plus the saved upstream
advertisement. Latest captured Mail/Zotero branch heads are the immutable merge
ancestors above. Older local PR aliases remain explicitly labeled observations;
they are not relabeled as fresh advertisements. The snapshot establishes the
qualification cutoff and does not claim other writers cannot advance branches
afterward.

The stable Notes Review layout, focus/selection/composition, tracked and
untracked IME/undo coverage, and revision-identity assertions remain intact.
Five reviewed Notes paths retain exact prior qualified bytes. Captured Zotero
Add Annotation work and all incoming Notes/Mail/Zotero evidence are retained.

## What the continuation adds and repairs

Mail now includes nullable durable standard flags and transactional schema-v3
migration from v1/v2, plus the initial native IMAP foundation: scoped account/
vault configuration, bounded UID synchronization, exact message retrieval,
guarded flag/move operations, cancellation and resource bounds. Omitted flag
snapshots preserve known state; explicit empty snapshots clear it. The browser
transport entry returns typed unsupported without using the vault or codec.

Parser repairs preserve the specialized resource-limit exception's
`FormatException` relationship, require one canonical FETCH root, reject
repeated lists and trailing fields, and enforce decimal UID wire syntax before
integer conversion. Invalid responses latch failure instead of accepting a
successful prefix or fabricating missing-message tombstones. The merged parser
retains unsolicited flag/status handling, missing-notified-literal checks,
EXPUNGE ambiguity protection and later flag confirmation semantics. Fourteen
raw-parser regressions retain both malformed and valid byte-exact controls.

The final reconciliation adopts the revised Socket-compatible transport facade
after reviewing its repaired ownership behavior. It retains the original TCP
owner during and after TLS, closes TCP before secure output can block shutdown,
settles aborted direct calls, guards generations and late results, preserves
ordered partial writes and cancels idle or active stream producers. Existing
Socket-returning factory signatures and trusted manual STARTTLS remain compatible.

Independent review reproduced a rejected direct upgrade leaving the client
connected. The merged fix restores generation-guarded abort cleanup while
rethrowing the handshake exception. Existing actual-TLS rejection cases assert
disconnected and logged-out state before test cleanup. The controlled RED/GREEN
probe and exact patch are preserved in the
[cleanup evidence](socket-final/upgrade-cleanup-evidence.tar.xz).

Immediate physical closure of a stalled handshake is qualified for the default
owned transport. With a manually supplied SDK Socket, TLS handoff can detach its
TCP owner; the fallback settles abort and destroys eventual late results but
cannot immediately close an inaccessible owner. See the
[merge decision](socket-final/merge-review.md) and
[suite/fixture review](socket-final/suite-review.json). The earlier adapter
decision and its 611-execution qualification remain separately preserved.

The latest FETCH detector also catches malformed response separators before
strict shape validation. Six provider cases and twelve parser cases exercise
failures without successful prefixes or false absent-UID tombstones, together
with valid unrelated response controls.

The Mail equality fixture retains separately constructed equivalent objects and
adds the incoming hash equality assertion. Migration matcher disambiguation is
preserved. The timeout regression now handles process reaping between `/proc`
observations without weakening the child-termination requirement.

## Fresh qualification on the final source

| Focused cohort | Suites | Distinct passed cases |
| --- | ---: | ---: |
| Native transport/configuration/SQLite coordinator | 3 | 86 |
| TLS and connection ownership | 3 | 26 |
| Node unsupported transport boundary | 1 | 3 |
| IMAP and byte-reader regressions | 8 | 193 |
| Connection lifecycle, POP, SMTP and authentication | 10 | 63 |
| MIME consumers | 6 | 32 |
| Mail UI consumers | 4 | 30 |
| **Focused run** | **35** | **433** |

The fresh core/store gate on the same commit passed 31 core VM, 31 core Node,
95 native-store VM and 42 portable-store Node executions: **199 executions /
129 distinct cases**. Across both receipts there are **632 executions / 562
distinct cases / 47 distinct suites**, with 70 VM/Node repetitions excluded from
the distinct-case count. Identities use test file and case name. Earlier Office
and intermediate Mail/transport results are not added to these totals.

The TLS group combines real Linux TCP/TLS loopback tests with deterministic
raw-write and lifecycle controls. Coverage includes successful
implicit TLS and STARTTLS, default-trust rejection, hostname mismatch,
peer-observed closure after stalled-handshake cancellation/deadlines, fresh
connections, exact delayed 1 MiB encrypted payloads, ordered partial writes,
blocked-flush abort, idle-producer cancellation, direct abort completion,
manual STARTTLS and TCP closure before stalled secure shutdown. Test certificates and keys
are explicitly public fixtures; trust is isolated to injected test contexts.
Production certificate and hostname checks remain enabled.

Strict analysis with fatal infos/warnings and formatting passed on **26
transport/vendor Dart paths**. The core/store gate also passed package analysis,
formatting, offline lock enforcement, **42 runner controls**, whitespace checks
and browser entry/worker compilation. Controlled cleanup reproductions and earlier supplemental adapter stream
probes retain their own records and are not counted as Dart cases.

The [independent raw-event audit](socket-final/socket_final_review.json) reconstructs exact
suite coverage, unique identities, complete starts/completions and successful
termination. It verifies zero failures, skipped cases, reporter errors,
unfinished cases, duplicate case identities, layout overflows or missed-tap
diagnostics. The sole existing Drift debug-warning episode belongs to the
separate-host-container test; its two warning-bearing messages remain visible
and the case passed. Strict analysis was clean.

All **5,031 focused source inputs and 11,164 runtime records** remained unchanged.
The store gate independently binds 53 source inputs and seven direct launcher/
config/native inputs. Live readback verified all recorded hashes and 11,142
retained runtime files. The runtime is the hash-verified Flutter 3.47.8 /
Dart 3.13.7 release, with 176 verified hosted archives and a genuine SQLite/FTS5
smoke check. Its 131 resolved packages match 114 locked and 17 workspace names.
Earlier runtime-helper and cleanup-control results retain their own receipts.

Primary evidence: [focused verification](socket-final/verification.json),
[store receipt](socket-final/store-receipt.json),
[distinct case inventory](socket-final/socket_final_review-cases.json),
[35-suite plan](socket-final/plan.json), and
[raw archive index](socket-final/qualification-evidence.index.json).

## Later Arabic tooling and overlapping continuations

After publication `cd430b22`, main advanced through PR #176 to
`f059065fa622da8cee7824d66d29a2aff414d529`. PR #177 was captured at
`c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e` and PR #178 at
`0b8f8f7f78fbf4e2e26671ecf9a0d858c38ca75c`. These additional known heads are
reconciled by ancestry without changing any of the 5,031 qualified inputs.
Their incomplete continuation plans retain their checkpoint status and are
not represented as completed executions.

The new standalone AyaSpell bundle builder and its controls live under
`tools/proofing/ayaspell`, outside the frozen application-input selection. The
selected builder retains the published card metadata and restricts uploads to
manifest members plus `manifest.json`. Unrelated files in reused directories
are excluded. Complementary incoming controls cover deterministic output,
unchanged unrelated/nested files, byte counts and digests, rejection before
publication, and immutable-revision content/manifest readback. The exact source
and passing result for **seven offline Python controls** are recorded in the
[Arabic receipt](socket-final/arabic-controls-receipt.json) and
[exact review archive](socket-final/arabic-controls-evidence.tar.xz). No real
bundle upload or new live resource download is performed by this continuation.
The Hunspell adapter and in-app Arabic download workflow remain planned.

## Earlier qualifications remain separately attributed

The [preserved first TLS report](pre-socket-report.md) records **611 executions /
541 distinct cases** at `4624218f`; its receipts, raw events and independent
audits remain unchanged under `tls/`. The separately received
[Mail-branch report](../mail-m06-resume-20261119/README.md) retains **631 executions /
508 scenarios / 48 suites** at `71edec2d`. Neither checkpoint is added to the
current totals. The separately merged
[completion report](../office-main-completion-20261119/README.md) preserves
**836 application executions / 73 distinct files and 78 separate Python
controls** at `5569c055`. That checkpoint does not include the rejected-upgrade
cleanup in the current source; its broader results remain separately attributed.
All eight incoming Mail archives were independently checked
against their indexes: 218 members and 21,444,149 uncompressed bytes. The store
README update is a changed bound documentation input, captured afresh in this
run; no prior source inventory was rewritten.

The [preserved report before TLS](pre-tls-report.md) records the preceding
389-case focused pass at `7d279e08`, retained 199-execution gate at `1655db9f`,
the 359-case first transport pass and earlier flags qualification. Their raw
evidence and failed reproductions remain under their original directories.

The original **129-suite / 2,018-case** Office qualification, separate
**14-suite / 208-case** native fixture and successful web compilation remain
attributed to `39843ed4` in the
[original continuation report](../thesaurus-20261118/resumed-20261119/README.md).
They are not reruns or a fresh web build of the current source.

The [historical continuity audit](socket-final/socket_historical_continuity.json) verifies
all 129 original suite files, 4,971 of 4,992 ordinary source records, the tracked
Dart closures of 125 Office suites / 1,988 historical cases, all 14 native
fixture closures, the web fixture closure and 12 bound fixture/helper sources.
Twenty-one records changed and 32 product paths were added. Four original Mail
UI suites reach changed core inputs and are covered by the fresh run. No
original suite closure reaches the changed vendor TLS/parser source.

The historical web inventory remains 1,155 compiled files / 87,446,576 bytes and
1,156 installed-cache files / 87,447,167 bytes, with its original warnings and
screenshots. The linguistic packet remains `not_reviewed`; human judgments
have not been filled in.

## Incremental remote preservation and replay

The checkpoint history retains initial reconciliation (`a9e417d3`, `f38959f0`),
flags fixes/evidence (`ebe0498a`, `86560baf`), initial transport repairs/evidence
(`1655db9f`, `f9104833`), latest notification/runtime reconciliation
(`d1dda005`, `2890a0f2`), decimal UID qualification/publication
(`7d279e08`, `99dd7307`, `7a5c6874`), incoming native TLS capture (`f9346ed1`),
the first combined TLS source/publication (`4624218f`, `59e0a7c2`), main merge
(`d4100033`), latest Mail evidence (`3cd60db2`) and final Socket-compatible source
(`ac1e4c8c`). The later `55e262ef` main merge contributes documentation and
evidence; the final publication preserves every qualified input. Commits after
that application source preserve its executable/test/harness inputs; the later
standalone Arabic bundle helper and controls have their own review and receipt. The remote checkpoint branch is retained.

The [qualification archive](socket-final/qualification-evidence.tar.xz) contains raw
events, receipts, source/runtime snapshots and case inventories. The
[development archive](tls/development-evidence.tar.xz) retains adapter probe,
merge and certificate-review inputs. Earlier flags, transport, parser-failure
and runtime archives remain intact. Generated JavaScript is recorded by compile
logs and hashes rather than duplicating reproducible application bytes.

For a new replay, use a clean checkout at `ac1e4c8c` and a separate empty runtime
directory. Follow the
[runtime recovery instructions](../document-review-notes-20261118/runtime/README.md)
with `--node-tests`, then source the generated `env.sh`. From the repository:

```bash
python3 tools/mail/check_store.py \
  --flutter-sdk /absolute/path/to/toolchains/flutter \
  --offline --direct-tests --command-timeout 300 \
  --output /absolute/path/to/fresh-store-results

python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head ac1e4c8c788ea608402c2260488235c0189efcba \
  --base 4624218f9468eeeac07f1f100ac0e4bb6b050a17 \
  --plan docs/validation/office-main-integration-20261119/socket-final/plan.json \
  --runtime /absolute/path/to/toolchains \
  --output /absolute/path/to/fresh-focused-results --command-timeout 300
```

Preserve new replay receipts separately; do not overwrite these observations.

## Acceptance still open

| Gate | Current status |
| --- | --- |
| Actual offline browser | Browser rendering, CSP, offline lifecycle, persistence and performance remain unverified. Node and compilation do not establish these behaviors. |
| Installed Studio and real OS/IME | Installed-app acceptance, live Zotero sessions and external Word/LibreOffice interoperability remain unperformed. |
| Independent English/German linguistic review | Review packet is prepared; human identity, judgments and recommendations remain incomplete. |
| Mail interoperability and remaining product work | Local Linux TLS controls passed. External providers/disposable accounts, other operating systems, OAuth redirect/refresh, platform credential hosts and power-loss durability remain unqualified. Large/sparse UID pagination, SMTP/composition and the account-aware mailbox workspace remain subsequent implementation. |

Integration into main does not close these release and product gates.
