# Incoming-ref equivalence audit

Captured main: `4970f71f983535d045ce263e86835b499db4fda9`.

All **375 fetched refs** are accounted for: **361 ancestors** and **14 independently verified historical equivalents**; **0 uncovered**.

Scope: 39 origin branch tips, 332 PR heads, 4 upstream branch tips. Symbolic `origin/HEAD` is excluded.

The prior intake record supplied candidate replacement SHAs. This audit recomputed replacement ancestry, complete tree object identities, and (for PR #140) mode/type/blob equality for every path changed since its merge-base. Prior conclusions were not accepted as proof.

| PR | Original head | Replacement on main | Independent proof |
| --- | --- | --- | --- |
| #134 | `128a187d69555db80890c2a1945a442b951f9c74` | `d790bca444eef0e160a75ce3d8cb555af541004f` | Identical complete Git tree |
| #135 | `74ce9ffb816c70c0d2ae50b91ec52a614f26d688` | `4584d5f319aab198f1d705f48b4d6647e6cbabea` | Identical complete Git tree |
| #136 | `58fdddfbcf198a8c0e38e32f6fcc9d6604e95283` | `4eaca83b192897edad82658107dfeb5bcbed0920` | Identical complete Git tree |
| #137 | `68a0db23408e4c95d6d283219504c79aea33a6fe` | `d754bf15b07a24c8a86c8dce339ca749fecd9531` | Identical complete Git tree |
| #138 | `b8ddaaeb581e010467de304c828764d353149102` | `d6010059644b34accd6f188e0e2a4863ab63e318` | Identical complete Git tree |
| #140 | `c34945761e7991f5fe49037d79529acdd260b31c` | `2c47165d01d01cc883135a434ac9f6591ce6e770` | All 37 changed paths match mode/type/blob |
| #141 | `0a53b8a70128870f3e1df6d18cdb177bb64290ee` | `b3f41eb4b4bca8ca13676b4114891ea6d9185043` | Identical complete Git tree |
| #142 | `69d14f84cabd3931b7640c1654b401c89faba766` | `52c73ae4dbadf2ca00a5d619144350ccc353b31a` | Identical complete Git tree |
| #145 | `005c708e9f747cb46cf02e12c869b0a2f85ac824` | `c84d5e16024c502f6c451fd04b9807b1e65f20d3` | Identical complete Git tree |
| #146 | `a7f144cc983f2df7c16d88f8644ad67a9254c3d0` | `0ff7d23929e4640af6c1d57f87c7ac71b73d2ed4` | Identical complete Git tree |
| #147 | `cee6e2632f891a3fe21c5c02d6bf508805973051` | `bb5556e8cc4cb73e2c668b5319a2844a20c6c50c` | Identical complete Git tree |
| #149 | `3abf8f43b0e79c10271bbd046f391e462b8fe6b9` | `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` | Identical complete Git tree |
| #151 | `7ef09f2408f467c65427700e65907531ecb26acb` | `34dc6b6806869570e9ec342e4d7ee0d6951c0ba6` | Identical complete Git tree |
| #152 | `da9c956ec5d65c0e5a9f9ea84c2b0bca98e824a0` | `23f3b4204fce45d38a103e3159bdc7f1e8d37c4e` | Identical complete Git tree |

## PR #140 detail

Its merge-base is `e3a38789359adaa33b2da1345c952fa1c2d8aebb`. All 37 changed paths exactly match replacement `2c47165d01d01cc883135a434ac9f6591ce6e770`. The full per-path tree entries are included in `intake-equivalence.json`. The complete trees differ because other work was present at integration, so this audit makes the narrower changed-path claim.

## Disposition

No historical PR should be replayed over current source: the changes are already present through the verified replacement commits, which are all ancestors of captured main. This audit establishes intake completeness; it does not independently requalify functionality changed after those historical integrations.

No GitHub Actions were queried or awaited, and no git ref/index/working-tree/remote mutation was performed.
