# Arabic proofing roadmap

Accepted: 19 November 2026. Scope: Arabic spelling first, then grammar rules,
then optional model-backed analysis. Nothing here is enabled by default yet.

## Constraints

- **The app binary carries only our own MIT/MPL code** and components under
  App-Store-compatible licences (MIT, BSD, Apache-2.0, MPL, CC-BY). GPL code is
  never compiled into the app, including as an embedded WebAssembly module.
- **Language resources are not shipped in the app.** They are published by us on
  Hugging Face or GitHub under their own licences, with their notices and
  sources. The user downloads them from inside the app (the same pattern as the
  existing model downloads).
- **Downloaded resources are data**: dictionaries, rule files and GGUF weights
  interpreted by our engines. App Store guideline 2.5.2 forbids downloading
  executable code that changes app functionality, so no downloaded native or
  WebAssembly code is planned. If a resource ever truly needs downloaded logic,
  the only fallback considered is WebAssembly executed inside a WebView
  (WebKit/JavaScriptCore, the sanctioned route under guideline 4.7), with an
  explanation in the review notes. No Python runtime, in any form.
- **No paid data.** Resources whose terms forbid redistribution or restrict use
  to research cannot be published by us, regardless of who downloads them.

## Resource assessment

| Resource | Licence | Status for Quds |
|---|---|---|
| AyaSpell Hunspell dictionary (`ar.aff`/`ar.dic`, LibreOffice packaging 3.5) | GPL 2.0 / LGPL 2.1 / MPL 1.1 tri-licence ("or later") | **Usable.** We elect MPL 1.1 and publish it as a downloadable dictionary. Step 1. |
| AyaSpell Arabic thesaurus (`th_ar.dat`, MyThes) | Same package and tri-licence | Usable; published alongside, integration belongs to the [thesaurus roadmap](thesaurus/README.md). |
| Hunspell engine 1.7.x | GPL / LGPL / MPL 1.1 tri-licence | **Usable in the app under MPL 1.1** (file-level copyleft, App-Store compatible); native library, plus a WebAssembly build for the web target that is part of the app, not downloaded. |
| LanguageTool Arabic module (~450 XML rules, 16 Java rules) | Code LGPL 2.1; rule resources need per-file verification | Rule XML could be downloaded as data and interpreted by a native rule engine. Needs licence check of the rule files and of the Arabic POS dictionary they depend on. Step 3. |
| Fareh Arabic rule database | GPL-3.0 | Downloadable as data only; format not yet assessed. Ask the author (Taha Zerrouki) about an MPL/MIT dual licence. |
| CAMeL Tools weights (disambiguator, UD/CATiB parsers, NER, GED/GEC) | Weights tagged MIT/Apache by CAMeL Lab; morphology database GPL v2 | Technically the best fit (BERT + token-classification/biaffine heads, same shape as the native spaCy transformer port). Training data is LDC Penn Arabic Treebank (parsers, disambiguator) or QALB (GEC, research-only terms). Publishing converted weights means accepting that residual risk; owner decision pending. |
| Stanza / UDPipe Arabic (PADT) | CC BY-NC-SA | Out for a commercial app. |
| Camel Treebank, QALB | Internal research and evaluation only; no redistribution or modification | Out. |
| LDC Penn Arabic Treebank (needed for UD Arabic-NYUAD) | Paid LDC licence | Out under the no-cost constraint. |
| UD Arabic-PUD | CC BY-SA 3.0, 1,000 sentences | Evaluation only (too small to train on). |

## Steps

1. **AyaSpell download (in progress).** `tools/proofing/ayaspell/build_bundle.py`
   pins LibreOffice `dictionaries` commit
   `951bb429a4d846699b02e7adb4fc6fca128c6bae` (`ar/`), verifies every byte,
   adds the MPL 1.1 text, a manifest and a card, and can publish the bundle to
   Hugging Face. The upstream GitHub copy (`linuxscout/ayaspell`
   `36a90abb`) is not used: its `.dic` contains file-concatenation separators
   and its `.aff` differs, and Hunspell 1.7.2 rejects common forms such as
   `الولد` and `المدرسة` with it.
   Local check with Hunspell 1.7.2 on UD Arabic-PUD (1,000 news sentences,
   15,676 Arabic-script tokens): 5.1% of tokens flagged, dominated by foreign
   proper names (personal vocabulary covers these); typical errors are caught
   with the expected first suggestion (`الى`→`إلى`, `المدرسه`→`المدرسة`,
   `هاذا`→`هذا`). Load takes about 1.5 s and 39 MB RSS on macOS arm64.
2. **Hunspell engine in Quds.** An MPL-1.1 Hunspell adapter behind the
   existing spelling-provider interface: native library for desktop/mobile,
   WebAssembly for the web build, dictionary bytes from the user's download.
   Arabic needs right-to-left offsets, tatweel and harakat handling and
   UTF-16 mapping of findings; the existing provider contract already reports
   original UTF-16 offsets. Personal vocabulary and ignore controls as for
   German.
3. **Arabic grammar rules.** First an independently authored, MIT-licensed set
   in the existing rule framework for checks that need no model: hamza on alif
   (أ/إ/ا), ta marbuta vs ha (ة/ه), alif maqsura vs ya (ى/ي), Arabic
   punctuation (، ؛ ؟) and spacing, tatweel, repeated words, إن/أن. Then
   assess the LanguageTool Arabic rules as downloadable data (licence of the
   XML and of the POS dictionary; which rule features they use) and, if clean,
   interpret them natively.
4. **Model-backed analysis (optional, owner decision).** Either accept the
   CAMeL weights' training-data risk and port them natively like the spaCy
   transformer pipelines, or train our own licence-clean models:
   - an error detector on synthetic errors injected into permissively licensed
     text (Arabic Wikipedia, CC BY-SA) with an MIT encoder (XLM-R base): about
     1–2 weeks of work, a few GPU hours per run (free Kaggle quota suffices);
   - a POS/morphology/lemma tagger trained on silver annotations: about 2–4
     weeks plus annotation cost; dependency parsing noticeably weaker.
   Compute is not the bottleneck; licence-clean training data is.
