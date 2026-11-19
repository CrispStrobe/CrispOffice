# Expanded main delta qualification

This second plan version integrates incoming main
`b559f6c764fbfac143f593e89ddc1096ad8b5c4e` while retaining the original qualification
and rejected first delta under their original source identities. The **1,372
application executions / 90 Python controls at `0669ac11`** and the **rejected
159 visible successes / 17 controls at `aea5d91a`** contribute zero to this gate.

Copy the plans, driver, verifier, fixture plan, and reviewed-source override file
to `docs/validation/office-main-sync-20261119/main-delta-v2/`. Complete the exact
override hashes after applying the reviewed Arabic/Studio patches and formatting
changed Dart files. The verifier rejects a pending override receipt. Preserve the
older `main-delta/` files and evidence unchanged.

The current selection is **24 native suite/platform executions**, **6 Node
suite/platform executions**, **53 strict Dart analysis/format targets**, the
**17 verbose AyaSpell bundle controls**, and browser transport compilation.
The source-freeze guard additionally checks that every Dart path changed from
either `0669ac11` or `b559f6c7` appears in both strict target lists; add any new
reviewed test helper before freezing if necessary.

Native tests include the complete real-library/dictionary/install/live-download
file, the compiled lifecycle-counter tests and portable provider tests. Arabic
writing, extension and range suites run on VM and Node, with Word integration on
Flutter. The thirteen Studio suites cover the renamed workspace, compact and sheet
navigation, PDF gallery/sample/font/export behavior, the Mail dialog, and renamed-selector consumers in the Zotero/review workflows.

Continuity accepts the exact incoming Studio implementation/assets changes and
the **36 exact retired sample/source deletions**. Four reviewed Arabic source/test
files and any Studio corrections require exact immutable incoming and resulting
SHA-256 identities in `reviewed-source-overrides.json`. All other existing
application changes must equal incoming main. The five Mail cursor repair paths
remain subject to exact prior-source preservation by the independent auditor.

The original 131 package mappings remain byte-identical and only the Hunspell
workspace mapping is added. The only allowed existing dependency graph change is
the Studio node gaining `quds_mail_core`, `quds_mail_mime`, and `quds_mail_ui`.
The lockfile and original runtime bootstrap receipt remain unchanged; the current
132-package workspace receives its own explicit receipt.

The three upstream license files stay exact. Whitespace is checked against
`b559f6c7`, so no exemptions or changes to the shared runner are needed. The
macOS entitlement check is static; neither that check nor the browser compile
claims a macOS launch or real WebAssembly worker execution.

```bash
python3 docs/validation/office-main-sync-20261119/main-delta-v2/run-delta-validation.py \
  --repo /workspace/scratch/79e6ad9e4046/quds_office_suite \
  --head NEW_COMMITTED_SOURCE \
  --runtime /workspace/scratch/79e6ad9e4046/quds-runtime \
  --fixture-root /workspace/scratch/79e6ad9e4046/hunspell-review \
  --pre-resolution /workspace/scratch/79e6ad9e4046/main-delta/pre-resolution \
  --prior-gate /workspace/scratch/79e6ad9e4046/final-integration-checks \
  --prior-audit /workspace/scratch/79e6ad9e4046/audit-review/final-0669ac11-accepted/independent-summary.json \
  --output /workspace/scratch/79e6ad9e4046/main-delta/v2-final-checks \
  --command-timeout 600
```

## Original paths and fresh replay

The command above names the recorded checkout and runtime layout. Archived
commands, package mappings, runtime receipts and fixture-build receipts preserve
their original absolute paths. The continuity check is deliberately exact; those
old receipts are not generically relocatable, and changing their path strings
would invalidate their identities.

For a fresh replay at another layout, first check out `0669ac11` at the new target
checkout, restore its pinned runtime there, run and independently audit that
baseline, and preserve the new baseline package configuration/graph before
advancing the same checkout to this integrated source. Supply those newly
generated baseline and pre-resolution receipts to the delta command. This yields
a separate replay with its own timestamps and hashes; it does not rewrite or
relabel the published original run. The thirteen frozen native fixture files,
including both shared libraries, all eight dictionary files and three provenance
receipts, are packaged for verified retrieval. Their original provenance records
stay unchanged even when their checked bytes are materialized under a different
`--fixture-root`.

Example reviewed override entry:

```json
{
  "prior_qualified_source": "0669ac119da05f5eb777c8cfdbce32e0261df647",
  "incoming_main_source": "b559f6c764fbfac143f593e89ddc1096ad8b5c4e",
  "status": "REVIEWED",
  "paths": [
    {
      "path": "packages/quds_office_engine/lib/src/proofing/arabic_writing_rules.dart",
      "incoming_sha256": "EXACT_B559_BLOB_SHA256",
      "after_sha256": "EXACT_REVIEWED_MERGE_SHA256",
      "reason": "Preserve both prior Unicode safeguards and incoming T1 rules."
    }
  ]
}
```

For a newly added regression file absent from `b559`, omit `incoming_sha256`.
The override verifier permits only specific recorded `.dart`, `.yaml` and `.md`
files within the engine or Studio example; it does not exempt a directory.
