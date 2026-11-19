# Initial diagnostic fixture run

The first executed run had 13 passing cases and two failures because the independent test fixture omitted `verbose: true` on archive diagnostics. Non-error events are intentionally suppressed by default, so its completion callback never requested cancellation. Only the two fixture options were corrected; no product fix was needed. Raw logs, receipt, before/after source hashes, and the exact executed test file are retained here. These case counts are not included in the accepted run.
