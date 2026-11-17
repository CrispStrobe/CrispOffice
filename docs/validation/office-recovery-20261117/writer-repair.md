# ODT paragraph decoration and PAGE field repair

The incoming paragraph decoration implementation omitted shading and border
colors from its paragraph-style cache key. Neighboring paragraphs therefore
reused the first paragraph's decoration. It also interpolated arbitrary color
strings into XML attributes. The incoming PAGE implementation returned before
processing runs, discarding run formatting, the supported footer title suffix,
bookmarks and comments. In a note story it left the first-paragraph reference
space pending and incorrectly applied it to the following paragraph.

## Supported behavior

Paragraph shading and border colors accept the model's documented six ASCII
hexadecimal digits (`RRGGBB`). Valid values normalize to lowercase for both the
style key and XML. Invalid values are omitted independently without changing
the source model. The incoming border mapping remains `0.5pt solid`; this does
not add a general border-width or border-style model.

Simple paragraph PAGE fields emit one live ODF page-number element, using the
first run's formatting. The model's existing `WordFields.pageResultWithSuffix`
helper preserves the supported ` | title` suffix. When the numeric cache and
suffix span several runs, suffix text keeps the original run styles. The
numeric cache is replaced without editing source runs. Hyperlinks, bookmark
endpoints and comment ownership continue through the existing inline writer.
An empty paragraph can emit a live field without inserting a run in the model;
an empty bookmark range keeps that field inside its endpoints.

A nonempty explicit paragraph field instruction takes precedence over the
compatibility flag. Explicit PAGE is recognized; other instructions keep their
cached text. Paragraphs containing complex-field boundaries or atomic runs
(inline fields, note references or pictures) also keep their existing cached
inline content. This prevents the whole-paragraph compatibility flag from
replacing a locked inline field or moving an independently owned story. This
change does not implement generic native ODF fields, arbitrary Word field
switches, or native serialization of mixed inline fields.

Pending note-reference spacing is consumed by the first PAGE paragraph,
including when its numeric cache is empty. An intentionally absent reference
space remains absent. Existing list wrappers and section paragraph styles are
assigned before inline emission and continue to own their original boundaries.

## Regression evidence

The two new suites initially contained 40 substantive cases. Against the
integrated source before the writer repair, the preserved VM baseline reported
**31 failures, four errors, and five successes**. The two additional cases
check malformed colors when their style is emitted first and empty bookmarked
PAGE paragraphs without runs. The source-identity assertion compares the
exported paragraph's run object against its saved original reference.

The final suites contain **42 cases: 20 decoration and 22 PAGE cases**. Focused
VM and Node runs exercise the same cases; Node repetitions are not additional
unique cases. The run logs and strict analysis results are retained with the
continuation's evidence. The original failed baseline is preserved.

A broader development VM run covered these cases and six existing ODT suites.
It exposed an independent incoming contract mismatch in
`odt_section_continuation_test.dart`: its empty-document case expected a
synthetic body paragraph, while the integrated empty-document guard and the
other section suite intentionally require no authored body content. The failed
run remains retained; it is not represented as a passing qualification. The
continuation reconciles that single stale assertion in
`source-reconciliation.json`, retaining the master, geometry and source
immutability assertions without another production change.

These focused development checks do not replace the frozen combined-source
qualification. Historical reports retain their original source attribution.
