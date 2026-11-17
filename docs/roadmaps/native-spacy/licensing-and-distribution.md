# Licensing and distribution decisions for native linguistic analysis

Recorded: **17 November 2026**. This is an engineering evidence and decision
record, not legal clearance of a binary release or a prediction of App Review.
Recheck the applicable platform terms before distribution.

Read this with the sibling source audit, architecture, implementation plan and
validation documents. Those documents own technical scope and qualification;
this document owns license evidence, distribution constraints and unresolved
rights questions.

## 1. User requirements and the resulting decision

The user clarified that LGPL is **acceptable in principle**. The actual product
constraints are:

- Quds must remain suitable for commercial distribution, including an optional
  developer tip such as “buy me a coffee” and possibly paid features or IAP.
- Apple App Store requirements must be satisfied on each supported Apple target.
- There must be **no Python runtime in the application**. A native C++ or Rust
  implementation is the direction being evaluated. A Python process or bundled
  interpreter is not an acceptable product workaround.
- We must have a defensible grant for the exact code, model, data and transitive
  dependencies that we distribute, and fulfill their actual obligations.

The older [proofing policy](../../PROOFING.md#scope-and-license-policy) excludes
LGPL-only dependencies. The user's later clarification supersedes a categorical
LGPL prohibition for this new work. It does **not** approve any particular LGPL
package, waive license obligations, authorize an App Store submission, or clear
the AOT runtime described below. Other existing dependency qualifications remain
specific to the versions and distributions that were reviewed.

The current decision is to pursue the native spaCy-compatible direction because
its identified engine/model licenses are clearer and its release obligations
can be narrower. This is a practical preference, not a conclusion that LGPL
forbids monetization. Engineering and evaluation may proceed while the exact
distribution inventory is developed. A release must pass that inventory and
platform review before it is represented as cleared for distribution.

## 2. Repository state and historical evidence

The documentation baseline is `main` at `16228835`. That line excludes AOT under
the integration scope of [PR #125](https://github.com/CrispStrobe/quds_office_suite/pull/125).
Do not reintroduce it by merging an old implementation branch as a shortcut.

The final documentation refresh also reconciled main at
`aa9591d496d66a549d4e0c67aee73eada0d9d46f`, including
[PR #129](https://github.com/CrispStrobe/quds_office_suite/pull/129), which retains
independent context rules and excludes the AOT/RML runtime. Historical AOT
evidence files may be present without the corresponding runtime/package being
an application dependency. The provenance findings below remain historical.

The earlier working prototype remains useful historical evidence:

- [PR #120](https://github.com/CrispStrobe/quds_office_suite/pull/120).
- Branch `codex/aot-daemon-free-20261117`, qualified implementation head
  [`e37ccdb47c047f6a0250585cf5cb20efc17573b4`](https://github.com/CrispStrobe/quds_office_suite/commit/e37ccdb47c047f6a0250585cf5cb20efc17573b4).
- [Historical native build and packaging recipe](https://github.com/CrispStrobe/quds_office_suite/blob/e37ccdb47c047f6a0250585cf5cb20efc17573b4/packages/quds_proofing_aot/tool/build_native.py).
- [Historical native CMake build](https://github.com/CrispStrobe/quds_office_suite/blob/e37ccdb47c047f6a0250585cf5cb20efc17573b4/packages/quds_proofing_aot/native/CMakeLists.txt).
- [Historical implementation and test report](https://github.com/CrispStrobe/quds_office_suite/blob/e37ccdb47c047f6a0250585cf5cb20efc17573b4/docs/validation/aot-daemon-free-20261117/README.md).

That report established functionality for a Linux native build. It did not
establish a complete license inventory or App Store distribution compliance.
Its passing tests must not be recast as licensing or mobile-platform approval.

The AOT audit concerned these exact upstream revisions:

| Input | Pinned revision |
| --- | --- |
| `sokirko74/aot` | `0d591d972c7bb2729f4764d3bc32611ea6fd142a` |
| `sokirko74/nlp_base` | `244b3d1f9a09e4a81e75ea83c3b55b209c663503` |

## 3. AOT: known LGPL grants and unresolved provenance

### 3.1 “Library GPL” and “Lesser GPL”

AOT's exact pinned [root `copying` file][aot-copying] contains the **GNU Lesser
General Public License, version 2.1, February 1999**. Its README uses the older
“Library” terminology. The FSF records that the GNU Library GPL version 2 was
the predecessor of the GNU Lesser GPL version 2.1; neither name means ordinary
GPL merely because the word “GPL” appears in it. See the [FSF historical
license list][gnu-old].

It is correct to say **AOT contains code offered under LGPL**. It is not correct
to say we know that every file and data source in the assembled runtime has a
complete, uniformly documented LGPL grant. Do not infer a blanket `-or-later`
identifier from boilerplate in a license template: record the applicable grant
and any file-specific version language.

### 3.2 Code actually used by the historical Linux worker

The audit inspected the actual link command and compiler dependency files. The
worker statically linked 18 AOT/`nlp_base` archives and system `libz.a`; its dynamic
ELF dependencies were `libstdc++.so.6`, `libgcc_s.so.1` and `libc.so.6`. A process
boundary separated it from Dart, but did not change the libraries inside the
worker or their terms.

The [historical build receipt](aot-license-build-evidence.md) preserves the
archive list, direct ELF dependencies, binary/source hashes, notice inventory
and read-only inspection commands. Its binary hash matches the immutable
historical runtime manifest; this documentation inspection did not rebuild or
execute the worker.

| Component | Evidence at the inspected revision/build | Consequence |
| --- | --- | --- |
| AOT analysis libraries | Root LGPL 2.1 text; multiple LGPL source headers | A real LGPL dependency. |
| `nlp_base` morphology, graphematics and utilities | Inherited files such as [`MorphDict.cpp`][nlp-morphdict] explicitly say LGPL; no root `LICENSE`, `copying` or `NOTICE` at the pin | The modern submodule's complete grant/provenance needs clarification; a missing root file is not proof that every file is unlicensed. |
| `iconv_subset` | Compiled [libiconv headers][nlp-iconv] expressly grant Library GPL version 2 or later | An independently LGPL component even if AOT itself were relicensed. |
| RapidJSON | [MIT header notices][nlp-rapidjson] | Retain copyright and license notices. |
| plog | [MIT header notice][nlp-plog] | Retain the MIT notice. |
| zlib | System static archive with Zlib terms | Include it in the platform-specific inventory; do not label it MIT. |
| Bison-generated parser skeleton | Generated file had GPL terms **with the parser-output exception** | The exception matters; do not classify it as bare GPL-only solely from a scanner match. |
| Flex lexer/header | Inspected header carries permissive BSD-style terms | Preserve applicable notices. |
| GCC runtime / libstdc++ | GPL with the GCC Runtime Library Exception | Ordinary qualifying compilation does not force the application under GPL; inventory any runtime files actually redistributed. |
| glibc | Used as a host system library, not copied into the runtime package | Distinguish host OS dependencies from files we ship; reassess if packaging those libraries. |

Official explanations of the [Bison output exception][bison-exception] and
[GCC runtime exception][gcc-exception] confirm why license expressions must
include exceptions.

Qt, the HTTP server, httplib, doctest and libzip were not in that worker's actual
linked/dependency set. Windows and macOS would require their own inventory;
the Linux inspection is not evidence for those targets.

An additional compiled source, [`nlp_base/common/utf8.cpp`][nlp-utf8], attributes
external `UtfConv.c` code from Alphabet AB but contains no explicit license grant.
The referenced author's file described itself as open-source code, but the
inspected version did not provide a conventional license grant. Clarification
or replacement is needed before treating that imported portion as cleared.
This finding is an evidence gap, not a determination of infringement.

### 3.3 Language data is a separate rights question

AOT's [morphology documentation][aot-morph-doc] identifies Morphy, WordNet and
Zaliznyak as lexicon origins. The [pinned `nlp_base` README][nlp-readme] and import
history add detail, but do not supply a complete per-asset license manifest.

| Data | Evidence | Unresolved question |
| --- | --- | --- |
| German morphology | Based on Morphy; German development associated with BBAW/DWDS | Establish the applicable original grant and subsequent AOT changes. Do not assign the license of a different modern Morphy-derived distribution by analogy. |
| English morphology | Based on WordNet | Identify the imported WordNet version and preserve its actual notice; distinguish upstream input rights from AOT modifications. |
| Russian morphology | Based on Zaliznyak, with later imported and authored additions | Establish the rights/provenance chain for the particular included material. |
| Recent Russian additions | The exact pinned commit adds plural forms for 2,363 nouns from Wiktionary; import scripts document other additions | Determine which material is linguistic facts and which may be protected expression or other licensed content; preserve applicable provenance/notices. |
| Syntax rules, fixed expressions, graphan lists and structural/thesaurus data | Included in AOT/`nlp_base`, without a separately established permissive grant in the inspected trees | Inventory the actual installed assets and their applicable grants. |

Princeton permits commercial use and redistribution of WordNet under its own
notice-preserving license. Its [license page][wordnet-license] does not identify
which historical version AOT imported, or make all subsequent AOT dictionary
changes permissive.

The [Wiktionary importer][nlp-wiktionary] has MIT-licensed parser code. That does
not automatically give its inputs or outputs an MIT license. Conversely,
Wikimedia's [Terms of Use §7][wikimedia-terms] distinguish licensed contributed
text from freely reusable facts and waive contributors' applicable sui generis
database rights. A Wiktionary provenance reference alone does not prove that
every inflected form or the entire resulting dictionary must use CC BY-SA.
Review the actual imported material; neither blanket clearance nor blanket
contamination is justified by the available evidence.

### 3.4 Historical packaging was not a complete compliance bundle

The earlier assembler copied the **entire `Dicts` and `Thes` trees**, including
resources beyond the UI's minimal morphology/syntax needs. Licensing scope
therefore includes installed but unused assets.

Its built `notices/` directory contained only `AOT-COPYING` and
`QUDS-NATIVE-NOTICE.md`. The builder tried a root `nlp_base/LICENSE` or `copying`,
then silently continued when both were absent. It did not collect all identified
third-party notices or produce a verified corresponding-source/relinking bundle.
Pinned source hashes and a generic compliance instruction are useful evidence,
but not a substitute for those materials.

Vendoring a fork would improve maintenance, pinning and publication of our
changes. It would not create missing rights in externally authored code or
imported data. Adding our own LGPL file cannot cure that gap. Keeping AOT as
a historical prototype is justified without asserting that its authors lack
rights or that local testing was unlawful.

## 4. LGPL, commercial use and distribution obligations

### 4.1 Commercial use is allowed

LGPL does not prohibit charging for an application, selling features, IAP,
subscriptions or voluntary tips. GNU's [commercial distribution explanation][gnu-selling]
distinguishes software freedom from price. A source-offer cost
limit is not an app-price cap. There is no general obligation to donate the
application's revenue to an LGPL author.

Our independently authored code can retain MIT where applicable. Imported or
modified library code retains its own terms. A native port of someone else's
code does not become independently authored merely because its language changes.

### 4.2 Exact LGPL version and distribution method matter

[LGPL 2.1 §6][lgpl21] permits qualifying combined works under other terms,
provided the required user rights and distribution conditions are met. A static
linking route includes the exact library source with modifications and the
application source/object materials needed to modify the library and relink.
Required notices and modification/debugging rights also remain relevant.

[LGPL 3 §4][lgpl3] has recombination/relinking requirements and expressly adds
Installation Information when GPLv3 §6 requires it. LGPL 2.1 does not contain
that identical installation-information clause. Do not apply every LGPL3
locked-device conclusion to LGPL2.1, or infer that LGPL2.1 is automatically
compatible with every store.

Publishing our MIT source and a maintained fork can make compliance more
practical. It does not establish that the exact released executable can be
rebuilt/relinked using the provided materials, or that the chosen platform
distribution satisfies all applicable terms. A separate process likewise does
not make the worker permissive or excuse its own obligations.

## 5. Apple distribution and monetization

These observations were checked against public primary sources on 17 November
2026. The agreement accepted in the developer account and the rules effective
at release are authoritative. This roadmap does not authorize account changes,
submission, payment setup or publication.

### 5.1 Developer tips and IAP

Apple's [App Review Guidelines §3.1.1][apple-review] explicitly permit IAP
currencies for tipping developers or digital content providers. An optional
StoreKit developer tip is a plausible route for “buy me a coffee.” External
payment buttons have storefront/program-specific rules; do not assume either
universal permission or a universal ban. A developer tip is not automatically
a charitable donation. Paid apps/IAP also require the applicable [Paid
Applications Agreement][apple-agreements].

Choosing LGPL, MIT or Apache does not itself determine whether a particular
payment UI meets Apple's rules. The license and the store payment mechanism
must each be assessed.

### 5.2 Open-source components are recognized, not automatically cleared

Apple's [Standard EULA §a][apple-eula] contains an open-source exception to its
copying/modification/reverse-engineering restrictions. This makes a blanket
claim that Apple always forbids LGPL-required reverse engineering inaccurate.

The [Developer Program License Agreement][apple-program] defines FOSS to include
GPL/Lesser/Library GPL and requires compliance with its terms in §3.3.4(A)(v).
Its §5.1 nevertheless requires license compatibility with Apple's signing and
content-protection arrangements, without requiring disclosure of Apple's
security/signing information. These provisions require a concrete review;
they are not a categorical LGPL ban or an automatic approval.

### 5.3 Platform packaging must be designed and tested

| Target | Work that the plan must account for |
| --- | --- |
| Direct desktop distribution | Establish a usable notice/source/rebuild arrangement for the exact artifacts and dependencies. |
| Mac App Store | Signed, sandboxed and self-contained app packaging, appropriate helper lifetime, and no assumption that arbitrary external runtime installation is acceptable. |
| iOS/iPadOS App Store | Embedded native integration and platform-supported execution. The old desktop subprocess worker is not a mobile implementation. |

The relevant review rules include [§2.4.5 and §2.5.2][apple-review]. On macOS,
[library validation][apple-library-validation] can also constrain replacement
libraries, so a `.dylib` extension alone does not prove user replaceability.
Do not weaken signing or security controls as a presumed license workaround.

For an LGPL option, review the actual relinking/rebuild and user-installation
arrangement with qualified counsel. For a permissive option, the native binary
still must satisfy platform APIs, signing, sandboxing and code-loading rules.
Passing App Review would not independently prove compliance with third-party
licenses.

## 6. Native spaCy-compatible direction

### 6.1 What has actually been identified

The [spaCy engine license][spacy-license] is MIT. The specific German
`de_core_news_sm` **3.8.0** [published metadata][spacy-de-meta] declares MIT and
lists `tok2vec`, tagger, morphologizer, parser, lemmatizer,
attribute rules and named-entity components. This makes it a credible starting
point; it is not a complete license audit of an eventual C++/Rust distribution.

The metadata file retrieved for this record had Git blob SHA
`e69a86109f374cda79c110610d4a4d0e26bad57a`. This identifies the inspected metadata,
**not** the model weights or an entire source checkout. The source audit must
pin the selected implementation sources and actual model artifact separately.

That same metadata preserves the following training/source disclosures:

| Source | Publisher's recorded description | How to use the evidence |
| --- | --- | --- |
| TIGER Corpus | Commercially licensed by Explosion | The published model is labeled MIT; this does not grant us independent access to, redistribution of, or retraining rights in the original corpus. |
| Tiger2Dep | Citation for reference; no code packaged with the model | Do not invent a shipped dependency from a citation. Verify if our chosen distribution actually contains code from it. |
| WikiNER | CC BY 4.0 | Preserve the model's source disclosures and inspect the exact packaged notices; do not relabel the training corpus MIT. |

Use the exact model's `LICENSE`, `LICENSES_SOURCES`, metadata and package
contents, not just the engine's repository license or a model-hub badge. Other
languages, model versions and pipeline components require their own decisions.

### 6.2 Native implementation implications

The product must not bundle or launch Python. A C++/Rust implementation can
reuse or port appropriately licensed source, with original notices and
modification attribution where required. Translating MIT source preserves
the obligation to retain its notice. Replacing the runtime does not change
the license of the model weights or dictionaries.

Model conversion/export and reference comparison, if used during development,
belong in explicit tooling described by the implementation plan. They must not
become an undeclared runtime Python dependency. Verify that exported weights,
lookup tables, tokenization rules and generated code have an identified source
and permitted distribution basis.

Select native numeric, serialization, Unicode, compression and inference
dependencies deliberately. A permissive spaCy grant does not automatically
clear a new BLAS distribution, Rust crate graph, model converter, runtime,
training dataset or vendored utility. Preserve an exact inventory on each
target, including compiler-runtime exceptions where applicable.

The desired product behavior remains separate from license status: a parser
can supply linguistic features and dependencies, but grammar diagnostics,
suggestion generation, ambiguity guards and source-safe edits still need their
own implementation and validation. Do not advertise AOT equivalence or App
Store readiness on the basis of a model's MIT declaration.

## 7. Questions to resolve and evidence required

These are checkable work items, not a requirement to pause all engineering for
a permission request. Prefer permitted, well-documented inputs while unresolved
alternatives remain outside the distributable package.

| Question | Evidence that closes it | Release consequence if unresolved |
| --- | --- | --- |
| Which source files and model assets are used? | Immutable revisions, archive hashes, generated-file provenance and installed-file inventory | Do not represent the distribution as audited. |
| Do the selected code/model grants permit the intended commercial distribution? | Original notices and applicable license/version/exception for each included component | Replace, exclude or obtain the missing grant. |
| Are model notices and source disclosures preserved? | Inspect the exact model archive, conversion outputs and packaged notices | Complete packaging before release. |
| Does the native runtime introduce new restricted or uncertain dependencies? | Resolved C++/Rust/platform dependency inventory; code and binary inspection | Change the dependency or review its obligations explicitly. |
| If any LGPL material is chosen, can recipients exercise its required rights? | Exact corresponding source/patches, source or objects for relinking, usable instructions and reviewed distribution arrangement | No claim that publishing a fork alone suffices. |
| Does each Apple target satisfy its technical/store requirements? | Target build, signed-bundle inspection, sandbox/lifecycle tests and applicable-terms review | Do not infer support from Linux or from license compatibility. |
| Is a chosen tip/IAP flow permitted in each storefront? | Current rule review, StoreKit/product configuration and correct disclosures | Reassess before implementing or submitting the payment flow. |

For any renewed AOT investigation, additionally resolve the `nlp_base` and
`UtfConv.c` grants, dictionary origins and imported material, trim the installed
data to an audited allowlist, and assemble the missing notices/source/relink
materials. No upstream contact, relicensing agreement or exception was obtained
in the discussion preserved here.

## 8. Instructions for the next agent

1. Preserve the clarified user requirement: LGPL is conditionally acceptable;
   there is no Python runtime in the app; commercial and App Store use matter.
2. Continue the native implementation and bounded validation described in the
   sibling plan. Do not treat this document as an instruction to implement IAP,
   submit an app, or merge the historical AOT branch.
3. Record source/model/dependency provenance as inputs are selected, not after a
   binary has already been labeled release-ready. Distinguish inspected facts,
   publisher declarations, engineering inferences and legal questions.
4. Prefer a minimal, explicit distributed file set. Include original notices
   and the required source materials for any accepted copyleft component.
5. Report technical results independently from license and platform conclusions.
   Do not describe the historical AOT runtime, an MIT-labeled model, or a passing
   test suite as proof of complete redistribution clearance.

## Primary references

The links below preserve the sources used for the conclusions above. Source
files with hashes are historical evidence; live Apple/FSF pages must be checked
again when preparing a distribution.

[aot-copying]: https://github.com/sokirko74/aot/blob/0d591d972c7bb2729f4764d3bc32611ea6fd142a/copying
[aot-morph-doc]: https://github.com/sokirko74/aot/blob/0d591d972c7bb2729f4764d3bc32611ea6fd142a/Docs/Morph_UNIX.txt
[nlp-readme]: https://github.com/sokirko74/nlp_base/blob/244b3d1f9a09e4a81e75ea83c3b55b209c663503/README.md
[nlp-morphdict]: https://github.com/sokirko74/nlp_base/blob/244b3d1f9a09e4a81e75ea83c3b55b209c663503/lemmatizer_base_lib/MorphDict.cpp
[nlp-iconv]: https://github.com/sokirko74/nlp_base/blob/244b3d1f9a09e4a81e75ea83c3b55b209c663503/contrib/iconv_subset/lib/cp1251.h
[nlp-rapidjson]: https://github.com/sokirko74/nlp_base/blob/244b3d1f9a09e4a81e75ea83c3b55b209c663503/contrib/rapidjson/rapidjson.h
[nlp-plog]: https://github.com/sokirko74/nlp_base/blob/244b3d1f9a09e4a81e75ea83c3b55b209c663503/contrib/plog/plog/Log.h
[nlp-utf8]: https://github.com/sokirko74/nlp_base/blob/244b3d1f9a09e4a81e75ea83c3b55b209c663503/common/utf8.cpp
[nlp-wiktionary]: https://github.com/sokirko74/nlp_base/blob/244b3d1f9a09e4a81e75ea83c3b55b209c663503/ru_wiktionary_merger/README.md
[gnu-old]: https://www.gnu.org/licenses/old-licenses/old-licenses.html
[gnu-selling]: https://www.gnu.org/philosophy/selling.html
[lgpl21]: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html
[lgpl3]: https://www.gnu.org/licenses/lgpl-3.0-standalone.html
[bison-exception]: https://www.gnu.org/software/bison/manual/html_node/Conditions.html
[gcc-exception]: https://gcc.gnu.org/onlinedocs/libstdc++/manual/license.html
[wordnet-license]: https://wordnet.princeton.edu/license-and-commercial-use
[wikimedia-terms]: https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use
[apple-review]: https://developer.apple.com/app-store/review/guidelines/
[apple-agreements]: https://developer.apple.com/support/terms/
[apple-eula]: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
[apple-program]: https://developer.apple.com/support/terms/apple-developer-program-license-agreement/
[apple-library-validation]: https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.disable-library-validation
[spacy-license]: https://github.com/explosion/spaCy/blob/master/LICENSE
[spacy-de-meta]: https://github.com/explosion/spacy-models/blob/master/meta/de_core_news_sm-3.8.0.json
