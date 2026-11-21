# Independent review support files

These are the actual review programs and accepted results for the combined
checkpoint `5289b90a83ce9042a4f4cfb73ba8115fe501513a`.

- `audit_combined_runtime.py` independently reads the fixed supplemental raw
  streams and source maps. `audit_qualification.py` is its unchanged, hashed
  raw-event parser from the earlier independent review. Neither launches tests.
- `parse_directives.dart` uses analyzer 13.3.0 to extract real Dart AST directives,
  including all conditional alternatives and decoded URI literals.
- `ast-directives.jsonl.gz` retains the complete accepted parser output for
  2,532 unique committed blobs, without embedding their source text. The
  decompressed output hash is recorded in `impact-ast-review.json`.
- `ast-language-versions.json` records the repository package language modes
  used by the parser and the source package-configuration hash.
- `audit_impact_ast.py` resolves the parsed directives against immutable Git
  trees and independently compares all 119 selected dependency closures.
- `impact-ast-review.json` and `combined-runtime-review.json` retain the complete
  accepted independent reports. The enclosing final review records the bridge
  between these results and the original qualification.

The programs preserve the actual absolute workspace paths used for review.
Replaying them requires the recorded workspace/runtime layout or deliberate
path relocation. The repository's portable evidence verifier does not require
that layout. Restore the archived raw and source-map files to their recorded
locations, and decompress `ast-directives.jsonl.gz` to the review directory's
`directive-ast.jsonl` before replaying the AST graph audit. Source text for a
fresh AST parse is reproducible from the two named Git trees, the recorded
language-mode table and `rebuild_ast_inputs.py`; it is not duplicated here.

The source audit is not a new Dart test execution. External package source is
not traversed, and recorded environment equality does not claim an exhaustive
hash of every extracted dependency byte.
