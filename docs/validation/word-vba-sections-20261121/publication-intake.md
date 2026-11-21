# Publication intake and accepted source boundary

The [initial intake](intake.md) reconciled all 335 captured fork/upstream branch
and PR heads before Word changes began. This record captures additional work
that arrived during implementation; it does not silently redefine that initial
snapshot. Original ancestry is retained for each integrated incoming commit.

## Later completed snapshots integrated

| Area | Accepted head | Integration | Qualification |
| --- | --- | --- | --- |
| Mail | `6ec90c8a3acdc8fb5878f1decef0131e478e6b1d` | `024e101500527e39c9e6ac15203c7b8ddc3a4751` | 58 mailbox/session/projection Flutter cases; includes `c375becb` streams and layout-retry/listener correction |
| Performance tooling | `1460876e70fcf3da49644e232e9942b7ee042d8d` | `324bff5860dcceb57fe7a82a6e229b2519991e86` | Parser assertions cover complete/B-E events, per-thread pairing, idle totals and handler overlap; frame/phase reporting was exercised without numeric assertions; no profile-mode performance claim |
| Zotero transfer | `3da241d5f1f3e43d7be47f00bcf7fbe62bd8272b` | `3ef8f406b33c363dcb3cd78d6c3aa9e03e6afa75` | 798 native cases, 97 editor cases, then strict analysis and 30 transfer cases after a brace-only cleanup |

The earlier [late-intake record](late-intake.md) remains a historical snapshot.
It deferred the incomplete Zotero `fb692a7f` checkpoint. Its successor
`3da241d5` fixes the exhaustive editor command switch and restores a coherent
callback contract. That completed successor is now integrated. The only
additional helper cleanup adds 21 required braces; all 5,977 non-brace tokens
are identical.

The final combined engine gate runs on source checkpoint
`47660815c429e15aa280005dc6d76bb36c53eca4`. Its results and exact source binding
are recorded in the [acceptance record](README.md).

## Active successors outside this accepted snapshot

At the final branch audit, `main` remained
`84046975f286407e3c62e5e5352bc16bc89c0d26`. Three active successors had advanced
beyond the completed inputs above:

- Mail `e162101d6852c6522850b848bb6473676d7fe02a` has draft PR
  [#284](https://github.com/CrispStrobe/quds_office_suite/pull/284), whose body
  explicitly says its final combined qualification is in progress. It adds
  foreground/cached Mail wiring and further integrations, including proofing.
- Zotero `d24240ee62afdd4253bfe3dd787741049923c398` contains additional
  transfer/ODT changes and concurrent Mail/proofing merges. It is not an
  evidence-only successor of the accepted `3da241d5` implementation.
- Proofing `690ce037d008089a228cf6058e2fd7824c5cc62a` and its preceding commit
  `ef30d54079cfbf25368e5af5bb39f221496543e7` explicitly identify their scheduler,
  tests and benchmark work as WIP.

Those later changes remain on their remote branches and are outside this
Word increment's accepted source boundary. Their branch heads are not falsely
classified as equivalent or already merged. The 47 current branches comprise
the 44 initially captured branches plus this Word branch, Zotero transfer and
proofing. The newly opened draft PR does not contradict the earlier snapshot's
absence of open PRs.

No GitHub Actions runs, checks or queues were queried or awaited. No repository
policy or protection was changed. The final publication uses a normal merge
with an expected feature-head SHA and a fresh check of main.
