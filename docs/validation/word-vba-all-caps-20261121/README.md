# Word VBA AllCaps continuation — 21 November 2026

## Accepted scope

The bounded Word source adapter now accepts Boolean `Font.AllCaps` writes on
explicit paragraph text and independent header/footer targets. Native import,
style inheritance, sparse DOCX export, layout and existing editor behavior
recognize the formatting flag. Display changes preserve authored text and its
UTF-16 offsets, including Unicode expansions, combining clusters, clipboard
content and PDF logical text. True AllCaps/SmallCaps writes clear the opposite
mode; false changes only its own mode. Explicit CSL small capitals also clear
inherited AllCaps, preserving citation Refresh behavior.

The [source contract](../../VBA_WORD_MACROS.md#all-capital-display-without-changing-source-text)
and [runnable BAS](../../../packages/quds_office_engine/example/macros/word_all_caps.bas)
define the exact supported subset. General Word automation, numeric toggles,
live property reads, embedded VBA execution, locale-tailored casing and new
ODT/RTF/HTML capitalization interchange remain outside this increment.
Installed Microsoft Word differential qualification was not performed.

## Frozen source and local results

Qualified source: **`0fe00b18fef6b79a435817c99714f987329d5f3c`**.

The [acceptance receipt](acceptance.json) selects one accepted result per
requested test file. Each gate captured the same 3,262 selected tracked
source/test/manifest/font inputs before and after execution:

`9b7185c99dbc2bd7cb77243d46565c34082327ebecd39a6fff42913efd66ae4e`

| Scope | Accepted result |
| --- | --- |
| Engine Word/VBA/macros, rendering, Zotero and ODT | **7,840 cases across 271 files**, after replacing the initial MCP file result with its complete successful replay |
| Editor rendering, selection, proofing and Zotero integration | **259 cases across 17 files**, process exit 0 |
| New increment cases, included in those totals | **98 engine + 7 editor** |
| Changed Dart paths | All **23** pass strict analysis and nonmutating formatting |
| Actual seven-operation BAS | Dart VM, optimized JavaScript compilation and Node all exit 0; complete semantic receipts and native-part hashes match |
| Source binding | All 3,262 selected inputs remain unchanged for every accepted gate |

New engine coverage comprises 32 compiler, 37 native, 11 transaction/CLI/MCP,
13 display/model/PDF and five CSL integration cases. Counts do not measure a
percentage of VBA parity. Development checks overlap these final suites and
are not added to the totals.

The archive's `independent-audit.json` reconstructs the counts from raw events,
matches the replay's complete test-name set, independently compares portability
receipts and verifies every selected input against the frozen commit's Git blobs.

### Engine timeout replay and counting

The original 271-file run completed with **7,837 passed, three errors, no
skips, and process exit 1**. All three errors were the default 30-second
timeouts in `office_macro_mcp_test.dart`'s source-launched stdio cases:

- Real handshake, JSON errors and persisted mutation.
- Validation without creating an output file.
- Persistence failure stopping later requests.

The fourth stdio case, extension mismatch, passed in that run. No other file
failed. The VM example separately took 50.662 seconds including source launch
and execution in this environment. The complete, unchanged MCP test file was
replayed with `--concurrency=1 --timeout=120s`: **15 passed, exit 0**, with no
error or skip events. Its before/after source hashes equal the original freeze.

Acceptance replaces that file's initial **12 successes + three timeouts**
with its **15 successful cases**. The other 270 files retain their original
results. Thus the accepted engine count is 7,840, without double-counting the
MCP file. The original failing stream and exit status remain in the archive.
No code or assertion was changed to obtain the replay result.

### Editor runner correction

The first editor run produced a successful terminal event and 259 visible
passing cases, but its wrapper rejected valid Flutter `test.startedProcess`
control-event arrays before persisting the nested process exit. That run is
retained only as development evidence; its Flutter process exit is unknown.

The wrapper was corrected to validate those control events separately and to
persist execution metadata before parsing. The identical 17-file gate then
completed with **259 passed, no failures/skips/error/parse events, and an
explicit process exit 0**. Only this second run supplies editor qualification.

### VM/JavaScript comparison

The portable runner compiles and executes the exact committed BAS bytes,
validates without publication, applies all seven writes, records and replays
the operations, checks repeated DOCX reopening, and preserves an opaque VBA
project payload. It checks observed document state before emitting its
asserted receipt. The native document, header and VBA-part hashes agree.

Raw JSON bytes differ only at ten `display.scale` values: VM prints `1.0`
and JavaScript prints `1`. The original failed raw-byte comparison is retained.
A separate strict, duplicate-free JSON comparison using exact decimal numbers
and distinct Boolean types proves complete semantic equality. Replacing only
those ten number spellings also makes the raw outputs identical.

Canonical complete receipt SHA-256:
`218ee6a9e72b3401a692826b35066d55df1118c6876ef09103072bb6f6603cc8`.
Whole DOCM ZIP byte equality is not asserted.

## Runtime and reproducibility

The [runtime receipt](runtime-provenance.json) records official archive hashes
for repository-pinned **Flutter 3.47.8 / Dart 3.13.7** and the observed Node
version, **24.22.3**. The archive's `locked-dependencies.json` records 202 verified
hosted archive entries and is hash-bound by that receipt. Its `checks/provenance.json`
and `portable/provenance.json` also record the Node executable identity. Full repository offline
`pub get --enforce-lockfile` succeeded; `.fvmrc` and `pubspec.lock` are unchanged.

The [engine suite list](engine-suites.txt) records every selected file. Exact
argument vectors, working directories, timestamps, process exits, raw JSONL
streams, source manifests, runtime identities, comparison scripts and the
compiled JavaScript are in [the evidence archive](evidence.tar.xz). Its complete
member sizes/hashes are in [the archive inventory](evidence-manifest.json).

The engine used the cached test-runner snapshot with `--concurrency=2 --reporter=json`;
the snapshot contains the runner, while suites compile the live frozen source.
The editor used `flutter test --no-pub --concurrency=2 --machine`.
Analysis used `--fatal-infos`; formatting used
`--language-version=3.12 --output=none --set-exit-if-changed`. The portable
example used the same base64 source define on VM and `dart compile js -O2`,
followed by Node with the unchanged locked `node_preamble 2.0.2`.

The archive retains the initial engine timeout run, the unqualified first
editor run and the failed raw JSON comparison alongside their accepted
replacements. Helper paths reflect the original execution workspace and need
rebinding when reproducing elsewhere. The engine's original wrapper predates
the Flutter control-array correction; engine output contains only ordinary
test-protocol objects, and its counts are independently reconstructed.

## History intake and incremental preservation

The [initial intake](initial-intake.json) starts from remote main
`01517de8886ef7bd24947894be5dc823d0328869` (PR #310). All 27 pre-existing fork
branches, the 100 recent PR heads (#211–#310) and four upstream heads were
already included. There were no open PRs. The complete receipt also includes
the newly created checkpoint branch, giving 132 captured references.

| Remote checkpoint | Saved work |
| --- | --- |
| `3794c8500dec2fbf7b541c346354964fdf696abd` | Complete initial intake and extension scope |
| `3f130d7f68ce40cf4596ee27c6920ded0220e8e0` | Compiler, native model/formatting, display implementation and first regressions |
| `0fe00b18fef6b79a435817c99714f987329d5f3c` | Editor and CLI/MCP integration, CSL preservation correction and exact contracts |

The final evidence commit changes documentation and artifacts only. All
checkpoints use parent-preserving, expected-head, non-forced remote updates on
`codex/word-vba-formatting-20261121`. [PR #311](https://github.com/CrispStrobe/quds_office_suite/pull/311)
is the publication record.

At the [final fixed intake](final-intake.json), 21 November 2026
15:42:43 CET (14:42:43 UTC), main remained unchanged. All 132 initial references were
independently rechecked as ancestors of the frozen source. Of 31 final fork
heads, 28 were included; all 100 recent PR heads and four upstream heads were
included, with zero unclassified references. The only open PR was #311.

Three branches began after the initial cutoff and remain preserved separately:

| Branch | Captured head | Reason |
| --- | --- | --- |
| `codex/zotero-libreoffice-styles-20261121` | `2aa7833239ec4507a4a9db1c7f23c84bd01b4028` | Planning/intake documents; committed status says implementation and fresh qualification are pending |
| `work/mail-client-next-20261121` | `c9a3475541a58778b0db26f4d1b4516e9e51e20a` | Saved searches/conversation work remains an unfinished qualification milestone, including a new persistence schema |
| `fix/de-proofing-l10n-20261121` | `db790347cecfea34f761adb3fc202c1109d603c7` | German review/proofing/notes localization explicitly labeled WIP |

None of those captured changes overlaps AllCaps paths, and none has a completed
local qualification claim or corresponding open PR at that cutoff. This gate
does not qualify them. Current main is checked again immediately before merge.

**GitHub Actions, workflow runs, CI checks and queued jobs were not queried or
awaited.**

## Primary contracts

- [Word Font.AllCaps](https://learn.microsoft.com/en-us/office/vba/api/word.font.allcaps)
- [Word Font.SmallCaps](https://learn.microsoft.com/en-us/office/vba/api/word.font.smallcaps)
- [WordprocessingML caps](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.caps)

The Boolean source setter follows the documented reciprocal mode behavior,
with the existing Quds restrictions. Unicode default casing, synthetic small
capitals and the conservative fallback for contradictory source flags are
explicit implementation contracts, not installed Office-host observations.
