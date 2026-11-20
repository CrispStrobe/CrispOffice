# Final incoming-reference audit — 20 November 2026

The fork's `main` remained at `5e38de19ab5af8d6811d601c7317cba7f69d516b`.
A newly opened, non-draft Android grammar PR supplied a small documentation and
workflow continuation, which was incorporated with original ancestry during
this audit. The active VBA and Zotero checkpoints still explicitly describe
unfinished combined-source qualification and remain separate.

## Capture and method

The audit began at **2026-11-20 09:07:25 UTC** (10:07:25 Europe/Berlin).
The principal PR metadata observations completed at **09:09:24 UTC**. The
post-fetch Git reference inventory was captured at
**2026-11-20T09:10:40.351141+00:00**. These are sequential observations, not an atomic
snapshot of all GitHub state. Contributors continued publishing while the
Mail task ran; this report records exact observed objects rather than assuming
that every branch stopped advancing.

The fixed comparison base was Mail checkpoint
`ffb8cee3acec878cdbe3c27e0bb82f228468a30f`. At the reference-inventory capture,
the task's own remote and local checkpoint had advanced to
`e7fa9095bf1e0a9f80a0c87b6d46d7d4f5a585cd`. The subsequent Android integration was
independently observed reachable from local
`49e854d6b80ae00c8883c866f34bdeecd21fb93a` at `2026-11-20T09:11:35.818387+00:00`.
The changing task head does not change the fixed ancestry comparisons below.

The audit fetched all **22 fork branch heads**, all **236 pull-request heads**,
and all **four upstream branch heads**. GitHub branch metadata and open-PR
metadata were read. No GitHub Actions, workflow runs, checks or commit-status
endpoint was queried, and no hosted CI completion was awaited. A retained
source document contains an existing Actions URL; that link was not opened.
No product file, working branch or remote branch was changed by the audit.
The parent task separately performed the already authorized Android merge.

```bash
git fetch origin \
  '+refs/heads/*:refs/remotes/origin/*' \
  '+refs/pull/*/head:refs/remotes/pull/*'
git fetch upstream '+refs/heads/*:refs/remotes/upstream/*'
git for-each-ref --format='%(refname) %(objectname)' \
  refs/remotes/origin refs/remotes/upstream refs/remotes/pull
git merge-base --is-ancestor <captured-head> \
  ffb8cee3acec878cdbe3c27e0bb82f228468a30f
git cherry ffb8cee3acec878cdbe3c27e0bb82f228468a30f <historical-ODS-head>
```

The complete reference inventory, ancestry counts, historical `git cherry`
results, PR states and original PR descriptions are retained in
[git-refs.json](remote-refresh/git-refs.json) and
[github-metadata.json](remote-refresh/github-metadata.json). Fetch diagnostics
are retained as `fetch-origin.stderr` and `fetch-upstream.stderr`, with their
corresponding stdout files. Both fetch commands completed successfully.

## Open pull requests

