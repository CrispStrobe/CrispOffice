# Final source qualification

The accepted source is `cf60a17bcd825dc9b4ecdf840d54e6a0271d3647`, tree
`4a1a29d5029d25da9700b56a1fd244f3f5679547`. `summary.json` reports 353 VM
passes across 18 files and 236 JavaScript/Node repetitions across ten files.
All strict gates and unchanged-input guards passed with zero failures, errors,
or skips. Both platforms execute all 89 new regression cases.

`final-qualification.tar.xz` contains 49 files: both original final receipts,
gzip-compressed raw command streams and runtime inventories, exact version
outputs, a summary, and copies of both harness sources. Its SHA-256 is
`15fef1f2385e1ac1473eea21aee65704e152db20e012b334ae0acaab1b226b26`.
`final-qualification-index.json` binds the exact file set, sizes, and hashes;
restoration and comparison passed before publication.

## Inspect or reconstruct evidence

Verify the archive SHA-256, extract into a fresh directory, and compare every
restored member with the index. Each receipt names its selected tests, exact
commands, command exit codes, raw-event summaries, runtime metadata, and source
hashes before/after. Runtime inventories include the selected SDK/artifact and
activated dependency files; they are hash inventories, not bundled SDK binaries.

The top-level `check_review.py` independently restores indexed archives and
reconstructs raw events. Its complete input audit additionally needs the recorded
runtime/source files and package mappings at their recorded paths. Another
environment can verify archive integrity directly, or perform a new qualification
with its own accurately recorded runtime; it should not relabel these receipts.

## Reproduce tests

Use a separate checkout of the exact accepted source, the preserved lock at
`docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock`,
and the recorded Flutter 3.47.8 / Dart 3.13.7 / Node 24.22.1 runtime. The driver
uses the explicitly configured runtime location and rejects a different source
HEAD or lock. The runtime restoration receipt identifies the one missing locked
package restored from its checksum-verified official archive.

Run the repository harness, whose relative paths target that checkout:

```sh
python docs/validation/office-fidelity-lists-sections-20261117/run_qualification.py \
  odt-vm --source cf60a17bcd825dc9b4ecdf840d54e6a0271d3647
python docs/validation/office-fidelity-lists-sections-20261117/run_qualification.py \
  odt-node --source cf60a17bcd825dc9b4ecdf840d54e6a0271d3647
```

Each output directory must be fresh. The archived harness copies document the
exact executed bytes; run their repository versions rather than relocating the
copies and relying on invalid relative paths. No GitHub Actions, checks, or
commit-status endpoints are required or queried.

## Exact historical source objects

`local-source-checkpoints.bundle` preserves the exact commits used by the
incoming correction (`56dc162b`), extraction correction (`fa9821a7`), and
pre-publication consumer attempt (`59b8d494`). The latter has the same tree as
published `4fdac35c`. Its adjacent JSON records the bundle SHA-256, named refs,
and prerequisite commits. Bundle verification passed, and every prerequisite
is in the published final-source ancestry.

From a clone containing the published branch, import these historical objects
without changing the current checkout:

```sh
git bundle verify docs/validation/office-fidelity-lists-sections-20261117/qualification-evidence/local-source-checkpoints.bundle
git fetch docs/validation/office-fidelity-lists-sections-20261117/qualification-evidence/local-source-checkpoints.bundle \
  'refs/validation/office-fidelity-lists-sections/*:refs/validation/office-fidelity-lists-sections/*'
```

This makes the historical Git IDs used by the independent scoped-source
comparison available exactly. Source patches in the individual archives remain
useful for reviewing the changes without importing Git objects.

Incoming integration tests, the isolated extraction-correction qualification,
historical failures, and consumer-checker controls remain separate from these
final-source totals. Node executions repeat selected VM cases.
