# Historical intake equivalence — 2026-11-22

Audited frozen remote main `c522851d165b395a7f60422a1be969dffc39c9ff` against all 380 captured refs in `intake.json`. Independently recomputed replacement ancestry and content identity. **No uncovered captured source work remains.**

| Historical PR | Head | Replacement already in main | Content proof |
| --- | --- | --- | --- |
| #134 | `128a187d6955` | `d790bca444ee` | Identical complete Git tree |
| #135 | `74ce9ffb816c` | `4584d5f319aa` | Identical complete Git tree |
| #136 | `58fdddfbcf19` | `4eaca83b1928` | Identical complete Git tree |
| #137 | `68a0db23408e` | `d754bf15b07a` | Identical complete Git tree |
| #138 | `b8ddaaeb581e` | `d6010059644b` | Identical complete Git tree |
| #140 | `c34945761e79` | `2c47165d01d0` | Identical tree entries on all 37 paths changed from merge base `e3a38789359a` |
| #141 | `0a53b8a70128` | `b3f41eb4b4bc` | Identical complete Git tree |
| #142 | `69d14f84cabd` | `52c73ae4dbad` | Identical complete Git tree |
| #145 | `005c708e9f74` | `c84d5e16024c` | Identical complete Git tree |
| #146 | `a7f144cc983f` | `0ff7d23929e4` | Identical complete Git tree |
| #147 | `cee6e2632f89` | `bb5556e8cc4c` | Identical complete Git tree |
| #149 | `3abf8f43b0e7` | `4b2b4e78839d` | Identical complete Git tree |
| #151 | `7ef09f2408f4` | `34dc6b680686` | Identical complete Git tree |
| #152 | `da9c956ec5d6` | `23f3b4204fce` | Identical complete Git tree |

The 366 other ref observations are direct ancestors of the captured main. Thirteen historical heads have exactly identical complete tree objects at their replacement commits. PR #140 has identical file modes/object IDs on every path in its original change set. All fourteen replacement commits are ancestors of the frozen main.

This proof concerns source intake, not runtime feature qualification. It does not assert that today’s main matches every older tree after subsequent intentional development. Replaying those obsolete PR heads would reintroduce already incorporated history. No merge or ref mutation was performed, and GitHub Actions was neither queried nor awaited.

Full SHAs, tree IDs, subjects, PR #140 path-level evidence, and the input-manifest hash are in `historical-intake-equivalence.json`.
