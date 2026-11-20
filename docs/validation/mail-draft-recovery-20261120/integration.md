# Incoming work reconciliation — 20 November 2026

This capture precedes the mail draft recovery implementation. GitHub branch,
open/recent pull-request and commit metadata were read without querying or
waiting for Actions, workflow runs, checks or commit statuses. Local Git fetched
all fork heads, PR heads and the upstream main before implementation.

## Captured main and upstream

- Fork main: `7501b604db23e2df3d765f2ea44f572b2ea43d97`, the merge of PR #223.
- Upstream `MohammedAsaadAsaad/quds_office_suite` main:
  `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`; an ancestor of captured fork main.
- PR #223 retained Zotero work at `a31616d3567a43307251e13a9728cf92fd8690c6`
  and merged Mail attachments PR #221 at
  `177f29d3f9450a58f41189b462b0814aad37e45c` through merge `a45ee3bf`.
- Recent mail providers, EWS, archive/search, export/restore/resume, threading,
  and recipients/Reply all work (#197, #200, #203, #205, #209, #212, #216,
  #217, #221) is already incorporated. The captured main also retains the
  newer web proofing, Arabic morphology and mobile proofing merges.

## Surviving branches at the initial capture

| Branch | Captured head | Disposition |
| --- | --- | --- |
| `main` | `7501b604db23e2df3d765f2ea44f572b2ea43d97` | Integration base |
| `codex/zotero-research-materials-20261120` | `a31616d3567a43307251e13a9728cf92fd8690c6` | Ancestor of main |
| `work/mail-attachments-20261120` | `177f29d3f9450a58f41189b462b0814aad37e45c` | Ancestor of main |
| `codex/vba-variant-conversions-20261120` | `7eedf461d50f19e84cb85086e3757855cd50fb87` | Active draft PR #227; fetch and retain separately |
| `integrate/recent-pptx` | `9c544ecc0377222c1c491f34328b4a7a340fc02e` | Genuine incoming changes, merged with original ancestry |
| `codex/odt-field-continuation-20261117` | `c34945761e7991f5fe49037d79529acdd260b31c` | Combined patch already squashed into #140 |
| `integrate/office-union-148` | `3abf8f43b0e79c10271bbd046f391e462b8fe6b9` | Exact tree already landed in #149; later #152 repairs retained |
| `docs/ods-color-scale` | `58fdddfbcf198a8c0e38e32f6fcc9d6604e95283` | Patch-equivalent to main |
| `docs/ods-data-bar` | `69d14f84cabd3931b7640c1654b401c89faba766` | Patch-equivalent to main |
| `feat/ods-color-scale` | `74ce9ffb816c70c0d2ae50b91ec52a614f26d688` | Patch-equivalent to main |
| `feat/ods-data-bar` | `0a53b8a70128870f3e1df6d18cdb177bb64290ee` | Both unique commits patch-equivalent to main |
| `feat/ods-dynamic-validation-links` | `68a0db23408e4c95d6d283219504c79aea33a6fe` | Patch-equivalent to main |
| `feat/ods-icon-sets` | `005c708e9f747cb46cf02e12c869b0a2f85ac824` | Patch-equivalent to main |
| `feat/ods-time-period-conditions` | `7ef09f2408f467c65427700e65907531ecb26acb` | Patch-equivalent to main |

`git cherry -v main <branch>` identified the eight equivalent commits on the
seven ODS branches. ODT's aggregate patch and squash commit
`2c47165d01d01cc883135a434ac9f6591ce6e770` have the same stable patch ID
`3af21ea00630f8743cf70df6167b863fca712bd1`. The union branch and squash
`4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` have identical trees and matching
aggregate patch ID `9a240fe6c91cc5e99d2896549a87bc8663eac539`. Reapplying
those old branches would duplicate already incorporated work and could undo
later fixes. No old branch was deleted or rewritten.

## Genuine PPTX delta and resolutions

The incoming branch was four commits ahead of main, with merge base
`43db439e1e605d6329a6eabe6817b04ca44ba1aa`:

- `cae167b1b4d006de980f9b65072d38248f41c7ff`: multi-stop gradients.
- `b91761f37aa15e9be1958bb84a72e5c4a8ef4aa0`: merge of then-current main.
- `518ba30e47b68ba3c50f3d8bf55190ba3cc7cde1`: picture shadows.
- `9c544ecc0377222c1c491f34328b4a7a340fc02e`: picture transparency.

The ordinary merge conflicted only in `slide_serial.dart` and
`slide_import_fidelity_test.dart`. Current main's background ownership and all
existing tests were retained. Selected gradient backgrounds now use the same
copy/edit/clear lifecycle as selected pictures; they are not inserted among
ordinary master/layout decorations. Slide/layout overrides and hidden-master
behavior remain independent.

Review corrected these integration defects:

- Wire the new gradient renderer into PDF shape painting; keep connector stroke
  behavior and freeform clipping.
- Use each shape's projected width/height for gradient endpoints, including
  narrow vertical shapes.
- Reset shape-gradient parsing state so a later text gradient cannot borrow a
  preceding shape's stops.
- Apply picture opacity once; avoid multiplying paint opacity and matrix alpha.
- Paint one soft editor shadow rather than stacking the new shadow over the
  existing hard one. Keep the incoming PDF shadow before the image.
- Expose the working linear-gradient API. Inactive table-gradient and radial
  placeholders in the incoming patch are omitted. Path gradients retain the
  prior solid fallback; imported background source XML remains preserved.

Added tests exercise PDF colors/shadows, shape copy/save, inherited gradients,
explicit background replacement, repeated saves, parser scope, actual Flutter
pixels at gradient edges, picture opacity and the single shadow. Existing
import, rendering and transform regressions are included in the focused gate.
Final source-bound outcomes and raw events are recorded under `incoming-office/`.
This gate does not claim native PowerPoint or physical-device acceptance.

## Active independent work

PR #227 was the only open PR in the initial audit, remained draft and explicitly
reported combined-source qualification in progress. Its head advanced during
inspection to `7f157fcbd077c8bb41d8f52c3234e82b4daeea5c`; the PR reported
merge conflicts at that point. Its body identified nullable-expression and
Variant/object-checking gaps under repair. It is retained as fetched work and
must be refreshed before final publication. This mail integration does not
rewrite its branch or mislabel it as qualified. A later ready/merged state
requires a fresh source review and the relevant local validation.
