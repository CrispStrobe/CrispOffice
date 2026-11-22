# Late intake audit 2 — final follow-up

## Current disposition

Mail `a886d7d79ae3d63e78f09a9caeb8569da81243c9` independently passes the follow-up checks. Both failures found at the earlier `a61f7c07` checkpoint were corrected by the author before any local patch was needed. No source or index edits were made in either the root checkout or isolated Mail checkout.

| Final follow-up at exact a886 source | Result |
| --- | --- |
| Migration, Archive journal, Archive journal migration (three files) | 37 passed |
| Native Archive provider | 15 passed |
| Same three affected Studio files | 276 passed |
| Strict analysis of four follow-up Dart files | Clean, fatal infos enabled |

The new production change in a886 is bounded native Archive discovery: it detects duplicate INBOX aliases case-insensitively while retaining case-sensitive identity for other mailbox names. Four added cases cover aliases and special-use attributes.

Main subsequently advanced to `4621326a5a452da475f219353c298d0f9b12470e`, an ancestry-only merge with an identical tree to `05bb203e`. Reconciled Mail head `8280277cd27bcc276d66b61f8073eddf37ca6e5e` includes that main, Word `4dafb6f7`, and our Zotero `50895a7b`/`aac3dda7`. There is no difference from a886 for any Mail package or Studio Mail production/test/support path. The Mail-specific source qualification therefore applies by identical bytes; combined application compilation is covered by the root release cohort.

No separate patch is supplied because the exact two recommended corrections already exist in the remote branch. All initial failures and the interrupted full-store attempt remain recorded below and in the JSON. They are not rewritten as successful runs. The 37 migration cases overlap the earlier focused 20 and partial full-store run; repeated qualification counts must not be summed as distinct cases.

Observed root release candidate at report time: `168297fea2df1f49cb1362f8ac21002edd222ac4`. Its precise ancestry against all latest captured heads is recorded in the JSON. No GitHub Actions were queried or waited for.

# Initial captured heads and qualification history

Captured 22 November 2026. Read-only ancestry/source audit and isolated local qualification. No root index/source edits, remote writes, or GitHub Actions queries.

## Captured heads

| Ref | Captured SHA | Includes Zotero aac3dda7? |
| --- | --- | --- |
| main | `05bb203e1b74f8aff0873a6325d9ac18b83515f3` | No |
| word | `4dafb6f7e7fc844d11cb7219add5a82acfed5135` | No |
| mail | `a61f7c0746219f1fc82d44b5e9e9b3c6cdb13dd1` | No |

Main `05bb203e` merged PR #378 at 10:40:51 UTC and includes Word `4dafb6f7`. It does not yet include Zotero `aac3dda7` or Mail `a61f7c07`.

Observed root release candidate `50895a7b9670058e27d3f081626defac9ea1aebc` contains main `05bb203e`, Word `4dafb6f7`, and Zotero `aac3dda7`. It does not contain captured Mail `a61f7c07`.

## Word source and local qualification

Word `19a63d4` → `4dafb6f7` changes 24 documentation/evidence files only. Production, test and tool source is identical to the independently qualified `19a63d4`. The source qualification therefore carries across this docs-only head update.

- 405 Mid assignment/runtime/conformance/native integration/CLI tests passed.
- 529 existing shared string/array regression tests passed.
- 231-case portable adapter corpus emitted equal VM and Node canonical JSON.
- Native DOCX and DOCM template receipts emitted equal VM and supported Node-host JSON.
- Existing raw reporters and exact source/fixture hashes are retained in `late-intake-1.json` and its linked evidence.

The Word author additionally reports 8,006 macro tests; that is author evidence, distinct from the independent checks above. Repeated portable executions are not additive distinct cases.

## Mail source delta and buildability

Mail advanced from the incomplete typed-intent checkpoint `9d8758e5` through `dd00d169` to `a61f7c07`. The later two commits change 52 files; the branch changes 19 production Dart files overall. Previously identified missing exhaustive Archive switch arms are now fixed.

The completed source adds Gmail INBOX-label removal, authoritative IMAP Archive folder resolution, Microsoft Graph ordinary Archive destination, reviewed fallback destinations, durable journal restore/recovery, membership/search reconciliation, and Archive UI. Store schema advances from 15 to 16 to gate the new persisted intent; unexpected Archive data in an old schema is refused.

Strict analysis of all 19 changed production Dart files passed with fatal infos. Independent tests ran against a clean detached worktree at exact `a61f7c07`.

| Cohort | Result | Meaning |
| --- | --- | --- |
| Core Archive/bulk behavior | 120 passed | Four selected core files |
| Native/cloud/EWS transports | 256 passed | Three selected provider files |
| Real SQLite Archive/migrations | 20 passed | Focused new persistence tests |
| Message list Archive widget | 21 passed | Focused widget file |
| Affected Studio integration files | 275 passed; 1 failed | Three-file cohort is not accepted |
| Full store attempt | 1,116 passed; 1 failed; interrupted | Not a completed full-store acceptance |

The focused store cases overlap the partial full-store run; do not sum these as unique cases.

## Initial failures, since corrected upstream

1. `packages/quds_mail_store/test/migration_test.dart` still labels versions `[16, 17]` as future. Schema 16 is now current. The dummy schema-16 database has none of the required tables and produces `storageFailure`, while the outdated fixture expects `unsupported`. Use actual future versions such as `[17, 18]`, preserving the byte-for-byte nonmutation assertions.

2. `packages/quds_office_editor/example/test/studio_mail_organization_dialog_test.dart` taps Archive destination index 1 below the dialog scroll viewport. Flutter reports a missed hit at y568, and the final selection is null. Ensure the widget is visible before tapping, then retain the selection assertion. This is a test interaction failure; do not suppress the warning.

No source fix was made locally. The initial captured Mail head was buildable but not fully qualified; upstream a886 later supplied these exact corrections, and the follow-up reruns below passed.

## Environment and evidence limits

The isolated Mail worktree copied the established package configuration and package graph. SQLite tests used a command-specific preload of the installed real `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0`; no source or dependency lock changes were made. Initial missing-native-asset and missing-package-graph launches are preserved as setup failures and excluded from passing results.

The full store attempt reached inherited POSIX crash tests that launch the adjacent official `dart run` CLI. That path had not reached its READY barrier and can reenter the known Pub/native-hook startup issue. The run was interrupted after the stated 1,116 passes and stale fixture failure; no full-store success is claimed.

Live-provider authentication/network behavior and platform release qualification remain unverified. The Mail author README explicitly calls this an in-progress checkpoint and had not yet claimed full-store or affected Flutter completion.

Exact heads, ancestry matrix, all changed paths, source/runtime/report hashes, test paths, commands, error text, and prior Word qualification references are in `late-intake-2.json`. Raw reporters are adjacent `late-intake-2.mail-*.jsonl` files.
