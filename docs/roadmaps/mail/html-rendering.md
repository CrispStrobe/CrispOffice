# Safe formatted HTML mail

**Status:** implemented 22 November 2026 for the native CrispOffice Studio
reader. The plain-text projection remains the fallback and the source of
find/copy values.

## Why the old view was not enough

The previous reader projected HTML into styled text. Paragraphs, bold text and
links survived, but tables, spacing, colours and inline images did not. That is
safe, but it is not a usable rendering of a transactional or marketing email.

## Rendering model

Studio opts into `MailMessageView(richHtml: true)`. The reader then uses a
bounded Flutter HTML renderer for the admitted HTML body. The existing text
projection and source views remain available through **Show plain text**.

The rich view is not a browser and has no network port:

- scripts, stylesheets with external resources, forms, frames, objects, SVG,
  MathML, media, templates and active elements are removed;
- event-handler, `srcset`, background, poster and form-action attributes are
  removed;
- links are accepted only through the existing `http`/`https`/`mailto`
  allowlist and the host's approval callback;
- CSS containing `url()`, `@import`, `@font-face`, `expression`, `behavior`,
  `-moz-binding`, `javascript:`, `vbscript:` or `data:` is discarded; positioning
  rules are removed;
- the sanitizer enforces the existing HTML node/depth budgets plus a 2 MiB
  sanitized-markup cap;
- images are emitted with `data-mail-cid` or `data-mail-remote` metadata and
  **no `src` attribute**. The custom image widget can render only bytes already
  admitted to `MailReaderPresentation.images`; otherwise it shows a local
  placeholder. There is no URL fetcher in the renderer.

## Layout

The sanitizer preserves common mail structure, including paragraphs, headings,
lists, blockquotes, tables, table cells, colours, inline widths/heights and safe
inline styles. It unwraps unknown non-active wrappers so their text is not lost.
Safe `<style>` blocks are retained when they contain no external resource.

## Interaction

- Links call the same host approval path as the text reader.
- Inline CID images render from validated static PNG/JPEG bytes.
- Explicitly loaded remote images appear inline through the existing
  `data-mail-remote` key; before that they show a clickable **Load external
  image** placeholder. The same load action remains available from the reader
  actions.
- Tables are forced to the available reader width with safe auto layout so
  fixed-width transactional-mail tables cannot collapse into letter-wide
  columns.
- Rich mode uses Flutter `SelectionArea` for copying; the text mode keeps the
  explicit find, select-all and copy controls. Find is intentionally not
  highlighted over the rich layout.

## Verification

- `quds_mail_ui` full suite: **297/297 passed**.
- New sanitizer and rich-widget tests cover script/event removal, CSS URL
  removal, safe tables, CID/remote image metadata, link filtering and the
  no-`src` image invariant.
- Studio saved/cached Mail host tests: **113/113 passed**.
- Live IMAP mailbox.org: fetched a real HTML message, built the sanitized view,
  asserted no scripts/event handlers/active image `src`, and rendered it through
  `MailMessageView(richHtml: true)`.

The live test is
`packages/quds_office_editor/example/test/live_mail_html_render_test.dart` and
requires `MBOX_LOGIN`/`MBOX_PW`.
