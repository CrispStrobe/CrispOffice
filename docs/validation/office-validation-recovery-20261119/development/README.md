# Development and runtime-preparation evidence

This archive preserves the completed focused development work and runtime
preparation for the Office validation recovery on 19 November 2026. It contains
the original raw reporters, logs, command/source receipts, native build inputs
and outputs, browser compiler artifacts, and selected runtime manifests.

**These are unfrozen development observations, not an accepted final aggregate.**
Their individual source identities and dispositions remain authoritative.
Repeated runs, the intentionally failing baseline, and the skipped diagnostic
are retained without adding their counts to a final-source result. Subsequent
integration changes require their own source-bound qualification.

## Complete preserved inventory

The [index](development-evidence.index.json) lists all **143 archive members**:
**115 regular files**, **28 directories**, and no symbolic links. Regular-file
content totals **38,089,574 bytes**. Every regular file has its byte length and
SHA-256 recorded. Every member retains its original permission mode and exact
nanosecond modification timestamp. Tar ownership is deliberately normalized to
UID/GID zero with empty owner names; file contents are unchanged.

| Archive source label | Regular files | Content bytes | Preserved material |
| --- | ---: | ---: | --- |
| `mail-development` | 7 | 80,073 | Complete Mail reporter and stderr, strict analysis/format logs, exact test source, patch and development receipt |
| `language-review` | 26 | 153,589 | Engine VM/Node and CLD3 wrapper reporters, ordinary startup repetitions, strict analysis logs, source/command receipts, both review summaries |
| `language-native-development` | 14 | 41,609 | Real-model/fixture reporters, expected RED, skipped diagnostic, explicitly bound GREEN, exact before/after transport source and binding review |
| `language-web-development` | 10 | 32,495,201 | Full kernel and JavaScript artifacts, dependency lists, compiler/syntax logs and artifact/import-closure audits |
| `language-id-build` | 44 | 513,952 | Complete pinned downloaded source, CMake inputs/intermediates, shared libraries, fixture/build receipts and logs, preparation record and original runtime receipt |
| `runtime` selected files and `runtime/logs` | 10 | 4,803,551 | Runtime receipt, retained-input hashes, archive membership, package-cache receipt, cache omissions, environment file and all four preparation logs |
| `preparation-logs` selected files | 3 | 1,094 | Exact runtime restoration, language-ID preparation and web-SDK preparation console logs |
| `web-sdk/preparation.json` | 1 | 505 | Exact separate web-SDK preparation receipt |

Only the explicitly labelled sources in the index were read. Entire Flutter,
Dart, package-cache and web-SDK trees are outside this preservation archive.
Their selected manifests identify the prepared runtime independently. No raw
source log or receipt was rewritten while archiving.

## Preserved observation boundaries

The Mail development receipt records **48 passing widget cases**, including
failure followed by an explicit successful mark-read retry, and late success
or failure while a replacement session owns another pending mark-read request.
The exact test source and patch remain alongside the original reporter.

The language-policy development records contain **16 VM cases and the same 16
cases repeated on Node**. The wrapper initially had 15 passing VM cases, then
16 after a separate disposal-sequence review. The latest wrapper record is
`language-review/wrapper-disposal-vm.*`. Earlier ordinary `dart test` commands
eventually completed successfully; their reporters are preserved as repeated
observations. They are not extra distinct scenarios or final acceptance. The
first strict-analysis diagnostic contained one `unawaited_futures` finding;
the corrected analysis logs are retained separately.

The native development summary records **10 passing cases** from the real
pinned CLD3/model suite and the allocation-counting fixture. Its separate
`disposal-red` record intentionally fails one regression against the exact
incoming `40c3351e` native transport. The source was restored in a `finally`
block, and the original/fixed source bytes and reproduction receipt are kept.
`disposal-green` is an earlier misconfigured diagnostic with **one skipped
case** because its fixture environment was absent. It is not accepted.
`disposal-green-bound` then passes the selected case with the fixture explicitly
configured. These selected repetitions do not augment the ten-case result.

