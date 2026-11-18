# Focused Office merge controls

The ten incoming Office source/test files match merge `ec4aeefe1be6ce1868ee7eebf004c07b25d4108a` (tree `586035a32d59d3b255d3c30c20203e559e0b5522`) and remain byte-identical before and after these local tests. The workspace lock also remains unchanged.

The four engine test files pass **214 tests**, and the Studio example widget file passes **2 tests**. Commands use the pinned restored SDK, `--no-pub` and `--concurrency=1`. No GitHub Actions endpoints were queried or awaited.

The initial [receipt](receipt.json) and logs retain a setup failure before any test ran: the sandbox does not expose the default `/tmp` directory. The [successful retry](task-temp-retry/receipt.json) sets `TMPDIR` to a task-owned writable directory. No Office source fix was made. Both exact runner versions are retained and authenticated by their receipts. [Summary](summary.json) links the attempts and records the qualified counts.

This is focused regression evidence for the incoming Office fixes; it does not qualify the separate W6 grammar planner.
