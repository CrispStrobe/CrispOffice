# Proofing continuation: final validation

**Completed locally and saved incrementally to `codex/proofing-20261116-resume`.**
The final editor/source revision is **`3bd4657b1c1cccfad8adbcf5928e30b90e4a1aaa`**.
Later commits add documentation and evidence only.

The engine component run passed at **`6f87a4e849f9dc172fea7a0e57d1d9072d99efe3`**.
The [source comparison](source-scope-comparison.json) shows that the only
subsequent non-documentation changes were the editor's named input-guard method
and correction of a new test to use selecting mode. Engine, Harper, fonts,
dictionary, hyphenation and package-manifest inputs are unchanged.

## Reconciled incoming work

The final inventory covered **58 branch heads and 66 PRs** at
**2026-11-16 14:27:44 UTC (15:27:44 CET)**. All 58 observed heads are actual
ancestors of the integrated source, confirmed by individual GitHub comparisons.
The cutoff bounds this integration while other branches continue receiving work.

| Incoming history | Integrated scope |
| --- | --- |
| Original proofing branch through `c040389` | Renderer, caret, navigation, transport and packaging improvements, plus the complete final verification bundle supplied in the user's handoff |
| Main through `90024d5` | Recent ODS changes, including PRs #65–66 and their documentation |
| Zotero capabilities through `2480f09` | Source identity, session backoff, dialog scaling and the later qualification record |
| Focus/ruler work through `2e92a49` | Dialog input ownership and metric ruler support |

Useful overlapping implementations were reconciled into the continuation's
existing proofing API and protection/history contracts. Original and
patch-equivalent histories remain merge parents. See the
[reconciliation chronology](../continuation-next/README.md),
[final inventory](../continuation-next/remote-refresh-142744.json) and
[58-head ancestry verification](../continuation-next/ancestry-verification.json).

The [evidence-integrity receipt](evidence-integrity.json) confirms that the
incoming `c040389` final evidence tree is exactly preserved: 65 files,
including the original compressed manifests. All 528 files from the original
continuation's `docs/validation` directory are also unchanged. Historical
results retain the source identities in their original receipts.

## Improvements in this continuation

- German tokens must begin with a letter; isolated soft hyphens and combining
  marks cannot become empty words or crash suggestion generation.
- Apostrophes inside words such as `O’Connor`, `geht’s` and `d’Artagnan`
  do not prematurely close surrounding quotation marks.
- The existing agreement rule recognizes lowercase `ich ist` and `du ist`,
  preserves uppercase replacement style, and excludes the reviewed
  `wie`/`als` comparison contexts and capitalized nominal forms.
- Built-in spelling, writing and terminology providers omit matches whose
  endpoints split a grapheme, while preserving valid findings elsewhere.
  They do not widen a replacement over adjacent combining marks or joiners.
- Hyphen hit testing and caret ownership reconcile LTR/RTL text, zero-source
  display glyphs, explicit soft hyphens and presentation transforms.
- Finding navigation avoids creating a paragraph in an empty document,
  targets the header/footer page that actually contains the finding, and
  synchronizes the final IME paragraph/selection.
- Body finding navigation clears equation, visual, frame and table editing
  targets before selecting text, so subsequent input reaches the intended
  paragraph.
- Input guards reject stale text, action and selector traffic when focus or
  route ownership changes. They rebind on controller replacement, remain
  rejecting after unmount, and restore attachment when a route becomes current
  without a FocusNode change. Navigation remains available in non-mutating
  **selecting** mode.

The established F7 review dialog, personal vocabulary, ignore controls,
language/hyphenation settings, protected corrections, tracking and undo remain
connected. These existing features are described in [PROOFING.md](../../../PROOFING.md).

## Fresh verification

The final editor run completed **2026-11-16 15:22:42 UTC**.

