# Word VBA comparisons and foreground colors — 21 November 2026

## Scope

This increment adds shared bounded binary `StrComp` and Word
`Font.ColorIndex`/automatic foreground writes. It retains the source-to-plan
boundary, strict types, metered work, guarded native mutation and detached
atomic publication. The runnable BAS selects status colors using source data,
formats independent header/footer paragraphs and fills two existing table
cells. It does not introduce document-value reads, general VBA project
execution, locale collation, implicit text coercion or cell formatting.

## Captured intake and checkpoints

- Initial remote main: `3058d36c5354d46bde418555d59282116cce1e26` (PR #346).
  All six then-current fork heads and all four upstream heads were contained;
  no open PRs were returned. The latest 100 PRs (#247–346) were merged.
- The source checkout refreshed to main
  `52e72ca0b5677549f31742faae457f08df05759b` (README reorganization).
  Full current fork heads and pull-request heads were fetched, as were the
  four upstream heads. A new Mail intake checkpoint
  `02ef9dc85ff7e716809ee2e0de03bfc3546821a0` was merged before implementation.
- Remote work branch: `codex/word-vba-comparison-colors-20261121`.
- `8b7123d73d58a2d211a2657288fa84f73f917b8e`: reconciled intake with both
  original parent histories.
- `490828f98dd25a2dfa29e565bc97220036f43ef1`: shared StrComp plus focused tests.
- `e1eeb3dc6c13449b1e6357529f325067bdcf5048`: font-color implementation,
  native/source tests, complete BAS workflow and portable tools.
- `7b6f8ce515200c1dd055072d97bf2a10a0600514`: complete contracts, the independent
  conformance corpus, and this qualification record.
- `fa53e8b87aa65c3a9b6b6515615950ba4164e312`: five-parent reconciliation of
  the work branch with current main `cc797dc2e1921be0ee72f90799607af4d787d20b`,
  combined Mail `8858749fc4ffab56a8d429a15ab6625978dbd83f`, and the paired
  Zotero snapshots `fa028f7b96f5ddff93176bc0a502fb3f19903700` and
  `2168011b6104f680100b87404bc1bd409f724939`. All 14 then-fetched fork heads
  and all four upstream heads were ancestors of this checkpoint; see the
  [captured ref inventory](intake/reconciled-refs.tsv).
- `dfb41894add97dfe605bf05a17cd151dd4024b44`: independently qualified inherited
  frame-test correction and precise Word capability overview wording.
- `5e144156e0f6737f6a7c33328a807ff4d7ae975b`: focused-editor shortcut bridge,
  including the demonstrated Slide held-key composition fix and twelve passing
  dispatch cases.
- `ca2c7c2066771dda6c71eb8b2e70ce6bf18d56d4`: refreshed captured branch heads:
  host ownership `22dd2a4d474a59ad231f24a61dcb8046b029e993` (draft PR #347),
  separator implementation `a1b555979b25c5586f27915cf219a95e886febd7`
  (draft PR #348), and Mail integration
  `00fbd252d659777dc85f886df150f23c7a76bf1e`. Both independent shortcut test
  suites are retained under distinct names. The compatible separator read and
  automatic-color projection coexist in the Word deserializer.

The documentation reconciliation retains main's short overview guides and
detailed companions. The new [Word foreground contract](../../vba-word-macros-details.md#font-palette-and-automatic-foreground)
and [shared comparison contract](../../vba-macros-details.md#binary-string-comparison)
live in those detailed companions. Incoming Mail selection and address-search
contracts remain in the Mail roadmap's detailed status document.

Remote writes use expected-head, non-forced GitHub ref updates. The local git
transport can read this public repository but has no write credential, so Git
objects are saved through the connected GitHub API and fetched back locally.
No existing branch was force-pushed or deleted. GitHub Actions are not a gate;
checkpoint messages use `[skip ci]` and no Actions run is queried or awaited.

## Local environment

The first full checkout exhausted the initial executor's storage and that
executor became unavailable. Work resumed in a recovered runtime using a
source checkout and a standalone Dart validation workspace. There was no
dependency on the hosted CI queue.

The standalone SDK is Dart 3.14.1. The minimal validation workspace links the
actual engine/legacy-parser sources and resolves all 56 dependencies to the
versions and sources in the repository lockfile. Repository manifests and the
lockfile remain unchanged. This headless setup is distinct from the repository's
Flutter 3.47.8 pin and from installed Microsoft Office qualification.

The incoming UI integration was separately qualified on the repository-pinned
Flutter 3.47.8 / Dart 3.13.7 SDK. Its official archive checksum was verified,
and `flutter pub get --enforce-lockfile` resolved 166 packages in an isolated
workspace. The root lockfile remained byte-identical, SHA-256
`2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.
Both workspaces link the repository sources; generated configuration and build
outputs are outside the repository.

## Executed focused qualification

| Gate | Result |
| --- | --- |
| Existing Word language/integration baseline | 170 tests passed |
| Shared StrComp source tests | 78 passed |
| New Word color compiler tests | 74 passed |
| New native Word color tests | 43 passed |
| Actual BAS/native/CLI/MCP integration | 10 passed |
| Independently authored conformance wrapper | 31 tests passed: 30 cases plus provenance receipt |
| StrComp portable smoke | 72 checks, identical VM/JavaScript JSON |
| Actual BAS portable workflow | Identical VM/JavaScript results and native XML hashes |
| Versioned corpus | Same 30 fixture cases, identical VM/JavaScript receipts |
| Scoped source/new-test analysis and formatting | Passed |

The new corpus fixture SHA-256 is
`d527b6ca049ee154a3dd17297c4e3ec9a800f3498ceac67d47fb4118adc65241`.
Its identical VM/JavaScript receipt SHA-256 is
`2cca54083876741238892d12b1e454fcd2d97dcef87a49db7f4e0de7da77d60c`.
The StrComp smoke receipt SHA-256 is
`8df099428192365cb1befbcee1b3525555b69102f861c274c0c31b6581250aa5`.
The actual BAS workflow receipt SHA-256 is
`b832a9d6fdd14ca4a9f86309887b07d6a1c5035c49564d327d3839f4289b7ad8`.

Native checks cover automatic versus fixed black, every palette entry,
same-value style overrides, theme-selector removal, foreign attributes and
children, namespace aliases, Unicode ranges, repeated save/reopen, DOCM/custom
XML retention, guarded refusals, policy, recording/replay and whole-run
rollback. The tests caught and verified a fix for generated fragments whose
native `w` prefix is intentionally unbound before insertion into a document.

The source expectations distinguish specification-derived results from Quds
dialect restrictions. No test claims a recorded Microsoft Office host result.

## Final integration qualification

### Engine and macro regression

The explicit [139-file manifest](records/word-comparison-colors-final-test-manifest.txt)
contains 6,683 unique tests. The initial run passed 6,676 and exposed seven
failures. Subsequent isolated runs resolved all seven without a second full
broad execution:

- One MCP stdio test hit its 30-second deadline while a full analyzer was
  competing for resources; the unchanged test passed in isolation.
- Four native line-spacing/layout cases required the tracked Liberation Sans
  fixture, absent from the minimal staging workspace. Restoring that fixture
  resolved all four without production changes.
- Two DrawingML frame assertions also failed on the original main baseline
  `52e72ca0b5677549f31742faae457f08df05759b`. The XML helper matched the retained
  `xmlns:w` declaration when asked for local name `w`. The test now checks the
  actual bare width attribute. The corrected full 26-test file passes; no
  production frame code changed.

The [combined qualification receipt](records/word-comparison-colors-final-combined-qualification.json)
records this execution method and zero remaining failures. The independent
30-case corpus wrapper passed 31 additional tests. Full engine analysis,
`dart analyze --fatal-infos lib test tool/macros`, is clean on its isolated
run. Source hashes establish that the five production files, runnable BAS,
and portable tools were unchanged from the implemented checkpoint throughout
this initial qualification and the first incoming branch reconciliation.
The later separator integration adds its independent model read to the
deserializer; the bounded integrated gate below qualifies that final combination.

### Incoming Mail/Zotero and shortcut dispatch

The incoming snapshots exposed a real shortcut-precedence issue: a focused
Word surface consumed its built-in key before Studio could apply a configured
override. Studio now dispatches its resolved bindings through an optional
controller hook before the focused Word, Sheet or Slide surface handles its
defaults. Replaced defaults and aliases are retired, a conflicting override
executes once, and native text fields retain their editing keys. The hook also
respects composition and active-host guards; standalone editors keep their
existing defaults when it is unset.

| Flutter scope | Passing tests |
| --- | ---: |
| Mail range selection | 43 |
| Studio localized Mail help | 3 |
| Studio Mail synchronization and full-address search | 35 |
| Studio settings persistence/sanitization | 23 |
| Studio shortcut definitions/remapping | 12 |
| Studio Zotero shortcuts | 17 |
| Editor Zotero main dialog | 49 |
| Editor Zotero citing dialog | 24 |
| Editor Zotero direct commands | 23 |
| Editor Zotero stored details | 11 |
| New actual-focus shortcut dispatch | 12 |
| **Total** | **252** |

The final clean runs have no test warnings or failures. The twelve new dispatch
cases cover Linux/macOS defaults, conflicting overrides, one-step redo, IME,
native text fields, reserved Zotero commands, inactive Sheet formatting, and
standalone fallback. Held-key composition guards are exercised on Word, Sheet
and Slide; the Slide case reproduced its original failure before the hook
ordering correction. Both scoped editor/Studio analyzer passes are clean.
An earlier Studio invocation was interrupted when two commands shared its
build cache; only the subsequent exclusive run is counted. See the
[incoming Flutter receipt](records/incoming-branch-flutter-validation.json)
and [shortcut dispatch receipt](records/shortcut-dispatch-final-receipt.json).

### Latest captured branch qualification

The later separator snapshot changes native layout, DOCX/ODT persistence and
rendering. Its retained converter fixtures and evidence preserve both the
successful bounded ODT routes and the unsuccessful DOCX-to-LibreOffice
separator-appearance probes. Its draft status did not establish an integrated
passing gate.

The newly combined source is being checked with the changed separator suites,
adjacent note/Zotero persistence tests, color/package/atomicity regressions, a
new combined macro-and-separator transaction case, and the four affected editor
rendering/note suites. The incoming host suite is retained as
`studio_shortcut_host_ownership_test.dart`; its harness is being reconciled
with the actual editor-owned shortcut dispatch while retaining its assertions.
Completed results and exact-source records follow in the next checkpoint.

### Evidence and publication

The [record manifest](records/manifest.json) gives exact byte lengths and
SHA-256 hashes for the saved commands, source inventories, receipts and logs.
Large text logs use deterministic gzip compression. Original failing runs and
the successful follow-up checks are retained so the qualification is auditable.
Portable VM and JavaScript outputs have distinct filenames for the corpus,
intrinsic smoke and actual BAS workflow.

All integration commits preserve the incoming branch histories. Publication
uses a normal merge to remote main after refreshing its head, with an expected
PR head and no hosted-CI wait. No protected-branch rule is disabled.

Material limits remain explicit: general VBA execution/document reads,
locale-dependent StrComp behavior and installed Word differential testing are
not delivered by these changes. Native automatic foreground is preserved;
this increment does not add a new automatic-contrast rendering policy.
