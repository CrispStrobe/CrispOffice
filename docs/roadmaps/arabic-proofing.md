# Arabic proofing roadmap

Accepted: 19 November 2026. Scope: Arabic spelling, independently authored
writing rules, then optional model-backed analysis. The initial writing rules
are registered for Arabic-language text. The optional Hunspell adapter,
Studio registration and explicit dictionary download/setup workflow are
implemented. Platform packaging and qualification boundaries are recorded
below. No Arabic resource is downloaded by default.

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
   Hugging Face. Publishing includes only the manifest-listed files and
   `manifest.json`; unrelated files in a reused output directory are excluded.
   The Hunspell adapter package and Studio dictionary workflow are implemented
   (step 2); packaging and installed-platform acceptance remain target-specific.
   The upstream GitHub copy (`linuxscout/ayaspell`
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
2. **Hunspell engine in Quds (implemented and wired into Studio).**
   `packages/quds_proofing_hunspell`: MIT adapter + unmodified Hunspell 1.7.2
   library files (MPL 1.1 option, tarball SHA-256 `11ddfa39…`, every compiled
   file hashed in `licenses/manifest.json`, exact sources shipped as
   `licenses/hunspell-1.7.2-library-sources.tar.gz`); native isolate transport
   and bundled WebAssembly worker; pinned installer with atomic publish and
   removal. Incoming implementation evidence reports an identical flagged multiset to the Hunspell CLI on UD
   Arabic-PUD (795 of 15,676 words) for both native and Wasm; 18 Dart tests
   with the real library and dictionary; iOS/Android arm64 compile and link.
   **Host wiring (19 November 2026, branch `feat/arabic-host-wiring-20261119`):**
   - Studio: Review › Proofing › **Dictionaries** opens a setup dialog that
     names the immutable HF revision, licence (MPL 1.1), download size and the
     pinned SHA-256 of `ar.aff`/`ar.dic`; Download (progress, cancel) and
     Remove; a Licences button opens the app licence page. Nothing is
     downloaded without that action. Native hosts install into the app's
     private data directory through `HunspellInstaller`; the web host keeps the
     verified bytes in memory for the session. Installed dictionaries
     re-verify at start-up (no network).
   - Once installed, the Word service gains a `HunspellProofingProvider`
     after the Arabic rules; the service is rebuilt on install/remove. The
     library path comes from `QUDS_HUNSPELL_LIBRARY` or the packaged location
     next to the executable (`Contents/Frameworks` on macOS, `lib/` on Linux,
     the executable directory on Windows, `jniLibs` on Android).
   - Engine: findings from different providers with the same category, range
     and text that share a replacement are one review item; the earlier
     provider (the Arabic rule) keeps its rule id and message and the
     dictionary's extra suggestions follow its own. Different categories stay
     separate, so the German grammar/spelling pairs are unchanged.
   - Packaging: `tool/build.py --install-native/--install-web/--install-android/
     --install-licenses` copies receipt-verified outputs. The Studio example
     now has a macOS runner (sandbox entitlements: network client,
     user-selected files); `web/proofing/` and `android/.../jniLibs/` are
     generated and ignored. The app licence page lists the Hunspell MPL 1.1
     notices (`assets/licenses/hunspell/`, `registerStudioLicenses`).
   - Evidence (macOS arm64, Flutter 3.47.8): macOS release app built, the
     dylib installed into `Contents/Frameworks` and the bundle re-signed
     (`codesign --verify --deep --strict` passes); the end-to-end test loads
     that bundled dylib with the AyaSpell bundle and checks a Word document
     with `w:bidi`: findings `الى`→`إلى` (one merged item from the rule and
     the dictionary), `المدرسه`→`المدرسة` (merged), `هاذا`→`هذا` (merged with
     the `ar.spelling.common` rule from #184), German run silent. Web release build contains the worker, module and
     wasm under `proofing/`. Android arm64-v8a library cross-built (NDK 28,
     static libc++, only libc/libm/libdl needed) and installed into `jniLibs`;
     `flutter build apk --release --target-platform android-arm64` packages it
     as `lib/arm64-v8a/libquds_proofing_hunspell.so` (1.6 MB, stripped) in a
     69.8 MB release APK. Not yet run on a device.
   - Open: installed Linux/Windows application builds, iOS packaging (the example has no iOS
     runner), running on real devices, persisting the web download across
     sessions, signing with a release identity.
3. **Arabic writing rules (first set implemented, 19 November 2026).**
   `ArabicWritingRulesProvider` (`arabic-writing`) in `quds_office_engine`
   is independently authored, MIT-licensed and part of the app. It was
   written from general MSA orthography without reading any LanguageTool or
   Fareh rule content. It is active only for Arabic-script Arabic paragraphs
   (`ar`, `ar-SA`, `ar-Arab-…`) and is registered in the default Word
   proofing service and the Studio example. Eleven rule ids:
   - spelling: hamzat al-qat' on a closed list, with several suggestions
     where the form depends on syntax (`ان` → `أن`/`إن`);
   - spelling: ta marbuta, only for definite forms of 44 listed stems (after
     the article a final ه cannot be the possessive pronoun);
   - spelling: alif maqsura on 6 listed words;
   - spelling: detached conjunction waw (`و هو` → `وهو`);
   - style: final ya written as ى (`فى` → `في`), a regional convention;
   - style: Latin `, ; ?` after Arabic script, a space before `، ؛ ؟`, or a
     missing space after `، ؛`;
   - style: tatweel;
   - style: immediate repetition of 26 closed-class words;
   - style: numbers that mix Western and Arabic-Indic digits.

   Matching ignores harakat and tatweel while preserving combining hamza
   and maddah. Suggestions keep the writer's harakat. Whole-word matching
   respects mixed-script letters, digits, connector punctuation and joiners.
   Findings use original UTF-16 offsets, and links, email and code spans are
   excluded. Ambiguous words are left out on purpose: `علي` (the name Ali),
   `فان` ("perishing"), `لان` ("became soft"), indefinite `مدرسه`
   ("his teacher"). Suggestions are advisory; broader linguistic acceptance
   remains separate work. These rules need no dictionary download or model.

   Test coverage includes:
   - engine cases covering every rule and zero-finding controls (hamzat al-wasl
     words, names, emphatic repetition, consistent digits, Latin text and
     protected spans), plus ambiguity, offset, ignore, language and dispose
     checks; three decomposed hamza/maddah controls and a correction-offset
     regression preserve those spellings exactly;
   - 2 editor integration tests: default session on an `ar-SA` run with an
     applied suggestion, and silence on German text.

   The subsequent Office sync adds controls for decomposed spelling, mixed
   scripts, numeric and identifier boundaries, and the valid verb `لان`.

   **Complex-script language (closed 19 November 2026):** Word stores the
   language of right-to-left text in `w:lang/@w:bidi`. Runs marked
   `w:rtl`/`w:cs`, or containing Arabic or Hebrew letters, now use the run's
   or the document default's complex-script language
   (`wordRunProofingLanguage`), so Arabic in Word documents with
   `w:val="en-US" w:bidi="ar-SA"` reaches the Arabic providers; Latin runs
   keep `w:val`. Digits, punctuation and combining marks alone do not select
   the complex-script language. Unmodified attributes round-trip unchanged.
   Setting the selection language updates both `w:val` and `w:bidi`, so the
   choice also takes effect for Arabic/RTL runs; resetting to inherit clears
   those two direct overrides while retaining East Asian language and other
   native formatting. Document defaults remain live, and a changed default
   invalidates an already captured selection target.

   Interpreting LanguageTool's Arabic rules is assessed
   [below](#languagetool-arabic-assessment-v68).
3b. **Clean-room extension: tier T1 implemented (19 November 2026).** A
   separate "dirty-room" agent studied LanguageTool ar v6.8, Fareh, Ghalatawi
   and the aghlat list and wrote an abstract functional
   [specification](arabic-rule-spec.md) without any copied lists, messages,
   examples, IDs or patterns (reviewed: it contains no Arabic script, regexes,
   rule IDs or tag strings). An independent implementer who had not seen those
   sources wrote the MIT rules **from the spec only**: every word list,
   message, example and test sentence was authored from general knowledge of
   MSA, and none of those sources (or Arramooz/Qalsadi) was opened.

   Code: `arabic_extended_rules.dart`, a `part` of
   `ArabicWritingRulesProvider` (same provider id, no registration change).
   Opt-in rules are enabled with
   `ArabicWritingRulesProvider(enabledOptionalRuleIds: {...})`; only ids in
   `arabicExtendedOptionalRuleIds` are accepted. All conventions of step 3
   hold: harakat-insensitive matching, the writer's harakat kept where the
   letter count is unchanged, original UTF-16 offsets, URLs/e-mail/code spans
   excluded, reviewable suggestions only.

   Default-on rules (19), with spec category, positive cases / zero-finding
   controls in `arabic_extended_rules_test.dart`:

   | Rule id | Spec | + | controls |
   |---|---|---|---|
   | `ar.punctuation.doubled` (`،،` `؛؛` `..`, not `...`) | P3 | 3 | 1 |
   | `ar.punctuation.unpaired` (`()[]{}`, `«»`, `﴿﴾`, curly and straight `"`; either-order pairs; list labels `1)`/`أ)` and a paragraph-initial open quote exempt) | P4 | 5 | 9 |
   | `ar.spacing.multiple` | P5 | 1 | 1 |
   | `ar.spacing.after-sentence` (`. ! ؟ :` glued to the next Arabic word; single-letter abbreviations exempt) | P5 | 2 | 2 |
   | `ar.spacing.run-together` (ة or ى inside a word) | S6 | 3 | 2 |
   | `ar.spacing.theophoric` (`عبدالله` → `عبد الله`, 57 authored names) | T1-b | 3 | 2 |
   | `ar.hamza.maqsura-hamza` (`ىء` → `ئ`) | S5 | 3 | 2 |
   | `ar.hamza.wasl-measure` (verbal nouns of measures VII, VIII, X and hollow X written with إ; templates, not a list) | S2 generative | 7 | 9 |
   | `ar.spelling.common` (662 frozen misspellings; 54 before the list expansion below) | S2/S9 list | 20 | 2 |
   | `ar.consistency.spelling` (10 groups of two accepted spellings, e.g. مسؤول/مسئول, مئة/مائة; scope: one paragraph) | S8 | 2 | 2 |
   | `ar.date.weekday` (weekday + day + month name + year; three month-name series) | M1 | 4 | 4 |
   | `ar.date.invalid-day` (31 April, 29 February in a common year) | M1 | 2 | 1 |
   | `ar.date.implausible-year` (five digits after a year/month/season word) | M2 | 2 | 3 |
   | `ar.grammar.hal-particle` (هل + negator / إنّ / إذا / لو) | G14 | 4 | 3 |
   | `ar.redundancy.double-future` (سوف + سـ) | L6 | 2 | 3 |
   | `ar.redundancy.phrase` (9 authored pleonasm patterns) | L6 | 5 | 4 |
   | `ar.expression.error` (31 fixed-expression patterns, e.g. لا سيما, إن شاء الله, على حدة, سوف لن, عن ما, بادئ ذي بدء) | L2 | 11 | 5 |
   | `ar.register.colloquial` (147 dialect words without an MSA homograph or a frequent name) | L4 | 8 | 10 |
   | `ar.repetition.content-word` (distributive accusatives and tanwin, two-letter initials exempt) | L8 | 1 | 4 |

   Opt-in rules (13): prescriptive usage, register and hints, as the spec
   advises:

   | Rule id | Spec | + | controls |
   |---|---|---|---|
   | `ar.usage.baynama-initial` | G13 | 1 | 1 |
   | `ar.usage.talama` (→ ما دام) | G13 | 2 | 1 |
   | `ar.usage.imma-aw` (إمّا … أو → وإمّا) | G13 | 1 | 1 |
   | `ar.usage.kullama-repeated` | G13 | 1 | 1 |
   | `ar.usage.abadan-past` (لم … أبدًا → قطّ) | G13 | 2 | 1 |
   | `ar.usage.expression` (103 patterns, e.g. اختار بين, لا زال, أكد على, قال أنّ, على ضوء, العديد من, لعب دورًا, نفس + noun, 32 verbs and particles written with لـ for إلى) | L2 | 13 | 9 |
   | `ar.usage.word` (80 forms, e.g. ساهم, هام, تواجد, لوحده, مشاكل, استلم, يعتبر, توفّر) | L3 | 6 | 1 |
   | `ar.style.wordiness` (130 patterns: 24 fixed phrases, 26 `بشكل/بصورة` + adjective, 80 `قام بـ` + verbal noun) | L6 | 7 | 3 |
   | `ar.style.long-sentence` (> 80 words) | L9 | 1 | 2 |
   | `ar.style.tanwin-placement` (اً → ًا) | T1-a | 1 | 2 |
   | `ar.register.loanword` (216 entries) | L4 | 4 | 2 |
   | `ar.hint.vowelling` (146 words, unvowelled occurrences only) | L7 | 5 | 1 |
   | `ar.hint.dad-za` (5 rare→frequent ض/ظ pairs) | S10 | 1 | 1 |

   Tests: 195 new engine tests (81 positive cases, 68 default and 16 opt-in
   zero-finding controls, 21 "off by default" checks, plus RTL offset tests
   with an emoji and harakat, a phrase found on the harakat-free text, an
   Arabic-Indic date, protected spans, ignore and opt-in filtering). The incoming
   T1 checkpoint reported 1,384 engine proofing tests
   (1,189 before) and two editor integration tests passing. These are historical
   incoming results, separate from this reconciliation. The merged step-3
   file retains all 82 tests from both continuations; the final source-bound
   gate reports their acceptance together with the extension.

   This reconciliation adds 11 controls for phrase/date checks inside mixed-script
   identifiers and for combining hamza at phrase-token boundaries. The extension
   file now contains 206 cases; all 195 incoming T1 cases remain.

   **Incoming T1 false-positive check on UD Arabic-PUD** (r2.14 test, 1,000 `# text =`
   news sentences, CC BY-SA, evaluation only, not committed), every rule
   enabled:
   - **default-on extension: 1 finding in total** —
     `ar.punctuation.unpaired` 1 (a quotation that continues into the next
     sentence of the source paragraph; a corpus segmentation artifact). All
     other 18 default-on rules: 0. Two rules were tightened after the first
     run: `ar.hamza.wasl-measure` hit the place name إنديانا (the bare
     accusative-alif suffix was removed from the templates) and
     `ar.repetition.content-word` hit `بي بي سي`/`إس إس` (two-letter tokens
     exempted).
   - opt-in: `ar.style.tanwin-placement` 443 (PUD writes tanwin on the
     alif; this is the convention choice the rule exists for),
     `ar.hint.vowelling` 37, `ar.usage.expression` 6 (لمدة ×3, بعضهم البعض
     ×2, لا زال ×1), `ar.style.wordiness` 6, `ar.usage.word` 3,
     `ar.usage.imma-aw` 1; all are the intended prescriptive targets. The
     ض/ظ hint fired 5 times on the frequent word ظل before it was limited
     to the rare member of each pair; now 0.
   - for reference, the step-3 rules on the same corpus:
     `ar.punctuation.arabic-mark` 651 (PUD uses Latin commas),
     `ar.style.tatweel` 13, `ar.repetition.word` 7,
     `ar.spacing.conjunction-waw` 1.

   **List expansion (19 November 2026).** The word and phrase lists were
   expanded by the same clean-room process: every entry was authored from
   general knowledge of MSA following only the [specification](arabic-rule-spec.md);
   no LanguageTool, Fareh, Ghalatawi, aghlat, Arramooz, Qalsadi or
   Hunspell-derived list was opened, and no "common mistakes" list was
   searched for. Sizes, before → after:

   | List | Rule | Before | After |
   |---|---|---|---|
   | hamzat al-qat' words (exact match) | `ar.hamza.initial` | 36 | 242 |
   | definite ta-marbuta stems | `ar.ta-marbuta.final` | 44 | 277 |
   | alif-maqsura words | `ar.alif-maqsura.final` | 6 | 52 |
   | frozen misspellings (hamza seats, wasl/qat', ة/ه, ض/ظ, joined words, plural alif) | `ar.spelling.common` | 54 | 662 |
   | fixed-expression errors | `ar.expression.error` | 3 | 31 |
   | prescriptive expressions (opt-in) | `ar.usage.expression` | 6 | 103 |
   | prescriptive single words (opt-in) | `ar.usage.word` | 26 | 80 |
   | colloquial words | `ar.register.colloquial` | 40 | 147 |
   | loanwords (opt-in) | `ar.register.loanword` | 28 | 216 |
   | wordiness patterns (opt-in) | `ar.style.wordiness` | 8 | 130 |
   | vowelling hints (opt-in) | `ar.hint.vowelling` | 20 | 146 |

   `ar.register.colloquial` stays default-on (no change to the rule-id
   sets), so its new entries were held to the default-on bar: no MSA
   homograph, no frequent name, and no hit on valid text in the corpora
   below. Words that are valid in another reading (pronoun suffixes,
   imperatives of measure I, names, the second member of a ض/ظ pair) were
   left out or given several suggestions. Two code changes came with the
   lists: a suggestion that carries its own harakat is no longer respelled
   letter by letter (it produced `يُُعدّ` from `يُعتبر`), and compiled phrase
   patterns are cached across checks.

   **False-positive check of the expanded lists**, every rule enabled, on
   the 1,000 UD Arabic-PUD test sentences and on 17,417 sentences sampled
   from 1,600 random articles of the Arabic Wikipedia dump `20231101.ar`
   (CC BY-SA; evaluation only, not committed). Default-on list-driven rules,
   findings on main → expanded lists → after tightening:

   | Rule | PUD | Wikipedia |
   |---|---|---|
   | `ar.hamza.initial` | 0 → 0 → 0 | 173 → 251 → 251 |
   | `ar.spelling.common` | 0 → 2 → 0 | 15 → 162 → 129 |
   | `ar.ta-marbuta.final` | 0 → 0 → 0 | 1 → 5 → 5 |
   | `ar.alif-maqsura.final` | 0 → 0 → 0 | 6 → 11 → 11 |
   | `ar.expression.error` | 0 → 0 → 0 | 4 → 8 → 8 |
   | `ar.register.colloquial` | 0 → 0 → 0 | 15 → 18 → 9 |

   Every default-on finding was inspected. After tightening, all hamza,
   spelling, ta-marbuta, alif-maqsura and expression findings are real
   errors in the Wikipedia text (unhamzated أن/إلى/أيضًا, `ذالك`, `إنتقل`,
   `الدكتوراة`, `حتي`, `على حدى` …); the 9 colloquial findings are dialect
   words inside quoted Egyptian film, play and song titles and dialogue (and
   one typo for من). Removed or narrowed:
   - spelling: `لدية` (it matched `بلدية`, municipality, through the ب
     prefix: 29 Wikipedia and 2 PUD hits), `كانو` (the city of Kano);
     `جزئ` now offers both جزء and جزيء (it was written for the molecule);
   - colloquial, names and toponyms: `فين` (Funen), `هيدي` (Heidi), `دابا`,
     `ليه` (French *les*, Leh) from the original list; `اتنين` (a place
     name), `ازيك` (via `فازيك`, Vazgen), `وين` (Wynne), `ديالو` (Diallo),
     `بكير` (Ibn Bukayr) from the new entries; `يلا`/`يللا` were left out
     before the run because `فيلا`/`فيللا` (villa) would match through the
     ف prefix;
   - opt-in loanwords colliding with names: `مايك`, `بليز` (Belize),
     `بلان`, `لايك`, `برافو`, `بوست`, `براند`, `بلوك`;
   - opt-in expressions: `تخرج من` no longer matches `تخرج`/`تخرجه` (also
     تَخرُج, "she leaves"); `الغير` + word was dropped (`بمساعدة الغير هو`);
     the لـ-for-إلى patterns match only the definite `لل` form (before an
     indefinite word the lam may mean purpose) and give advice without a
     replacement (`لل` also absorbs a noun-initial lam, `للغة`).

   Opt-in rules on Wikipedia after tightening (prescriptive targets, as
   designed): `ar.hint.vowelling` 5,265, `ar.usage.expression` 1,700 (mostly
   the advice on `تمّ` + verbal noun and `العديد من`), `ar.usage.word` 561,
   `ar.style.wordiness` 317, `ar.register.loanword` 201.

   Tests: 117 new engine tests: positive samples for every list (68 new
   cases), regression controls for each removed false positive, list-size
   floors, a check that no suggestion of any list or phrase is itself
   flagged by a default rule (over 1,500 suggestions), and a check that no
   surface form (with the rule's prefixes and article) is claimed by two
   lists with different suggestions. The engine proofing suite passes 1,510
   tests (1,393 before); the editor Arabic integration test passes.

   Limitations: consistency is per paragraph (the request carries one block;
   a document-wide pass belongs to the host); dates are day–month-name–year
   only (no numeric or month-first dates, Hijri dates are skipped); straight
   single quotes are not paired (apostrophes in transliteration); the
   Hijri abbreviation `هـ` still triggers the step-3 tatweel rule.

   **Deferred.** T1 items left out: S3/S4 list extensions (indefinite ta
   marbuta is ambiguous with the ha pronoun), S10 context selection, verb
   forms of the wasl templates (collide with loanwords such as إستبرق).
   T2 (needs the morphology lexicon, Camel Morph MSA under consideration):
   G10/G11 numerals, G5 jussive, G7/G8 case of duals and plurals, G2, G6,
   G15 transitivity, L1 collocations, L5 light verbs, S7 particle merging,
   S9 inflected forms, S1 general spelling, L2/L3 lemma variants, the
   tense-aware part of G13 and G14's future restriction. T3 (needs a
   disambiguator): G1, G3, G4, G12 and kana/inna predicate case.
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
