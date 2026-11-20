# Word and PowerPoint VBA continuation — 20 November 2026

## Completed local qualification

**2,190 test cases passed across 64 files, with zero failures and
zero skipped tests.** The runner exited 0. Engine analysis with `--fatal-infos`
reported no issues; the 17 relevant Dart files required no formatting changes.
The actual Word and PowerPoint BAS examples each produced 12 native operations
on both the VM and compiled JavaScript. Their semantic JSON outputs matched
byte for byte, including a second native save/reopen.

The accepted engine source is `08020076b1552fef214d7625ace7ae087b70be88`
(tree `76b0a8eb9625b45ec0deaa9a26baa1bb21db62c8`). The later integration checkpoint
`153c818cd6dba07559fead6e86214a8482cf08b7` includes the final captured remote snapshot. Every input in
the recorded engine/test/tool/example/font/lockfile scope is byte-identical to
the accepted source. Subsequent delivery changes are documentation and evidence.

| Gate | Executed result |
| --- | --- |
| Combined local regression selection | 2,190 passed; 64 files; exit 0 |
| New Word typography and PowerPoint layout/transition cases | 165 cases within that total |
| Strict engine analysis | No issues; exit 0 |
| Dart formatting | 17 files; zero changes |
| Actual examples on Dart VM | Both complete native transactions pass |
| Actual examples compiled to JavaScript | Compilation and Node execution pass; output equals VM |
| Input identity | All recorded source hashes unchanged during the gate |
| GitHub Actions | Neither used as an acceptance gate nor awaited |

See [the qualification receipt](qualification.json),
[per-file counts](runtime/cases-by-file.json),
[the exact selection](runtime/selection.json),
[environment and dependency versions](runtime/environment.json), and
[portable semantic results](runtime/portable-result.json).
[Raw events, exit codes, full source hashes and executed drivers](runtime/acceptance-evidence.tar.gz)
are retained in an archive with SHA-256 `e1fb9b4f685e126fa0470ac4102b1fbeb3692eceb5f4d09d1062e060bf479828`.
Earlier attempts are not added to the accepted case count.

## Delivered capability

Word adds explicit `ActiveDocument` / `Application.ActiveDocument` bindings,
`Paragraphs.Item`, `Font.SmallCaps`, `Font.Superscript`, `Font.Subscript`, and
the fixed `HighlightColorIndex` palette plus removal. True small caps explicitly
clears the opaque AllCaps property; script-mode clears retain the opposite mode
in mixed runs. Explicit baseline and no-highlight survive inherited styles and
repeated saves. Namespace-qualified ownership retains unrelated XML properties.

PowerPoint adds typed TextFrame/Font/ParagraphFormat/SlideShowTransition aliases
and helpers, top/middle/bottom vertical anchors, slide visibility, click advance,
exact positive millisecond duration, and eleven supported effect constants.
Partial transition edits retain automatic timing, sounds and extension data.
Empty text bodies and same-value writes retain explicit intent. Unsupported
root MC transition containers survive unrelated saves and refuse transition
edits before publication. Known Morph/native extension projection and the
historical unbound-fragment parser contract remain supported.

The native and source adapters retain detached validation/publication, late
failure rollback, policy enforcement, recording rules and inert embedded VBA
parts. These are bounded source-to-plan adapters. They do not execute existing
embedded VBA projects or provide COM, events, document-content reads, a macro
ribbon/editor, or complete Microsoft VBA compatibility.

See [Word vocabulary and limits](../../VBA_WORD_MACROS.md),
[PowerPoint vocabulary and limits](../../VBA_POWERPOINT_MACROS.md), and
[the parity roadmap](../../VBA_PARITY_ROADMAP.md).

## Reconciled remote work

The work began at main `d040c15a07f652d01e75363031d0efdee6357bda`.
The first intake fetched every then-live fork branch and all 239 available PR
heads before implementation. Its later 25-branch/241-PR proof is retained
separately from the final live snapshot captured at 2026-11-20 11:02:39 UTC:
16 live branches and 244 PR heads. The inclusion receipts distinguish actual
ancestry from exact historical equivalence; no equivalent commit is claimed as
an ancestor merely because its files match.

The integration includes typing/proofing, Mail, Zotero, fonts, Downloads and the
later accepted main changes. The final captured heads include main
`e59b8918db508da46039a943080dc4b7a5c7a0bb`, Downloads
`d886ee8eb985f34c2ce5a02cc6044d6f88132bf6`, and Mail accounts
`c8b5080ad3d33abda44275a9b3679514d7526c58`.

The latest accepted Word reader is retained verbatim, together with both the
incoming Zotero structural tests and our independent per-note counter/marker
regressions. Downloads retains the latest grouped/localized catalog and RTL
correction together with installed-font review/repair, busy guards and visible
errors. Mail-account source merges without changing the engine acceptance inputs.

See [final inclusion and preservation evidence](integration/final-inclusion.json),
[the initial branch audit](incoming-branches.json),
[the initial PR audit](incoming-prs.json), and
[incremental remote checkpoints](integration/checkpoints.json).
The retained branch is `codex/word-powerpoint-vba-continuation-20261120`.
Each published checkpoint tree was compared with its local tree and updated
with an expected-head lease; original incoming parents remain in the history.

## Corrections found by the local gate

The existing Morph fixture exposed a namespace-filter regression. The fix
recognizes known Microsoft extension namespaces and permits conventional
unbound prefixes only for the existing unbound `p:sld` fragment contract.
Foreign bindings, nested lookalikes and opaque root MC containers retain their
guards. Existing and new regression cases pass in the accepted gate.

Incoming Zotero note-target tests exposed a preexisting Word reader gap:
numbered note paragraphs had native numbering IDs but no reconstructed labels.
Latest main independently fixed the same gap. Its unchanged projection runs
with separate counters for body and each note story, matching the existing
restart serializer. Both regression sets survive integration and pass.

The shared filesystem exhausted capacity during earlier attempts. Five native
failures were also caused by font fixtures omitted from the sparse checkout;
the exact repository fixtures were restored. The final accepted run uses the
supported `package:test --compiler source` strategy with concurrency 4 and
fail-fast enabled, avoiding test-kernel cache duplication. Failed and interrupted
attempts are historical evidence only; see [recovery history](recovery/README.md)
and [the earlier source checkpoint](development/source-5cf0fb7b.json).

## Qualification boundaries

The recorded environment uses Dart 3.13.7 and Node v24.22.3.
Both package manifests match the repository and all 56 shared resolved
dependency versions match the repository lock. No production dependency or
compiler implementation was modified to make the gate pass.

Flutter widget/desktop/browser UI, installed Microsoft Word/PowerPoint,
platform keychains and live mail providers were not executed here. Incoming
Downloads, PDF and Mail UI changes are preserved and source-reviewed; their
new UI/provider tests are not represented as passing results of this gate.
Imported placeholder performance results and unfinished qualification plans
are likewise not counted as executed evidence.
