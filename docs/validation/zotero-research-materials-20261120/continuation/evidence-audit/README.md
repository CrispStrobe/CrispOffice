# Continuation evidence audit

The recovered branch `e79c32e77f1990e303527e477e4909df993c1b9b` contains the
complete earlier qualification evidence. An independent recount of its eleven
raw event streams verifies **2,886 distinct application cases in 135 files**.
The audit verifies receipt and artifact digests, exact selected suites,
per-suite counts, unique case identities, saved input-inventory consistency,
and 55 static target hashes. It rehashes 3,833 distinct Git blob objects for
the 3,996 recorded source paths. Static log digests and the supplemental
archive digest also match the saved audit records.

`restored-branch.json` confirms that the recovered branch preserves every
recorded source input. `publication-candidate.json` repeats the historical
evidence check for `f3f98987824e021ed22a4d909e38d6307495267b` and explicitly
reports **22 changed existing input paths**. Its
`candidate_preserves_all_qualified_source_inputs` field is therefore false.
This is expected: the continuation preserves newer main and branch work. The
earlier 2,886 cases retain their original source attribution; they are not
represented as a fresh run against the publication source.

`publication-delta.json` records all 46 changed paths between the recovered
branch and the publication candidate, including newly added files. No
manifest, lockfile, Zotero source/test, editor-library or Mail source/test path
changes. The engine's only production change appends read-only German grammar
fact classes, retaining all previous bytes as an exact prefix. The other
application changes concern spaCy grammar and code identity, Studio setup
and language synchronization, macOS packaging, and the explicit German
language in a Studio regression fixture.

The aggregate engine import closure includes the appended German facts, so
this audit does not claim that every transitive test input remains identical.
Fresh proofing, spaCy, Studio integration, Zotero and static gates are recorded
separately in the continuation directory. Historical VBA, rendering, DOCX and
Mail tests remain credited to their recorded commits.

## Reproduce the evidence check

From `docs/validation/zotero-research-materials-20261120`, use a checkout
containing the named Git objects:

```bash
python3 continuation/evidence-audit/recheck_saved_evidence.py \
  --repo /path/to/quds_office_suite --evidence . \
  --candidate f3f98987824e021ed22a4d909e38d6307495267b \
  --output /path/to/new-publication-evidence-audit.json

python3 continuation/evidence-audit/assess_publication_delta.py \
  --repo /path/to/quds_office_suite \
  --base e79c32e77f1990e303527e477e4909df993c1b9b \
  --candidate f3f98987824e021ed22a4d909e38d6307495267b \
  --output /path/to/new-publication-delta.json
```

These scripts run no application tests, analysis or formatting commands.
They do not re-observe the old SDK, dependency cache or execution; those saved
inventories are checked for internal consistency. Source bytes are rehashed
from immutable Git objects. They do not query GitHub Actions or send any mail.
