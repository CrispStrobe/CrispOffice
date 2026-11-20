# Arabic main follow-up


The latest combined source is **`f69e774fbb32a103260541e4a28fb17600bfc17e`**,
tree `1a45545ffa7f4c8548853a30c95bdb38309e3da9`. It preserves published main
`098412152fa1d64796eb3fb9c06699ced0f0c44d` (PR #231) and the complete earlier
source/evidence checkpoint `a3373021`. The ordinary merge is conflict-free;
all 38 incoming paths, including 23 Dart paths, match main exactly. The
[incoming review](incoming-review.json) covers the Arabic
context-morphology API, host setup, transport, grammar rules, pins and notices.

| Fresh Arabic follow-up gate | Distinct passing cases | Files |
| --- | ---: | ---: |
| [Morphology unit](accepted-arabic-unit/receipt.json) | 17 | 1 |
| [Engine Arabic rules](accepted-engine-arabic/receipt.json) | 526 | 4 |
| [Studio integration](accepted-studio-integration/receipt.json) | 90 | 7 |
| **Latest focused total** | **633** | **12** |

Every selected case passes with all original source, runtime, dependency,
configuration, coverage and event-accounting guards; there are no failures or
skips in these three cohorts. The Studio selection includes new Arabic setup,
downloads, settings, linguistic analysis, comment drafts, Zotero shortcuts and
citing transport. The author's unspecified Studio baseline exception is not
used to excuse any failure here. The [independent summary](summary.json)
and [source applicability](applicability.json) preserve
all earlier raw receipts and their original source attribution. These 633
cases overlap earlier proofing/Studio selections and are not added to earlier
totals. Word, Zotero, slide and Mail implementations remain exact; changed
Arabic and Studio paths receive this separate qualification.

**All 129 active changed Dart targets pass strict analysis and formatting.**
The [static receipt](static/receipt.json) captures all 131
changed-file fingerprints, including the same two byte-preserved historical
Mail harnesses excluded from the active selection. The earlier 110-path
archive-inclusive diagnostic remains unchanged; it is not relabeled or rerun
as this source's acceptance.

The [dependency proof](dependency-reuse.json) explicitly
records the local morphology manifest's version change from 0.2.0 to 0.3.0.
Dependency edges, unversioned local path consumers, hosted versions/hashes and
resolved paths are unchanged. The saved graph retains its prior 0.2.0 label
and the earlier indirect Studio-to-web edge; neither is claimed to have been
regenerated. All 126 hosted versions/hashes, 4,502 dependency files, 12 runtime
records and both configurations match their prior inputs. The effective 152
package dependency closures remain equal. No package resolution or runtime
replacement was required for these tests.

Arabic's updated native ABI 3 / adapter 2 requirement is distinct from the
unchanged spaCy library. The macOS build script builds and installs the Arabic
library separately, and its updated builder pins the compatible revision.
Existing ABI 2 Arabic libraries require rebuilding. This is a source-level
compatibility review; the native build, real model execution and WebAssembly
runtime are not freshly qualified in this environment.

**Browser qualification remains unavailable.** The earlier blocked Chrome
attempt belongs to `a45ee3bf`; no fresh browser application cases execute at
this later source. In particular, the earlier PR #229 nine-path equivalence
is superseded where the Arabic README and web host changed. The
[web model-removal limitation](web-model-removal-limitation.json)
records an additional source-identified concern: the web host retains a
verified database object whose buffers are transferred to its worker, then
reuses that object when removing the optional model. On the JavaScript path,
those retained buffers can already be detached, so restoring the base analyzer
is at risk. This is a source finding, not a reproduced browser result, and it
is retained as an incoming Arabic limitation outside the Zotero workflow.

Reproduce the three selections using `run_arabic_followup.py`
with `--expected-head f69e774fbb32a103260541e4a28fb17600bfc17e` and fresh output
directories. Use `run_product_static.py` for its exact
active-source static selection. The summary retains native/browser scope and
all source boundaries explicitly.


The preceding source phases are retained in the [complete continuation report](../README.md).
