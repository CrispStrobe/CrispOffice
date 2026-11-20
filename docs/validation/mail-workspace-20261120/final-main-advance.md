# Final main advance: Word/PowerPoint VBA and proofing integration

The newly captured main is
**`d040c15a07f652d01e75363031d0efdee6357bda`**. It merges the previously reviewed
main `33190e50cae486be362eedb5fa687dd9c82b0c51` with the completed
Word/PowerPoint VBA evidence head
`06f119566235aa3765445526f5ffab48832b1a31`.
The latter also carries an incoming proofing/editor change whose runtime
qualification is explicitly outside that author's engine gate.

This audit read committed Git objects and recorded its receipt at
**2026-11-20T09:56:07.531308+00:00**. It performed no product edit, merge, commit,
test execution, remote-reference fetch or hosted-CI query. The complete source
deltas, exact blob IDs, ancestry checks and inspected evidence identities are
in [final-main-advance.json](final-main-advance.json).

## Source and ancestry

| Object | Exact identity or observation |
| --- | --- |
| New main | `d040c15a07f652d01e75363031d0efdee6357bda` |
| Main's first parent | `33190e50cae486be362eedb5fa687dd9c82b0c51` |
| Main's incoming VBA parent | `06f119566235aa3765445526f5ffab48832b1a31` |
| Mail task before its new-main merge | `811fb16297524ac3ea051f0d7f8bd264b45d4636` |
| Common merge bases | `33190e50cae486be362eedb5fa687dd9c82b0c51` and `44abcfa10367c8cf586ad3cf826feb3cb1de6dab` |
| Later Mail/Office follow-up `01290ceed6f9163023ce8f27bb74033f088b62e4` | Not an ancestor of captured main; its changes remain to be preserved by the parent's merge. |
| Earlier Word/PowerPoint branch head `b9e4f1d4bc691714f68e3685dbf729b09ccb0449` | Now a true ancestor of main through the incoming VBA branch. |
| Proofing head | `604e5f1ab3b70d1cd770e4413f54d167078185a4`, a true ancestor of main. |

The prior reports remain historical captures. This new ancestry supersedes the
previous current disposition that `b9e4f1d4` was separate. Its actual merge
commits are now included; no tree-equivalence inference is needed to establish
that fact.

The incoming VBA report names final product source
`a6068b4d46421e8a0c5921ba0b5cc24b4873ca12`. Its entire engine tree is
`aabb48ef7ab6a79904a889c50dc3756eab116e7c`. This audit independently checked
that **the exact same engine tree is present at `d040c15a`** and is the tree
named in the incoming macro and PDF receipts. That identity applies to the
captured main; the parent's later resolved merge must retain its own source
and qualification record.

## Changed inputs and Mail preservation

Relative to `33190e50`, the new main changes **169 tracked paths**, including
**57 package/app paths**. Relative to the Mail task's `811fb162` checkpoint,
there are **50 package/app paths** with different blobs. Both complete
comparisons are retained in the JSON receipt, with statuses and exact old/new
blob identities. The differences include Word/PowerPoint compiler and native
operations, PDF/PPTX reconciliation, proofing scheduling/status controls,
Studio integration, tests, examples and evidence.

All **122 selected Mail implementation and manifest paths** match `811fb162`
exactly. These are the same explicitly enumerated Mail package and Studio host
paths used by the earlier audit; their selection is referenced in the receipt.
The source comparison does not remove the need to qualify changed shared
Studio, editor and rendering dependencies against the parent's final merge.

No Pub manifests/locks, SDK pin, analyzer configuration, Melos configuration,
Rust/Cargo manifests/locks or npm manifests/locks differ from the Mail
checkpoint. The workflow differences are confined to:

- `.github/workflows/ci.yml`: an added macOS Poppler installation step for the
  gallery-rendering test.
- `.github/workflows/typing-proofing-benchmark.yml`: a new configured benchmark
  and Studio-suite comparison across branch and merge-base sources.

These files were inspected as committed source. No workflow run or status was
requested or used as an acceptance condition.

## Incoming VBA and PDF qualification: original attribution

The source and evidence are retained in the incoming
[Word/PowerPoint report](../office-vba-word-powerpoint-20261120/README.md).
Its final source extends the bounded shared compiler with a PowerPoint
application adapter and additional Word formatting. It retains explicit native
transactions, permissions, work limits, positioned diagnostics and preservation
of opaque embedded VBA projects. It does not claim full VBA or Microsoft Office
object-model compatibility.

| Other contributor's gate | Exact recorded source and outcome | Scope retained here |
| --- | --- | --- |
| Frozen macro gate | Start `fb09a29b70e469c2858bde48c8977590791b6ba7`; finish `55e52def1b964a85764eb9c4fcf8163fbdcee625`. **1,221 executed cases across 32 files**, zero failures/skips; strict whole-engine analysis passed. | Compiler, operations, transaction/admission/rollback, conformance, MCP and real CLI subprocesses. |
| PDF/import reconciliation | Same engine tree; **213 cases across 10 files**, in three bounded processes, all exit codes zero. | Autofit, layout, geometry, opacity/alpha resources, radial fills, backgrounds and import preservation. |
| PowerPoint portability | Source `55e52def`; Dart **3.13.7** and Node **24.22.3**. **20 conformance cases per runtime**, plus the native transaction smoke, report byte-identical VM/JavaScript receipts and unchanged inputs. | Bounded application adapter and transaction behavior; no Microsoft Office host execution. |
| Runnable PowerPoint example | Public default `Main` entrypoint; **18 independently specified native operations**, followed by PPTX save/readback. | Both formatted target shapes, unchanged third shape, calculated text and validation without publication. |

The recorded macro gate hashes **1,041 inputs** before and after execution.
The subsequent reconciliation to `a6068b4d` rechecked all 1,041 as identical.
Its frozen engine identity matches captured main as described above. The
incoming README distinguishes 1,221 runner executions from 1,220 display labels
because two guard fixtures share an existing title; the retained identifiers
preserve those distinct inputs.

The macro and PDF selections overlap. Their counts are **not summed into a
unique grand total and are not added to this Mail task's local acceptance**.
This audit inspected source identities and retained receipt fields; it did not
rerun those external commands. The standalone Dart runtime, reduced validation
workspace and dependency-lock provenance belong to the original report, not
this task's Flutter installation.

## Proofing/editor boundary

Proofing head `604e5f1a` follows the earlier as-you-type coalescing work and
changes progress/manual-cache handling and Studio status/theme scheduling.
The incoming VBA report explicitly says the inherited editor/proofing
integration received **source and call-site review**, and that its engine tests
**do not qualify Flutter runtime behavior**. No native application build or
Microsoft Office host was executed by that incoming gate.

The new workflow's comment references
`docs/performance/typing-proofing-20261120.md`, but that path is absent from the
captured `d040c15a` tree. The inspected committed evidence therefore does not
establish a completed typing benchmark or a measured performance improvement.
The parent's new combined-source Studio/proofing checks must stand on their
own actual commands, input hashes and outcomes. No queue wait or Actions result
is required for this local qualification.

This follow-up changes no acceptance totals by itself. It records the landed
feature ancestry, exact applicable incoming engine evidence, unchanged Mail
implementation/configuration scope, and the separate shared-UI qualification
boundary. It makes no claim of full Mail-client, VBA, Zotero or Office parity.