| Scope | Result | Evidence |
| --- | --- | --- |
| Full engine analysis under the resolved Flutter workspace | Passed with `--fatal-infos` | [Editor/integration receipt](editor/receipt.json) |
| Editor library and 23 selected test files | Strict analysis passed | [Analysis log](editor/editor-analyze.log) |
| Example host library | Strict analysis passed | [Analysis log](editor/example-analyze.log) |
| Combined editor proofing, focus, navigation, rendering, history and Zotero suite | **294 tests passed**, no failures or skips | [Test log](editor/editor-tests.log) |
| Separate canvas IME reattachment regression | **1 test passed** | [Test log](editor/editor-ime-reattachment.log) |
| Example release web compilation | **Succeeded** | [Build log](editor/example-web-build.log) |
| German proofing | **49 Dart tests and 10 compiled-JavaScript checks passed** | [Engine report](engine/README.md) |
| Dictionary and hyphenation regeneration | All **18 dictionary files** and the **36,709-pattern** output reproduced exactly | [Engine receipt](engine/receipt.json) |
| Hyphenation, bidi, Word layout, DOCX and PDF regressions | **231 tests passed** | [Test log](engine/hyphenation-layout-export-tests.log) |
| Incoming ODS, Zotero and comment-style regressions | **496 tests passed** | [Test log](engine/incoming-ods-zotero-tests.log) |
| Harper Dart provider contract and native lifecycle guards | **8 provider tests + 3 guard tests passed**; **1 real-library test skipped** | [Engine receipt](engine/receipt.json) |
| Harper packaging and license regressions | **5 Python tests passed** | [Python receipt](harper-python/receipt.json) |

These groups overlap. The counts are not a unique repository-wide total.
The incoming ODS regression count covers the cases in the retained test list;
empty/not-empty semantics were not separately qualified by this proofing work.

The editor run recorded **2,032 source inputs**, **16
runtime/configuration inputs**, the **108-package** workspace, and its exact
resolved lock. Source, runtime, lock and package-configuration hashes all
remained unchanged throughout the final run. The web manifest contains **117 files**
(**59,800,207 bytes**). The engine run separately recorded 4,273 repository
inputs, 3,400 cached dependency source/configuration files and 36 runtime/
configuration inputs; all remained unchanged during that run.

The [engine receipt](engine/receipt.json) and [editor receipt](editor/receipt.json)
retain exact commands, durations, exit codes, log hashes and compressed original
manifests. The [Flutter setup evidence](flutter-setup/README.md) records the
official SDK digest, actual Flutter 3.47.8/Dart 3.13.7 identity, verified locked
archives and successful offline workspace resolution.

## Reproduction

Check out the exact source revision appropriate to the component being repeated.
Use the saved [bootstrap helper](flutter-setup/bootstrap_flutter.py) to prepare
the pinned Flutter SDK/cache and resolve the workspace. The editor verifier is
independent of GitHub Actions:

```sh
python3 docs/validation/proofing-20261116/integration-followup/editor/verify_editor_source_bound.py \
  --repo "$PWD" \
  --flutter /path/to/flutter/bin/flutter \
  --dart /path/to/flutter/bin/cache/dart-sdk/bin/dart \
  --expected-source 3bd4657b1c1cccfad8adbcf5928e30b90e4a1aaa \
  --output /path/to/new-editor-validation
```

Retain the chosen `PUB_CACHE` and `TMPDIR` environment settings. Use a new
output directory for each run. The [engine report](engine/README.md) documents
the isolated pure-Dart harness used for that component; it includes its exact
lock and runner.

## Failed attempts and practical limits

The earlier disk exhaustion, disconnected execution namespaces and failed setup
attempts remain recorded. The first engine attempt used the wrong working
directory for relative fixtures; its complete logs and manifests are in
[the engine attempt archive](engine/initial-harness-attempt.tar.gz).

The [first editor attempt](editor/initial-editor-attempt.tar.gz) retains the
strict-analysis warning and the new test's incorrect viewing-mode assumption.
The guard now uses a named method while retaining a stable callback reference.
The test now uses selecting mode and explicitly verifies mutation is disabled.
The superseded first web build was stopped to validate the corrected source;
although Flutter returned zero after that signal, the verifier rejected its
incomplete output because required JavaScript was absent. The final run
completed without interruption and passed all eight stages against the final source, with the required JavaScript output present and stable inputs.

The final web build emitted the existing, nonfatal CupertinoIcons font warning. The complete warning and successful build completion are retained in the build log.

A release web build establishes compilation and the recorded output files.
Actual browser interaction and HTTP/CSP delivery remain unverified. Real
Android/iOS dictionaries and non-Linux native Harper loading also require their
platform acceptance checks. This continuation does not rebuild or rerun the
real Harper native library or Wasm backend; their previous source-specific
evidence is preserved, while the fresh contract/guard and packaging results
are listed separately above. Optional Harper assets still need the documented
host build/install step.

The German dictionary remains a finite pinned word list and the grammar support
remains the documented conservative rules and terminology checks. The
experimental model stays disabled and evaluation-only: the retained probe
matched 9/18 expected corrections and changed 1/12 valid controls. Its inference
was not rerun.

**No GitHub Actions, workflow, check-run or commit-status endpoints were queried
or waited for.**
