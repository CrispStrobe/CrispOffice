# Preserved qualification before the final TLS integration

This is the report saved at publication checkpoint `7a5c6874`, before the later
Mail/Zotero TLS ownership changes. Its counts and acceptance status retain that
source and time scope. See [the current integration report](README.md) for the
subsequent same-source 611-execution qualification.

---

# Office integration for remote main — 19 November 2026

The final integrated application source is
`7d279e084bae438d383630726ad7b0514da77d35`. Its focused transport/protocol/MIME/UI
qualification passed **389 distinct cases across 32 suites**. The separately
qualified core/store receipt contributes **199 executions / 129 distinct
scenarios**, with every recorded source and direct runtime input verified
unchanged. Together these specifically attributed receipts cover **588
executions / 518 distinct scenarios / 44 distinct suites**.

This record accompanies the user-authorized integration into remote `main`
through PR #174. Later publication commits change documentation and evidence
only. Actual release acceptance remains separately tracked below. No GitHub
Actions run was queried, dispatched or awaited.

## Captured work and reconciliation

The final capture includes **213 fork branches, 175 PR heads, 17 tags and four
upstream branches: 409 actual references**. Four additional peeled-tag
advertisement rows are excluded from that count. The independent audit accounts
for 381 references by ancestry and 28 by 14 freshly reverified historical source
equivalences; no missing objects or unaccounted references remain.

| Incoming work | Captured head integrated |
| --- | --- |
| Existing main | `690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e` |
| PR #174, offline thesaurus | `df62b58975bab1f650879fc88f850550a3df5c13` |
| PR #175, Notes | `c320f28347f1cd292b848be2cf72998d41f8a6ac` |
| PR #172, Mail | `7d1adf1636450b3f6040b79856ea62045d03f23d` |
| PR #173, Zotero and concurrent integration | `c634f494b85f7b2118781300a322ad0d9c216a17` |

The last incoming Zotero update adds evidence and integrates already captured
work. Its recursive merge changes no qualified application or test source.
The sole conflict was equivalent `FormatException` wording in the vendored
patch notes; the exact qualified wording was retained.

See [the captured advertisements](incoming/),
[final reference audit](review/final_ancestry_review.json),
[incoming merge review](review/final_incoming_merge_review.json), and
[publication continuity](review/final_publication_continuity.json).

## Implementation and fixes

The integrated Mail increment includes nullable durable standard flags and
transactional schema-v3 migration from v1/v2. Omitted snapshots preserve known
flags; explicit empty snapshots clear them. The new native IMAP foundation
provides scoped configuration and vault access, bounded UID synchronization,
exact message literals, guarded flag/move operations, cancellation and resource
bounds, plus a Node-tested unsupported browser boundary.

Review and failed reproductions produced four narrow parser repairs:

- Preserve `ProtocolResourceLimit` as a `FormatException` subtype while retaining
  its specialized quota classification and content-free diagnostics.
- Require one canonical FETCH response root, rejecting extra trailing fields
  and multiple FETCH bodies that could otherwise hide a UID.
- Reject repeated field lists, including empty lists, in strict iteration while
  retaining the legacy non-strict behavior.
- Require decimal UID wire grammar before integer conversion; hexadecimal,
  plus-prefixed and leading-zero tokens now fail and latch the whole operation.

The merged parser also retains the incoming handling for unsolicited flags,
status text containing FETCH, missing notified literals, EXPUNGE ambiguity and
late flag changes that prevent false mutation confirmation. Fourteen focused
raw-parser regressions cover the repairs and valid byte-exact controls.

Two incoming Mail test defects were repaired before qualification: the equality
case now uses separately constructed equivalent flag values, and migration tests
disambiguate the test matcher from Drift's `isNull`. Formatting was reconciled.

The qualified Notes implementation remains intact: stable Review layout,
focus/selection/composition, tracked and untracked IME/undo coverage, and incoming
revision-identity assertions. Five reviewed Notes paths preserve exact prior
qualified bytes. The captured Zotero Add Annotation work and its existing
regression evidence remain integrated.

## Final qualification and exact attribution

All six focused cohorts below were executed on `7d279e08`:

| Focused cohort | Suites | Distinct passed cases |
| --- | ---: | ---: |
| Native transport, configuration and SQLite/coordinator integration | 3 | 80 |
| Node unsupported transport boundary | 1 | 3 |
| Vendored IMAP and byte-reader regressions | 8 | 181 |
| Connection lifecycle, POP, SMTP and authentication regressions | 10 | 63 |
| MIME consumers | 6 | 32 |
| Mail UI consumers | 4 | 30 |
| **Final focused run** | **32** | **389** |

The core/store gate was executed separately on `1655db9f`: 31 core VM,
31 core Node, 95 native-store VM and 42 portable-store Node cases, for **199
executions / 129 distinct scenarios**. Its 53 source inputs match both that
original commit and the final source; its seven direct launcher/config/native
bindings remain unchanged. These are retained results supported by continuity,
not a claim that all 588 executions were freshly run on `7d279e08`.

The independent audit reconstructed exact suite coverage, case identities,
starts/completions, successful termination and hashes from raw events. It
verified zero failures, skips, reporter errors, layout overflows or missed-tap
diagnostics. There are 70 repeated VM/Node executions in the combined receipts.
Neither the earlier 359-case transport checkpoint nor any older Office totals
are added to the final counts.

