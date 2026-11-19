# Dynamic-array offline execution assessment

**No VBA tests were executed.** This assessment stops at a concrete dependency-graph blocker, without network attempts, fake dependencies, or production changes.

The new `office_vba_dynamic_arrays_test.dart` imports the automation barrel. Replacing that test import with direct production imports would not isolate the compiler: `office_vba_language.dart` itself imports `office_operations.dart`, and the shared operation library resolves the following dependencies.

| Unavailable compatible package | Production dependency path |
| --- | --- |
| `characters` (`^1.4.1`) | `office_vba_language.dart` → `office_operations.dart` → `word_deserializer.dart` → `word_proofing_language.dart` → `office_proofing.dart` |
| `image` (`^4.5.0`) | `office_vba_language.dart` → `office_operations.dart` → `operations/inspect_word.dart` → `quds_office_engine.dart` → `pdf_image.dart` |
| `archive` (`^4.6.0`, required by `legacy_doc_parser`) | `office_vba_language.dart` → `office_operations.dart` → `operations/inspect_word.dart` → `quds_office_engine.dart` → `legacy_word_conversion.dart` → `legacy_doc_parser.dart` → `legacy_word_metafile.dart` |

`characters` and `image` are absent from the workspace package cache. Only archive 3.6.1 is cached; it does not satisfy the legacy parser's ^4.6.0 constraint. Crypto 3.0.7 is available in the legitimate earlier offline harness, but it cannot resolve these other dependencies.

Dart import `show` clauses limit visible names, not the resolution of the imported library and its transitive imports. Substituting an enum, package, operation implementation, or source-edited compiler would not validate the actual production graph and was not attempted.

The inspected direct compiler graph contains 384 local sources; the automation barrel graph contains 387. `inspect_graph.py` reproduces the read-only import/export walk. `receipt.json` preserves exact paths, cached package availability, source SHA-256s, the four requested test paths, and zero executed tests.

The previously passing mail-source qualification is unaffected by this graph assessment. Full VBA unit/integration execution remains pending a legitimate compatible dependency resolution.
