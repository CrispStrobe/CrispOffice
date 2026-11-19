# CrispOffice image editor integration design

Date: 19 November 2026. Status: design and source investigation; no image-editor
runtime, dependency, or copied CrispCloud host implementation is added by this
document.

## Recommendation

Reuse CrispCloud's maintained `pro_image_editor` package as a native Flutter
surface. Write a small, independent CrispOffice host that opens a picture in a
modal editor and returns validated image bytes. Apply those bytes through the
existing Word, Sheet, or Slide undo command. Keep the Office document's save
workflow responsible for persistence.

This gives CrispOffice crop/rotate, drawing, text, adjustments, filters, blur,
zoom, and layer editing without a WebView or a port of the image engine. A
separate image-file workspace can use the same host later. Its file identity,
overwrite, conflict, and save lifecycle should be implemented separately from
editing an embedded Office picture.

The important reuse boundary is the explicitly licensed vendor package.
CrispCloud's application dialog and storage services are useful architectural
references, but they are not an independent permissively licensed SDK to copy
into this repository.

## Verified source and provenance

The GitHub connector was used to inspect actual files and Git trees in
[`CrispStrobe/CrispCloud`][cc-repo]. The immutable source snapshot is:

| Item | Observed value |
| --- | --- |
| CrispCloud commit | `40b955c262f980f9745812e6021d9ca30048b764` |
| Vendor directory | `packages/pro_image_editor/` |
| Complete vendor Git tree | `947764f4d92dceabe62590ab9a40ddf7c36927f6` |
| Vendor contents | 838 blobs, 7,583,861 bytes before checkout overhead |
| Package version | `14.24.0` |
| Upstream project | `hm21/pro_image_editor` |
| Upstream commit recorded by the fork | `548591a6854691a8c31cbfb5637794e9bc6ded34` |
| Published archive | `https://pub.dev/api/archives/pro_image_editor-14.24.0.tar.gz` |
| Recorded archive SHA-256 | `de1d0a5eaee1f80871b09a6ea03c2341cb86f00b590181f14ab4d6485ab978bb` |
| Flutter SDK pinned by CrispCloud | `3.47.8`, also pinned by CrispOffice |
| Vendor SDK constraints | Dart `>=3.12.0 <4.0.0`, Flutter `>=3.44.0` |

The upstream archive identity is recorded in the fork's [UPSTREAM.md][cc-upstream];
this investigation did not independently download that archive. The package
identity and SDK constraints come from its [pubspec.yaml][cc-pubspec]. Its Darwin
podspec still says `12.0.8`; that is native packaging metadata, not the Dart
package version. Use the package manifest and recorded source tree for the
import identity.

The maintained fork includes host-owned navigation, awaitable tool completion
and retry, nested cancellation, desktop modifier handling, history for mouse
wheel edits, localization of popup routes, preservation of image bounds and
alpha, crop-handle hit testing, and browser-worker recovery. Importing the
unmodified upstream package would omit these documented changes. Preserve
`UPSTREAM.md`, `UPSTREAM.patch`, the local regression tests, and any subsequent
CrispOffice patch record when importing the exact tree.

The [CrispCloud integration document][cc-integration] describes the host's
ownership and save contract. It also contains historical test results. Those
results are not evidence that a future CrispOffice integration has passed.

### License boundary

| Source | License declared in the inspected source | Consequence for this design |
| --- | --- | --- |
| `packages/pro_image_editor/LICENSE` | BSD-3-Clause, Alex Frei | Preserve the license, copyright, disclaimer, and distribution notices with the vendor copy. |
| `packages/pro_image_editor/NOTICES` | Retained BSD, MIT, and Apache-2.0 notices for bundled sources | Keep the complete notice file and include applicable notices in distributed application materials. |
| CrispCloud root `LICENSE.txt` | GNU AGPL version 3 | Do not copy the application dialog, services, or translation implementation into an MIT host under a different label. |
| CrispOffice root `LICENSE` | MIT, followed by additional third-party notices | Write the CrispOffice adapter as original repository code and retain each dependency's own notices. |

These are observations of the [vendor license][cc-license],
[vendor notices][cc-notices], [CrispCloud license][cc-root-license], and
[CrispOffice license](../LICENSE). The design does not depend on changing
CrispCloud's application license or obtaining rights to relabel its host code.
Its file-level vendor license remains part of the imported package.

