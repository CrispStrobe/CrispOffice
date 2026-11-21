# Zotero native round-trip completion — 21 November 2026

The subsequent [table-layout continuation](../zotero-table-layout-20261121/README.md)
delivers the uniform-margin layout followup and qualifies its reconciled Office
source with 4,635 fresh local cases. The historical counts and source identities
below remain specific to this earlier completion record.

This increment reconciles the pending native ODT bibliography, image and note
work with accepted Office main, adds semantic uppercase import, and qualifies
the combined result locally. The native-file checkpoint passed **3,444 distinct
accepted test cases**. The [cache followup](final-delivery/README.md) raised that
union to 3,452. The [final main reconciliation](final-main/README.md) incorporates
completed Word positioning and native Zotero qualification, verifies their
source-bound evidence, and brings the union across documented checkpoints to
**3,467 passing cases**. Four
synthetic document fixtures survive two actual LibreOffice saves with an
intervening native DOCX/ODT cycle. PNG and JPEG fixtures separately retain their
pictures and active citations through three further native save cycles.

Checkpoint branch: `codex/zotero-roundtrip-complete-20261121`.
Native-file checkpoint:
[`5a829066238b94685db5145ff14420e7e7f0928a`](https://github.com/CrispStrobe/quds_office_suite/commit/5a829066238b94685db5145ff14420e7e7f0928a),
tree `faf0d91961b145e5358f0fd3909a9489933b3e2b`. The final qualified product is
[`a7f69313ed2e610f82242c31be8ad5387ae5cea0`](https://github.com/CrispStrobe/quds_office_suite/commit/a7f69313ed2e610f82242c31be8ad5387ae5cea0),
tree `8f0acd00b505c230ea6ccd2db2d57e17d7475011`. Its production/configuration
bytes match accepted main `aa861c28...`; the extra Dart file is the independent
cache regression. Current engine coverage uses verified incoming qualification
and a fresh native/LibreOffice replay; 51 renderer/position cases passed on this
exact source. The earlier populations were not all rerun on the final tree. Later
delivery changes contain documentation and evidence only. The publication PR records the remote main
merge and readback. GitHub Actions, workflow checks and status queues were
neither queried nor awaited. No repository protections or remote history were
rewritten.

This is a bounded native-file and local application qualification. It does not
establish a new installed Zotero/Word/LibreOffice plugin session, stable-release
LibreOffice acceptance, arbitrary ODT fidelity or complete plugin parity.

## What changed

| Area | Result |
| --- | --- |
| Bibliographies saved by LibreOffice | Reopens supported inherited, inert TextSection styles while retaining rich and empty bibliography entries, field identity and unknown metadata. |
| Tables and DOCX persistence | Retains fixed physical table widths/alignment and complete uniform table margins, including zero; preserves unrepresented source XML and validates cached page-break hints. |
| Native note interchange | Exports separate footnote/endnote symbol and anchor identities with explicit native superscript scaling and a compatible endnote page master. Validates style inheritance, exact decimal labels and supported geometry before editable import. |
| Inline pictures | Integrates bounded embedded PNG/upright RGB JPEG import, exact picture ownership, accessible metadata, hyperlinks, unique drawing identities and active citation positions. |
| Uppercase text | Maps ODT uppercase to native display-only capitals. Authored Unicode, caches, JSON and UTF-16 citation endpoints remain unchanged. Explicit normal-case spans override inherited capitals; script-specific formatting survives. |
| Header and comment fidelity | Fixes a merge interaction that erased authored picture-title distinctions during continuous-header comparison. Inline annotation pictures retain their character style, including links whose parent already owns that style. |
| Parallel Office work | Retains original accepted Word, Mail and performance ancestry. Reconciles the latest main selection-cache invalidation fix and tests its renderer behavior. |

The uppercase regression uses independently constructed ODT with two
identical-looking citations carrying distinct metadata, a PNG between them,
emoji, Arabic/CJK text, combining marks, `ß` and a ligature whose uppercase
presentation expands. It exercises inheritance, explicit false overrides,
native layout, field enumeration and three ODT/DOCX cycles. Lowercase and
capitalization transforms remain unsupported. Effective uppercase plus small
capitals is rejected after inheritance, following the undefined combination in
[ODF 1.4 section 20.227](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.html).
Word's equivalent [caps property](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.caps?view=openxml-3.0.1)
also preserves underlying Unicode text.

## Incoming work and preservation

Initial main was `5c59a062e86e24d043ba06cfe8f0a69074c44f62`. The first complete
fork/upstream intake captured **383 refs**. After reconciliation, **369 were
ancestors and 14 were independently verified historical equivalents**, with no
uncovered initial work. The historical proofs comprise 13 identical full trees
and one exact comparison of all 37 original changed paths, including modes and
blobs; every replacement is a main ancestor.

The publication snapshot at **2026-11-21 19:15:48 UTC** captured **386 external
refs**, excluding this continuation branch. At the native-file checkpoint its accounting was **370
ancestors, 14 verified equivalents and two explicitly deferred refs**. The
deferred refs are the branch and PR aliases of the new Word typography draft
[#336](https://github.com/CrispStrobe/quds_office_suite/pull/336), at
`a646cf761f7eafe7915988a1d84f90ca6dbe5793`. That separate cross-layer feature
appeared after the initial cutoff and explicitly still required its own frozen
source, portable and Flutter qualification. Its remote work is preserved and
was not accepted at that checkpoint. It subsequently completed qualification
and merged through main `aa861c28...`. The [final intake](final-main/intake.json)
now resolves all 386 refs as **372 ancestors and 14 verified equivalents**,
with no remaining deferred captured work.

Accepted incoming tips include:

- Native ODT round-trip PR #333 through `9b4323500d476558a13af8194a65cec165d45da6`.
- Inline-image continuation through `ef05b99ec9bbf1d539181c8519eb41455d182603`.
- Scheduled Mail and its qualification through `917f7ea13425b2c078cc8f0e6e73d4e59b7e4608`.
- Main `3440c90bc63f9d43edb7e64172bfec3d82036fee`, followed by the completed Mail/main
  merge `2058a434b2bcc76e7fc7e8a449ff6ce31488eb25` and its renderer correction.

The [intake directory](intake/) retains exact snapshots, original and classified
replays, explicit dispositions and the unchanged audit script. The historical
native-checkpoint replay identifies the two then-draft refs as unmerged. The
final replay proves their actual ancestry after main integration. Later main
followups remain separate from the unchanged bounded 386-ref snapshot.

All accepted incoming branch commits remain reachable through the merge parents.
Because command-line Git had no write credential, the connected GitHub Git Data
API saved the locally reconciled trees with those parents. Each returned tree
SHA was required to match the local tree, and every branch update used an
expected-head lease without force. Local metadata-only merge wrappers were
replaced by equivalent published commits; the original incoming history and
source bytes were retained.

| Remote checkpoint | Purpose |
| --- | --- |
| `4dd06224b410c27d87053175dfa532e8f4be210a` | Complete initial branch reconciliation |
| `96f850531a7b4fe43963dc0ef72ffa4f94428148` | Uppercase import, header identity correction and converter fixture |
| `538d002ab9da5a8a12ef6adbb66c8062b0560810` | Inline annotation-picture character styles |
| `a9839a97ba5645fcaf36e34729e011074d6a868b` | Refreshed main, explicit note styles and completed incoming evidence |
| `0692e06203d19b89025f63615ba71abd309c9438` | Updated malformed-style regression assertion; production unchanged |
| `5a829066238b94685db5145ff14420e7e7f0928a` | Latest accepted main and selection-cache correction |
| `a7f69313ed2e610f82242c31be8ad5387ae5cea0` | Final accepted main, Word positioning, live proofing and retained independent cache regression |

## Native-file checkpoint qualification: 3,444 cases

Runtime: **Flutter 3.47.8 / Dart 3.13.7**. The official SDK archive and 204
unique locked Pub archives were hash-verified. Enforced offline resolution
retained the tracked lockfile SHA-256
`2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.
SQLite used its genuine native build hook. No real email was sent by the tests.

| Nonoverlapping accepted scope | Passed | Qualification |
| --- | ---: | --- |
| Engine: Zotero, ODT, table and affected Word serialization | 2,698 | Complete isolated replay, zero failures/skips/errors, unchanged captured inputs |
| Editor: ODT/Zotero lifecycle, rendering and selection | 500 | 499-case combined cohort plus 28-case final renderer replay; 27 repeated cases counted once |
| Studio: native transport, shortcuts, ODT opening/export | 41 | Complete accepted cohort, zero failures/skips/errors |
| Mail intake: core, store and Studio scheduling/Outbox | 205 | 14 suites; Mail core/store and entire Studio subtree verified unchanged in accepted successors |
| **Distinct accepted cases** | **3,444** | No failed or skipped cases in accepted executions |

Strict formatting and fatal-info/fatal-warning analysis passed for the 46
changed Dart files, with an additional clean check of the corrected test and
the two latest renderer paths. The two incoming renderer paths are the only
production/test changes after the engine replay; engine and converter inputs
remain identical. The final renderer cohort verifies those exact paths.

Raw test events, cases, commands, exit codes, source manifests, runtime details
and accepted/rejected-stage separation are retained in [evidence](evidence/).
The evidence verifier checks archive hashes and every archived member. A
Flutter startup-lock notice appears in one accepted stderr stream; it is not a
runtime error. The runner also checks raw background-error markers rather than
relying only on the final JSON success event.

### Rejected attempts are retained

- A combined writer review reproduced the header-name normalization defect;
  the next writer pass exposed missing inline-comment picture styling. Their
  corrected focused replay passed 109 cases. These overlap the final engine
  population and are not added to the total.
- An early static pass rejected a dynamic access in the new test; explicitly
  typed metadata access corrected it, and the complete static replay passed.
- The first refreshed engine attempt recorded 1,703 passes and one outdated
  error-type expectation, then exited with signal-derived code `-9` without a
  completion receipt. No passing publication claim uses that attempt. Missing
  referenced marker styles are now correctly asserted as malformed, while
  unsupported paragraph/master settings retain their capability errors. The
  unchanged production code then passed the complete 2,698-case isolated run.
- The earlier generic LibreOffice endnote file remains an explicit refusal;
  it was not rewritten to make a test pass.

## Actual LibreOffice file routes

Converter: **LibreOfficeDev 26.8.0.0.alpha0**,
build `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. All 12 commands in the completed
acceptance route exited zero. Native models and Zotero inventories were matched
against original expected JSON, including unknown metadata and exact owners.

| Fixture | Active fields | Two actual saves with intervening native DOCX/ODT cycle |
| --- | ---: | --- |
| Body citations and rich bibliography | 3 | Passed |
| Left/center/right fixed-width tables and merged cells | 6 | Passed |
| Decimal endnotes and explicit marker styles | 2 | Passed |
| Uppercase citations with unchanged raw Unicode | 2 | Passed |

PNG and JPEG fixtures separately passed an actual LibreOffice save followed by
three native DOCX/ODT cycles, each retaining two pictures and two active
citations. Original fixture files and all 372 executable/dependency inputs
remained unchanged during the successful converter route. Its aggregate input
hash was `eba0401e77a82d7e3cb8425a322fbb48310e14d1ec6ef38fd7a86ae902149de8`.

The original endnote export allowed LibreOffice's empty symbol style, 58-percent
anchor and different endnote-page margins. The corrected exporter declares
native 65-percent styles and compatible geometry. Reading the untouched older
output with the corrected reader still refuses its unsupported marker
position; that negative check and its unchanged input SHA are archived.

The [converter summary](evidence/converter-summary.json),
[member index](evidence/converter-index.json) and
[184-file archive](evidence/converter.tar.gz) preserve original and returned
documents, expected models, exact command logs, the earlier failure, the
successful route and the direct expected-refusal probe.

## Remaining parity work

1. Run identified supported-release Word and LibreOffice installations with
   their actual Zotero plugins and a synthetic library: edit/refresh citations,
   change styles, edit bibliographies, convert notes and reopen saved files.
2. Add a native model, layout and persistence contract for active footnote
   separator geometry before accepting those LibreOffice documents. Keep
   richer note numbering, restarts and configured paragraph styles explicit.
3. Make native layout consume preserved table-cell margins; current rendering
   still uses fixed padding. Extend table header/footer groups and merged-row geometry, then image
   orientation/color envelopes and structural replacement across protected
   boundaries with matching ownership and rendering tests.

The [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) retains the
broader sequence. Zotero's current supported desktop comparison targets are
Word and LibreOffice; its [troubleshooting guidance](https://www.zotero.org/support/word_processor_plugin_troubleshooting)
explicitly excludes Apache OpenOffice. Any historical OpenOffice target needs
separately identified application, Zotero and plugin versions and its own
acceptance record.
