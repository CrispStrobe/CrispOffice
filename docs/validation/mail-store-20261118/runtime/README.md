# Mail store runtime and dependency qualification

The pinned official Flutter 3.47.8 archive was downloaded and verified against
SHA-256 `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
Its original Git metadata identifies framework revision
`737ba8f885dc774b53b442759999a312c9461e4e`; the bundled Dart executable reports
3.13.7 stable. The archive's required compiler, framework, Linux x64 engine,
and web SDK members were retained. Optional platform assets, symbol files,
sanitizer runtimes and the DevTools web UI were omitted to fit the executor
filesystem. The original sources, package constraints and version records were
not edited. The initial disk-exhausted extraction and a missing optional archive
member are disclosed in [receipt.json](receipt.json).

`dart pub get --enforce-lockfile --example` resolved the Flutter tool's original
pinned dependencies. Ordinary root `dart pub get` added the Mail Store dependencies,
then `dart pub get --enforce-lockfile` succeeded. The
[dependency comparison](dependency-diff.json) confirms that **no existing package
version changed or disappeared**. The eight new dependencies include Drift,
sqlite3 and its native build tooling. The new direct `web` dependency uses the
version already locked by the workspace.

The sqlite3 3.9.1 package's default native-assets hook downloaded and verified
its Linux x64 SQLite binary. It reports **SQLite 3.54.1**, SHA-256
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.
The isolated setup smoke creates an FTS5 table and successfully searches an
inserted row; it is preparation evidence and is not counted as a Mail Store
regression test. No system SQLite override, SQLCipher, or MultipleCiphers
alternative was configured.

The complete package dependency closure and original license hashes are in
[DEPENDENCIES.json](../../../../packages/quds_mail_store/DEPENDENCIES.json).
[THIRD_PARTY_NOTICES.md](../../../../packages/quds_mail_store/THIRD_PARTY_NOTICES.md)
retains the 27 hosted-package notices. This includes build-hook dependencies;
it does not claim that every listed package is part of a shipped runtime.
Product-specific host, Flutter and asset notices remain the host's obligation.

The [platform receipt](platform-validation.json) records **7 native platform tests**,
**4 portable configuration tests** on both VM and Node, **3 JavaScript error-mapping
tests** on Node, and separate compiler checks. The native cases include a real child
process terminated with SIGKILL: the exclusive owner lease is released and its
committed account survives reopening. A migration failure initially lost its
quota classification inside nested Drift remote exceptions. Both failed runs
are retained; bounded typed unwrapping fixes the error without parsing exception
messages. All seven native cases then pass. The multi-host fixture intentionally
opens two distinct database files concurrently; Drift emits its generic debug
warning about multiple database instances, even though their executors and
containers are separate. No warning suppression was added.

One Chromium 156 launch was attempted in this fresh workspace. It aborted before
rendering, with `process_singleton_posix.cc: socket() failed: Operation not permitted`.
The [exact launch receipt](chromium-smoke.json) retains the command, empty stdout,
fatal stderr and return code. No further launch attempts were made. Browser worker
and public entry compilation use the exact pinned dependencies. **Actual
browser persistence and Web Locks execution remain unqualified.** A successful
JavaScript compile or Node policy test is not a browser durability result.
Hosts must verify and serve the pinned SQLite Wasm artifact and the compiled
worker themselves from the application's origin, then qualify browser quotas,
reloads, tab contention and recovery. The expected Wasm hash is recorded; the
Wasm artifact was not downloaded or executed during this checkpoint.

No GitHub Actions workflow, job, or check status was queried or awaited.
