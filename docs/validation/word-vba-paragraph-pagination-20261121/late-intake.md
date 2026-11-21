# Concurrent work retained before publication

The fixed intake adds two concurrent work heads to the validated Word checkpoint `c093f6387fcae69f04c63f4344476e4785906a54`. Remote main remained `bf761552d22dcd1eb8cbb0ab00ddab6507e1d572`; the fresh fork listing contained 42 branches and no open pull requests. The latest PRs remained merged. [The compact receipt](late-intake.json) records exact heads, parents, source identities and resolutions; the earlier complete inventory and equivalence proofs remain in this directory.

| Incoming head | Retained work |
| --- | --- |
| `e5b9240512158c329dd2671aa9f36eb08cb74e11` | Zotero intake ancestry and eight exact audit artifacts. This snapshot contains no new Zotero feature implementation. |
| `71a9d73f86a30380d7fe3563f1a0048f1f7eb860` | Mail intake parent `d6e8fddd08755fe84e82f2a7a0bce200f0c92826`, two audit artifacts, defensive-copy alias tests, documentation, and the optional fresh read-only flag-observation API with provider implementations. |

Both heads are merged with ancestry, in that order. The source review found the captured Mail increment self-contained: its optional port has complete native/provider and explicit unsupported-platform implementations, strict identity and lease checks, bounded reads, and tests. It does not require an unfinished recovery UI. Later pushes to these work branches are outside this fixed snapshot.

The merge retains the current Word implementation and documentation exactly. Reviewed conflicts preserve the current image alias shape and historical evidence, including two Zotero files that a recursive merge attempted to delete. Compatible Mail assertions and changelog entries are retained. The final core, transport and UI package trees exactly match the captured Mail head; all ten new incoming audit files preserve their original blobs.

Independent local validation of that exact Mail source passed **498 cases**: 257 transport VM, 235 core, and six compiled JavaScript Node fallback cases. Strict core/transport analysis also passed. [The source-bound validation summary](late-mail-validation.json) records suite counts, runtime, archive identity, source-drift checks and log hashes. These checks use local protocol/HTTP fixtures; they do not claim Flutter UI or live-account acceptance. No GitHub Actions queue was used.

Remote main is refreshed again before the final publication. The source intake is bounded by these captured SHAs rather than an indefinitely moving set of work branches.
