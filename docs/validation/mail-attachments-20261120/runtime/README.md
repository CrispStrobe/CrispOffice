# Recovered pinned local runtime

The fresh mail/Office checks use Flutter **3.47.8**, Dart **3.13.7** and Node
**24.22.3**. `runtime.json` records exact binaries and versions;
`pub-cache-receipt.json` records **194** verified hosted dependency archives.
The official Flutter archive SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.

Offline `pub get --enforce-lockfile` succeeded on the repository's original
lockfile, SHA-256
`b71c74cada904d0a3fac7d057b7c718011c50d2e108b6cfd0390566f8abab202`.
No package version was upgraded for qualification. The normal SQLite 3.54.1
native package hook supplied FTS5; the binary SHA-256 is
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.
The details and native readiness checks are in `readiness-receipt.json`.

`bootstrap_runtime.py`, `verify_native_readiness.py`, `env.sh` and the adjacent
logs retain setup and checking commands. Paths in these records identify the
original execution environment; consumers should select their own pinned SDK
and cache paths. Acceptance receipts separately fingerprint actual runtime,
dependency, workspace and source files before and after execution.

This recovery resolves the earlier handoff's dependency gap for the executed
local scopes. It does not imply that every workspace suite, installed platform,
native model or live mail provider was exercised. No GitHub CI result was used.
