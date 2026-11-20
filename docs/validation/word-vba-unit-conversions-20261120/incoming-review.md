# Incoming integration review — Word VBA unit conversions

Reviewed on 2026-11-20 before implementing the unit-conversion extension. This
review used the live GitHub branch and pull-request APIs and the fetched Git
history. It did not wait for GitHub Actions or change workflow settings.

## Captured starting state

- Repository: <https://github.com/CrispStrobe/quds_office_suite>.
- Remote `main`: `c954d00d2fc85604ae394674bca91ea8a1dede0e`.
- 36 branch heads were inspected; 24 non-main heads were already ancestors of,
  or identical to, the captured `main`.
- The explicit open-PR endpoint returned an empty array. The latest 100 updated
  PRs were also inspected; none was open.
- Upstream `MohammedAsaadAsaad/quds_office_suite/main`:
  `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`. A local
  `git merge-base --is-ancestor` check confirmed it was already in `main`.

## Recent outstanding ancestry

The existing branch `codex/word-vba-measurements-20261120` at
`30c8401d6c6083737c2bdb55dd08e5aa03162aff` was two commits ahead of captured
`main` and had an identical file tree. It merges these parents:

- `c954d00d2fc85604ae394674bca91ea8a1dede0e` (captured `main`);
- `332d7b26a320ca560f4f2214e1e63da9392269ab`
  (`fix/main-green-20261120`).

The latter commit only changes the attribution matrix in
`.github/workflows/tmp-regenerate-editor-goldens.yml`. Main had intentionally
removed that temporary workflow. The existing merge preserves the deletion
while retaining the maintenance commit's history; it has no product changes.
The new working branch `codex/word-vba-unit-conversions-20261120` starts from
this reviewed merge. No temporary workflow is restored.

## Retained historical heads

These divergent branch heads already have equivalent work in `main`; replaying
their patches is unnecessary. The evidence below checks content equivalence,
not merely branch names or PR state.

| Branch | Captured head | Verified representation in main |
| --- | --- | --- |
| `docs/ods-color-scale` | `58fdddfbcf198a8c0e38e32f6fcc9d6604e95283` | `git cherry -v origin/main` reports patch equivalence (`-`). |
| `docs/ods-data-bar` | `69d14f84cabd3931b7640c1654b401c89faba766` | Patch equivalent (`-`). |
| `feat/ods-color-scale` | `74ce9ffb816c70c0d2ae50b91ec52a614f26d688` | Patch equivalent (`-`). |
| `feat/ods-data-bar` | `0a53b8a70128870f3e1df6d18cdb177bb64290ee` | Both unique commits are patch equivalent (`-`), including `b8ddaaeb581e010467de304c828764d353149102`. |
| `feat/ods-dynamic-validation-links` | `68a0db23408e4c95d6d283219504c79aea33a6fe` | Patch equivalent (`-`). |
| `feat/ods-icon-sets` | `005c708e9f747cb46cf02e12c869b0a2f85ac824` | Patch equivalent (`-`). |
| `feat/ods-time-period-conditions` | `7ef09f2408f467c65427700e65907531ecb26acb` | Patch equivalent (`-`). |
| `codex/odt-field-continuation-20261117` | `c34945761e7991f5fe49037d79529acdd260b31c` | All changed files match the landed squash `2c47165d01d01cc883135a434ac9f6591ce6e770` ([PR #140](https://github.com/CrispStrobe/quds_office_suite/pull/140)). |
| `integrate/office-union-148` | `3abf8f43b0e79c10271bbd046f391e462b8fe6b9` | Its entire tree matches landed squash `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` ([PR #149](https://github.com/CrispStrobe/quds_office_suite/pull/149)). |

The ODT comparison includes all four changed product/test files, all files
under `docs/validation/odt-field-continuation-20261117`,
`docs/odf-export-fidelity.md`, and
`docs/validation/german-proofing-recovery-20261117/README.md`. Its only tree
differences from the squash are unrelated intervening ODS changes.

## Recent merged work retained

| PR | Work | Captured head |
| --- | --- | --- |
| [#268](https://github.com/CrispStrobe/quds_office_suite/pull/268) | Word paragraph spacing controls | `90ecd41c8a3ef2a6f35967f1219223022e2b0d32` |
| [#263](https://github.com/CrispStrobe/quds_office_suite/pull/263) | Word custom paragraph spacing and line/point conversions | `d30299dd91634ad7e20c32db5c39a6687fcef4aa` |
| [#261](https://github.com/CrispStrobe/quds_office_suite/pull/261) | Word outline numbering and list-level editing | `fff4a4afda2beecdd20ae0bd1f3c31622e8c0b37` |
| [#259](https://github.com/CrispStrobe/quds_office_suite/pull/259) | Word paragraph ListFormat | `650afb7d117337bab943af05d63a250a7e90c058` |
| [#257](https://github.com/CrispStrobe/quds_office_suite/pull/257) | Word custom tab stops | `22e5960e99915e81a1b5997058cac44dac27ba1a` |
| [#252](https://github.com/CrispStrobe/quds_office_suite/pull/252) | Word/PowerPoint helpers, paragraph layout and text margins | `0f6239396ff3328473a5f57c280b982d57e33a08` |
| [#269](https://github.com/CrispStrobe/quds_office_suite/pull/269) | Persistent versioned Studio settings | `e8db6b3f21401f8c6ac4dae4c2934edde8699f4b` |
| [#270](https://github.com/CrispStrobe/quds_office_suite/pull/270) | Mail header search and sorting | `540eb7a41554620e1405807ac1db9dc38bd62148` |
| [#265](https://github.com/CrispStrobe/quds_office_suite/pull/265) | macOS 13 minimum and native-library deployment guard | `a51c20737b1932d9c6475ea6dddc33fbd50b2c17` |

All listed recent PR heads are ancestors of captured `main`. This is a fixed
incoming snapshot: refresh remote refs before the final merge to account for
any work arriving after this review.
