# Word VBA tab stops: source intake

This increment starts from remote checkpoint `49d0fe9966edff96e2cbda7e483a9ba8a689219a`, tree `0417c5d9c881cb7835c840419812cb909968ac48`. It preserves both integration parents:

- `d8ee0c9a6b61b925ac27750e04124a82d82b8b33`: recent Mail drafts/accounts, Word/PowerPoint VBA, Zotero and completed main work.
- `aedb870e32ffd1842ddd40329bd2e12995281a1b`: subsequent Mail EWS regression coverage for composing local drafts while provider capabilities are read-only.

The locally constructed integration commit `01f69b2bbcf716ec5d2fcf4137092377c794d10e` and the published checkpoint have identical tree and parent identities. GitHub recreated the commit for authenticated publication; the audit below is bound to the published checkpoint.

## Captured source inventory

[Machine-readable intake](intake.json) records every captured branch and PR head, upstream heads, ancestry results and independently recomputed historical equivalence checks.

| Inventory | Ancestral heads | Historical equivalents | Uncovered |
| --- | ---: | ---: | ---: |
| 18 fork branches | 9 | 9 | 0 |
| 252 PR heads | 238 | 14 | 0 |
| 4 upstream branches | 4 | 0 | 0 |

All 14 historical equivalence proofs were recomputed from Git objects. Thirteen historical and accepted commit pairs have identical full trees. The ODT continuation pair has identical mode, type and blob identity across all 37 originally changed paths. Every accepted equivalent is an ancestor of the published checkpoint. Those older branches therefore contribute no missing source changes that require another merge.

The captured open PRs were #249 (Zotero research tables), #251 (Mail accounts) and #252 (Word/PowerPoint VBA expansion). Their exact captured heads are ancestors of the published checkpoint. Source inclusion does not imply that those PRs were separately closed or merged through the GitHub PR interface.

### Fork branch heads

| Branch | Captured head |
| --- | --- |
| `codex/odt-field-continuation-20261117` | `c34945761e7991f5fe49037d79529acdd260b31c` |
| `codex/word-powerpoint-vba-expansion-20261120` | `0f6239396ff3328473a5f57c280b982d57e33a08` |
| `codex/zotero-research-tables-20261120` | `93dc987cf993787bd613018b3028e7ad60d5472a` |
| `docs/ods-color-scale` | `58fdddfbcf198a8c0e38e32f6fcc9d6604e95283` |
| `docs/ods-data-bar` | `69d14f84cabd3931b7640c1654b401c89faba766` |
| `feat/ods-color-scale` | `74ce9ffb816c70c0d2ae50b91ec52a614f26d688` |
| `feat/ods-data-bar` | `0a53b8a70128870f3e1df6d18cdb177bb64290ee` |
| `feat/ods-dynamic-validation-links` | `68a0db23408e4c95d6d283219504c79aea33a6fe` |
| `feat/ods-icon-sets` | `005c708e9f747cb46cf02e12c869b0a2f85ac824` |
| `feat/ods-time-period-conditions` | `7ef09f2408f467c65427700e65907531ecb26acb` |
| `fix/mail-credential-stores-chrome-20261120` | `a652a205e6daf6b4b8e3baec04db1c1b52fabd0d` |
| `integrate/office-union-148` | `3abf8f43b0e79c10271bbd046f391e462b8fe6b9` |
| `integrate/recent-pptx` | `4f5c153774ab7492430c2b68653c54e0c08dc2ad` |
| `main` | `13be50464d1b43e9f2100fb9ccc12f8fe22eb55e` |
| `work/mail-accounts-20261120` | `c20b41d9c7eed574c02e49f1fd96789843aec2e6` |
| `work/mail-multiple-drafts-20261120` | `aedb870e32ffd1842ddd40329bd2e12995281a1b` |
| `work/mail-outbox-20261120` | `9443612b024114c424ba2f8146e04050d6e049b0` |
| `work/mail-outbox-management-20261120` | `d8ee0c9a6b61b925ac27750e04124a82d82b8b33` |

The new `codex/word-vba-ranges-20261120` checkpoint branch was created after this initial 18-branch capture; it is not included in that count. The captured main head is `13be50464d1b43e9f2100fb9ccc12f8fe22eb55e`.

### Upstream heads

The upstream repository is `MohammedAsaadAsaad/quds_office_suite`.

| Branch | Captured head |
| --- | --- |
| `ci/flutter-workspace` | `aca2f66941832bd0b19b436baeab1656a1b7de98` |
| `cursor/class-certificates-2db8` | `f45099688e7a3f67a1302efdb442830d052f2240` |
| `cursor/cloud-agent-1790580069020-0rk1h` | `9930be8df44ffe117fb22778c514eea0ee73ce21` |
| `main` | `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` |

## Scope of this record

This is a source/history inclusion audit. It makes no runtime qualification claim for the new tab-stop increment or incoming Mail, editor, credential-store, Zotero or other product work. Existing incoming validation records retain their own source-specific scope. GitHub Actions was neither queried nor awaited. Any later advance of main or another branch requires a separate refresh before final publication.
