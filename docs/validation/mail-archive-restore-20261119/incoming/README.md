# Focused incoming-branch validation

These checks freshly exercise the integrated desktop/PDF and VBA work while the
mail restore increment is developed. They use the repository-pinned Flutter
3.47.8 / Dart 3.13.7 runtime and existing resolved lockfile. GitHub Actions are
neither queried nor awaited.

## Results

**564 distinct tests passed, zero failed, zero skipped, across 30 test files.**
All **13 commands** passed: four test cohorts, four JavaScript compilation/run
pairs, and one macOS build-script syntax check. Command gates are separate from
the test count. Every final phase began at the formatted product checkpoint
`358544a48466c942873a4718a87fa9d1c2be11f7`. The final evidence verification
replayed the raw reporter output and matched the qualified product/test inputs
against the current checkout, as well as the dependency inventory, SDK
executables and packaged SQLite library.

| Fresh cohort | Passed | Files |
| --- | ---: | ---: |
| Engine macro/VBA, procedures and bounded control flow | 269 | 13 |
| Incoming engine branding, ODS/revision fidelity and structural atomicity | 216 | 8 |
| Editor PDF save/surface and Review controller/dialog | 52 | 4 |
| Studio desktop menus, ribbon preferences/customization, File lifecycle and workspace | 27 | 5 |
| **Total** | **564** | **30** |

The four genuine JavaScript builds execute in Node and require their exact
assertion-bearing JSON outputs: basic macros, VBA, reusable procedures and
bounded control flow. The latter includes cold nested procedure/block/expression
depth cases. The `bash -n` command validates the macOS build script's shell
syntax; Linux does not qualify AppKit, an installed macOS bundle, or signing.

See [summary.json](summary.json), [engine receipt](engine/receipt.json),
[editor receipt](editor/receipt.json), and [Studio receipt](studio/receipt.json).
Every command directory contains its exact arguments, working directory,
timeout, raw stdout/stderr, hashes, results, and compressed before/after source
inventories. Test cohorts additionally retain individual machine-reporter cases.
Case keys include the test file, platform and full name; totals count each once.

## Source binding and retained attempts

Each successful command's relevant source hashes agree before and after
execution. Runtime receipts, resolved package configuration and the physical
dependency inventory also remain stable within each phase. The final summary
checks these bindings against the current product and test files. Each phase
preserves its executed harness. The final phases all use the same corrected
offline launcher; the earlier editor harness remains with its superseded run.

Engine CLI tests also use the committed example macro fixtures. Their
[supplementary inventory](engine/additional-example-inputs.json) records SHA-256
values before execution and verifies equality to the phase's starting commit.
The final runner includes them in every per-command source inventory.

Earlier attempts remain separate and contribute no duplicate counts:

- `attempts/01-implicit-dart-test-resolution/`: the `dart test` launcher entered
  implicit dependency resolution and the execution service reported cancelled
  network approval before any test-reporter output. It supplies no test results.
  The accepted native run invokes the pinned `test/bin/test.dart` entry point
  with the explicit existing package configuration, without dependency resolution.
- `attempts/02-studio-before-timestamp-presentation/`: an initial successful
  27-case Studio run preceded the final Arabic timestamp presentation change.
  The final Studio phase reruns exactly those five test files against the final
  shared source. Only that final run contributes these 27 cases.
- `attempts/03-before-required-formatting/`: all previously successful phases
  were retained when the final mail gate found eight pre-existing incoming
  branding/sample sources requiring Dart formatting. The affected incoming
  engine, editor and Studio phases were rerun against the formatted source;
  no cases from this prior source are added to the final totals.

The independent engine/editor phases run while unrelated mail files may change.
Their per-command source manifests, rather than a claim that the entire working
tree was frozen, identify the checked inputs. Final publication must retain the
relevant product/test hashes or qualify a later change.

## Reproduction

The [evidence verifier](verify_incoming.py) replays raw reporter counts, checks
file coverage and uniqueness, verifies every log hash, and compares current
source/dependency/runtime identities with the retained records. Its successful
output is preserved in [verification.log](verification.log).

The [runner](run_incoming.py) records the complete command arrays in each
`command.json`. With the verified runtime environment sourced, those arrays can
be executed from their recorded working directories. The three harness phases
are `engine`, `editor`, and `studio`; a phase requires a fresh evidence directory
and refuses to replace an existing one. Production manifests, dependency locks,
SDK source and native-library mappings are not changed by the runner.

This focused coverage complements the mail restore acceptance. It is not a
full-repository, live-provider, browser-UI, or installed-platform qualification.
