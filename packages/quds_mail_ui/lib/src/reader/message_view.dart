import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'controller.dart';
import 'presentation.dart';
import 'selection_surface.dart';

enum MailSourceView { source, hex }

typedef MailReadOnlyAttachmentAction =
    Future<void> Function(MailAttachment attachment);
typedef MailSourceAction =
    Future<void> Function(MailBytes bytes, MailSourceView view);
typedef MailApprovedLinkAction = Future<void> Function(Uri target);
typedef MailCopyAction = Future<void> Function(String decodedText);

/// The same account-free reader can be embedded in a full or compact host.
///
/// The host supplies explicit source, attachment and approved-link actions.
/// There is no automatic external-resource loading. Source/attachment callbacks
/// receive immutable snapshots, never a writable path or a reconstructed MIME.
class MailMessageView extends StatefulWidget {
  const MailMessageView({
    super.key,
    required this.controller,
    this.compact = false,
    this.textDirection,
    this.externalResources = const MailDenyExternalResources(),
    this.onOpenApprovedLink,
    this.onOpenAttachmentReadOnly,
    this.onOpenSource,
    this.onCopy,
    this.onFindRequested,
  });
  final MailReaderController controller;
  final bool compact;
  final TextDirection? textDirection;
  final MailExternalResourcePolicy externalResources;
  final MailApprovedLinkAction? onOpenApprovedLink;
  final MailReadOnlyAttachmentAction? onOpenAttachmentReadOnly;
  final MailSourceAction? onOpenSource;
  final MailCopyAction? onCopy;
  final ValueChanged<MailReaderController>? onFindRequested;

  @override
  State<MailMessageView> createState() => _MailMessageViewState();
}

class _MailMessageViewState extends State<MailMessageView> {
  final FocusNode _focus = FocusNode(debugLabel: 'Decoded mail selection');
  final TextEditingController _findInput = TextEditingController();
  final FocusNode _findFocus = FocusNode(debugLabel: 'Find decoded mail');
  final ScrollController _scroll = ScrollController();
  final GlobalKey _surfaceKey = GlobalKey(debugLabel: 'Decoded mail body');
  bool _findVisible = false;
  String? _notice;
  int _action = 0;

