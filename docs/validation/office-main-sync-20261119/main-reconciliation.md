# Concurrent main reconciliation

## Source boundaries

The 1,372-application / 90-Python qualification belongs to
`0669ac119da05f5eb777c8cfdbce32e0261df647`. Publication checkpoint
`26046f9894283f3ac1cc863d355896699693926c` preserves those results and their
original raw bytes. Its post-publication audit verifies all 5,052 bound source
inputs unchanged, and all six archives / 243 members against their originals
and published Git blobs.

While that qualification ran, main advanced to
`b655b8a37fddc874bd42a453c371eed6253e82d8`. PR #178 had been closed after
direct integration at `be6df32b`, whose parents include the older `b8063b8a`
checkpoint. The later `2122066f` reconciliation and `0669ac11` repairs therefore
still needed to be preserved in main. This continuation merges both histories.

The original 401-ref inventory remains a fixed capture at
2026-11-19 07:51:46.468061 UTC. The additional incoming main is identified
separately; it does not retroactively expand or relabel that snapshot.

## Preserved incoming additions

- Optional `quds_proofing_hunspell`, its native and web transports, installer,
  exact source/license bundle, tests and build tools.
- Office Studio's macOS runner and generated Xcode project.
- Arabic rule specification, implementation notes and evidence.
- Later Mail UID and historical integration evidence.
- Three AyaSpell control files. The original five local controls are retained
  as `test_build_bundle_reproducibility.py`; the incoming five and seven
  controls remain alongside them.

## Merge decisions and review repairs

The automatic merge conflicted in three documents. The Arabic roadmap preserves
incoming Hunspell/rule-specification sections and the accurate Unicode/token
behavior from `0669ac11`. Mail status retains discovered-UID paging and v3
cursor freshness instead of reverting to the historical numeric-window limit.
The M06 historical report retains the identities and boundaries of its earlier
qualification, with links to the later records.

At the first incoming-main merge (`aea5d91a`), the earlier cursor, provider and
Arabic implementation/test blobs remained exact copies of `0669ac11`. The incoming change to transport configuration is comment
wording only. The optional package adds one workspace member without changing
any dependency version: enforced offline resolution leaves all 131 previous
package mappings identical, adds only `quds_proofing_hunspell`, and retains the
exact root lockfile. Original pre-resolution bytes are preserved separately.

Incoming main's bundle tests exposed a stale generated-card availability
assertion. The card and both old assertions now distinguish the implemented
optional Hunspell package from the still-open host registration/download UI.
All 17 offline development controls pass; they remain distinct from the frozen
source's earlier 12 controls until fresh merged-source qualification is recorded.

Review also reproduced a native Hunspell resource leak: after awaiting disposal,
an ABI-compatible allocation-counter fixture still observed one live dictionary
handle. The repair and its fresh lifecycle acceptance are recorded with the
merged-source result. Original failing-before output is retained separately.

Both macOS entitlement files now include outgoing network access and read/write
access to user-selected files, matching existing Studio Zotero HTTP and open/save
flows. Existing sandbox, debug JIT and debug server keys remain unchanged. Both
property lists parse and their Xcode references were checked. Bundle identity,
signing settings and other project configuration are preserved.

At that first main merge, guide passages described the active Arabic rules and
optional package while host setup remained open. Native qualification used
explicit fixture inputs. The later `be641457` integration below adds Studio's
user-initiated setup and registration of verified installed dictionaries.

## Qualification boundary

The original 1,372 application executions are retained at their actual source.
New main additions and review repairs receive a separate, source-bound delta
gate. It checks the workspace transition, changed Dart inputs, optional provider
on VM and Node, native/installer lifecycle, selected Mail/Arabic regressions,
browser compilation and the combined publisher controls. No GitHub Actions
workflow, job, status or queue is queried or awaited.

The native Hunspell artifact is built directly with the available C++ compiler
from the exact committed library-source bundle and the ten translation units
listed by CMake. Every source and pinned dictionary input is verified. This is
not a CMake, Emscripten/Wasm or macOS build claim. macOS signing, sandboxed launch,
real file/network acceptance, host download UI and independent linguistic
acceptance remain separate from these Linux qualification results.

## Later current main at `b559f6c7`

Before the repaired gate was frozen, a new direct read found current main at
`b559f6c764fbfac143f593e89ddc1096ad8b5c4e`. That head adds the CrispOffice Studio
branding, localized module navigation, a saved-message Mail reader, refreshed
sample/PDF content, and the T1 Arabic rule set with additional Unicode controls.
Those changes are preserved, including the intentional deletion of the old
Al Tahreer sample and its 35 assets. Their original blobs remain in Git history.

