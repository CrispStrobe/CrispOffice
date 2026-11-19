## 0.1.0

- Initial optional Arabic morphology backend: `CamelArabicMorphology`
  (`ArabicMorphology`) over the native Camel Morph analyzer (CrispEmbed
  `8e40ad88`, MIT port of camel_tools 1.6.0; Ryu Apache-2.0) in a persistent
  FFI isolate or a bundled WebAssembly worker, with the pinned,
  user-downloaded Camel Morph MSA v1.0 `noprob` database (CC BY 4.0).
