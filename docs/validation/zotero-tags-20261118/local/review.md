# Independent source review

The tag implementation and regression tests were independently reviewed after
the first remote code checkpoint. No remaining correctness blocker was found.
The review covered literal escaping against the online and desktop parsers,
bounded immutable input, complete-catalog filtering, draft/applied state,
selection retention, failed reads, late responses and narrow chip layouts.

One wording error was corrected before the final editor qualification: the UI
must not promise case-sensitive matching. It now says **Capitalization is kept
as entered**. The client preserves and deduplicates exact spellings; Zotero
determines server matching. The associated test name was corrected without
changing its assertions.

Pinned upstream evidence for this correction:

- [Online item lookup](https://github.com/zotero/dataserver/blob/bdc2dc713ff3ceb26dc2d3e1b0f5c30dc1020627/model/Items.inc.php)
  passes the case-insensitive flag to `Zotero_Tags::getIDs`.
- [Tag lookup implementation](https://github.com/zotero/dataserver/blob/bdc2dc713ff3ceb26dc2d3e1b0f5c30dc1020627/model/Tags.inc.php)
  uses `utf8mb4_unicode_ci` for that flag.
- [Online search parser](https://github.com/zotero/dataserver/blob/bdc2dc713ff3ceb26dc2d3e1b0f5c30dc1020627/model/API.inc.php)
  and [desktop search parser](https://github.com/zotero/zotero/blob/cdccfcffbab6bbd7b62cb6855efbc430c972f36b/chrome/content/zotero/xpcom/server/server_localAPI.js)
  confirm the leading-hyphen escape and differing OR delimiters that justify
  refusing ambiguous literal names.

The reviewer did not rerun tests or count other agents' runs. Executed results
are recorded separately in the cohort directories. The runtime provenance was
also checked for credentials and secrets; it contains only official software
identifiers, hashes, setup records and known temporary workspace paths.
