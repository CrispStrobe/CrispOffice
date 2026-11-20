# Main refresh conflict acceptance

Qualified local merge source: `233b506e341bc2e299e7e1021910a94858eb9e35`.
Tree: `e7c3f5520342e8a28ad44cd160afd56670e5fc99`.
Parents: `191605e3cc06d5ac2efbb2d9f60b6b2bd07d7903` and `e06eb3a7e21b71c1d5d4b1d2cc9abde24774eb26`.

The isolated merge retains the latest Word changes and combines the competing
background-gradient implementations using separate selected-gradient ownership.
The only resolved files are `slide_serial.dart` and
`slide_import_fidelity_test.dart`. The new incoming single-gradient replacement
case is retained; the identical shape-gradient case is included once.

## Acceptance

- **53 distinct engine cases passed**, zero failures, errors or skips, across
  `slide_import_fidelity_test.dart` and `slide_gradient_merge_test.dart`.
- Strict analysis of both resolved Dart files passed with no findings.
- Strict format verification passed with zero changes.
- Selected input hashes remained unchanged during both runs, and tracked package
  files remained clean against the qualified source commit.
- All **86** incoming Word/bidi/editor-Word/controller files are
  byte-identical to captured main; all **79** selected prior
  PPTX model/parser/PDF/editor paint files are byte-identical to the previously
  qualified Mail checkpoint. `preservation.json` records both Git blob IDs per
  file. No broader validation claim is inferred from that comparison.

`engine-0.jsonl` retains the raw test protocol. The receipts retain exact
commands, source parents/tree, elapsed time, input hashes and outcome counters.
Static stdout and stderr are retained alongside their receipt. These checks ran
locally with the same pinned Flutter/Dart SDK used by `../incoming-office/`.
No GitHub Actions queue was queried or awaited.

To repeat after preparing the pinned SDK and resolving the existing lockfile:

```sh
python docs/validation/mail-draft-recovery-20261120/main-refresh/run_validation.py engine
python docs/validation/mail-draft-recovery-20261120/main-refresh/run_validation.py static
```

These results belong to the source commit above. A subsequent API-created
remote merge may have different parents or additional Mail changes; retain this
provenance and record the source equivalence rather than relabeling the run.
