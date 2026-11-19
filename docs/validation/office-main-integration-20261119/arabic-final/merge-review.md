# Arabic runtime continuation

Main `f7117a493055008a72e6e16713dd67a4f7c2ad39` merged PR #180 after the
previous application qualification was published. Its source adds independently
authored Arabic writing rules, exports the provider, registers it in the default
Word proofing controller and workspace example, and adds engine/editor tests.
This checkpoint merges that work with publication `5ec15bdd` and preserves all
Mail/TLS/bundle controls and retained reports.

The earlier 632-execution / 562-distinct-case run remains bound to `ac1e4c8c`.
It is preserved under `socket-final/` and `pre-arabic-report.md`. The changed
engine export and proofing registration mean its full source inventory and the
older Office tracked-import closures cannot be described as unchanged on this
new source. A fresh full core/store gate and expanded focused gate will bind
to the new frozen source, including Arabic and existing proofing regressions.
No pending execution is counted as passing. Original 2018/208-case and web-build
records retain their historical source identities.

No GitHub Actions are queried, dispatched or awaited. Actual browser, installed
Studio/OS IME, live Zotero/external Office or mail-service interoperability, and
independent linguistic acceptance remain separate.
