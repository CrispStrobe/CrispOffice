# Word section controls: validation records

The section orientation/start implementation, committed BAS examples and
portable harnesses are described in the
[source contract](../../VBA_WORD_MACROS.md#section-orientation-and-start-controls).

The Mail integration's [incoming Word receipt](../mail-repository-sessions-20261121/incoming-word.json)
records 294 passing native section tests, strict analysis and byte-identical
VM/compiled-JavaScript results for both actual BAS examples. It also records
the preserved replacement-layout regression suite separately. The associated
`incoming-word.tar.xz` contains its exact commands, logs and input hashes.

The section branch's own qualification is retained in
[preintegration-qualification.json](preintegration-qualification.json), with
[source applicability](preintegration-source-applicability.json) and
[reproduce.py](reproduce.py). The incoming-editor, incoming-Zotero and
late-incoming-Flutter receipts in this directory retain their original scopes
and source fingerprints; they do not replace qualification of later source.

These records establish the documented local gates. They do not claim installed
Microsoft Word execution or measured target-device typing performance.
