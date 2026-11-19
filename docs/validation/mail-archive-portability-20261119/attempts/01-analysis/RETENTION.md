# Evidence retention

Receipts, commands, results, the executed harness, selected plan, input manifests and per-test records are retained unchanged. Raw stdout/stderr logs are stored with deterministic gzip compression; their recorded hashes apply to the decompressed bytes. `retention.json` maps every original file to its retained form and records hashes for omitted generated build products.

Compiled fixture libraries and JavaScript outputs are reproducible from the frozen source and retained command arguments. They remain in the local run directory but are not duplicated in Git. No earlier or failed run contributes to a later successful test total.