The new Arabic source is reconciled with the existing hamza, mixed-script token,
detached-waw and ambiguous-word safeguards. Native Hunspell disposal and
missing-dictionary repairs remain included. The original 1,372-run qualification
keeps its `0669ac11` identity; the expanded merged-source gate covers T1 rules,
the affected Studio modules/samples and the prior selected Mail/Hunspell paths.
Incoming historical evidence is retained without adding its results to the new
counts. The saved-message Mail surface does not complete an account-aware mailbox
workspace or SMTP composition.

The new Studio dependencies are three packages already in this workspace.
No locked dependency versions change. The package mappings stay stable; the
Studio dependency-graph entry is reconciled explicitly with those three additions.

## Later current main at `be641457`

During the second frozen attempt, main was read at
`be641457c8c7d1acc25091b31c87c73eaa3c9c2a`. It contains PR #185's Word
complex-script language routing, agreeing-provider finding merging, native/web
Hunspell host, explicit dictionary setup, licence assets and target-packaging
helpers, plus new CrispOffice English defaults, Settings and About. All incoming
features and unchanged licence/source bytes are retained.

Review reproduced and repaired these integration defects:

- Digits, punctuation and a BOM alone could select the complex-script language.
  Routing now requires letters unless complex-script formatting is explicit.
- Choosing or resetting a language did not update the active bidi slot. The
  selected fragment now changes the relevant slot, preserving inherited
  formatting, direction and East Asian metadata through undo and DOCX save.
  A changed document bidi default invalidates an already displayed target.
- Two rules from one provider could collapse through an agreeing second provider.
  Each merged group now tracks the providers it already represents.
- Show notes changed the Settings switch but reused the old editor configuration.
  The configuration key now includes that setting; tests inspect the actual
  notes pane, retained controller and note content.
- Pre-cancelled, stalled or final-chunk dictionary downloads could proceed too
  far. Native and web paths now abort active clients and check cancellation up
  to publication; completed installations remain stable after later cancellation.

Studio regressions explicitly select their required language and visible panes
under the new defaults, retaining their layout, focus and editing assertions.
The opt-in screenshot helper is updated and analyzed without claiming a screenshot
run. Formatting-only repairs are recorded separately. Four offline packaging
controls exercise receipt selection, tamper rejection, early flag validation and
exact licence/source copies; they do not build or launch another platform.

The third source-bound plan retains every suite from the rejected second attempt
and adds the affected Word language, merge, host/setup, Settings and cancellation
coverage. All prior failed/development/historical events remain outside its
accepted totals. The original `0669ac11` qualification remains separate.

## Latest Studio presentation and build definitions at `00014577`

A pre-freeze read found main advancing through `baf3dbd0` to
`00014577265d1f95d4c016159029510d3a10804b`. The next merge preserves its
application icons, branding assets, About layout, German labels, native menu
updates and the all-platform binary workflow. The Notes cache-key repair is
reapplied to the latest workspace source, preserving those intervening edits.
The macOS workflow build step receives the same Studio working directory used
by the other platform build steps. Workflow review is static: no Actions run,
job, status or queue is queried or awaited, and no manual dispatch is requested.
These definitions do
not constitute platform-build or optional-backend acceptance.

## Latest review footer at `d8b7f1c4`

The next observed main head is
`d8b7f1c4a576f727a0901c555dc327562dfff2b2`. Its two-file delta compacts the
Studio chrome and moves Word review status into the footer. The merge preserves
that placement, compact sizing, German labels and the earlier Notes setting
repair.

Review reproduced two concrete regressions. First, unavailable or incomplete
proofing could report “No writing issues,” and checking, waiting or paused states
could carry the clean-result icon. The footer now retains the controller's
checking, scheduled, live-disabled, not-yet-checked and partial-result distinctions;
only a complete zero-finding result displays the clean-result status. Seven
regressions drive real public controller/provider states, including unavailable
results in English, German and Arabic and manual coverage awaiting an explicit
check.

Second, the existing 390-pixel Arabic test at 1.4× text scale reproduced a
204-pixel horizontal overflow. Only the new review strip receives bounded flex
constraints and one-line labels. The same narrow-layout case and existing compact
navigation case pass with the seven status regressions in a separate focused
development run. These nine development executions are excluded from final
qualification totals. The full frozen delta gate includes their suites.

## Preserved pre-test rejection at `fce543de`

The [third attempted gate](main-delta-v3/attempt-fce543de/README.md) stopped
before all application and Python tests. Offline locked resolution succeeded,
but the continuity expectation omitted Studio's explicit, already-resolved
`url_launcher` dependency, added by the incoming About page. The corrected
expectation binds all five exact additions: three Mail packages, optional
Hunspell, and `url_launcher`. All 131 prior package mappings, other prior graph
nodes, dependency versions and the root lockfile remain unchanged; the only
new mapping is the Hunspell workspace package.

The original guard, raw output and independent rejection audit are preserved
unchanged. Their successful evidence-integrity checks do not qualify that
attempt: it executed zero application cases and zero Python controls. The next
frozen run uses a fresh output directory and retains every previously selected
suite, adding the new footer regression suite.
