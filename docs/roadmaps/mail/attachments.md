# Studio Mail attachment drafts

In a Mail composer, choose **Add attachments** and select one or more local
files. The composer shows each filename and size, the total selection, and a
remove action for each file. The limit is **10 files and 10 MiB of original
file bytes in total**. A failed selection leaves the earlier attachment list
intact. Closing the composer cancels an outstanding read; a late picker or
stream result cannot reopen or modify the closed draft.

Attachments are immutable byte snapshots. Editing or deleting a selected
source file afterward cannot change the message already prepared in the draft.
Reads verify both declared and actual size, bound stream allocation and time,
and refuse incomplete files. Filenames are preserved as Unicode names rather
than treated as paths or header fragments. Browser selection uses supplied
bytes or streams; a browser path is never fetched as a URL.

Sending uses the existing explicit provider/envelope path. Messages with
attachments use a mixed MIME container with a plain-text/HTML alternative body
and binary attachment parts. RFC 2231 parameters carry Unicode filenames;
binary text files keep their original bytes without a guessed character set.
The wire message has a separate bound of 22 MiB, leaving room for provider
request encoding beneath the existing cloud transport budget.

To/Cc remain visible in the message; Bcc stays in the private recipient
envelope and is handled by the provider-specific submission path. An uncertain
submission keeps the same immutable attachment snapshot alongside the body,
recipient groups and threading metadata. Retrying still requires the existing
explicit acknowledgement after checking delivery. No automatic replay is
introduced.

Reply and text-only forwarding continue to quote the available message body;
they do not silently attach files from the original message. This workflow
selects local files. Direct attachment of the current unsaved Office document,
durable drafts/outbox, provider upload sessions for larger files, and live
account interoperability remain separate work.

The [combined qualification report](../../validation/zotero-research-materials-20261120/README.md)
records the captured Mail/VBA/Office heads, exact source and runtime, host and
provider tests, MIME/SMTP regressions, and a separate independent Python MIME
inspection. Those checks use synthetic messages and controlled transports;
they do not send mail through a live account.