## Flutter embedding and runtime requirements

The actual [CrispCloud surface][cc-surface] constructs
`ProImageEditor.memory(bytes, key: ..., callbacks: ..., configs: ...)`.
`GlobalKey<ProImageEditorState>` exposes tool opening, undo/redo, image capture,
and history import/export. CrispCloud supplies its own surrounding toolbar,
commands, theme, localization, and persistence.

The engine uses `dart:ui` to render and capture images. Its
[content recorder][cc-recorder] selects native Dart isolates on non-web
platforms and workers on web. The [Darwin plugin][cc-darwin] implements emoji
glyph support queries; it is not an external image-rendering service. The
manifest declares Android, iOS, Linux, macOS, web, and Windows, with native
plugin registration for Android and shared Darwin sources. This is a native
Flutter integration, with no desktop JavaScript bridge or browser dependency.

The following parts of the package must travel together:

- Dart runtime and bundled sources under `lib/`.
- `pixelate.frag` and `pixelate_areas.frag` shaders.
- The `ProImageEditorIcons` font and its asset declaration.
- Android and Darwin plugin metadata and source.
- Generated browser worker and source map for any supported web build.
- Original licenses, notices, provenance, and regression tests.

The fork uses `material_ui` and `cupertino_ui`. The new host should keep normal
Flutter Material widgets for CrispOffice's chrome, and give the engine a
scoped `material_ui` theme and its localization delegates. Map the current
host color scheme and locale into that scope. Include text scaling and RTL
behavior in the first widget tests; moving a popup to the root navigator must
not lose the engine's localization scope.

The Office engine remains pure Dart. Put the modal in Studio host chrome, not
inside the Word/Sheet/Slide RenderBox document canvas. This preserves the
separation required by [CONTRIBUTING.md](../CONTRIBUTING.md).

### Proposed dependency placement

Use `third_party/pro_image_editor/` for the exact vendor copy, consistent with
the existing third-party source boundary. Add a path dependency from
`packages/quds_office_editor/example/pubspec.yaml` when implementation starts.
A later reusable editor package can depend on the same vendor; there is no
reason to make the pure Dart Office engine depend on it.

| Dependency | Existing/reference resolution | Planned treatment |
| --- | --- | --- |
| `pro_image_editor` | CrispCloud path package, `14.24.0` | Import the immutable vendor tree; no moving Git branch. |
| `material_ui` | CrispCloud lock: `1.10.0`; vendor constraint `^1.1.1` | New direct host dependency if host code uses its theme/localization types. |
| `cupertino_ui` | CrispCloud lock: `1.1.6`; vendor constraint `^1.0.2` | Transitive engine dependency unless host code imports it. |
| `shared_preferences` | CrispCloud lock: `2.5.6`; vendor constraint `^2.5.4` | Transitive dependency, including its platform plugins. |
| `image` | CrispOffice lock: `4.13.1`; CrispCloud host lock: `4.12.0` | Declare directly in the host if used for independent output validation or conversion; retain the current compatible Office version. |
| `http`, `intl` | Both checkouts resolve `1.6.0` and `0.20.3` respectively | Existing constraints appear compatible. |
| `plugin_platform_interface`, `vector_math`, `web` | Declared by the vendor | Resolve in the normal workspace lock; retain their notices. |

