# Mail connectivity and keychain development evidence

This capture preserves the complete `mail-keychain-development` directory and
the source-bound `latest-main-review.json`. It records focused development on
working source based at `d5e34fda24a3085a98f9072fb30869fd3c4a7b21`; exact source
hashes and commands are in the run receipts. These observations are **not final
aggregate acceptance** and are not combined with earlier qualification counts.

## Results and interpretation

| Record | Passed | Failed/error | Skipped | Exit |
| --- | ---: | ---: | ---: | ---: |
| Initial focused run | 61 | 3 | 0 | 1 |
| Final focused run | 64 | 0 | 0 | 0 |

Both runs contain 59 Studio Mail widget cases and five credential-store cases.
The initial run already used the repaired product. Two existing notice
assertions expected the incoming unconditional keychain claim; one new assertion
incorrectly expected a password to survive disconnect. The assertions were
adjusted to the conditional storage description and the existing password
clearing behavior. **This failed run is not baseline RED proof of the product
defects.** Its original JSON, stderr, receipt and test source remain preserved.

The final run includes delayed credential-load and replacement-session cases,
truthful write/delete failure handling, write-before-delete ordering, preserved
SMTP acceptance feedback, explicit STARTTLS, mailbox.org settings and credential
preflight before authentication. All five final Dart files pass strict analysis
with fatal infos and warnings; formatting and scoped whitespace checks pass.
Their hashes were unchanged during the passing run.

The repair removes automatic authentication replay after connection failure,
checks form/session ownership before applying a saved record, and orders shared
keychain operations across dialog lifetimes. Storage feedback is separate from
SMTP and mailbox outcomes. Existing EWS entry, exact UID operations, draft
retention and disconnect cleanup remain present.

All provider and storage interactions in these tests are controlled fakes or a
mocked platform channel. No real keychain or account credentials were used.
Installed-platform keychain entitlements and real-provider interoperability
remain outside this capture. The review JSON describes incoming main
`07b815a7` and the separate PR #200 draft at `b5eb7b81`; it is historical review
evidence, not acceptance of that later provider work. GitHub Actions were
neither queried nor awaited.

## Archive and verification

The archive contains **23 members: 22 regular files and one directory**, totaling
**382,748 original file bytes**. It includes both complete raw runs and receipts,
strict-analysis and formatting output, merged baseline and fixed source copies,
the exact repair patch, development summary and incoming-main review.

- Compressed file: `mail-keychain-evidence.tar.xz`, **35,552 bytes**.
- Compressed SHA-256: `d8e1b34861c9b8ff91383bf855fdbb04cc117f0abf42e5ee2d31f73b7768b1b9`.
- Decompressed tar SHA-256: `80aa83709721aef726f67dc1c9d231ed5041cdfe934f250cf60504a86bb54365`.
- [Complete archive index](mail-keychain-evidence.index.json).
- [Original-byte and reconstruction verification](mail-keychain-evidence.verification.json).

The existing archiver verified every original byte, the exact member set, sizes,
hashes, permission modes and nanosecond timestamps. A second complete archive
build reproduced identical bytes. A separate verification using only the
published archive/index also reconstructed the same compressed bytes.

From the repository root, verify without the original source files:

```bash
python3 docs/validation/office-validation-recovery-20261119/development/archive_development.py verify \
  --index docs/validation/office-validation-recovery-20261119/development/mail-keychain-evidence.index.json
```

While both original sources remain available, add these arguments to compare
their original bytes and metadata too:

```bash
  --source mail-keychain-development=/workspace/scratch/1db61dbeed56/mail-keychain-development \
  --source latest-main-review.json=/workspace/scratch/1db61dbeed56/latest-main-review.json
```

To rebuild in a new empty destination, use the same tool's `pack` command with
both source mappings and `--name mail-keychain-evidence`. Explicitly remapped
source paths must preserve the indexed file metadata.
