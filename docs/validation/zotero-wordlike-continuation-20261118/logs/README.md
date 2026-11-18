# Local execution logs

Final successful gates are plain text: `final-engine.log`, `release-editor.log`, `release-studio.log`, `release-analysis.log`, and `release-format.log`.

Some earlier failure logs and the note-fixture repair patch contain significant whitespace emitted by Flutter or unified diff. They are preserved byte-for-byte in `.gz` files. Expand those files with `gzip -dk FILE.gz` to obtain the original filename and exact bytes. The accompanying JSON receipts refer to those original names and hashes. `compressed-log-index.json` maps the originals to their stored paths and records both checksums.

Logs whose names begin with `root-document-actions` include intermediate fixture construction attempts. Logs beginning with `final-` include the first broad gate before follow-up repairs; only `final-engine.log` supplies an accepted gate result. `accepted-` records the merged-review gate before the inherited-language test correction. `release-` records the final editor/Studio/analysis/format gates at `d82d25cc`.

Baseline note failures were reproduced at `b2597485`, not inferred from the feature checkout. The baseline and repair JSON receipts document the isolated workspace package roots and unchanged behavior assertions.
