# Quds Mail UI components

`quds_mail_ui` provides an account-free Flutter saved-message reader and a
reusable foreground message list. A host supplies immutable reader input or
message-list rows and owns all transport, credentials, persistence and actions.
The components create no account, credential store, database or network client.

## Embed the same message list in either host

```dart
MailMessageList(
  scopeId: hostAccountAndFolderIdentity,
  items: rows, // List<MailMessageListItem>, with unique stable nonempty IDs
  strings: hostLocalizedListStrings,
  selectedId: openedMessageIdentity,
  onOpen: hostOpenMessage,
  busy: isFetching,
  hasMore: nextCursor != null,
  onLoadMore: hostLoadNextPage,
  limitNotice: reachedHostLimit ? hostLimitNotice : null,
);
```

The list searches loaded subjects and senders without making requests. Unread
and Flagged filters combine; nullable unknown flags do not count as observed
unread/flagged states. Counts distinguish visible and loaded rows. Load more
remains available when filtering hides every loaded row. Rows are virtualized.

Arrow Up/Down and Home/End move list focus; Enter explicitly activates
the focused row. Space activates it when bulk selection is unavailable, or
checks it when a bulk-action callback is supplied. Editing the search field
keeps its normal editing keys.
Focus and opened-message selection are separate stable identities. Changing
`scopeId` resets query, filters, focus and scrolling. Hosts can retain the
widget while displaying a compact reader, but must exclude hidden list focus
and invalidate callbacks when switching sessions.

`busy` prevents activation and pagination, while local filtering stays
available. The host validates pages/cursors, enforces quotas, confirms actions,
and supplies loading/error/retry and limit policy. The Studio integration uses
50-message requests and a 1,000-loaded-message ceiling. This list alone is not
the planned account-aware `QudsMailWorkspace`; repository streams, unified
inbox and durable command orchestration remain open. See the
[foreground mailbox contract](../../docs/roadmaps/mail/mailbox-workspace.md).

### Foreground bulk read and flag selection

Connected hosts can opt in to checked-message actions:

```dart
MailMessageList(
  scopeId: hostAccountAndFolderIdentity,
  selectionRevision: hostMailboxRevision,
  items: rows,
  strings: hostLocalizedListStrings,
  onOpen: hostOpenMessage,
  onBulkAction: hostRunForegroundFlagBatch,
  bulkEnabled: !refreshRequired,
  busy: isFetchingOrChangingFlags,
  bulkStatus: hostBatchProgressOrResults,
);
```

The list keeps checkboxes separate from the opened message. **Select visible**
and Ctrl/Cmd+A, while the list owns focus, check only the currently matching
loaded rows. Space checks the keyboard cursor; Escape clears checked rows;
Enter opens the cursor. Selection itself
does not open messages, load pages, read bodies or invoke a mutation callback.
Filtering prunes hidden checks permanently; newly loaded rows are not selected
automatically. Sorting preserves checked identities.

The action menu exposes `markRead`, `markUnread`, `flag` and `unflag`. An explicit
choice forwards an unmodifiable ID list in visible order and immediately clears
the checks. Pending menu and pointer callbacks are rejected after host updates,
scope/revision/filter/sort/selection changes, or disposal. Changing `scopeId` or
`selectionRevision` clears the selection. The host must advance the revision
when its account, provider session or mailbox identity observations change, and
independently validate the submitted IDs before issuing provider commands.

`busy` disables selection and mutation controls. `bulkEnabled: false` clears
checks and keeps controls unavailable while the host requires a refresh. Omit
`onBulkAction` entirely for cached/read-only hosts; no mutable bulk controls are
shown. Host-owned progress, cancellation and per-message outcomes can be supplied
as `bulkStatus` within the compact scrollable header. This list does not queue,
retry, persist or send commands by itself.

## Embed the same reader in either host

```dart
final reader = MailReaderController.fromBytes(
  emlBytes,
  codec: const QudsMimeCodec(), // from quds_mail_mime
  mode: MailReaderMode.preview,
);

MailMessageView(
  controller: reader,
  compact: true,
  externalResources: hostLinkPolicy,
  onOpenApprovedLink: hostOpenLink,
  onOpenAttachmentReadOnly: hostPreviewImmutableAttachment,
  onOpenSource: (original, view) => hostSourceOrHex(original, view),
);
```

Dispose the controller when its host session ends. `replaceResult` changes the entire message identity, resets selection, rebuilds the bounded projection, and invalidates pending link approvals. The widget never disposes a host-owned controller. Full and preview constructors pass their actual budgets to the supplied codec: 32 MiB raw input for full mode and 20 MiB for preview. `compact` changes layout; it does not silently change the input budget.

The example under `example/` parses an independently authored multipart EML through the actual `QudsMimeCodec`. Its plain/HTML alternatives, local CID raster, binary attachment and blocked active/remote content all come from the same original byte snapshot. It offers full/compact modes, real query entry, source/hex, and read-only attachment bytes without accounts or network setup.

## Decoded selection, find and copy

