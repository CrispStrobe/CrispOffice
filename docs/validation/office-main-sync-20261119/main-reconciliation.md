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

Older guide passages now describe the active Arabic rules and optional Hunspell
package consistently. No dictionary is downloaded and no Hunspell provider is enabled by the
application automatically; native qualification uses explicit fixture inputs.

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
