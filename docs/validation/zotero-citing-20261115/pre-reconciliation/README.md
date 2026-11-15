# Pre-reconciliation qualification

This receipt belongs to canonical source `706971b6818d5382e135ea947ce862b27124a46a`, before the concurrent main/branch integration. All 513 selected tests passed (380 engine, 117 editor, 16 Studio), and editor/Studio strict analysis passed. The overall qualification correctly failed because `word_zotero.dart` still had one curly-brace analyzer info and formatter differences. The incoming main already corrected those issues.

The source and harness fingerprints were unchanged during this run. This directory is retained as an intermediate receipt; its counts overlap and are not added to the later final qualification. See [the final evidence](../final/receipt.json) for the reconciled source.
