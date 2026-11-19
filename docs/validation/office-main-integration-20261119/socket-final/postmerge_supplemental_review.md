# Supplemental review: remaining Mail and Zotero integration

Status: pre-freeze review. The final historical-continuity and reference audits
will bind to the exact frozen integration commit separately.

## Source and evidence boundaries

The Mail publication commit `700e5a35ce5f96e7abd1dc92d1a00d2110d40649`
is included in saved merge `3cd60db25cb81ff836bbc06fed9af28819337339`, whose
parents are main `d41000336c84b6ebfe6b35f7f8335140b5d46038` and that Mail head.
The additional known Zotero head is
`022a974a96db23e22bc161f7d465e4b972e8c2a9`. These immutable heads define this
supplement's incoming scope; no fresh remote advertisement was requested by
this review.

Mail's added result belongs to source
`71edec2de364805113d18e0f1d7edbb1f00467e5`: **631 executions, 508 distinct
suite/test-name scenarios and 48 suites**. It remains separate from the prior
main integration result at `4624218f9468eeeac07f1f100ac0e4bb6b050a17`:
**611 executions, 541 distinct cases and 47 suites**. Neither result is a test
execution on the forthcoming combined source. Do not add the two totals or
replace current qualification counts with the Mail branch's historical totals.

All eight incoming indexed archives were checked independently: **218 members,
21,444,149 uncompressed bytes**, with exact member sets, sizes and SHA-256
digests. The native and Node manifests each bind 5,027 source records whose
Git modes and blob identities match `71edec2d`; before/after snapshots agree and
plan hashes match the qualified source. All 53 core/store input hashes also
match that source. This review did not rerun tests, recount raw events, or
revalidate the historical runtime environment.

## Documentation and test preservation

Keep the current integration status and counts in the Mail roadmap until the
new qualification completes. Preserve the complete incoming Mail report and
original archives, receipts and failed attempts. Contextualize its continuation
README and the store README as the `71edec2d` Mail-branch checkpoint, with a
separate link to the current Office integration report.

`packages/quds_mail_store/README.md` is a bound input in the prior 5,031-record
focused snapshot. Updating it changes that inventory record, although it
changes no Dart implementation. Record an explicit publication-documentation
exception and preserve the old manifest. The README is absent from both
53-input core/store bindings.

Keep the qualified model-test blob
`dd9172e8aed55f976baf698ce9e5ed52d8cc0c02`. It retains the runtime-created
equivalent value, explicit nonidentity, equality, equal-hash and `Set.add`
assertions. Incoming Zotero already retains the first four checks and changes
only the set-construction syntax relative to main; retaining main's exact bytes
preserves the stronger continuity claim without losing incoming assertions.

## Final audit scope

After freeze, rerun historical tracked-import closure and original Notes-file
comparisons at the exact new head. Keep the original 129-suite/2,018-case and
native 208-case/web-build evidence attributed to source `39843ed4`; do not label
it as a new execution. Check the frozen reference inventory and the known
Mail/Zotero additions by ancestry, with all 14 historical equivalence proofs
reverified. Preserve the distinction between a previously advertised inventory
and an updated inventory derived from already-fetched local refs.

Detailed pre-freeze evidence and replay are in
`postmerge_mail_documentation_review.json` and `audit_postmerge_mail.py`.
No tracked checkout edits, remote queries or GitHub Actions queries were made
by this review.