  @override
  void didUpdateWidget(MailMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _action++;
      _notice = null;
    }
  }

  @override
  void dispose() {
    _action++;
    _focus.dispose();
    _findInput.dispose();
    _findFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _current(MailReaderController controller, int revision, int action) =>
      mounted &&
      !controller.isDisposed &&
      identical(controller, widget.controller) &&
      controller.revision == revision &&
      action == _action;

  Future<void> _hostAction(Future<void> Function() callback) async {
    final controller = widget.controller;
    final revision = controller.revision, action = ++_action;
    try {
      await callback();
      if (_current(controller, revision, action)) {
        setState(() => _notice = null);
      }
    } on Object {
      if (_current(controller, revision, action)) {
        setState(
          () => _notice =
              'The host action failed. The saved message is unchanged.',
        );
      }
    }
  }

  Future<void> _openLink(Uri target) async {
    final callback = widget.onOpenApprovedLink;
    if (callback == null || approvedMailLink(target.toString()) == null) return;
    final controller = widget.controller;
    final revision = controller.revision, action = ++_action;
    try {
      final decision = await widget.externalResources.openLink(target);
      if (!_current(controller, revision, action)) return;
      if (decision == MailResourceDecision.deny) {
        setState(() => _notice = 'The host did not approve this link.');
        return;
      }
      await callback(target);
      if (_current(controller, revision, action)) {
        setState(() => _notice = null);
      }
    } on Object {
      if (_current(controller, revision, action)) {
        setState(() => _notice = 'The host could not open this link.');
      }
    }
  }

  Future<void> _copy() async {
    final text = widget.controller.selectedText;
    if (text.isEmpty) return;
    await _hostAction(
      () =>
          widget.onCopy?.call(text) ??
          Clipboard.setData(ClipboardData(text: text)),
    );
  }

  void _showFind() {
    widget.onFindRequested?.call(widget.controller);
    _findInput.text = widget.controller.searchQuery;
    setState(() => _findVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  }

  void _next({bool backwards = false}) {
    if (widget.controller.nextSearchMatch(backwards: backwards) == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final render = _surfaceKey.currentContext?.findRenderObject();
      if (render is! RenderMailSelectionSurface ||
          render.selectionRect == null) {
        return;
      }
      final viewport = RenderAbstractViewport.of(render);
      final target = viewport
          .getOffsetToReveal(render, .3, rect: render.selectionRect)
          .offset;
      _scroll.jumpTo(
        target.clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final control =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final controller = widget.controller;
    if (control && event.logicalKey == LogicalKeyboardKey.keyA) {
      controller.selectAll();
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyC) {
      unawaited(_copy());
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyF) {
      _showFind();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f3) {
      _next(backwards: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _findFocus.hasFocus) {
      setState(() => _findVisible = false);
      _focus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.select(
        TextSelection.collapsed(offset: controller.selection.extentOffset),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final direction = widget.textDirection ?? Directionality.of(context);
    return Directionality(
      textDirection: direction,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final result = controller.result;
            final presentation = controller.presentation;
            final message = result.message;
            final links = presentation.runs
                .map((run) => run.link)
                .whereType<Uri>()
                .toSet()
                .toList(growable: false);
            final padding = widget.compact ? 12.0 : 20.0;
            return Material(
              color: Theme.of(context).colorScheme.surface,
              child: CustomScrollView(
                key: const ValueKey('mail-reader-scroll'),
                controller: _scroll,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.all(padding),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            presentation.rejected
                                ? 'Message display unavailable'
                                : '${_statusLabel(result.status)} · ${controller.mode.name} reader',
                            key: const ValueKey('mail-reader-status'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              TextButton.icon(
                                key: const ValueKey('mail-select-all'),
                                onPressed: presentation.text.isEmpty
                                    ? null
                                    : controller.selectAll,
                                icon: const Icon(Icons.select_all),
                                label: const Text('Select all'),
                              ),
                              TextButton.icon(
                                key: const ValueKey('mail-copy'),
                                onPressed: controller.selection.isCollapsed
                                    ? null
                                    : () => unawaited(_copy()),
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy selection'),
                              ),
                              TextButton.icon(
                                key: const ValueKey('mail-find'),
                                onPressed: _showFind,
                                icon: const Icon(Icons.search),
                                label: const Text('Find in message'),
                              ),
                              if (result.original != null &&
                                  widget.onOpenSource != null)
                                for (final view in MailSourceView.values)
                                  TextButton.icon(
                                    key: ValueKey('mail-${view.name}'),
                                    onPressed: () => unawaited(
                                      _hostAction(
                                        () => widget.onOpenSource!(
                                          result.original!,
                                          view,
                                        ),
                                      ),
                                    ),
                                    icon: Icon(
                                      view == MailSourceView.source
                                          ? Icons.code
                                          : Icons.data_array,
                                    ),
                                    label: Text(
                                      view == MailSourceView.source
                                          ? 'Raw source'
                                          : 'Hex',
                                    ),
                                  ),
                              if (message?.body.html != null &&
                                  message?.body.plainText != null)
                                TextButton(
                                  onPressed: () => controller.setPreferHtml(
                                    !controller.preferHtml,
                                  ),
                                  child: Text(
                                    controller.preferHtml
                                        ? 'Show plain text'
                                        : 'Show static HTML',
                                  ),
                                ),
                            ],
                          ),
                          if (_findVisible)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: TextField(
                                key: const ValueKey('mail-find-input'),
                                controller: _findInput,
                                focusNode: _findFocus,
                                maxLength: 2048,
                                decoration: const InputDecoration(
                                  labelText: 'Find in decoded message',
                                  counterText: '',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: controller.search,
                                onSubmitted: (_) => _next(),
                              ),
                            ),
                          if (controller.searchQuery.isNotEmpty)
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '${controller.searchMatches.length}${controller.searchHasMore ? '+' : ''} '
                                  '${controller.searchMatches.length == 1 && !controller.searchHasMore ? 'match' : 'matches'}',
                                ),
                                IconButton(
                                  tooltip: 'Previous match (Shift+F3)',
                                  onPressed: controller.searchMatches.isEmpty
                                      ? null
                                      : () => _next(backwards: true),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                IconButton(
                                  tooltip: 'Next match (F3)',
                                  onPressed: controller.searchMatches.isEmpty
                                      ? null
                                      : _next,
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                              ],
                            ),
                          if (_notice != null)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _notice!,
                                key: const ValueKey('mail-host-notice'),
                              ),
                            ),
                          for (final diagnostic in presentation.diagnostics)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Semantics(
                                liveRegion:
                                    diagnostic.severity ==
                                    MailDiagnosticSeverity.error,
                                child: Text(
                                  diagnostic.message,
                                  style: TextStyle(
                                    color:
                                        diagnostic.severity ==
                                            MailDiagnosticSeverity.error
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          const Divider(),
                          if (!presentation.rejected)
                            MailSelectionSurface(
                              key: _surfaceKey,
                              controller: controller,
                              textDirection: direction,
                              style:
                                  Theme.of(context).textTheme.bodyLarge ??
                                  const TextStyle(fontSize: 16),
                              textScaler: MediaQuery.textScalerOf(context),
                              onFocusRequest: _focus.requestFocus,
                              onCopy: () => unawaited(_copy()),
                              onLink: widget.onOpenApprovedLink == null
                                  ? null
                                  : (target) => unawaited(_openLink(target)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!presentation.rejected && presentation.images.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      sliver: SliverList.builder(
                        itemCount: presentation.images.length,
                        itemBuilder: (context, index) => _CidImage(
                          key: ValueKey(
                            presentation.images[index].attachment.partPath,
                          ),
                          image: presentation.images[index],
                        ),
                      ),
                    ),
                  if (!presentation.rejected &&
                      links.isNotEmpty &&
                      widget.onOpenApprovedLink != null)
                    SliverPadding(
                      padding: EdgeInsets.all(padding),
                      sliver: SliverList.builder(
                        itemCount: links.length,
                        itemBuilder: (context, index) => Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: ValueKey('mail-link-$index'),
                            onPressed: () => unawaited(_openLink(links[index])),
                            icon: const Icon(Icons.open_in_new),
                            label: Text(
                              'Open link: ${links[index]}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!presentation.rejected &&
                      message != null &&
                      message.attachments.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.all(padding),
                      sliver: SliverList.builder(
                        itemCount: message.attachments.length,
                        itemBuilder: (context, index) {
                          final attachment = message.attachments[index];
                          return Semantics(
                            label:
                                'Read-only attachment ${attachment.displayName}',
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '${attachment.displayName} · ${attachment.mediaType} · ${attachment.observedSize} bytes',
                                    ),
                                    if (widget.onOpenAttachmentReadOnly != null)
                                      TextButton.icon(
                                        key: ValueKey('mail-attachment-$index'),
                                        onPressed: () => unawaited(
                                          _hostAction(
                                            () =>
                                                widget
                                                    .onOpenAttachmentReadOnly!(
                                                  attachment,
                                                ),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                        ),
                                        label: const Text('Open read only'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _statusLabel(MailParseStatus status) => switch (status) {
  MailParseStatus.complete => 'Decoded message',
  MailParseStatus.partial => 'Partially decoded message',
  MailParseStatus.rejected => 'Message rejected',
  MailParseStatus.unsupported => 'Unsupported message',
  MailParseStatus.failed => 'Message decoding failed',
  MailParseStatus.cancelled => 'Message decoding cancelled',
};

class _CidImage extends StatefulWidget {
  const _CidImage({super.key, required this.image});
  final MailInlineImage image;
  @override
  State<_CidImage> createState() => _CidImageState();
}

class _CidImageState extends State<_CidImage> {
  ui.Image? _image;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_CidImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.image.attachment.content,
      widget.image.attachment.content,
    )) {
      _image?.dispose();
      _image = null;
      _failed = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final spec = widget.image;
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(spec.attachment.content.bytes);
      if (codec.frameCount != 1) {
        throw const FormatException('Animated image rejected');
      }
      image = (await codec.getNextFrame()).image;
      if (image.width != spec.width || image.height != spec.height) {
        throw const FormatException('Image dimensions changed during decode');
      }
      if (mounted && generation == _generation) {
        setState(() => _image = image);
        image = null;
      }
    } on Object {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const Text('Inline image could not be decoded.');
    if (_image == null) return const Text('Decoding bounded inline image…');
    return Semantics(
      image: true,
      label: 'Inline image ${widget.image.attachment.displayName}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: widget.image.height.clamp(1, 320).toDouble(),
          child: RawImage(image: _image, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
