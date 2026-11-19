# Retained local validation evidence

Command stdout/stderr logs are gzip-compressed without changing their bytes.
Hashes in result/receipt files refer to the decompressed original logs.
Compiled fixture libraries and emitted JavaScript are reproducible from the
recorded sources/runtime and are identified by hash rather than copied here.
The full command, original runner, input manifests and case-level results are
retained. Counts belong only to this attempt.
