## 0.1.0

- Initial bundled language identifier: `Cld3LanguageIdentifier`
  (`LanguageIdentifier`) over CrispASR's CLD3 runtime (`crisp_lid`
  `19d86f9b`, MIT, compiled unchanged with a bounded GGUF shim instead of
  ggml) in a persistent FFI isolate or a WebAssembly worker, with the
  pinned, bundled `cld3-f16.gguf` (Apache-2.0, Google).
