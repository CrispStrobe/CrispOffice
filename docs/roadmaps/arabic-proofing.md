# Arabic proofing roadmap

Accepted: 19 November 2026. Scope: Arabic spelling first, then grammar rules,
then optional model-backed analysis. Built-in Arabic writing rules now run for
Arabic-script Arabic paragraphs. Downloadable dictionary integration and
model-backed analysis remain planned; no Arabic resource is downloaded by default.

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
| LanguageTool Arabic module v6.8 (454 XML rules, 16 Java rules) | Code and `grammar.xml` LGPL-2.1-or-later; POS/synthesis dictionaries derived from Arramooz (GPL-2.0); replace list from aghlat (AGPL-3.0) | Downloadable as data only; needs a native pattern engine plus the GPL dictionary. See [assessment](#languagetool-arabic-assessment-v68). |
| Fareh Arabic rule database | GPL-3.0 | Downloadable as data only; format not yet assessed. Ask the author (Taha Zerrouki) about an MPL/MIT dual licence. |
| CAMeL Tools weights (disambiguator, UD/CATiB parsers, NER, GED/GEC) | Weights tagged MIT/Apache by CAMeL Lab; morphology database GPL v2 | Technically the best fit (BERT + token-classification/biaffine heads, same shape as the native spaCy transformer port). Training data is LDC Penn Arabic Treebank (parsers, disambiguator) or QALB (GEC, research-only terms). Publishing converted weights means accepting that residual risk; owner decision pending. |
| Stanza / UDPipe Arabic (PADT) | CC BY-NC-SA | Out for a commercial app. |
| Camel Treebank, QALB | Internal research and evaluation only; no redistribution or modification | Out. |
| LDC Penn Arabic Treebank (needed for UD Arabic-NYUAD) | Paid LDC licence | Out under the no-cost constraint. |
| UD Arabic-PUD | CC BY-SA 3.0, 1,000 sentences | Evaluation only (too small to train on). |

## Steps

1. **AyaSpell download (published).** `tools/proofing/ayaspell/build_bundle.py`
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
   **Published** 19 November 2026 as
   [`cstr/ayaspell-ar-hunspell`](https://huggingface.co/cstr/ayaspell-ar-hunspell/tree/e9ace7cca3844bef906d8d9fc5431c4e15bd2740)
   at immutable revision `e9ace7cca3844bef906d8d9fc5431c4e15bd2740`; all eight
   files read back with matching SHA-256 (the builder's readback), and a fresh
   download of `ar.aff`/`ar.dic` from that revision gives the same Hunspell
   results. The Hub's metadata has no `mpl-1.1` identifier, so the card
   declares `license: other` / `license_name: mpl-1.1` and ships the text.
2. **Hunspell engine in Quds.** An MPL-1.1 Hunspell adapter behind the
   existing spelling-provider interface: native library for desktop/mobile,
   WebAssembly for the web build, dictionary bytes from the user's download.
   Arabic needs right-to-left offsets, tatweel and harakat handling and
   UTF-16 mapping of findings; the existing provider contract already reports
   original UTF-16 offsets. Personal vocabulary and ignore controls as for
   German.
3. **Arabic grammar rules (first set implemented, 19 November 2026).**
   `ArabicWritingRulesProvider` (`arabic-writing`) in `quds_office_engine`
   is independently authored, MIT-licensed and part of the app. It was
   written from general MSA orthography without reading any LanguageTool or
   Fareh rule content. It is active only for Arabic-script Arabic paragraphs
   (`ar`, `ar-SA`, `ar-Arab-…`) and is registered in the default Word
   proofing service and the Studio example. Eleven rule ids:
   - spelling: hamzat al-qat' on 36 listed words, with several suggestions
     where the form depends on syntax (`ان` → `أن`/`إن`);
   - spelling: ta marbuta, only for definite forms of 43 listed stems (after
     the article a final ه cannot be the possessive pronoun);
   - spelling: alif maqsura on 6 listed words;
   - spelling: detached conjunction waw (`و هو` → `وهو`);
   - style: final ya written as ى (`فى` → `في`), a regional convention;
   - style: Latin `, ; ?` after Arabic script, a space before or a missing
     space after `، ؛ ؟`;
   - style: tatweel;
   - style: immediate repetition of 26 closed-class words;
   - style: numbers that mix Western and Arabic-Indic digits.

   Matching ignores harakat and tatweel while preserving combining maddah and
   hamza (U+0653–U+0655) as spelling content. Correct decomposed spellings are
   left unchanged. Suggestions keep the writer's harakat. Findings use original
   UTF-16 offsets, and links, email and code
   spans are excluded. Ambiguous words are left out on purpose: `علي` (the
   name Ali), `فان` ("perishing"), indefinite `مدرسه` ("his teacher").

   Tests:
   - 73 engine tests: 39 positive cases covering every rule, 23 zero-finding
     controls (hamzat al-wasl words, names, emphatic repetition, consistent
     digits, Latin text, protected spans), plus ambiguity, offset, ignore,
     language and dispose checks, three decomposed hamza/maddah controls and a
     correction-offset regression that preserves those spellings;
   - 2 editor integration tests: default session on an `ar-SA` run with an
     applied suggestion, and silence on German text.

   **Known gap:** paragraph language comes from `w:lang/@w:val`. Word stores
   the language of right-to-left text in `w:lang/@w:bidi`, so Arabic in
   documents written by Word with `w:val="en-US" w:bidi="ar-SA"` is still
   routed as English. Selecting the complex-script language for `w:rtl`/`w:cs`
   runs is the next editor change. Documents written by Quds already set
   `w:val="ar-SA"` on Arabic runs.

   Interpreting LanguageTool's Arabic rules is assessed
   [below](#languagetool-arabic-assessment-v68).
4. **Model-backed analysis (optional, owner decision).** Either accept the
   CAMeL weights' training-data risk and port them natively like the spaCy
   transformer pipelines, or train our own licence-clean models:
   - an error detector on synthetic errors injected into permissively licensed
     text (Arabic Wikipedia, CC BY-SA) with an MIT encoder (XLM-R base): about
     1–2 weeks of work, a few GPU hours per run (free Kaggle quota suffices);
   - a POS/morphology/lemma tagger trained on silver annotations: about 2–4
     weeks plus annotation cost; dependency parsing noticeably weaker.
   Compute is not the bottleneck; licence-clean training data is.

## LanguageTool Arabic assessment (v6.8)

Checked 19 November 2026 against the release tag `v6.8`. The assessment read
only licence files, file headers, build metadata and the resource README. It
counted XML element and attribute kinds mechanically, without reading any
rule bodies.

**Licences**
- **Module code:** `pom.xml` declares LGPL-2.1, with the comment "The
  license refers to the source code, resources may be under different
  licenses".
- **`grammar.xml`** (418 KB): its header carries an LGPL-2.1-or-later
  notice, copyright 2019 Taha Zerrouki, Sohaib Afifi and the LanguageTool
  contributors.
- **POS dictionary** `resource/ar/arabic.dict` (12.0 MB, morfologik FSA,
  SUFFIX encoder): generated from **Arramooz**, GPL-2.0 according to its
  repository; the resource README says GPL. The synthesis dictionary
  `arabic_synth.dict` (14.9 MB) is used for inflected suggestions; its
  provenance is presumably the same, not separately stated.
- **Other components named in the README:** the tag manager
  (mysam-tagmanager) and common words (Tashkeela) are GPL-3.0. Rules are
  authored with **Fareh** (GPL-3.0).
- **`rules/ar/replaces.txt`** (61 KB): its header says "Mainly from
  aghlat". aghlat is **AGPL-3.0**.
- **The bundled Hunspell copy** of AyaSpell differs slightly in size from
  the LibreOffice packaging we publish.

**What the rules need from an engine**

`grammar.xml` has:
- 454 rules: 40 rule groups in 14 categories, 1,070 examples;
- 1,055 `token` elements, 455 `pattern`, 42 `antipattern`, 6 `exception`,
  9 `or`, 1,139 `marker`;
- 629 `suggestion` and 516 `match` elements;
- 45 `unify` with 165 `feature` and 11 `equivalence`;
- 6 Java filters: date check (×2), number phrase, masdar-to-verb,
  verb-to-maf'ul-mutlaq, adjective-to-exclamation.

Attributes in use:
- 408 `inflected`, 361 `postag`, 350 `postag_regexp`;
- 304 `regexp` and 305 `regexp_match`/`regexp_replace` pairs;
- 151 `skip`, 22 `postag_replace`.

`disambiguation.xml` has 5 rules.

In addition, 16 Java rule classes drive the plain-text lists:
- homophones, diacritics, darja, wordiness, redundancy, coherency;
- the transitive-verb rule;
- the simple-replace and inflected-one-word lists;
- the masdar/verb lists, about 320 KB.

**Feasibility under the constraints**

Downloading `grammar.xml`, the lists and both dictionaries as data is
allowed: they are interpreted, not executed. Two caveats:
- the dictionaries are GPL-derived and the replace list is AGPL-3.0, so each
  must stay a separate download carrying its own licence and source;
- none of it may be compiled into the app.

A native interpreter would need:
- a morfologik FSA reader for tagging and synthesis;
- a port of `ArabicTagger`'s clitic handling (proclitics و/ف/ب/ل/ك and
  enclitic pronouns are not stored in the dictionary);
- a LanguageTool pattern engine subset: token, regexp, inflected and postag
  matching, skip, exceptions and antipatterns, markers, match/regexp_replace
  suggestions with synthesis, and unification;
- the disambiguator;
- reimplementation of the 6 filters and the list-driven Java rules.

Rough size: 3–5 weeks for a faithful, tested interpreter. Download size is
about 27 MB of dictionaries plus about 0.8 MB of rules and lists. The
authored rules above cover the model-free orthography checks without any
download. LanguageTool's value lies in its POS-aware rules (agreement,
verb transitivity, number phrases), which need the GPL dictionary.

**Alternative:** ask Taha Zerrouki (author of AyaSpell, Arramooz, Fareh and
most of the Arabic module) whether the Arramooz-derived dictionaries and
Fareh could be offered under MPL-2.0 or LGPL. That would remove the
GPL-download separation but would not reduce the engine work.

