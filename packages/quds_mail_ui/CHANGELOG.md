## 0.1.0

- Add bounded structured search of loaded message headers with localized syntax
  errors, recipient/date/state predicates, explicit clear and accessible help.
  Technical examples keep their left-to-right order within Arabic help.
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
