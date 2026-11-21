## Unreleased

- Declare the Hunspell provider's spelling-only `categories` so Word can check
  completed words without invoking grammar providers.

- Honor cancellation requested by the final download-progress callback before
  committing a dictionary installation on native and web hosts.

## 0.1.0

- Initial optional Hunspell spelling backend: MIT adapter over unmodified
  Hunspell 1.7.2 (MPL 1.1 option), native isolate and bundled WebAssembly
  worker, pinned user-downloaded AyaSpell Arabic dictionary.
- Native disposal now waits for dictionary closure after an active call;
  repeated disposal shares cleanup, and failed replacement cannot reuse a
  freed handle. Added native-finalizer fallback and eight deterministic
  FFI/isolate lifecycle regressions.
