# Final live-main reconciliation

After independent acceptance of Word checkpoint `8b9be399da380b0b8ab3abf238833eb221996c7d`, remote main advanced
to `d1e9cbc0c5dd38f0c8d28e3d76e7fdd59990f3f4` through PR #267. The new merge contains the previously captured
Arabic web-context head `be47bed22a88382f016d823e526bae49590bd0eb`. Its nine paths are disjoint from the Word
changes and all qualified inputs. A clean three-way merge retains every incoming
file, Git mode and object exactly. Both heads are actual parents of the final
reconciliation checkpoint. The [receipt](main-reconciliation.json) binds the
source objects, exact bytes, expected parents and scope update.

All 1,131 qualified Word inputs and all ten separately reviewed source/contract
inputs remain unchanged. The [accepted preceding checkpoint review](publication-checkpoint-8b9be399.json)
and original scope report remain exact historical records. No Word tests need
to be rerun for this disjoint merge, and no Arabic runtime/parity validation or
GitHub workflow execution is claimed.

The same captured inventory now has the following disposition. Only the two
references to the newly incorporated Arabic head change classification; the
other 12 deferred references identify seven distinct heads. There are zero
unclassified references. This table supersedes the disposition table in the
historical scope report without replacing its original capture or audit result.

| Captured source | Captured | Incorporated or equivalent | Explicitly deferred |
| --- | ---: | ---: | ---: |
| Fork branch heads | 33 | 26 | 7 |
| Fork PR heads | 270 | 265 | 5 |
| Upstream branch heads | 4 | 4 | 0 |
| Upstream PR heads | 4 | 4 | 0 |

The complete accepted final reconciliation review and post-merge consistency
proof are preserved in PR #263. All existing checkpoints remain ancestors.