The reference versions above come from [CrispCloud's lockfile][cc-lock] and the
inspected local `pubspec.lock`. This was a source comparison, not a dependency
solve. Do not transplant CrispCloud's application lockfile or its unrelated
dependency overrides. Review and commit the minimal new resolution when adding the runtime
integration. Declare any other package directly if the new
host imports it, even if it is already present transitively.

## Independent CrispOffice adapter

Suggested implementation files are `studio_image_editor.dart` for the modal
and `studio_image_edit_session.dart` for immutable input/output and session
state, under `packages/quds_office_editor/example/lib/`. They are proposed
names, not existing runtime code.

The modal should receive a typed request with a copied, read-only byte buffer,
validated encoding and dimensions, output policy, and host presentation
settings. It should return either cancellation or an immutable result with
encoded bytes, encoding, decoded dimensions, and whether content changed.
It should not receive a writable `OfficeVisual`, a document controller, or a
source-file path. Keep engine-specific history objects inside the adapter.

The caller captures the target controller, document identity, target picture
identity, original bytes, and `contentRevision` before opening the modal. This
is the binding used when the asynchronous editor returns; a changed selection
must never redirect an edit into a different picture.

### Modal edit-return-bytes lifecycle

1. **Open.** Commit pending document text/cell edits first. Check that mutation
   is allowed and the selected object is a picture with supported bytes.
   Copy and validate the source before decoding. Capture the originating
   document, picture, and revision. Open one modal session.
2. **Edit.** Keep image undo/redo inside the engine. Configure host-owned
   navigation and disable duplicate main-engine chrome and main keyboard
   shortcuts. The host routes image commands while allowing an active text or
   crop tool to own its input. Tool Apply and Cancel remain distinct from
   applying the complete image to the document.
3. **Capture.** Disable the final Apply action while a subeditor has unapplied
   changes. When all tools are closed, block overlapping capture requests and
   pointer/keyboard mutations, record the session revision, await the render,
   and capture. Reject stale completion or disposal. A capture failure leaves
   the modal and current edits available for retry.
4. **Validate.** Check output size, encoding, dimensions, frame count, and
   actual independent decoding before returning bytes. Return cancellation
   without a document mutation. Return no change without creating an undo
   command.
5. **Apply once.** Recheck controller disposal, document identity, target
   membership/identity, mutation permission, source bytes, and content
   revision. The first implementation should conservatively reject a stale
   document revision. Only then call the correct existing controller mutation
   API with a synchronous assignment of the already prepared byte snapshot.
6. **Save normally.** Applying an image makes the document dirty. It does not
   mark it saved or write over an external raster. The existing Office save
   workflow serializes and persists the changed document.

Use **Apply to document** for the final action so the distinction from saving
the Office file is visible. Escape first cancels an active tool; closing a
dirty image session then offers Apply, Discard, or Cancel. App/window close
must resolve this modal before reaching the document's unsaved-change guard.
Background document File, Edit, and ribbon commands must not act through the
modal. A native menu command that was queued before the modal opened must
also check the active command owner at dispatch time.

Do not derive dirty state from a reusable history index. A branch created
after Undo can have the same index and different content. Track immutable
history identities and effective in-place gestures, or an equivalent stable
revision scheme. CrispCloud's [dialog][cc-dialog] and
[session][cc-session] demonstrate why this contract is necessary; the
CrispOffice implementation should be original code with its own tests.

## Existing picture replacement and undo APIs

These symbols were inspected in the CrispOffice checkout at HEAD
`37ac6ea8a08225a42098c455deb5375837912eec`; ongoing unrelated GUI changes may
move their line numbers. They share
[`OfficeVisual`](../packages/quds_office_engine/lib/src/visual/office_visual.dart),
whose `copy()` and `restoreFrom()` copy image bytes and picture formatting.

| Host | Selected target | Existing mutation API |
| --- | --- | --- |
| Word | `WordEditorController.selectedVisual?.visual` | `mutateSelectedVisual(void Function(OfficeVisual))` |
| Sheet | `SheetEditorController.selectedDrawing?.visual` | `mutateSelectedDrawing(void Function(OfficeVisual))` |
| Slide | `SlideEditorController.selected?.visual` | `mutateSelectedShapeVisual(void Function(OfficeVisual))` |

All three implementations in
[`office_controller.dart`](../packages/quds_office_editor/lib/src/embed/office_controller.dart)
check mutation permission, capture before/after `OfficeVisual` copies, and
commit a command that restores those snapshots for execute/undo. Word also
relayouts. Controller command notifications advance `contentRevision` and
mark the document dirty. Therefore one accepted image result can become one
existing Office undo step. Prepare and validate the result before entering
the callback: these methods call the edit callback before committing the
command, so it must not contain fallible decoding or asynchronous work.

These methods target the **current selection**. The caller must validate
that it still denotes the captured object immediately before calling them.
If a later integration needs to survive selection changes, add an explicit
target-based command with the same membership and stale-result checks.
Do not write `visual.imageBytes` outside a command and call `refresh()` as a
substitute for undo integration.

`WordEditorController.insertPicture(OfficeVisual)` already supplies the
undoable insertion path for a newly edited image. Reuse it for an optional
edit-before-insert flow, after image-picker cancellation is handled as a real
cancel. The current Studio `_pictureBytes` helper falls back to a sample
image when picking returns no bytes; that demo fallback should not be used
as the new editor's cancellation contract.

The existing Studio save flow captures controller revision and document
identity and marks clean only after persistence of the matching document.
Reuse that ownership rather than adding an image-specific file write inside
the modal. See
[`suite_workspace.dart`](../packages/quds_office_editor/example/lib/suite_workspace.dart),
`_saveFile`.

### Picture geometry and existing Office formatting

The first embedded-image action edits the source raster. Preserve the existing
picture frame, position, wrap distances, accessibility text, crop, rotation,
and Office effects when replacing only `imageBytes`. Show this distinction in
the editor: existing Office picture formatting remains applied after the
image edit. Do not capture that formatting into the raster and then apply it
again on return.

Cropping or rotating the source can change its aspect ratio. The default
replacement should preserve the existing document frame, with a preview of
the resulting fit before Apply. An explicit fit/resize option may update the
appropriate Office geometry, but it must be part of the same undo transaction
and must account for Sheet drawing anchors and Slide shape transforms. The
initial byte-only path should not silently change those layout objects or
reset all `PictureAdjust` properties.

## Encodings, limits, and editable projects

### Initial embedded-picture policy

Start with static PNG and JPEG input and validated PNG output for the edited
embedded picture. PNG preserves alpha and avoids another lossy JPEG encode.
This is a replacement inside the Office package; it does not overwrite or
rename the original image file. A later explicit JPEG export option can
provide a size/quality choice.

The current Office writers identify PNG/JPEG directly. Word also recognizes
GIF, while Sheet and Slide use `WordLikeMedia.mimeOf`, which recognizes JPEG
and otherwise reports PNG. Consequently WebP, BMP, or TIFF bytes must not be
returned directly to these existing writers without extending their media
contract. See [Word media handling][office-word-media],
[Sheet media handling][office-sheet-media], and
[Slide serialization][office-slide-media].

Validate signatures and structure instead of trusting a filename. Reject
animation and multi-image inputs unless the UI explicitly supports their
semantics. Preserve full source resolution within explicit budgets; do not
inherit the engine's default JPEG output or 2000-pixel bound. Straight RGBA
capture and a square bound based on the original longest side are the
existing [CrispCloud surface's][cc-surface] approach to transparent borders
and quarter-turn rotation.

Use these explicit initial budgets, matching the existing host's
[session contract][cc-session], and test their behavior before shipping:

| Budget | Initial policy |
| --- | --- |
| Encoded input | 32 MiB |
| Encoded output | 64 MiB |
| Decoded image area | 40 million pixels |
| Maximum side | 16,384 pixels |

Apply the checks before large allocations where header information permits.
Bound concurrent captures and retained history memory as well as encoded
file sizes. Multiple RGBA surfaces and the document's undo snapshots consume
more memory than the input file. Metadata, color profiles, and high bit depth
are not preserved by a flattened Flutter-rendered raster; state that behavior
where the user applies or exports an image.

### Additional formats and standalone image files

CrispCloud's current [file store][cc-store] supports static WebP, GIF, BMP, and
TIFF through a PNG editing surface, in addition to PNG/JPEG. Its older
integration prose lists fewer formats; the source at the pinned commit is the
authority. The [raster codec][cc-raster] rejects multipage TIFF and checks
decoded output pixels for fidelity. GIF has an exact color/transparency
policy rather than silently reducing edited colors. WebP output is lossless.

Those are useful later feature contracts, not capabilities supplied by simply
constructing `ProImageEditor.memory`. A standalone CrispOffice image-file
workspace needs its own validated format adapters, atomic local writes,
original-file conflict detection, Save As cancellation, and truthful export
results. Browser download initiation must never be treated as proof that the
original file was saved. It can reuse the same modal/session engine boundary
without importing CrispCloud's cloud accounts or storage abstractions.

### Project-state decision

The first Office integration returns a flattened image. The image session's
editable layers and engine history are not silently inserted into DOCX,
XLSX, or PPTX, and no undocumented sidecar is written. Office Undo retains the
pre-edit raster through its normal command snapshot.

If editable project interoperability is added later, investigate explicit
`.ccimage` import/export. CrispCloud's [project model][cc-project] uses a
version-1 JSON envelope with type `crispcloud-image-project`, source filename,
base64 source bytes, SHA-256 source integrity, and the fork's serialized
history. Its size limit is 64 MiB and it rejects external file, network, and
asset references in layers. Preserve that format identity when intentionally
supporting compatibility; do not rename fields or assume history stability
across engine upgrades. Implement and test a typed boundary around the
engine's serialized map rather than exposing untyped maps throughout Studio.

## Staged implementation and verification

Each stage should be a reviewable remote checkpoint. No stage relies on
waiting for a GitHub Actions queue.

1. **Vendor and reproducible resolution.** Import the exact reviewed tree with
   its notices and provenance into `third_party/`; record the source commit
   and tree in the local receipt. Add the Studio path dependency and minimal
   direct dependencies, resolve using the pinned SDK, and review the lockfile
   change. Verify shader/font assets and native plugin registration. Retain
   the generated web worker if web remains supported.
2. **Independent modal and lifecycle.** Implement typed immutable requests and
   results, input budgets, host theme/localization scope, command ownership,
   active-tool Apply/Cancel, capture retry, disposal guards, and output
   validation. Test real rendered edits, transparency, resolution beyond
   2000 pixels, keyboard focus, mouse gestures, RTL, and large text.
3. **Office picture bridge.** Add an Edit Image action to the contextual
   Picture ribbon for Word, Sheet, and Slide. Test cancel/no-op, one-step
   apply/undo/redo, stale selection/document/revision, disposal, read-only
   mode, and preserved frame/wrap/accessibility properties. Serialize and
   reopen DOCX/XLSX/PPTX and independently decode the embedded output.
4. **Desktop and web acceptance.** Exercise real macOS native-menu focus and
   app/window close, plus Windows/Linux behavior; method-channel mocks alone
   do not establish native desktop acceptance. Run relevant retained vendor
   regressions. If web is shipped, run real worker success/failure tests and
   verify source/compiled-worker consistency. Preserve actual commands,
   source hashes, outputs, and environment limitations.
5. **Separate extensions.** Add standalone image files, additional formats,
   independent export copies, or `.ccimage` projects only with their storage,
   format, and compatibility tests. Keep these separate from the initial
   modal's simple return-bytes contract.

Retained vendor regression sources include `test/crispcloud/` cases for
embedded/host navigation, completion failure/retry, image bounds, desktop
wheel history, modifier keys, localized overlays/numbers, and worker failure.
The future integration must run the relevant cases against its own resolved
dependencies rather than quoting CrispCloud's historical totals.

## What was checked for this document

Read-only GitHub source inspection and local source reads established the
vendor identity, declared licenses, Flutter architecture, dependency
constraints, host behavior, and existing Office mutation APIs. The complete
vendor tree response was not truncated. No image-editor dependency solve,
compiler, widget test, native build, or application launch was performed for
this design. Those checks belong to the implementation stages above.

[cc-repo]: https://github.com/CrispStrobe/CrispCloud/tree/40b955c262f980f9745812e6021d9ca30048b764
[cc-upstream]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/packages/pro_image_editor/UPSTREAM.md
[cc-pubspec]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/packages/pro_image_editor/pubspec.yaml
[cc-license]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/packages/pro_image_editor/LICENSE
[cc-notices]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/packages/pro_image_editor/NOTICES
[cc-root-license]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/LICENSE.txt
[cc-lock]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/pubspec.lock
[cc-integration]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/docs/image-editor-integration.md
[cc-surface]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/lib/widgets/image_editor_surface.dart
[cc-recorder]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/packages/pro_image_editor/lib/shared/services/content_recorder/controllers/content_recorder_controller.dart
[cc-darwin]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/packages/pro_image_editor/darwin/pro_image_editor/Sources/pro_image_editor/ProImageEditorPlugin.swift
[cc-dialog]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/lib/widgets/image_editor_dialog.dart
[cc-session]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/lib/services/image_edit_session.dart
[cc-store]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/lib/services/image_file_store.dart
[cc-raster]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/lib/services/image_raster_codec.dart
[cc-project]: https://github.com/CrispStrobe/CrispCloud/blob/40b955c262f980f9745812e6021d9ca30048b764/lib/services/image_edit_project.dart
[office-word-media]: ../packages/quds_office_engine/lib/src/word/serial/word_drawing_io.dart
[office-sheet-media]: ../packages/quds_office_engine/lib/src/sheet/serial/sheet_drawing_io.dart
[office-slide-media]: ../packages/quds_office_engine/lib/src/slide/serial/slide_serial.dart
