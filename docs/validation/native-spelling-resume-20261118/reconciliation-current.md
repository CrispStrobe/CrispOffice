# Native spelling continuation: current incoming reconciliation

The fixed current inventory accounts for **376 observed references / 242 distinct
heads** against integrated commit
`fb1fd4dc3edda824c3e043c035dbfad1f0fe0869` (tree
`d75c06607da4074dbcb153d90c7d99cd59107ce7`). No captured incoming head remains
unaccounted for.

| Source | References |
| --- | ---: |
| Fork branches | 204 |
| Fork PR heads | 164 |
| Upstream branches | 4 |
| Upstream PR heads | 4 |
| Total | 376 |

| Classification | References | Distinct heads |
| --- | ---: | ---: |
| Exact ancestors of the integrated commit | 348 | 228 |
| Unchanged historical tips with prior identical-tree merge trials | 10 | 5 |
| Unchanged historical tips already landed through reconciled PRs | 18 | 9 |
| Unaccounted | 0 | 0 |

The inventory includes all named references returned by the paginated captures;
unlike the preceding Zotero audit, it also includes the Zotero continuation and
its PR. It does not include a symbolic `origin/HEAD`, and makes no claim about
remote changes after its recorded cutoff.

## Integration and source retention

The previously saved spelling checkpoint
`f482b06fc47545c8b03124c30ea78f54e8e4b9e5` is an exact ancestor of `fb1fd4dc`,
which adds 11 commits. Main `f383c826205e321eda3ed3bdbcd584e9a2d4da14` and
document-review PR head `3840e19ff949f5fc03ecf1ec30ab0a71f67e8c68` are also
included. The two spelling production files, four new spelling regression files,
and portable spelling checker retain their exact Git blobs across the
integration. Product changes after the spelling checkpoint are the qualified
Zotero workflow and its related tests, changelog and documentation.

The root publisher fast-forwarded `codex/native-spelling-resume-20261118` from
`f482b06f` to `fb1fd4dc` and reported a successful non-forced expected-head
update. An independent exact Git-ref read returned `fb1fd4dc`, preserved in
`spell-ref-after-integration.json`. The fixed initial inventory remains intact;
that expected own update is recorded separately.

One snapshot inconsistency is retained explicitly: the document-review branch
listing and exact Git ref both returned `fb1fd4dc`, while PR #162 metadata still
returned `3840e19f`. Both exact objects are included ancestors, so this does not
leave incoming work unresolved.

## Historical evidence

The preceding immutable audit is
[`docs/validation/zotero-continuation-20261118/reconciliation-final.json`](https://github.com/CrispStrobe/quds_office_suite/blob/fb1fd4dc3edda824c3e043c035dbfad1f0fe0869/docs/validation/zotero-continuation-20261118/reconciliation-final.json).
It accounts for 373 references at product `b2bcfc23`. Relative to that audit,
the current inventory adds the Zotero continuation branch, its PR #164, and the
Zotero offline-workflow branch. The document-review branch advances from
`3840e19f` to `fb1fd4dc`. No prior reference is absent.

All 28 historical nonancestor reference names and SHAs are unchanged. The
recorded landed merge commits were freshly checked as ancestors. Prior
identical-tree trials remain historical evidence, chained through the earlier
integration commit whose ancestry was also checked. This audit does not claim
to have rerun those historical merge trials.

## Reproduction and evidence

`resume-reconciliation.json` contains every reference, classification, the exact
source bindings, the old evidence identity and the own-update readback.
`current-inventory.json` and the captured paginated API JSON files retain the
input observations. `detail0.json` and `detail1.json` retain the GitHub compare
responses; `detail2.json` and `detail3.md` are the preceding audit fetched through
GitHub and checked against the local immutable Git object.

Run the read-only verifier with a Git checkout containing the captured histories:

```sh
python audit_current.py --repo /path/to/quds_office_suite --data /path/to/this/directory
```

The verifier only reads Git objects and rewrites its local output JSON. It never
fetches, changes Git refs, modifies the index or checkout, or queries GitHub.
The recorded audit fetches used repository branches, PR metadata, exact refs,
source files and commit comparisons only. No GitHub Actions, workflow, check or
CI-status endpoint was queried or awaited. This is source reconciliation and
does not constitute fresh product test execution.
