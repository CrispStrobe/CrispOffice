## 0.3.0

- Context disambiguation: `CamelArabicMorphology` implements the engine's
  `ArabicContextMorphology` when the optional context model
  (`camelMorphMsaDisambig`, Hugging Face `cstr/camel-morph-msa-disambig@07fd9e65`,
  4.5 MB, CC BY-SA 4.0) is loaded (`disambiguator:` or `loadDisambiguator`).
  `disambiguate` returns per token every analysis with its candidate's rank
  and probability in context (CrispEmbed ABI 3,
  `crispembed_ar_morph_disambiguate`), batched and cached per sentence.
- On UD Arabic-PUD the best reading's UPOS is right for 77.9% of tokens
  (all analyses unranked: 47.0%; the PATB-trained `full` ranking: 77.9%).
- Adapter version 2 adds `quds_arabic_morph_enable_disambiguation` (the
  CrispEmbed disambiguator is default-off); the worker protocol gains
  `open_model` and `disambiguate`. `MorphInstaller.removeOtherBundles` takes
  `alsoKeep`. `tool/pud_rule_findings.dart` gains `--model`, `--reading` and
  `--margin`; `tool/web_smoke.mjs` an optional model check.

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
