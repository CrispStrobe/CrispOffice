# First frozen host attempt — retained failure record

The first host qualification ran at `4681760c542eb2a3473b72605ebb7606e0e7b4a3`
against captured main `be641457c8c7d1acc25091b31c87c73eaa3c9c2a`.
It is **not** an accepted final qualification.

The main run completed 920 passing and 59 failing cases across 56 suites.
All 59 failures were pending default proofing request timers at teardown in
three Studio comment suites (14 draft-proofing, 8 keyboard-review and 37
comment-review cases). Their setup opened Settings before installing the
existing controlled proofing service. Settings pumps crossed the initial
proofing debounce. The correction installs the same controlled provider
before opening Settings, without changing product code, test assertions or
provider semantics.

The five Node suites independently completed 306 passing cases with no
failures or skips. These are repeated scenarios, not additional distinct
product cases. Strict analysis reported two infos: export ordering and an
unnecessary interpolation brace. Formatting and whitespace checks passed.
Source and runtime inventories were unchanged during each run.

The [archive](first-attempt-evidence.tar.xz) and
[index](first-attempt-evidence.index.json) preserve raw events, per-case
results, diagnostics, receipts and both before/after inventories. Archive:
851,508 bytes; SHA-256
`2ab660cc80fcb9a709323f731f57bc45bf8a3e9aefb84f7a95851ea67cd7adbf`.
The later accepted run must use a separate output directory and its own
frozen source identity. No first-attempt pass count is added to that run.