The browser evidence establishes successful frontend/JavaScript compilation,
syntax checking, exact compiler-artifact hashes, and the browser import closure.
It does **not** establish a browser session, execution of the worker or Wasm
classifier, or browser persistence. The full generated artifacts are retained
so their recorded hashes can be checked after this workspace disappears.

Runtime preparation and native build receipts identify tooling and binaries;
they do not establish application acceptance. No installed-platform,
external Mail/Zotero account, Word/LibreOffice interoperability, independent
linguistic acceptance, or final combined aggregate is inferred from this archive.
The original failed `de24bdfc` Store logs were not recovered here. No GitHub
Actions run, job, status or queue was queried or awaited.

## Archive identity and verification

The compressed archive is split into **13 ordered parts**, each at most
**1,048,576 bytes (1 MiB)**. Parts `0001` through `0012` are exactly that size;
part `0013` contains 459,724 bytes. Each part's name, offset, length and SHA-256
is recorded in the index.

| Object | Bytes | SHA-256 |
| --- | ---: | --- |
| Reconstructed `development-evidence.tar.xz` | 13,042,636 | `da65c53c846ff6eae616b90623c5b5ae35d236a5631dfc396c65609a5bd8e5d7` |
| Decompressed PAX tar | 38,338,560 | `1407a1ddf331f8df7809ef7dba381ddf1e8ccca4886ece2b12aa79cf566f9a52` |
| Complete index | — | `6f6f6dbafbab544dba16d4029a2920913afac5bc25757a01eae6a8f635834c01` |

The [verification receipt](development-evidence.verification.json) records:

- The decompressed member set exactly matches the complete index, without
  duplicate, missing or additional members.
- Every regular member's length and SHA-256 match, and **every original file
  was compared byte for byte** with its archived representation.
- Original modes and nanosecond modification timestamps match for all members.
- A second complete tar/XZ build from the original sources reproduced the first
  archive byte for byte.
- Rejoining the published parts reconstructs that exact compressed archive,
  and decompression reconstructs the exact indexed tar.
- A second source inventory after packing matched the first; no source file,
  directory, mode, timestamp or content change was hidden during packing.

## Verify and reconstruct without the original workspace

From the repository root, this requires only Python's standard library and the
committed tool, index and parts:

```bash
python3 docs/validation/office-validation-recovery-20261119/development/archive_development.py verify \
  --index docs/validation/office-validation-recovery-20261119/development/development-evidence.index.json
```

The tool verifies every part before joining it, the joined and decompressed
hashes, every indexed regular file, and the exact member metadata. It does not
need or silently read the former absolute source paths for this operation.

To write the verified compressed archive into a new recovery directory:

```bash
mkdir -p /tmp/office-development-recovery/files
python3 docs/validation/office-validation-recovery-20261119/development/archive_development.py verify \
  --index docs/validation/office-validation-recovery-20261119/development/development-evidence.index.json \
  --reconstruct /tmp/office-development-recovery/development-evidence.tar.xz
tar --extract --xz --same-permissions \
  --file /tmp/office-development-recovery/development-evidence.tar.xz \
  --directory /tmp/office-development-recovery/files
```

Choose an unused output path: `--reconstruct` refuses to overwrite an existing
file. Extraction restores the archived relative labels, file modes and mtimes.

## Reproduce or compare against originals

[The archive tool](archive_development.py) accepts repeated explicit
`--source LABEL=PATH` arguments. [commands.json](commands.json) preserves the
exact packing command and the original-byte verification command. Source labels
are logical archive roots; the absolute original paths are provenance, not
requirements for portable verification.

If the original inputs still exist unchanged, run the
`verify_original_bytes_argv` command from `commands.json` to repeat every
original-byte comparison. To reproduce the complete archive, use its
`pack_argv` with only `--output` changed to a new empty directory. The tool
refuses to replace an existing archive. It sorts members, preserves their
indexed modes/mtimes, uses deterministic PAX headers and XZ preset 6 with a
SHA-256 check, performs two complete builds, and checks exact reconstruction.
The resulting archive parts must match this index's part lengths and hashes.