`MailSelectionSurface` is a `LeafRenderObjectWidget` backed by `RenderMailSelectionSurface`. Message text is laid out and painted by `TextPainter`; it is not inserted into a browser DOM or an editable Flutter text widget. It supports mouse/stylus drag selection, touch long-press selection, Unicode grapheme boundaries, read-only selection semantics and explicit copy.

The view supplies accessible host chrome for Select all, Copy selection, Find, source/hex, links and attachments. The search query field is host chrome. Keyboard commands are Ctrl/Command+A, Ctrl/Command+C, Ctrl/Command+F, F3 and Shift+F3. Search navigation reveals the selected result. These operations also remain available directly to an embedding host:

```dart
reader.search('agenda', caseSensitive: false);
reader.nextSearchMatch();
final textToCopy = reader.selectedText;
reader.selectAll();
final allDisplayedText = reader.decodedText;
```

The search/copy projection includes visible subject, From/To/Cc/Bcc/Reply-To, date, the selected decoded body, and attachment names/type/size. Addresses are isolated for mixed-direction display and control characters are not allowed to rewrite the displayed header direction. These display safeguards never alter retained wire bytes. The search retains at most 1,000 matches and exposes `searchHasMore`; it does not silently claim an exhaustive count. Query input is bounded to 2,048 UTF-16 code units.

## Static HTML and resource policy

The renderer uses a bounded scanner, **without constructing an HTML DOM**. It admits input bytes, cumulative decoded bodies and attachments, rendered text, HTML token/attribute count, and nesting depth before growing each corresponding presentation structure. A scalar, count or nesting rejection discards the partial presentation and keeps explicit diagnostics and original-source access.

The supported subset includes paragraphs and line breaks, headings, bold/italic emphasis, list markers, simple table-cell/row text, link metadata, and separately displayed local CID PNG/JPEG rasters. It is a static reading projection, not browser-equivalent HTML layout. CSS layout/fonts are not supported. Common named and numeric character references are decoded; unsupported named references remain literal. Original HTML stays available through source view.

Script, forms, frames, embedded objects, SVG, MathML, media and other active containers are omitted. Event attributes, every CSS rule/style, `url`, `@import`, background, `srcset`, font and equivalent routes never reach a resource loader. Remote, protocol-relative, data, blob and file image URLs are blocked. Only exact unambiguous CID attachment references can reach the local raster decoder.

Only absolute HTTP, HTTPS and mailto links without control characters or embedded credentials become interactive. An explicit click or keyboard action first calls the host's `MailExternalResourcePolicy.openLink`. Only an `allow` result for the still-current reader identity can invoke `onOpenApprovedLink`. The default policy denies every link. The host must evaluate redirected destinations as new decisions; the reader itself performs no navigation or redirect fetch. This release does not offer remote-image loading, so `loadRemoteResource` is never called and there is no misleading remote-load control.

## CID rasters and immutable callbacks

Before a platform decoder sees a CID image, the reader checks the attachment byte budget, PNG/JPEG signature and dimensions, static-image structure, individual dimension bounds, and the cumulative pixel budget across unique images. PNG animation and ambiguous duplicate content IDs are rejected. JPEG scanning rejects duplicate or unsupported frame headers and missing/extra end markers. Other raster/vector formats are explicitly unsupported. The decoder must produce one frame with the admitted dimensions; a decode failure remains visible. Image resources are disposed when the message/view changes.

Attachment callbacks receive the exact `MailAttachment` snapshot from the parse result. Its `MailBytes` view is immutable; hosts can explicitly call `copyBytes()` to export or create a separate working copy. The reader never fabricates a writable source path. Source and hex callbacks receive the retained original `MailBytes`, not reserialized MIME or decoded display text.

## Qualification and scope

Tests next to the implementation cover hostile HTML/resource routes, byte/node/depth/pixel limits, source and attachment identity, search/grapheme selection, pending-approval invalidation, compact enlarged RTL layouts, and independent native/browser runtime network guards. Guards include a positive control proving that an attempted request is denied. Browser guards install after bootstrap and intercept fetch/XHR plus remote image, source, iframe, script and stylesheet property assignments; local data/blob raster decoding remains available.

Reproduction, using the repository's resolved workspace and compatible Flutter SDK:

```sh
flutter test --no-pub
flutter test --no-pub --platform chrome
# From example/:
flutter build web --release --no-pub --no-web-resources-cdn
```

The example's custom Flutter bootstrap uses same-origin CanvasKit and font-fallback paths. The build flag bundles CanvasKit and the default Roboto fallback. It does not bundle every Unicode font: embedding hosts must bundle/cache their required fonts and qualify the completed application without outbound requests. The reader accepts the host's text theme; it does not download a font named by message HTML. Browser build success is not evidence that arbitrary multilingual content works fully offline.

Run status and exact toolchain evidence belong to the Mail validation report in `docs/validation/mail-reader-20261118/`; test source alone does not establish a passing run. This package does not claim CrispCloud route parity, installed-app acceptance, low-memory-device performance, remote-image fetching, sending, mailbox sync, or App Store qualification.

Independent Quds code is MIT. This UI package depends on Flutter, `characters`, and `quds_mail_core`; the separate MIME codec retains its own reviewed MPL dependency boundary.
