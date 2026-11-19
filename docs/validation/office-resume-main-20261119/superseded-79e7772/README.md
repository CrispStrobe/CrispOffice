# Superseded source qualification at `79e7772`

Source: `79e77725925d937bae944b03aac795ffb3fd967d`.
Tree: `e71c487e07dbf323fb964e795f2a3b803dc02d96`.

This source passed 928 native/VM cases in 43 suites, strict analysis and format
checks on all 48 changed Dart files, and the whitespace gate. Its 21 separate
Python controls also passed. Independent recount verified the raw reporters,
case identities and exact suite coverage, all pinned source objects, and stable
before/after inventories of 5,177 source and 11,171 runtime records. There was no
Node run at this source.

Independent review then identified a behavior absent from the selection:
`SmtpClient` inherited a socket abort that did not settle the current command.
An SMTP server withholding a reply could therefore leave the send pending and
retain the outgoing lock needed by high-level disconnect. The source is
superseded until that behavior is repaired and qualified.

These successful results remain evidence for their exact source. They contribute
**zero executions and zero controls** to the later final-source totals. This is
a passing superseded gate, distinct from the rejected `409258f9` gate.

The archive preserves native and Python receipts, raw and compressed logs,
case inventories, complete source/runtime manifests, independent audits, the
exact captured-reference graph audit and historical artifact-preservation audit.
Every indexed archive member was reopened and checked for exact size and SHA-256.
