# Independent review of later incoming heads

Reviewed against frozen Word source `0201b549d0dc3f601c50e36255d557034cb01699`.
The refreshed fork inventory contains 27 branch heads and 265 PR heads. Three
later commits remain outside that source, represented by three branches and two
PR heads. Every other captured fork entry is the target, an ancestor, or a
recomputed historical equivalent. The original intake remains fully included.

| Head | Scope | Integration assessment |
| --- | --- | --- |
| `5a73a056f7c757a64d56345c31eabdd6de6eb18a` (PR #264) | One PDF editor early-return brace change | Semantics-preserving syntax change; no Word input overlap. |
| `a51c20737b1932d9c6475ea6dddc33fbd50b2c17` (PR #265) | Five macOS deployment, native-build and release-documentation files | No Word input overlap; correct the numeric version comparison edge cases below before publication. |
| `3bbd414d8f1129bd802b33c3af961d5c12489da2` | Six paragraph-controls intake-evidence files | Direct descendant of frozen Word source; contains no controls implementation. |

The two PR heads each have parent `5ad4461a93c835479bf67acab63623944b3900a3`.
Their changes from the merge base are disjoint from all 1,131 qualified Word
inputs. The controls-intake commit directly descends from `0201b549`. Its
committed capture predates PRs #264/#265: all 296 recorded references were
independently classified again, including 13 complete-tree equivalences and the
exact 37-path ODT continuation. Its zero-uncovered conclusion is valid for that
capture. It explicitly withholds Word runtime acceptance, so it is not a claim
that this final spacing gate was already complete.

## Concrete findings in PR #265

The version helper compares the first sorted string to the original spelling.
It reports `13.0.0 <= 13.0` as false. The library-minimum maximum pipeline sorts
only major/minor numerically, so it selects `13.0.9` over `13.0.10` by lexical
fallback. Both behaviors were reproduced from the exact committed shell code
in `late-macos-version-probe.sh`; stdout and stderr identities are recorded in
the JSON report. Shell syntax and the Hunspell Python AST pass.

Apple’s current cctools source also confirms that `-show-build` emits legacy
`LC_VERSION_MIN_MACOSX` records with the field `version`, while modern
`LC_BUILD_VERSION` records use `platform MACOS` and `minos`. A minos-only
parser therefore refuses valid legacy records. The official source URL, Git
blob identity and short rendering excerpts are saved in
`apple-vtool-source-reference.json`; no macOS execution is claimed.

Compare normalized numeric major/minor/patch components, checking every
architecture and deployment record against the application minimum. Recognize
legacy and modern fields in their load-command context, excluding tool-version
fields. Preserve the
original PR ancestry and add the narrow correction before publication. A real
macOS app/native-library build is not claimed by this Linux source review.

After the frozen Word gate finishes, these heads can be merged while retaining
the qualified Word input identities. Recheck all 1,131 paths, modes, object IDs,
sizes and content hashes after integration. The macOS issue is separate from
Word acceptance and does not require restarting the frozen Word gate. No
GitHub Actions were queried or awaited.

## Corrected candidate accepted

The initial findings and raw probes are retained separately in
`late-intake-review-initial.json` and its Markdown companion. The reviewed
scratch candidate is now accepted for integration:

`8592dd41fb59da7fa3ead05287005cfa06d90c02bb5de495e9f985062ffff904` (SHA-256).

Independent checks passed **36 expectations**: 18 numeric comparisons and
18 parser fixtures. Coverage includes arbitrary-width decimals, zero/omitted
components, correct patch ordering, modern and legacy commands, mixed universal
architectures, every deployment command, missing minima, duplicate fields,
wrong platforms, ignored tool versions, and vtool failure. All candidate input
hashes remained unchanged. The full receipt, raw outputs per expectation and
fixtures are in `late-macos-independent/review.json`; the independent runner is
`review_macos_correction.py`.

These checks used installed Linux Bash 5 with its 3.2 compatibility option.
They are not an actual Bash 3/macOS run and do not claim a native app build or
signing. The 36 checks add zero cases to the Word regression total. Integration
is pending; preserve all three original heads and apply this exact candidate
before final publication.
