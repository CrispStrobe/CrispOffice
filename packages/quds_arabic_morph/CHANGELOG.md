## 0.2.0

- Switch to the `proofing-bin` bundle (`camelMorphMsaProofingBin`, Hugging
  Face `d5364e04`, 12 MB). It is the noprob database in CrispEmbed's
  memory-mapped binary format, reduced to the 24 proofing features, with
  analyses and those values exact against camel_tools. Studio removes
  installs of the earlier `noprob` bundle (`MorphInstaller.removeOtherBundles`).
- Use CrispEmbed's compact batch ABI (ABI 2) in the FFI isolate and the Web
  Worker instead of per-word JSON. Results are cached as compact per-word
  records with lazily read maps (`CompactAnalysisDecoder`), and repeated
  analyses are dropped.
- Load: about 0.2 s instead of 1.2–2.5 s. Native process RSS after load:
  30 MB instead of 230–250 MB. Wasm heap: 16–19 MB instead of 320 MB.
  Throughput through Dart is 2–3.7× higher (see README).
- `tool/pud_rule_findings.dart` compares rule findings between backends.

## 0.1.0

- Initial optional Arabic morphology backend: `CamelArabicMorphology`
  (`ArabicMorphology`) over the native Camel Morph analyzer (CrispEmbed
  `8e40ad88`, MIT port of camel_tools 1.6.0; Ryu Apache-2.0) in a persistent
  FFI isolate or a bundled WebAssembly worker, with the pinned,
  user-downloaded Camel Morph MSA v1.0 `noprob` database (CC BY 4.0).
