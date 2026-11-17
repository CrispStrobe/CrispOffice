# Continued local qualification — 17 November 2026

This checkpoint preserves the first fresh preflight at canonical source
`b32dee6f1fb6993c928a466b553226209cf27fb8` and its formatting correction.
**No product tests ran in this attempt. Full qualification awaits a new frozen
commit containing the four formatted tests.**

The selected scope is 174 unique test files: 19 engine Zotero, 13 editor Zotero,
91 engine integration, 37 editor integration, three Harper contracts and 11
GECToR contracts. All four strict analysis commands passed. Formatting then
identified four changed test files and stopped the run. All six before/after
input maps were unchanged, the source remained at its frozen commit, and the
analyzer configuration was restored.

Only `odp_presentation_writer_test.dart`, `odt_document_writer_test.dart`,
`odt_section_continuation_test.dart` and `odt_section_fidelity_test.dart` were
formatted. The official Dart formatter used the same resolved dependency graph
and explicit language version 3.12. Genuine analyzer parser output is identical
before and after for each file. Every token type and lexeme is also identical
except nine optional trailing commas inserted immediately before closing
parentheses. The initial verifier's stricter literal-token rejection is retained
alongside the final AST/token accounting. Production code was not edited.

The read-back-verified archive includes the failed attempt, source/dependency/
runtime/workspace/system/harness snapshots, raw compressed logs, exact executed
setup and qualification scripts, formatter/token/parser outputs and correction
receipts. The adjacent index binds every archive member by size and SHA-256.
Generated lexical and morphology data were preserved byte-for-byte against
their committed manifests; generator-owned encoded-literal indentation is
explicitly outside the handwritten formatting scope.

The isolated canonical workspace resolved 109 packages offline with the
unchanged pinned lock `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
Dart and Flutter tester executable hashes match the earlier runtime record.
The actual locally generated Flutter-tool snapshot is separately hash-bound.
No GitHub Actions or CI-status endpoint was queried or awaited.