| PR | Exact observed head | Observed state | Disposition |
| --- | --- | --- | --- |
| [#227 — VBA Variants and paragraph macros](https://github.com/CrispStrobe/quds_office_suite/pull/227) | `1ceae221d37e733f0195d35622a05f896a2d13a1` | Open, draft; updated 09:04:02 UTC | Retained separately. The PR explicitly says qualification and reconciliation remain in progress. |
| [#234 — CrispOffice app identities](https://github.com/CrispStrobe/quds_office_suite/pull/234) | `afc3524eb896c496475d6763ab4b37dddfe68932` | Open, non-draft | Already incorporated with original ancestry. Migration corrections and static review are described in the incoming Office report. |
| [#236 — Android arm64 grammar qualification](https://github.com/CrispStrobe/quds_office_suite/pull/236) | `67a4917b33dcd578333adabac1c50db0fc2a62b6` | Open, non-draft; created 09:07:25 UTC and updated 09:07:45 UTC | Its new documentation and workflow continuation was incorporated with original ancestry during this audit. |

The upstream repository returned no open PRs for
`repo:MohammedAsaadAsaad/quds_office_suite is:pr is:open` at this capture.
A non-draft PR state is not treated as proof that its author's platform tests
were reproduced here. The prior native qualification retains its original
platform, source, library-digest and execution attribution.

## Newly ready Android continuation

The task had already incorporated Android head
`7ac3d3be4a62bf9d2e0ab8a67f0e122568691b22`. Exactly two new non-merge commits
were absent from the fixed audit base:

| Commit | Changed paths | Effect |
| --- | --- | --- |
| `cf5532b3978c074f96e2448c2f47773609a08c18` | `docs/validation/native-spacy-android-grammar-20261120/README.md`; `docs/validation/native-spacy-android-grammar-20261120/ios.md` | Records where the existing runs occurred and makes the absence of an iOS grammar claim explicit. |
| `67a4917b33dcd578333adabac1c50db0fc2a62b6` | `.github/workflows/android-spacy-grammar.yml` | Runs `rustup target add` inside the Harper crate so the target is installed in the crate's pinned toolchain. |

The intervening merge `33ed2e82` incorporates the already retained fork main.
There are no additional product source paths in this continuation.
The task incorporated the new head without discarding its original ancestry;
[android-tail.json](remote-refresh/android-tail.json) and
[integration-relationships.json](remote-refresh/integration-relationships.json)
record the exact identities and reachability. The parent task separately
reported successful YAML parsing and `bash -n` of all nine workflow run blocks;
this audit did not run or query the workflow.

The Android PR's existing arm64 replay result does not claim a newly completed
mobile gate. Its iOS document explicitly withholds a device grammar claim and
distinguishes simulator bytes from device bytes. Those boundaries remain part
of the incoming evidence.

## Active independent work

PR #227 advanced from `1fe093a217741d228c86bad4e6a5a13f777ed851` to
`1ceae221d37e733f0195d35622a05f896a2d13a1`; it remains draft. Its new head merges
the already integrated manual Android workflow from main. The PR description
still says independent review and combined-source qualification are in
progress. Its committed
[VBA evidence README](https://github.com/CrispStrobe/quds_office_suite/blob/1ceae221d37e733f0195d35622a05f896a2d13a1/docs/validation/office-vba-variant-conversions-20261120/README.md)
has a **Work in progress** section and explicitly distinguishes development
receipts from the pending final combined-source gate.

The new `codex/word-powerpoint-vba-20261120` head
`b9e4f1d4bc691714f68e3685dbf729b09ccb0449` inherits the older draft VBA head
`1fe093a2`, Zotero image head `3100725d`, Zotero list/image continuation
`aa51b570`, and integrated main `5e38de19`. It does not contain the subsequent
VBA merge `1ceae221`. Its latest three first-parent commits reconcile incoming
Mail, PPTX and Android work; the branch has not replaced the inherited
[VBA work-in-progress report](https://github.com/CrispStrobe/quds_office_suite/blob/b9e4f1d4bc691714f68e3685dbf729b09ccb0449/docs/validation/office-vba-variant-conversions-20261120/README.md)
with a final combined-source acceptance report. No separate open PR for this
new branch was returned by the captured open-PR search.

The original Zotero image head
`3100725d07a715f230c263f640dbd588c7c75660` remains unchanged. Its
[embedded-image report](https://github.com/CrispStrobe/quds_office_suite/blob/3100725d07a715f230c263f640dbd588c7c75660/docs/validation/zotero-note-images-20261120/README.md)
explicitly says **In progress**. The separate continuation advanced from
`aa51b5700a4791db088a2d47b66ff521540b42e0` to
`a4ed68f2c78e0f41013c2af160fe84e27d9d84ad`, incorporating autofit repairs and
incoming Android/PPTX work. Its
[continuation report](https://github.com/CrispStrobe/quds_office_suite/blob/a4ed68f2c78e0f41013c2af160fe84e27d9d84ad/docs/validation/zotero-parity-continuation-20261120/README.md)
still says **In progress**, records that main has not been published by that
continuation, and retains a **Remaining publication gate** section.

These four heads were fetched and retained. Their current evidence does not
establish completed combined-source acceptance. They are not silently merged,
overwritten or deleted as part of Mail publication. The exact committed
progress markers, path names, line numbers and blob identities are retained in
[progress-markers.json](remote-refresh/progress-markers.json).

## All captured fork branches

| Fork branch | Exact captured head | Disposition |
| --- | --- | --- |
| `ci/android-spacy-grammar-workflow` | `596fb68f64c447177ed202a40f890c20205a0270` | Already an ancestor of the audit base. |
| `codex/odt-field-continuation-20261117` | `c34945761e7991f5fe49037d79529acdd260b31c` | Already landed as the ODT squash; 37 changed paths match the accepted ancestor by mode, type and blob. |
| `codex/vba-variant-conversions-20261120` | `1ceae221d37e733f0195d35622a05f896a2d13a1` | PR #227 remains draft; qualification explicitly in progress. Retained separately. |
| `codex/word-powerpoint-vba-20261120` | `b9e4f1d4bc691714f68e3685dbf729b09ccb0449` | New concurrent branch inherits unfinished VBA and Zotero checkpoints; retained separately. |
| `codex/zotero-parity-20261120` | `3100725d07a715f230c263f640dbd588c7c75660` | Embedded-image report explicitly in progress. Retained separately. |
| `codex/zotero-parity-continuation-20261120` | `a4ed68f2c78e0f41013c2af160fe84e27d9d84ad` | Continuation report explicitly in progress with remaining publication gate. Retained separately. |
| `codex/zotero-research-materials-20261120` | `a31616d3567a43307251e13a9728cf92fd8690c6` | Already an ancestor of the audit base. |
| `docs/ods-color-scale` | `58fdddfbcf198a8c0e38e32f6fcc9d6604e95283` | All unique commits are patch-equivalent to the audit base (`git cherry` reports `-`). |
| `docs/ods-data-bar` | `69d14f84cabd3931b7640c1654b401c89faba766` | All unique commits are patch-equivalent to the audit base (`git cherry` reports `-`). |
| `feat/android-spacy-grammar-20261120` | `67a4917b33dcd578333adabac1c50db0fc2a62b6` | New non-draft PR #236. The two new non-merge commits were incorporated during this audit; see below. |
| `feat/crispoffice-rename-20261120` | `afc3524eb896c496475d6763ab4b37dddfe68932` | Non-draft PR #234; its exact head is already an ancestor of the audit base. |
| `feat/ods-color-scale` | `74ce9ffb816c70c0d2ae50b91ec52a614f26d688` | All unique commits are patch-equivalent to the audit base (`git cherry` reports `-`). |
| `feat/ods-data-bar` | `0a53b8a70128870f3e1df6d18cdb177bb64290ee` | All unique commits are patch-equivalent to the audit base (`git cherry` reports `-`). |
| `feat/ods-dynamic-validation-links` | `68a0db23408e4c95d6d283219504c79aea33a6fe` | All unique commits are patch-equivalent to the audit base (`git cherry` reports `-`). |
| `feat/ods-icon-sets` | `005c708e9f747cb46cf02e12c869b0a2f85ac824` | All unique commits are patch-equivalent to the audit base (`git cherry` reports `-`). |
| `feat/ods-time-period-conditions` | `7ef09f2408f467c65427700e65907531ecb26acb` | All unique commits are patch-equivalent to the audit base (`git cherry` reports `-`). |
| `integrate/office-union-148` | `3abf8f43b0e79c10271bbd046f391e462b8fe6b9` | Exact tree already landed in accepted squash 4b2b4e78; later repairs retained. |
| `integrate/recent-pptx` | `20573cabfd4dcae091e4c705fd58277cc6372075` | Exact head already an ancestor of the audit base; incoming rendering repairs are covered by the separate local Office report. |
| `main` | `5e38de19ab5af8d6811d601c7317cba7f69d516b` | Unchanged from the integrated 5e38de19 main; already an ancestor of the audit base. |
| `work/mail-attachments-20261120` | `177f29d3f9450a58f41189b462b0814aad37e45c` | Already an ancestor of the audit base. |
| `work/mail-draft-recovery-20261120` | `20b2ecf572f8fd5663a728529da7bf5c7ebbda1d` | Already an ancestor of the audit base. |
| `work/mail-workspace-20261120` | `e7fa9095bf1e0a9f80a0c87b6d46d7d4f5a585cd` | This task's fifth remote checkpoint at the inventory capture; the local task advanced during the audit. |

The seven ODS branches have eight unique commits; all eight are patch-equivalent
to the fixed audit base. For the ODT continuation, all 37 aggregate changed
paths are identical by Git mode, type and blob to accepted squash
`2c47165d01d01cc883135a434ac9f6591ce6e770`. The union branch tree exactly equals
accepted squash `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4`. Both accepted
squashes are ancestors of the audit base. These fresh comparisons are recorded
in [historical-equivalence.json](remote-refresh/historical-equivalence.json).
The older branches are not replayed over subsequent fixes.

## Upstream branches

| Upstream branch | Exact captured head | Disposition |
| --- | --- | --- |
| `ci/flutter-workspace` | `aca2f66941832bd0b19b436baeab1656a1b7de98` | Already an ancestor of the audit base; no unique commits to integrate. |
| `cursor/class-certificates-2db8` | `f45099688e7a3f67a1302efdb442830d052f2240` | Already an ancestor of the audit base; no unique commits to integrate. |
| `cursor/cloud-agent-1790580069020-0rk1h` | `9930be8df44ffe117fb22778c514eea0ee73ce21` | Already an ancestor of the audit base; no unique commits to integrate. |
| `main` | `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` | Already an ancestor of the audit base; no unique commits to integrate. |

## Acceptance and publication boundary

This is a reference and source-readiness audit. It does not add runtime test
cases to the accepted Mail or Office totals. The repaired incoming Office
source, actual local selections, raw runner output, regression controls and
platform limits are recorded in [incoming-office.md](incoming-office.md).
The runtime and development transport evidence have their own scope in
[runtime/README.md](runtime/README.md). Final Mail acceptance must identify the
exact combined product inputs used by its own local run.

Remote references can advance after this capture. Publication must recheck
main and preserve any later qualifying changes before updating remote main.
This report's snapshot remains attributable to its recorded objects and times.
