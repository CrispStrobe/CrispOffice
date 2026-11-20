## 0.1.0

- Add explicit visible-message selection and foreground read/flag action
  callbacks, with immutable ordered snapshots, Ctrl/Cmd+A and Space selection,
  hidden-row pruning, scope/revision resets and stale-menu rejection.
- Keep bulk controls absent in read-only hosts and unavailable while busy or
  refresh is required; expose a scrollable host-owned progress/results slot.
- Add bounded structured search of loaded message headers with localized syntax
  errors, recipient/date/state predicates, explicit clear and accessible help.
  Technical examples keep their left-to-right order within Arabic help.
- Keep long localized controls and errors scrollable in compact workspaces,
  reserving usable space for message rows and explicit pagination.
- Add stable local provider/date/sender/subject ordering without provider work,
  keeping unknown dates last and preserving message identity through reordering.
- Add a bounded body-only quotation API, preserving empty plain alternatives and
  rejecting incomplete HTML without reading message headers or attachments.
- Add a reusable foreground mailbox list with explicit loaded-message search,
  combined unread/flagged filters, bounded host-owned pagination, stable message
  focus, keyboard opening and provider/account scope resets.
- Expose the bounded, inert body text separately from envelope and attachment summaries for safe reply and forward quotes.
- Add the reusable account-free saved-message reader and a real multipart EML example.
- Add a bounded static HTML projection, explicit diagnostics, local CID PNG/JPEG admission, and immutable source/attachment callbacks.
- Add custom RenderBox decoded selection, grapheme-safe copy, full/preview input budgets, accessible find controls, keyboard navigation, and mixed-direction headers.
- Gate explicit links through host policy and reject stale asynchronous approval after message/view replacement.
- Add hostile input, resource denial, immutable callback, controller and reader widget regressions.
