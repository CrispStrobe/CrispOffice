# Word and Studio author verification

This archive preserves all twelve focused author runs, including failed and interrupted attempts. It is separate from final combined qualification.

The completed final author checks passed 41 engine VM executions (28 routing/cascade and 13 inherited-language cases), 28 portable Node executions, and all 62 comment-suite executions. The earlier editor run passed 37 cases at the initial Word repair. The initial eight-suite Studio run also records its 31 passes and 60 failures; its stale default assumptions are retained as failures, not accepted wholesale.

The marker regression first produced two failures and six passing controls: a direct empty `rtl` or `cs` marker incorrectly retained an inherited `val="0"`. The narrow repair extends the existing default-on merge treatment to those markers and passes every combination before and after DOCX save/reopen.

The Studio helper sequence is retained honestly. The original tests assumed visible comments. The first helper tried an offscreen lazy ribbon item and failed. The Settings helper exposed pending real-provider timers because it advanced animation time before disabling default proofing. That run was interrupted after the issue was established (exit 130). The final helper disables live proofing first, enables **Settings → Show comments**, then installs the suite's existing fixture provider. All 62 comment cases pass.

`receipt.json` lists every run, count, terminal record and raw-output hash. Historical helper source snapshots were reconstructed and checked against the manifests recorded before execution. All 18 final reviewed Dart paths equal the consolidated local source `21d979590ea902ad0593c38c816808cbb7134f6b`. Local author checkpoints and raw snapshots provide development provenance; the final frozen driver establishes whole-source/runtime acceptance.

No counts across repeated runs are claimed as distinct scenarios. No actual browser or additional operating-system execution is inferred. No GitHub Actions workflow or status was queried or awaited.
