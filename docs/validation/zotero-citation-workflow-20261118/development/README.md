# Development evidence

This directory preserves the existing development logs for the cited-reference
and citation-composer increment. It supports debugging and records unsuccessful
attempts alongside the later passing runs. These runs overlap the final editor
Zotero cohort and are **excluded from the final qualification total**.

The separate qualification uses the saved integration
`3668ed92829dfa012ec5b129943a86738ebb7992`. This reference describes the source
freeze after development; it does not claim that every earlier attempt ran
against that exact commit. Earlier source identity is claimed only where an
original receipt records it.

## Files and integrity

- [development-evidence.tar.gz](development-evidence.tar.gz) contains 20 files,
  preserving their original bytes and directory-relative names. The archive is
  7,612 bytes; its members total 91,768 uncompressed bytes.
- [member-index.json](member-index.json) records every member's path, byte size
  and SHA-256, plus the archive SHA-256 and a summary derived from each test
  event stream. Its recorded archive SHA-256 is
  `0bdede53e5abfd195e63f299702d580a838f2f8bef9a39a2fac138996b7c77b3`.
- All members were read back from the completed archive and checked against
  their indexed size and hash. The original evidence files were also checked
  and remained unchanged.

Only these three directories from this continuation were included:

| Archive directory | Contents |
| --- | --- |
| `zotero-composer-evidence/` | The captured 20-case composer run, actual process result, seven explicitly recorded source hashes before/after, strict analysis and formatter receipts |
| `document-source-tests/` | Both helper/picker attempts and actual exit receipts, plus two contemporaneous incoming-ref fetch logs |
| `zotero-integration-development/` | All three document-reuse attempts, their stderr files and the two actual exit receipts that were captured |

No historical evidence inherited from earlier repository work is included.
The composer receipt's seven source hashes are a bounded direct-input check,
not a claim to cover the entire transitive compilation graph. The final
qualification records its own broader input verification.

## Recorded attempts

Counts below exclude each suite's loading case. Failed cases remain failures
even if the same test passed in a later attempt. All six streams report zero
skipped cases.

| Captured run | Passed | Failed | Error events | Actual test-process exit | Final stream result |
| --- | ---: | ---: | ---: | --- | --- |
| Composer final development | 20 | 0 | 0 | 0, captured in `summary.json` | Success |
| Helper/picker attempt 1 | 9 | 9 | 9 | 1, captured in `attempt-1-exit.json` | Failure |
| Helper/picker attempt 2 | 18 | 0 | 0 | 0, captured in `attempt-2-exit.json` | Success |
| Document reuse first | 8 | 2 | 2 | **Not captured** | Failure (`success: false`) |
| Document reuse second | 4 | 6 | 6 | 1, captured in `reuse-second-exit.json` | Failure |
| Document reuse third | 11 | 0 | 0 | 0, captured in `reuse-third-exit.json` | Success |

The first helper/picker attempt records an expected-null-versus-empty-string
assertion, a non-JSON-value fixture failure, and ambiguous scrollable lookups in
the widget test helper. The first document-reuse attempt records missing-widget
lookups in its two narrow-layout cases; the second records ambiguous scrollable
lookups in its helper. The exact messages, stack traces and test identities are
retained in the raw streams. The later attempts show the executed corrected
tests passing; they do not rewrite or replace the failed receipts.

The shell running **document reuse first** continued with a summary command
after the test command. Its shell completion cannot establish the test process's
exit status. Accordingly, the index stores `test_process_exit_code: null` for
that attempt. The final event in its preserved raw test stream explicitly says
`success: false`; no passing exit code is inferred.

The three document-reuse streams also contain a non-JSON preamble line and a
JSON list that are not test events. Those bytes are preserved unchanged. The
index records their line numbers and excludes them from event counting.

The final development runs of 20 composer, 18 helper/picker and 11 document-reuse
cases are useful focused receipts. They are not added to the separately executed
final cohort, and no total in this directory combines repeated attempts.

## Verify the bundle

From this directory, the following read-only check verifies the archive and
every member without extracting any files:

```python
import hashlib
import json
import pathlib
import tarfile

index = json.loads(pathlib.Path("member-index.json").read_text())
archive = pathlib.Path(index["archive"]["path"])
assert hashlib.sha256(archive.read_bytes()).hexdigest() == index["archive"]["sha256"]
with tarfile.open(archive, "r:gz") as bundle:
    assert len(bundle.getmembers()) == index["member_count"]
    for member in index["members"]:
        data = bundle.extractfile(member["path"]).read()
        assert len(data) == member["bytes"]
        assert hashlib.sha256(data).hexdigest() == member["sha256"]
```

Packaging copied and verified the existing evidence only. It did not run tests,
change product source, move git refs, modify the git index, or query GitHub
Actions.