Strict analysis with fatal infos/warnings, formatting and whitespace passed for
21 transport/vendor Dart paths. The core/store gate additionally passed package
analysis/formatting, offline lock enforcement, 42 runner controls and browser
entry/worker compilation. The one existing Drift debug-warning episode in the
separate-host-container test remains visible in the logs; that case passed.

All **5,019 focused source inputs and 11,164 runtime records** remained unchanged.
Independent readback also verified 11,142 retained runtime files and provenance
for 176 hosted archives. The runtime is the hash-verified Flutter 3.47.8 /
Dart 3.13.7 release with a genuine SQLite/FTS5 smoke check. The recovered workspace
has 114 locked packages plus 17 workspace packages. Sixteen runtime-helper
controls passed, including exact package-name validation after the added member;
20 cleanup/runner controls also passed. These harness controls are reported
separately from Dart case totals.

Primary records: [final independent audit](review/final_transport_review.json),
[case inventory](review/final_transport_review-cases.json),
[focused verification](transport-final/verification.json),
[retained core/store receipt](transport-first/store-receipt.json), and
[32-suite plan](transport-plan.json).

## Preserved historical Office, native and build evidence

The earlier **129-suite / 2,018-case** qualification, separate **14-suite /
208-case** native fixture, and successful release web compilation remain
attributed to `39843ed4` under the
[original continuation report](../thesaurus-20261118/resumed-20261119/README.md).
They are not newly executed tests or a new web build of the integrated source.

The [historical continuity audit](review/final_historical_continuity.json)
verifies all original suite files and 4,971 of 4,992 ordinary source records.
Twenty-one records changed and 20 product paths were added. The tracked Dart
dependency closures of 125 Office suites / 1,988 historical cases are unchanged.
Four Mail UI suites reach changed core inputs and are covered by the fresh run
above. No original suite closure reaches a changed vendor parser source.
All 14 native fixture closures, the web fixture closure and 12 bound fixture/
helper sources remain identical, without implying a fresh build or runtime test.

The historical build inventories remain 1,155 original files / 87,446,576 bytes
and 1,156 installed-cache files / 87,447,167 bytes. Its two build warnings and
three reviewed screenshots remain under their original receipts. The linguistic
packet retains 15 observed queries, 109 distinct meaning records, ten notices
and `review_status: not_reviewed`.

## Saved evidence and remote checkpoints

The working branch is `codex/office-main-integration-20261119`. Remote writes
were incremental, guarded by the expected branch head and read back by exact
commit/tree comparison. Major saved checkpoints include:

| Checkpoint | Purpose |
| --- | --- |
| `a9e417d3`, `f38959f0` | Initial Mail, Zotero and final Notes reconciliation |
| `056414ba`, `ebe0498a` | Frozen flags plan and repaired test defects |
| `86560baf` | Passing flags evidence saved before the transport refresh |
| `3c66d76b`, `1655db9f` | Native transport and strict FETCH/exception repairs |
| `f9104833` | Independently audited first transport run saved |
| `d1dda005`, `2890a0f2` | Latest notification/runtime fixes and Mail review |
| `7d279e08` | Decimal UID repair and final executed source |
| `99dd7307` | Final evidence and last captured incoming evidence merge |

Compact archives retain raw logs, receipts, case lists, source/runtime snapshots
and hash inventories: [flags](flags/), [first transport pass](transport-first/),
[final focused pass](transport-final/), [failed reproductions](diagnostics/) and
[runtime recovery](runtime/). The final UID reproduction archive preserves both
the six failures before the fix and all 14 passes afterward. Reproducible browser
JavaScript outputs are represented by their hashes and compile logs rather than
duplicated generated bytes.

## Replay

Use a clean checkout at `7d279e084bae438d383630726ad7b0514da77d35` and a separate
empty runtime directory. Follow the
[runtime restoration instructions](../document-review-notes-20261118/runtime/README.md)
with `--node-tests`, then source its generated `env.sh`. From the repository:

```bash
python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head 7d279e084bae438d383630726ad7b0514da77d35 \
  --base 1655db9ff8a5fb9eb140ef236fa0cca74c472107 \
  --plan docs/validation/office-main-integration-20261119/transport-plan.json \
  --runtime /absolute/path/to/toolchains \
  --output /absolute/path/to/fresh-transport-results --command-timeout 300

python3 tools/mail/check_store.py \
  --flutter-sdk /absolute/path/to/toolchains/flutter \
  --offline --direct-tests --command-timeout 300 \
  --output /absolute/path/to/fresh-store-results
```

A replay creates new evidence with its own source/runtime binding; it does not
overwrite these receipts. The saved store run remains attributed to `1655db9f`.

## Acceptance still open

| Gate | Status |
| --- | --- |
| Actual offline-browser acceptance | Browser rendering, CSP, offline lifecycle and performance remain unverified; this host denies the required AF_UNIX socket. Node and compilation are separate evidence. |
| Installed Studio and real OS/IME | Required compiler/GTK/display environment remains unavailable. Controlled Zotero tests do not establish a live session or external Word/LibreOffice interoperability. |
| Independent English/German linguistic review | Packet is ready; human reviewer identity, judgments and recommendations remain incomplete. |
| Native Mail product interoperability | Real TLS/certificate/hostname rejection, authorized disposable accounts, host OAuth/refresh and platform credential hosts remain unqualified. Large/sparse-mailbox pagination, SMTP/composition and account-aware workspace features remain subsequent implementation. |

Integration into main does not close these release and product gates.
