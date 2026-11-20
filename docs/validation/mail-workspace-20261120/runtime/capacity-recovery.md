# Capacity recovery and remaining filesystem limit

Recovery completed at **2026-11-20T10:21:05.811116+00:00**. Product source, Git references,
commit/tree/tag objects, indexed entries and all seven acceptance runtime pins
were preserved. **New temporary-directory creation remains blocked by ENOSPC.**
The latest Studio acceptance cohort must remain rejected; this recovery does
not turn its partial passes into an accepted current-source total.

## Completed recovery

The worker removed inactive generated editor/Studio/Mail UI test caches,
unused Flutter web and DevTools UI resources, completed Git-reconstructable
PPTX baseline copies, dependency tests/examples/docs, and wasm-only compiler
assets. VM, analyzer, frontend and JavaScript compilers, required Linux engine
assets, dependency libraries/build hooks/manifests and current evidence remain.

Removed files account for **820,625,408 allocated file bytes**. Some files may
share hard-linked blocks, so that sum is not an asserted increase in global
free space. Separately, the initial pure-blob promisor pack was reduced from
**445,732,303 to 178,140,336 bytes**, an exact pack-file reduction of
**267,591,967 bytes**. No commit, tree, tag or unpublished loose object was
retired. Only 8,783 remotely recoverable older validation blobs, absent from
the sparse working tree and outside its retained evidence roots, were omitted
from this local cache.

The replacement was generated in a memory-backed file to avoid a temporary
disk spike. Git's strict index verification and an exact 6,307-object set
comparison passed **before** the original pack was retired. The replacement
was verified again on disk. Three older blobs were recovered independently
into an isolated scratch bare repository and matched their Git object IDs.
Git connectivity verification returned exit 0.

## Preserved identities

- All **23,242** locally present commit/tree/tag object IDs remained identical.
- All Git refs and indexed path/mode/blob entries remained identical.
- All **6,706** retained dependency library/bin/build-hook/manifest and
  non-wasm compiler files remained hash-identical.
- All **seven runtime pins** matched their original SHA-256 values: Dart,
  Flutter tester, Flutter tools snapshot, SQLite library, package configuration,
  package graph and real package:test entrypoint.
- No product-file hash changed. The parent independently edited two Mail
  roadmap Markdown files; the receipt lists those exact changes.
- Sparse reapplication completed successfully and removed no additional files.

The SDK/archive and Pub download receipts continue to describe their initial
verified installation. Unused auxiliary cache contents were subsequently
removed as recorded here; a browser/Wasm/DevTools task would need those
auxiliary resources restored. The retained native VM and Node runtime closure
and its seven pins are unchanged.

## Observed capacity boundary

| Observation | Result |
| --- | --- |
| Final `statvfs` available bytes | **0** |
| Final `statvfs` free block bytes | **3,292,729,344** |
| Final available inodes | **3,274,378** |
| Temporary 1 GiB regular-file allocation, end writes and fsync | Succeeded as UID 1000; file then deleted. |
| Python `mkdtemp` under runtime/tmp, runtime root and repository root | All failed with **errno 28, ENOSPC**. |
| Pinned Dart 3.13.7 `Directory.systemTemp.createTempSync` | Failed with **errno 28**, process exit **255**, under the intended runtime/tmp path as UID 1000. |

The successful regular-file allocation does **not** establish usable Flutter
temporary-directory capacity. The failed Dart probe reproduces the first
operation that blocked the rejected Studio cohort. Available-block and
free-block readings are retained separately; this audit does not claim a
verified underlying storage-policy cause for their difference. No privilege,
mount or outside-workspace workaround was attempted.

The executed recovery script, object plan, recovery verification, before/after
identity checks, sparse diagnostics, directory probes and failed Dart outputs
are retained in [capacity-recovery-support.tar.gz](capacity-recovery-support.tar.gz).
The structured [capacity-recovery.json](capacity-recovery.json) records exact
hashes, commands, timestamps and archive identity. No Flutter/product suite or
GitHub Actions/check/status query ran during this recovery.
